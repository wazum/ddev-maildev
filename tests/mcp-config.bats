#!/usr/bin/env bats
#
# Unit tests for maildev/scripts/setup-mcp.php.
#
# These exercise .mcp.json ownership logic only: no DDEV, no Docker, no
# containers. The script reads DDEV_APPROOT and DDEV_HOSTNAME from the
# environment, so a temp directory is a complete fixture.

setup() {
  set -eu -o pipefail

  ADDON_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export ADDON_ROOT
  export SCRIPT="${ADDON_ROOT}/maildev/scripts/setup-mcp.php"

  export DDEV_APPROOT="${BATS_TEST_TMPDIR}/project"
  export DDEV_HOSTNAME="myproj.ddev.site"

  mkdir -p "${DDEV_APPROOT}/.ddev"
}

# Reads a dotted path out of a JSON file so assertions stay readable.
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
  run php "${SCRIPT}" install
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

  run php "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run mcp_json "mcpServers.context7.url"
  [ "$status" -eq 0 ]
  [ "$output" = "https://context7.example/mcp" ]
}

@test "install records the entry it wrote as ownership state" {
  run php "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run state_json "entry.url"
  [ "$status" -eq 0 ]
  [ "$output" = "https://myproj.ddev.site:1081/mcp" ]
}

@test "install records that it created .mcp.json when none existed" {
  run php "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run state_json "created_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "install records that it did not create a pre-existing .mcp.json" {
  echo '{"mcpServers":{}}' > "${DDEV_APPROOT}/.mcp.json"

  run php "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run state_json "created_file"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "install fails without modifying a malformed .mcp.json" {
  printf '{ "mcpServers": { oops' > "${DDEV_APPROOT}/.mcp.json"
  local before
  before="$(cat "${DDEV_APPROOT}/.mcp.json")"

  run php "${SCRIPT}" install
  [ "$status" -ne 0 ]
  [[ "$output" == *".mcp.json"* ]]

  [ "$(cat "${DDEV_APPROOT}/.mcp.json")" = "${before}" ]
}
