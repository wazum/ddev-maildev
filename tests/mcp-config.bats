#!/usr/bin/env bats
#
# No DDEV or Docker needed: the script reads DDEV_APPROOT and DDEV_HOSTNAME from
# the environment, so a temp directory is a complete fixture.

setup() {
  set -eu -o pipefail

  ADDON_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export ADDON_ROOT
  export SCRIPT="${ADDON_ROOT}/maildev/scripts/setup-mcp.php"

  export DDEV_APPROOT="${BATS_TEST_TMPDIR}/project"
  export DDEV_HOSTNAME="myproj.ddev.site"

  mkdir -p "${DDEV_APPROOT}/.ddev"
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

  run php "${SCRIPT}" install
  [ "$status" -ne 0 ]
  [[ "$output" == *"maildev"* ]]

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

  run php "${SCRIPT}" install
  [ "$status" -eq 0 ]

  [ ! -f "${DDEV_APPROOT}/.ddev/maildev/mcp-state.json" ]
}

@test "reinstall leaves an untouched owned entry as it is" {
  run php "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run mcp_json "mcpServers.maildev.url"
  [ "$output" = "https://myproj.ddev.site:1081/mcp" ]
}

@test "reinstall updates an owned entry after the project hostname changes" {
  run php "${SCRIPT}" install
  [ "$status" -eq 0 ]

  export DDEV_HOSTNAME="renamed.ddev.site"

  run php "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run mcp_json "mcpServers.maildev.url"
  [ "$output" = "https://renamed.ddev.site:1081/mcp" ]
}

@test "reinstall fails when the owned entry was edited by hand" {
  run php "${SCRIPT}" install
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

  run php "${SCRIPT}" install
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

  run php "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php "${SCRIPT}" remove
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

  run php "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php "${SCRIPT}" remove
  [ "$status" -eq 0 ]

  run mcp_json "mcpServers.context7.url"
  [ "$status" -eq 0 ]
  [ "$output" = "https://context7.example/mcp" ]
}

@test "remove preserves a maildev entry that was edited after install" {
  run php "${SCRIPT}" install
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

  run php "${SCRIPT}" remove
  [[ "$output" == *"maildev"* ]]

  run mcp_json "mcpServers.maildev.url"
  [ "$status" -eq 0 ]
  [ "$output" = "https://edited-by-hand.example/mcp" ]
}

@test "remove deletes .mcp.json when the add-on created it and nothing else remains" {
  run php "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php "${SCRIPT}" remove
  [ "$status" -eq 0 ]

  [ ! -f "${DDEV_APPROOT}/.mcp.json" ]
}

@test "remove keeps a pre-existing .mcp.json even when it ends up with no servers" {
  echo '{"mcpServers":{}}' > "${DDEV_APPROOT}/.mcp.json"

  run php "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php "${SCRIPT}" remove
  [ "$status" -eq 0 ]

  [ -f "${DDEV_APPROOT}/.mcp.json" ]
}

@test "remove keeps a created .mcp.json that gained an unrelated server" {
  run php "${SCRIPT}" install
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

  run php "${SCRIPT}" remove
  [ "$status" -eq 0 ]

  [ -f "${DDEV_APPROOT}/.mcp.json" ]
  run mcp_json "mcpServers.context7.url"
  [ "$output" = "https://context7.example/mcp" ]
}

@test "remove keeps an emptied mcpServers as a JSON object" {
  echo '{"mcpServers":{}}' > "${DDEV_APPROOT}/.mcp.json"

  run php "${SCRIPT}" install
  [ "$status" -eq 0 ]

  run php "${SCRIPT}" remove
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

  run php "${SCRIPT}" install
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

  run php "${SCRIPT}" install
  [ "$status" -eq 1 ]
  [[ "$output" != *"Fatal error"* ]]
  [[ "$output" == *".mcp.json"* ]]

  [ "$(cat "${DDEV_APPROOT}/.mcp.json")" = "${before}" ]
}

@test "install reports an actionable error for a .mcp.json whose mcpServers is not an object" {
  printf '{"mcpServers": "nonsense"}' > "${DDEV_APPROOT}/.mcp.json"
  local before
  before="$(cat "${DDEV_APPROOT}/.mcp.json")"

  run php "${SCRIPT}" install
  [ "$status" -eq 1 ]
  [[ "$output" != *"Fatal error"* ]]
  [[ "$output" == *"mcpServers"* ]]

  [ "$(cat "${DDEV_APPROOT}/.mcp.json")" = "${before}" ]
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
