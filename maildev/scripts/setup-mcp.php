<?php

#ddev-generated

$projectRoot = getenv('DDEV_APPROOT');
$hostname = strtok(getenv('DDEV_HOSTNAME'), ',');

$configurationFile = $projectRoot . '/.mcp.json';
$stateFile = $projectRoot . '/.ddev/maildev/mcp-state.json';

$entry = (object) [
    'type' => 'http',
    'url' => sprintf('https://%s:1081/mcp', $hostname),
];

match ($argv[1] ?? 'install') {
    'install' => install($configurationFile, $stateFile, $entry),
    'remove' => remove($configurationFile, $stateFile),
    default => fail("Usage: setup-mcp.php [install|remove]\n"),
};

function install(string $configurationFile, string $stateFile, object $entry): void
{
    $configurationExisted = file_exists($configurationFile);
    $configuration = $configurationExisted ? readConfigurationOrFail($configurationFile) : new stdClass();
    $state = file_exists($stateFile) ? readJsonOrFail($stateFile) : null;

    $existingEntry = $configuration->mcpServers->maildev ?? null;

    if ($existingEntry !== null && $state === null) {
        if ($existingEntry == $entry) {
            echo "An identical 'maildev' MCP server is already configured; leaving it alone.\n";

            return;
        }

        fail(sprintf(
            "A 'maildev' MCP server this add-on does not own already exists in %s.\n"
                . "Remove or rename it and install again; it has been left unchanged.\n",
            $configurationFile
        ));
    }

    if ($existingEntry !== null && $existingEntry != ($state->entry ?? null)) {
        fail(sprintf(
            "The 'maildev' MCP server in %s was changed since this add-on wrote it.\n"
                . "Your version has been left unchanged. Delete the entry to let the add-on manage it again.\n",
            $configurationFile
        ));
    }

    $configuration->mcpServers ??= new stdClass();
    $configuration->mcpServers->maildev = $entry;

    writeJson($configurationFile, $configuration);
    writeJson($stateFile, (object) ['entry' => $entry, 'created_file' => !$configurationExisted]);

    printf("Configured the 'maildev' MCP server at %s\n", $entry->url);
}

function remove(string $configurationFile, string $stateFile): void
{
    if (!file_exists($stateFile)) {
        echo "No add-on owned MCP entry was recorded; leaving .mcp.json alone.\n";

        return;
    }

    $state = readJsonOrFail($stateFile);

    if (file_exists($configurationFile)) {
        $configuration = readConfigurationOrFail($configurationFile);
        $existingEntry = $configuration->mcpServers->maildev ?? null;

        if ($existingEntry !== null && $existingEntry != ($state->entry ?? null)) {
            printf(
                "The 'maildev' MCP server in %s was changed since this add-on wrote it.\n"
                    . "It has been left in place; delete the entry by hand if you no longer want it.\n",
                $configurationFile
            );

            return;
        }

        unset($configuration->mcpServers->maildev);

        if (($state->created_file ?? false) && holdsNothingElse($configuration)) {
            unlink($configurationFile);
        } else {
            writeJson($configurationFile, $configuration);
        }
    }

    unlink($stateFile);

    echo "Removed the 'maildev' MCP server entry.\n";
}

function holdsNothingElse(object $configuration): bool
{
    $servers = (array) ($configuration->mcpServers ?? new stdClass());
    $otherProperties = (array) $configuration;
    unset($otherProperties['mcpServers']);

    return $servers === [] && $otherProperties === [];
}

function readJsonOrFail(string $file): object
{
    try {
        $decoded = json_decode(file_get_contents($file), false, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $exception) {
        fail(sprintf(
            "Error: %s is not valid JSON (%s).\nLeaving it unchanged; fix it and try again.\n",
            $file,
            $exception->getMessage()
        ));
    }

    if (!$decoded instanceof stdClass) {
        fail(sprintf(
            "Error: %s must contain a JSON object at its top level, found %s.\n"
                . "Leaving it unchanged; fix it and try again.\n",
            $file,
            get_debug_type($decoded)
        ));
    }

    return $decoded;
}

function readConfigurationOrFail(string $file): object
{
    $configuration = readJsonOrFail($file);

    if (isset($configuration->mcpServers) && !$configuration->mcpServers instanceof stdClass) {
        fail(sprintf(
            "Error: the 'mcpServers' value in %s must be a JSON object, found %s.\n"
                . "Leaving it unchanged; fix it and try again.\n",
            $file,
            get_debug_type($configuration->mcpServers)
        ));
    }

    return $configuration;
}

// DDEV runs add-on actions behind an error handler that ignores
// error_reporting(), so `@` suppresses nothing and every warning arrives as an
// ErrorException. Everything here therefore reports through exceptions.
function writeJson(string $file, object $data): void
{
    $directory = dirname($file);
    $json = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
    $temporaryFile = $directory . '/.mcp-' . bin2hex(random_bytes(8)) . '.tmp';
    $temporaryFileCreated = false;

    try {
        if (!is_dir($directory)) {
            mkdir($directory, 0o755, true);
        }

        $permissions = file_exists($file) ? fileperms($file) & 0o777 : 0o600;

        // 'x' fails rather than falling back elsewhere, so the replacement below
        // always stays inside $directory and is a real atomic rename.
        $fileHandle = fopen($temporaryFile, 'xb');

        if ($fileHandle === false) {
            throw new RuntimeException(sprintf('no temporary file could be created in %s', $directory));
        }

        $temporaryFileCreated = true;

        if (fwrite($fileHandle, $json) !== strlen($json)) {
            throw new RuntimeException('the temporary file could not be written in full');
        }

        fclose($fileHandle);
        chmod($temporaryFile, $permissions);
        rename($temporaryFile, $file);
    } catch (Throwable $exception) {
        if ($temporaryFileCreated && file_exists($temporaryFile)) {
            unlink($temporaryFile);
        }

        fail(sprintf("Could not write %s: %s.\n", $file, $exception->getMessage()));
    }
}

function fail(string $message): never
{
    fwrite(STDERR, $message);
    exit(1);
}
