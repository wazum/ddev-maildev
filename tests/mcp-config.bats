#!/usr/bin/env bats
#
# No DDEV or Docker needed: the script reads DDEV_APPROOT and DDEV_HOSTNAME from
# the environment, so a temp directory is a complete fixture.

setup() {
  set -eu -o pipefail

  ADDON_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export ADDON_ROOT
  export SCRIPT="${ADDON_ROOT}/maildev/scripts/setup-mcp.php"
  export RUNNER="${ADDON_ROOT}/tests/ddev-action-runner.php"

  export DDEV_APPROOT="${BATS_TEST_TMPDIR}/project"
  export DDEV_HOSTNAME="myproj.ddev.site"

  mkdir -p "${DDEV_APPROOT}/.ddev"
}

# A false `[[ ]]` does not fail a bats test, because `[[` is a shell keyword and
# errexit skips it. These are functions so a failed assertion stops the test.
assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) echo "expected to find '$2' in:" >&2; echo "$1" >&2; return 1 ;;
  esac
}

refute_contains() {
  case "$1" in
    *"$2"*) echo "expected NOT to find '$2' in:" >&2; echo "$1" >&2; return 1 ;;
    *) return 0 ;;
  esac
}

# Exits non-zero when any segment of the path is missing.
json_at() {
  php -r '
    $configuration = json_decode(file_get_contents($argv[1]), true);
    foreach (explode(".", $argv[2]) as $key) {
      if (!is_array($configuration) || !array_key_exists($key, $configuration)) {
        exit(1);
      }
      $configuration = $configuration[$key];
    }
    echo is_string($configuration) ? $configuration : json_encode($configuration);
  ' -- "$1" "$2"
}

mcp_json() {
  json_at "${DDEV_APPROOT}/.mcp.json" "$1"
}

state_json() {
  json_at "${DDEV_APPROOT}/.ddev/maildev/mcp-state.json" "$1"
}

@test "install creates .mcp.json with the maildev entry when no file exists" {
  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run mcp_json "mcpServers.maildev.url"
  [ "$status" -eq 0 ]
  [ "$output" = "https://myproj.ddev.site:1081/mcp" ]
}

@test "install preserves unrelated servers in an existing .mcp.json" {
  cat > "${DDEV_APPROOT}/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://context7.example/mcp"
    }
  }
}
JSON

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run mcp_json "mcpServers.context7.url"
  [ "$status" -eq 0 ]
  [ "$output" = "https://context7.example/mcp" ]
}

@test "install records the entry it wrote as ownership state" {
  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run state_json "entry.url"
  [ "$status" -eq 0 ]
  [ "$output" = "https://myproj.ddev.site:1081/mcp" ]
}

@test "install records that it created .mcp.json when none existed" {
  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run state_json "created_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "install records that it did not create a pre-existing .mcp.json" {
  echo '{"mcpServers":{}}' > "${DDEV_APPROOT}/.mcp.json"

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run state_json "created_file"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "install fails on a conflicting maildev entry it does not own" {
  cat > "${DDEV_APPROOT}/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "maildev": {
      "type": "http",
      "url": "https://someone-elses.example/mcp"
    }
  }
}
JSON

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -ne 0 ]
  assert_contains "$output" "maildev"

  run mcp_json "mcpServers.maildev.url"
  [ "$output" = "https://someone-elses.example/mcp" ]
}

@test "install accepts an unowned maildev entry that already matches without claiming it" {
  cat > "${DDEV_APPROOT}/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "maildev": {
      "type": "http",
      "url": "https://myproj.ddev.site:1081/mcp"
    }
  }
}
JSON

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  [ ! -f "${DDEV_APPROOT}/.ddev/maildev/mcp-state.json" ]
}

@test "reinstall leaves an untouched owned entry as it is" {
  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run mcp_json "mcpServers.maildev.url"
  [ "$output" = "https://myproj.ddev.site:1081/mcp" ]
}

