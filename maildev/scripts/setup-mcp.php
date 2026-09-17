<?php

#ddev-generated

$projectRoot = getenv('DDEV_APPROOT');

$configurationFile = $projectRoot . '/.mcp.json';
$ownershipFile = $projectRoot . '/.ddev/maildev/mcp-state.json';

match ($argv[1] ?? 'install') {
    'install' => installMaildevServer($configurationFile, $ownershipFile),
    'remove' => removeMaildevServer($configurationFile, $ownershipFile),
    default => fail("Usage: setup-mcp.php [install|remove]\n"),
};

function installMaildevServer(string $configurationFile, string $ownershipFile): void
{
    $serverEntry = buildMaildevServerEntry();

    failOnSymlinkedConfiguration($configurationFile);

    $configurationFileExists = file_exists($configurationFile);
    $configuration = $configurationFileExists ? readMcpConfiguration($configurationFile) : new stdClass();
    $ownership = file_exists($ownershipFile) ? readJsonObject($ownershipFile) : null;

    $existingEntry = $configuration->mcpServers->maildev ?? null;

    if ($existingEntry !== null && $ownership === null) {
        if ($existingEntry == $serverEntry) {
            echo "An identical 'maildev' MCP server is already configured; leaving it alone.\n";

            return;
        }

        fail(sprintf(
            "A 'maildev' MCP server this add-on does not own already exists in %s.\n"
                . "Remove or rename it and install again; it has been left unchanged.\n",
            $configurationFile
        ));
    }

    if ($existingEntry !== null && !isEntryOwned($existingEntry, $ownership)) {
        fail(sprintf(
            "The 'maildev' MCP server in %s was changed since this add-on wrote it.\n"
                . "Your version has been left unchanged. Delete the entry to let the add-on manage it again.\n",
            $configurationFile
        ));
    }

    $configuration->mcpServers ??= new stdClass();
    $configuration->mcpServers->maildev = $serverEntry;

    // Ownership must be recorded first to avoid untracked entries on failure.
    // File existence on reinstall does not reveal who originally created it.
    writeJsonAtomically($ownershipFile, (object) [
        'entry' => $serverEntry,
        // Keeps the entry a failed write leaves behind recognisable as ours.
        'previous_entry' => $existingEntry,
        'created_file' => $ownership->created_file ?? !$configurationFileExists,
    ]);
    writeJsonAtomically($configurationFile, $configuration);

    printf("Configured the 'maildev' MCP server at %s\n", $serverEntry->url);

    warnIfConfigurationIsTracked($configurationFile);
}

// The entry holds the inbox password, and .mcp.json is the MCP file people commit.
function warnIfConfigurationIsTracked(string $configurationFile): void
{
    // Without exec() this warning is not worth a fatal; a project can disable it
    // through .ddev/php, and git may not be installed either.
    if (!function_exists('exec')) {
        return;
    }

    $command = sprintf(
        'git -C %s ls-files --error-unmatch %s 2>/dev/null',
        escapeshellarg(dirname($configurationFile)),
        escapeshellarg($configurationFile)
    );

    exec($command, $output, $exitCode);

    if ($exitCode !== 0) {
        return;
    }

    printf(
        "\nWarning: %s is tracked by Git and now holds the MailDev password.\n"
            . "Untrack it, or move the 'maildev' entry to your own MCP config.\n",
        $configurationFile
    );
}

