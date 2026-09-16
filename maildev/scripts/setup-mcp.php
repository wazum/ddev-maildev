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

$configurationExisted = file_exists($configurationFile);
$configuration = $configurationExisted ? readJsonOrFail($configurationFile) : [];
$state = file_exists($stateFile) ? readJsonOrFail($stateFile) : null;

$existingEntry = $configuration['mcpServers']['maildev'] ?? null;

if ($existingEntry !== null && $state === null) {
    if ($existingEntry == $entry) {
        echo "An identical 'maildev' MCP server is already configured; leaving it alone.\n";
        exit(0);
    }

    fail(sprintf(
        "A 'maildev' MCP server this add-on does not own already exists in %s.\n"
            . "Remove or rename it and install again; it has been left unchanged.\n",
        $configurationFile
    ));
}

$configuration['mcpServers']['maildev'] = $entry;

writeJson($configurationFile, $configuration);
writeJson($stateFile, ['entry' => $entry, 'created_file' => !$configurationExisted]);

printf("Configured the 'maildev' MCP server at %s\n", $entry['url']);

function readJsonOrFail(string $file): array
{
    try {
        return json_decode(file_get_contents($file), true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $exception) {
        fail(sprintf(
            "Error: %s is not valid JSON (%s).\nLeaving it unchanged; fix it and install again.\n",
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