@test "reinstall updates an owned entry after the project hostname changes" {
  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  export DDEV_HOSTNAME="renamed.ddev.site"

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run mcp_json "mcpServers.maildev.url"
  [ "$output" = "https://renamed.ddev.site:1081/mcp" ]
}

@test "reinstall fails when the owned entry was edited by hand" {
  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  cat > "${DDEV_APPROOT}/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "maildev": {
      "type": "http",
      "url": "https://edited-by-hand.example/mcp"
    }
  }
}
JSON

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -ne 0 ]

  run mcp_json "mcpServers.maildev.url"
  [ "$output" = "https://edited-by-hand.example/mcp" ]
}

@test "remove deletes an owned entry from a file it did not create" {
  cat > "${DDEV_APPROOT}/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://context7.example/mcp"
    }
  }
}
JSON

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php "${RUNNER}" "${SCRIPT}" remove
  [ "$status" -eq 0 ]

  run mcp_json "mcpServers.maildev"
  [ "$status" -ne 0 ]
}

@test "remove keeps unrelated servers intact" {
  cat > "${DDEV_APPROOT}/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://context7.example/mcp"
    }
  }
}
JSON

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php "${RUNNER}" "${SCRIPT}" remove
  [ "$status" -eq 0 ]

  run mcp_json "mcpServers.context7.url"
  [ "$status" -eq 0 ]
  [ "$output" = "https://context7.example/mcp" ]
}

@test "remove preserves a maildev entry that was edited after install" {
  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  cat > "${DDEV_APPROOT}/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "maildev": {
      "type": "http",
      "url": "https://edited-by-hand.example/mcp"
    }
  }
}
JSON

  run php "${RUNNER}" "${SCRIPT}" remove
  assert_contains "$output" "maildev"

  run mcp_json "mcpServers.maildev.url"
  [ "$status" -eq 0 ]
  [ "$output" = "https://edited-by-hand.example/mcp" ]
}

@test "remove deletes .mcp.json when the add-on created it and nothing else remains" {
  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php "${RUNNER}" "${SCRIPT}" remove
  [ "$status" -eq 0 ]

  [ ! -f "${DDEV_APPROOT}/.mcp.json" ]
}

@test "remove keeps a pre-existing .mcp.json even when it ends up with no servers" {
  echo '{"mcpServers":{}}' > "${DDEV_APPROOT}/.mcp.json"

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php "${RUNNER}" "${SCRIPT}" remove
  [ "$status" -eq 0 ]

  [ -f "${DDEV_APPROOT}/.mcp.json" ]
}

@test "remove keeps a created .mcp.json that gained an unrelated server" {
  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  cat > "${DDEV_APPROOT}/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "maildev": {
      "type": "http",
      "url": "https://myproj.ddev.site:1081/mcp"
    },
    "context7": {
      "type": "http",
      "url": "https://context7.example/mcp"
    }
  }
}
JSON

  run php "${RUNNER}" "${SCRIPT}" remove
  [ "$status" -eq 0 ]

  [ -f "${DDEV_APPROOT}/.mcp.json" ]
  run mcp_json "mcpServers.context7.url"
  [ "$output" = "https://context7.example/mcp" ]
}

@test "remove keeps an emptied mcpServers as a JSON object" {
  echo '{"mcpServers":{}}' > "${DDEV_APPROOT}/.mcp.json"

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php "${RUNNER}" "${SCRIPT}" remove
  [ "$status" -eq 0 ]

  run php -r '
    $configuration = json_decode(file_get_contents(getenv("DDEV_APPROOT") . "/.mcp.json"));
    echo is_object($configuration->mcpServers) ? "object" : "array";
  '
  [ "$output" = "object" ]
}

@test "install keeps genuine JSON arrays as arrays" {
  cat > "${DDEV_APPROOT}/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "local": {
      "type": "stdio",
      "command": "some-server",
      "args": []
    }
  }
}
JSON

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php -r '
    $configuration = json_decode(file_get_contents(getenv("DDEV_APPROOT") . "/.mcp.json"));
    echo is_array($configuration->mcpServers->local->args) ? "array" : "object";
  '
  [ "$output" = "array" ]
}