function removeMaildevServer(string $configurationFile, string $ownershipFile): void
{
    failOnSymlinkedConfiguration($configurationFile);

    if (!file_exists($ownershipFile)) {
        echo "No add-on owned MCP entry was recorded; leaving .mcp.json alone.\n";

        return;
    }

    $ownership = readJsonObject($ownershipFile);
    $existingEntry = null;

    if (file_exists($configurationFile)) {
        $configuration = readMcpConfiguration($configurationFile);
        $existingEntry = $configuration->mcpServers->maildev ?? null;
    }

    if ($existingEntry !== null && !isEntryOwned($existingEntry, $ownership)) {
        printf(
            "The 'maildev' MCP server in %s was changed since this add-on wrote it.\n"
                . "It has been left in place; delete the entry by hand if you no longer want it.\n",
            $configurationFile
        );

        return;
    }

    if ($existingEntry !== null) {
        unset($configuration->mcpServers->maildev);

        if (($ownership->created_file ?? false) && isMcpConfigurationEmpty($configuration)) {
            unlink($configurationFile);
        } else {
            writeJsonAtomically($configurationFile, $configuration);
        }
    }

    unlink($ownershipFile);

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

function isEntryOwned(object $existingEntry, ?object $ownership): bool
{
    if ($ownership === null) {
        return false;
    }

    return $existingEntry == ($ownership->entry ?? null)
        || $existingEntry == ($ownership->previous_entry ?? null);
}

function buildMaildevServerEntry(): object
{
    $hostname = readProjectHostname();
    $authorizationHeader = readMaildevAuthorizationHeader();

    return (object) [
        'type' => 'http',
        'url' => sprintf('https://%s:1081/mcp', $hostname),
        'headers' => (object) [
            'Authorization' => $authorizationHeader,
        ],
    ];
}

function readProjectHostname(): string
{
    $configuredHostnames = (string) getenv('DDEV_HOSTNAME');
    $primaryHostname = strtok($configuredHostnames, ',');
    $hostnamePattern = '/^(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))*$/';

    if ($primaryHostname === false || !preg_match($hostnamePattern, $primaryHostname)) {
        fail(sprintf(
            "Error: DDEV_HOSTNAME is not a plain hostname: '%s'.\n"
                . "Refusing to write an MCP server URL that could point elsewhere.\n",
            $configuredHostnames
        ));
    }

    return $primaryHostname;
}

function readMaildevAuthorizationHeader(): string
{
    $userName = (string) getenv('MAILDEV_WEB_USER');
    $password = (string) getenv('MAILDEV_WEB_PASS');

    // MailDev has no authentication unless both are set.
    if ($userName === '' || $password === '') {
        fail(
            "Error: MAILDEV_WEB_USER and MAILDEV_WEB_PASS are not set.\n"
                . "The add-on will not configure an unauthenticated MailDev inbox.\n"
                . "Check that .ddev/.env.maildev exists and holds both values.\n"
        );
    }

    return 'Basic ' . base64_encode($userName . ':' . $password);
}

function readMcpConfiguration(string $file): object
{
    $configuration = readJsonObject($file);

    if (isset($configuration->mcpServers) && !$configuration->mcpServers instanceof stdClass) {
        fail(sprintf(
            "Error: the 'mcpServers' value in %s must be a JSON object, found %s.\n"
                . "Leaving it unchanged; fix it and try again.\n",
            $file,
            get_debug_type($configuration->mcpServers)
        ));
    }

    if (isset($configuration->mcpServers->maildev) && !$configuration->mcpServers->maildev instanceof stdClass) {
        fail(sprintf(
            "Error: the 'maildev' server in %s must be a JSON object, found %s.\n"
                . "Leaving it unchanged; remove the entry to let the add-on manage it again.\n",
            $file,
            get_debug_type($configuration->mcpServers->maildev)
        ));
    }

    return $configuration;
}

function isMcpConfigurationEmpty(object $configuration): bool
{
    $remainingServers = (array) ($configuration->mcpServers ?? new stdClass());
    $otherProperties = (array) $configuration;
    unset($otherProperties['mcpServers']);

    return $remainingServers === [] && $otherProperties === [];
}

function readJsonObject(string $file): object
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

// DDEV throws ErrorException for filesystem warnings despite @.
function writeJsonAtomically(string $file, object $data): void
{
    $directory = dirname($file);
    $json = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
    $temporaryFile = $directory . '/.mcp-' . bin2hex(random_bytes(8)) . '.tmp';
    $temporaryFileCreated = false;

    try {
        if (!is_dir($directory)) {
            mkdir($directory, 0o755, true);
        }

        // Atomic rename requires the same filesystem.
        $fileHandle = fopen($temporaryFile, 'xb');

        if ($fileHandle === false) {
            throw new RuntimeException(sprintf('no temporary file could be created in %s', $directory));
        }

        $temporaryFileCreated = true;

        // Narrowed before the credential is written, never after. A file the user
        // already had keeps the permissions they chose; one we create is ours.
        chmod($temporaryFile, file_exists($file) ? fileperms($file) & 0o777 : 0o600);

        if (fwrite($fileHandle, $json) !== strlen($json)) {
            throw new RuntimeException('the temporary file could not be written in full');
        }

        fclose($fileHandle);
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
