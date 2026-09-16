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

# Reads a value out of the generated .mcp.json so assertions stay readable.
mcp_json() {
  php -r '
    $file = getenv("DDEV_APPROOT") . "/.mcp.json";
    $configuration = json_decode(file_get_contents($file), true);
    foreach (explode(".", $argv[1]) as $key) {
      if (!is_array($configuration) || !array_key_exists($key, $configuration)) {
        exit(1);
      }
      $configuration = $configuration[$key];
    }
    echo is_string($configuration) ? $configuration : json_encode($configuration);
  ' -- "$1"
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