@test "install reports an actionable error for a .mcp.json whose root is not an object" {
  printf '["not", "an", "object"]' > "${DDEV_APPROOT}/.mcp.json"
  local before
  before="$(cat "${DDEV_APPROOT}/.mcp.json")"

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 1 ]
  refute_contains "$output" "Fatal error"
  assert_contains "$output" ".mcp.json"

  [ "$(cat "${DDEV_APPROOT}/.mcp.json")" = "${before}" ]
}

@test "install reports an actionable error for a .mcp.json whose mcpServers is not an object" {
  printf '{"mcpServers": "nonsense"}' > "${DDEV_APPROOT}/.mcp.json"
  local before
  before="$(cat "${DDEV_APPROOT}/.mcp.json")"

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 1 ]
  refute_contains "$output" "Fatal error"
  assert_contains "$output" "mcpServers"

  [ "$(cat "${DDEV_APPROOT}/.mcp.json")" = "${before}" ]
}

@test "install preserves the permissions of an existing .mcp.json" {
  echo '{"mcpServers":{}}' > "${DDEV_APPROOT}/.mcp.json"
  chmod 640 "${DDEV_APPROOT}/.mcp.json"

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php -r 'printf("%o", fileperms(getenv("DDEV_APPROOT") . "/.mcp.json") & 0777);'
  [ "$output" = "640" ]
}

@test "install creates a new .mcp.json readable only by its owner" {
  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php -r 'printf("%o", fileperms(getenv("DDEV_APPROOT") . "/.mcp.json") & 0777);'
  [ "$output" = "600" ]
}

@test "install reports an actionable error when .mcp.json is a directory" {
  mkdir "${DDEV_APPROOT}/.mcp.json"

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 1 ]
  refute_contains "$output" "Fatal error"
  assert_contains "$output" ".mcp.json"

  [ -d "${DDEV_APPROOT}/.mcp.json" ]
}

@test "install leaves no temporary files behind" {
  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run find "${DDEV_APPROOT}" -name '.mcp-*'
  [ -z "$output" ]
}

@test "install reports an actionable error when .mcp.json cannot be written" {
  [ "$(id -u)" -ne 0 ] || skip "root ignores directory permissions"

  chmod 500 "${DDEV_APPROOT}"

  run php "${RUNNER}" "${SCRIPT}" install
  local status_seen="$status" output_seen="$output"

  chmod 700 "${DDEV_APPROOT}"

  [ "$status_seen" -eq 1 ]
  refute_contains "$output_seen" "Fatal error"
  assert_contains "$output_seen" "Could not write"
}

@test "install refuses a hostname that hides another host in userinfo" {
  export DDEV_HOSTNAME="myproject.ddev.site@attacker.example.com"

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 1 ]
  refute_contains "$output" "Fatal error"

  [ ! -f "${DDEV_APPROOT}/.mcp.json" ]
}

@test "install refuses a hostname carrying a path" {
  export DDEV_HOSTNAME="attacker.example.com/myproj.ddev.site"

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 1 ]

  [ ! -f "${DDEV_APPROOT}/.mcp.json" ]
}

@test "install refuses an empty hostname" {
  export DDEV_HOSTNAME=""

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 1 ]

  [ ! -f "${DDEV_APPROOT}/.mcp.json" ]
}

@test "install accepts a project hostname with a custom TLD" {
  export DDEV_HOSTNAME="myproj.example.test"

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run mcp_json "mcpServers.maildev.url"
  [ "$output" = "https://myproj.example.test:1081/mcp" ]
}

@test "install uses the first of several hostnames" {
  export DDEV_HOSTNAME="myproj.ddev.site,extra.ddev.site"

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run mcp_json "mcpServers.maildev.url"
  [ "$output" = "https://myproj.ddev.site:1081/mcp" ]
}

