<?php

#ddev-generated

$projectRoot = getenv('DDEV_APPROOT');
$hostname = strtok(getenv('DDEV_HOSTNAME'), ',');

$configurationFile = $projectRoot . '/.mcp.json';
$stateFile = $projectRoot . '/.ddev/maildev/mcp-state.json';

$entry = [
    'type' => 'http',
    'url' => sprintf('https://%s:1081/mcp', $hostname),
];

match ($argv[1] ?? 'install') {
    'install' => install($configurationFile, $stateFile, $entry),
    'remove' => remove($configurationFile, $stateFile),
    default => fail("Usage: setup-mcp.php [install|remove]\n"),
};

function install(string $configurationFile, string $stateFile, array $entry): void
{
    $configurationExisted = file_exists($configurationFile);
    $configuration = $configurationExisted ? readJsonOrFail($configurationFile) : [];
    $state = file_exists($stateFile) ? readJsonOrFail($stateFile) : null;

    $existingEntry = $configuration['mcpServers']['maildev'] ?? null;

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

    if ($existingEntry !== null && $existingEntry != ($state['entry'] ?? null)) {
        fail(sprintf(
            "The 'maildev' MCP server in %s was changed since this add-on wrote it.\n"
                . "Your version has been left unchanged. Delete the entry to let the add-on manage it again.\n",
            $configurationFile
        ));
    }

    $configuration['mcpServers']['maildev'] = $entry;

    writeJson($configurationFile, $configuration);
    writeJson($stateFile, ['entry' => $entry, 'created_file' => !$configurationExisted]);

    printf("Configured the 'maildev' MCP server at %s\n", $entry['url']);
}

function remove(string $configurationFile, string $stateFile): void
{
    if (!file_exists($stateFile)) {
        echo "No add-on owned MCP entry was recorded; leaving .mcp.json alone.\n";

        return;
    }

    $state = readJsonOrFail($stateFile);

    if (file_exists($configurationFile)) {
        $configuration = readJsonOrFail($configurationFile);
        $existingEntry = $configuration['mcpServers']['maildev'] ?? null;

        if ($existingEntry !== null && $existingEntry != ($state['entry'] ?? null)) {
            printf(
                "The 'maildev' MCP server in %s was changed since this add-on wrote it.\n"
                    . "It has been left in place; delete the entry by hand if you no longer want it.\n",
                $configurationFile
            );

            return;
        }

        unset($configuration['mcpServers']['maildev']);

        if (($state['created_file'] ?? false) && holdsNothingElse($configuration)) {
            unlink($configurationFile);
        } else {
            writeJson($configurationFile, $configuration);
        }
    }

    unlink($stateFile);

    echo "Removed the 'maildev' MCP server entry.\n";
}

function holdsNothingElse(array $configuration): bool
{
    $servers = $configuration['mcpServers'] ?? [];
    unset($configuration['mcpServers']);

    return $servers === [] && $configuration === [];
}

function readJsonOrFail(string $file): array
{
    try {
        return json_decode(file_get_contents($file), true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $exception) {
        fail(sprintf(
            "Error: %s is not valid JSON (%s).\nLeaving it unchanged; fix it and try again.\n",
            $file,
            $exception->getMessage()
        ));
    }
}

function writeJson(string $file, array $data): void
{
    $directory = dirname($file);

    if (!is_dir($directory)) {
        mkdir($directory, 0o755, true);
    }

    file_put_contents(
        $file,
        json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n"
    );
}

function fail(string $message): never
{
    fwrite(STDERR, $message);
    exit(1);
}
