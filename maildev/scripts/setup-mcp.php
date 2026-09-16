<?php

#ddev-generated

$projectRoot = getenv('DDEV_APPROOT');

$configurationFile = $projectRoot . '/.mcp.json';
$stateFile = $projectRoot . '/.ddev/maildev/mcp-state.json';

// Only 'install' resolves the hostname, so a project whose hostname is unusable
// can still be uninstalled.
match ($argv[1] ?? 'install') {
    'install' => install($configurationFile, $stateFile, maildevEntry()),
    'remove' => remove($configurationFile, $stateFile),
    default => fail("Usage: setup-mcp.php [install|remove]\n"),
};

function install(string $configurationFile, string $stateFile, object $entry): void
{
    failOnSymlinkedConfiguration($configurationFile);

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

    // State first: a failure here leaves the user's config untouched. The other
    // order would put an entry in .mcp.json that nothing records as ours, which
    // neither remove nor a reinstall would ever clean up.
    writeJson($stateFile, (object) ['entry' => $entry, 'created_file' => !$configurationExisted]);
    writeJson($configurationFile, $configuration);

    printf("Configured the 'maildev' MCP server at %s\n", $entry->url);
}

function remove(string $configurationFile, string $stateFile): void
{
    failOnSymlinkedConfiguration($configurationFile);

    if (!file_exists($stateFile)) {
        echo "No add-on owned MCP entry was recorded; leaving .mcp.json alone.\n";

        return;
    }

    $state = readJsonOrFail($stateFile);
    $existingEntry = null;

    if (file_exists($configurationFile)) {
        $configuration = readConfigurationOrFail($configurationFile);
        $existingEntry = $configuration->mcpServers->maildev ?? null;
    }

    if ($existingEntry !== null && $existingEntry != ($state->entry ?? null)) {
        printf(
            "The 'maildev' MCP server in %s was changed since this add-on wrote it.\n"
                . "It has been left in place; delete the entry by hand if you no longer want it.\n",
            $configurationFile
        );

        return;
    }

    // Someone else already took the entry out. Touching the file now would only
    // add an empty 'mcpServers' back to a config the add-on no longer owns.
    if ($existingEntry !== null) {
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

// Reading follows the link but the atomic rename replaces it, so either command
// would turn the user's symlink into a regular file.
function failOnSymlinkedConfiguration(string $configurationFile): void
{
    if (!is_link($configurationFile)) {
        return;
    }

    fail(sprintf(
        "Error: %s is a symlink.\nPoint it at a real file, or retry with the link removed.\n",
        $configurationFile
    ));
}

function maildevEntry(): object
{
    $rawHostname = (string) getenv('DDEV_HOSTNAME');
    $hostname = strtok($rawHostname, ',');

    // This URL tells Claude Code where to connect. Anything but a bare hostname
    // can move the real target elsewhere while still reading like the project's
    // own address, e.g. "myproject.ddev.site@attacker.example.com".
    if ($hostname === false || !preg_match('/^(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))*$/', $hostname)) {
        fail(sprintf(
            "Error: DDEV_HOSTNAME is not a plain hostname: '%s'.\n"
                . "Refusing to write an MCP server URL that could point elsewhere.\n",
            $rawHostname
        ));
    }

    return (object) [
        'type' => 'http',
        'url' => sprintf('https://%s:1081/mcp', $hostname),
    ];
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
        $contents = file_get_contents($file);
    } catch (Throwable $exception) {
        fail(sprintf(
            "Error: %s could not be read (%s).\nLeaving it unchanged; fix it and try again.\n",
            $file,
            $exception->getMessage()
        ));
    }

    try {
        $decoded = json_decode($contents, false, 512, JSON_THROW_ON_ERROR);
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
// error_reporting(), so `@` suppresses nothing and warnings arrive as
// ErrorException.
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

        // 'x' fails instead of falling back elsewhere, keeping the replacement
        // a real atomic rename inside $directory.
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