@test "remove still works when the hostname is unusable" {
  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  export DDEV_HOSTNAME=""

  run php "${RUNNER}" "${SCRIPT}" remove
  [ "$status" -eq 0 ]

  [ ! -f "${DDEV_APPROOT}/.mcp.json" ]
}

@test "remove leaves the file alone when the maildev entry is already gone" {
  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  echo '{"otherTopLevel": true}' > "${DDEV_APPROOT}/.mcp.json"

  run php "${RUNNER}" "${SCRIPT}" remove
  [ "$status" -eq 0 ]
  refute_contains "$output" "Fatal error"

  run cat "${DDEV_APPROOT}/.mcp.json"
  refute_contains "$output" "mcpServers"
  assert_contains "$output" "otherTopLevel"
}

@test "install writes nothing when the ownership state cannot be recorded" {
  [ "$(id -u)" -ne 0 ] || skip "root ignores directory permissions"

  chmod 500 "${DDEV_APPROOT}/.ddev"

  run php "${RUNNER}" "${SCRIPT}" install
  local status_seen="$status"

  chmod 700 "${DDEV_APPROOT}/.ddev"

  [ "$status_seen" -eq 1 ]
  [ ! -f "${DDEV_APPROOT}/.mcp.json" ]
}

@test "install recovers on a retry after the config write failed" {
  [ "$(id -u)" -ne 0 ] || skip "root ignores directory permissions"

  chmod 500 "${DDEV_APPROOT}"
  run php "${RUNNER}" "${SCRIPT}" install
  local status_seen="$status"
  chmod 700 "${DDEV_APPROOT}"

  [ "$status_seen" -eq 1 ]

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run mcp_json "mcpServers.maildev.url"
  [ "$output" = "https://myproj.ddev.site:1081/mcp" ]
}

@test "remove cleans up state left behind by a failed config write" {
  [ "$(id -u)" -ne 0 ] || skip "root ignores directory permissions"

  chmod 500 "${DDEV_APPROOT}"
  run php "${RUNNER}" "${SCRIPT}" install
  chmod 700 "${DDEV_APPROOT}"

  [ -f "${DDEV_APPROOT}/.ddev/maildev/mcp-state.json" ]

  run php "${RUNNER}" "${SCRIPT}" remove
  [ "$status" -eq 0 ]

  [ ! -f "${DDEV_APPROOT}/.ddev/maildev/mcp-state.json" ]
}

@test "remove refuses a symlinked .mcp.json" {
  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 0 ]

  # The link appears after install, so the install-time guard never saw it.
  mv "${DDEV_APPROOT}/.mcp.json" "${DDEV_APPROOT}/elsewhere.json"
  ln -s elsewhere.json "${DDEV_APPROOT}/.mcp.json"

  run php "${RUNNER}" "${SCRIPT}" remove
  assert_contains "$output" "symlink"

  [ -L "${DDEV_APPROOT}/.mcp.json" ]

  run cat "${DDEV_APPROOT}/elsewhere.json"
  assert_contains "$output" "maildev"
}

@test "install refuses a symlinked .mcp.json" {
  echo '{"mcpServers":{}}' > "${DDEV_APPROOT}/elsewhere.json"
  ln -s "${DDEV_APPROOT}/elsewhere.json" "${DDEV_APPROOT}/.mcp.json"

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -eq 1 ]
  assert_contains "$output" "symlink"

  [ -L "${DDEV_APPROOT}/.mcp.json" ]
  run cat "${DDEV_APPROOT}/elsewhere.json"
  refute_contains "$output" "maildev"
}

@test "install fails without modifying a malformed .mcp.json" {
  printf '{ "mcpServers": { oops' > "${DDEV_APPROOT}/.mcp.json"
  local before
  before="$(cat "${DDEV_APPROOT}/.mcp.json")"

  run php "${RUNNER}" "${SCRIPT}" install
  [ "$status" -ne 0 ]
  assert_contains "$output" ".mcp.json"

  [ "$(cat "${DDEV_APPROOT}/.mcp.json")" = "${before}" ]
}
