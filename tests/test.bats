#!/usr/bin/env bats
#
# Docker-level tests: these start a real DDEV project and prove mail actually
# travels from PHP to MailDev. The .mcp.json logic is covered far faster by
# mcp-config.bats, so nothing here re-tests it.

setup() {
  set -eu -o pipefail

  export GITHUB_REPO=wazum/ddev-maildev

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true

  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  mkdir -p web
  run ddev config --project-name="${PROJNAME}" --project-type=php --docroot=web --project-tld=ddev.site
  assert_success
  run ddev start -y
  assert_success
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  # Keep TESTDIR on GitHub Actions so the action can upload it as an artifact.
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

maildev_password() {
  ddev dotenv get .ddev/.env.maildev.local --maildev-web-pass
}

# Runs a curl inside the web container, which reaches MailDev over the Docker
# network without needing the router or a hosts file entry.
maildev_api() {
  ddev exec curl -sf -u "ddev:$(maildev_password)" \
    "http://ddev-${PROJNAME}-maildev:1080$1"
}

# Polls instead of sleeping: SMTP delivery and storage are not instant, but they
# are usually done in well under a second.
wait_for_subject() {
  local subject="$1" i
  for i in $(seq 1 30); do
    if maildev_api /api/email 2>/dev/null | grep -q "${subject}"; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for a message with subject '${subject}'" >&2
  maildev_api /api/email >&2 || true
  return 1
}

health_checks() {
  run ddev exec curl -sf "http://ddev-${PROJNAME}-maildev:1080/api/healthz"
  [ "$status" -eq 0 ]

  # The whole point of the add-on: PHP's mail() must reach MailDev, not Mailpit.
  local subject="cli-$(date +%s)-${RANDOM}"
  run ddev exec php -r "mail('to@example.test', '${subject}', 'body');"
  [ "$status" -eq 0 ]

  run wait_for_subject "${subject}"
  [ "$status" -eq 0 ]

  # Same path through FPM rather than the CLI binary, since they load separate
  # php.ini files and only one of them proves the override reached both.
  local web_subject="fpm-$(date +%s)-${RANDOM}"
  echo "<?php mail('to@example.test', '${web_subject}', 'body');" > web/sendmail.php
  run ddev exec curl -sf "http://localhost/sendmail.php"
  [ "$status" -eq 0 ]

  run wait_for_subject "${web_subject}"
  [ "$status" -eq 0 ]

  rm -f web/sendmail.php

  run ddev exec curl -s -o /dev/null -w "%{http_code}" \
    "http://ddev-${PROJNAME}-maildev:1080/api/email"
  [ "$output" = "401" ]

  run test -f .mcp.json
  [ "$status" -eq 0 ]
  run cat .mcp.json
  assert_output --partial "${PROJNAME}.ddev.site:1081/mcp"
  assert_output --partial "Authorization"
}

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3

  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success

  health_checks
}

@test "mail survives a restart" {
  set -eu -o pipefail

  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success

  local subject="persist-$(date +%s)-${RANDOM}"
  run ddev exec php -r "mail('to@example.test', '${subject}', 'body');"
  assert_success
  run wait_for_subject "${subject}"
  assert_success

  run ddev restart -y
  assert_success

  run wait_for_subject "${subject}"
  assert_success
}

@test "removal restores DDEV's own mail handling" {
  set -eu -o pipefail

  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success

  run ddev add-on remove maildev
  assert_success

  run test -f .ddev/php/maildev.ini
  [ "$status" -ne 0 ]
  run test -f .ddev/.env.web.maildev
  [ "$status" -ne 0 ]
  run test -f .mcp.json
  [ "$status" -ne 0 ]

  run docker volume inspect "ddev-${PROJNAME}-maildev-mail"
  [ "$status" -ne 0 ]

  run ddev restart -y
  assert_success

  # Back on Mailpit, so mail() must land there again.
  local subject="mailpit-$(date +%s)-${RANDOM}"
  run ddev exec php -r "mail('to@example.test', '${subject}', 'body');"
  assert_success

  local i
  for i in $(seq 1 30); do
    if ddev exec curl -sf "http://127.0.0.1:8025/api/v1/messages" | grep -q "${subject}"; then
      break
    fi
    sleep 1
  done
  run ddev exec curl -sf "http://127.0.0.1:8025/api/v1/messages"
  assert_output --partial "${subject}"
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3

  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success

  health_checks
}
