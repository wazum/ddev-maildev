<?php

#ddev-generated

$projectRoot = getenv('DDEV_APPROOT');
$hostname = strtok(getenv('DDEV_HOSTNAME'), ',');

$file = $projectRoot . '/.mcp.json';

$configuration = [];
$fileExisted = file_exists($file);

if ($fileExisted) {
    try {
        $configuration = json_decode(file_get_contents($file), true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $exception) {
        fwrite(STDERR, sprintf(
            "Error: %s is not valid JSON (%s).\nLeaving it unchanged; fix it and run the install again.\n",
            $file,
            $exception->getMessage()
        ));
        exit(1);
    }
}

$entry = [
    'type' => 'http',
    'url' => sprintf('https://%s:1081/mcp', $hostname),
];

$configuration['mcpServers']['maildev'] = $entry;

file_put_contents(
    $file,
    json_encode($configuration, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n"
);

$stateDirectory = $projectRoot . '/.ddev/maildev';

if (!is_dir($stateDirectory)) {
    mkdir($stateDirectory, 0o755, true);
}

file_put_contents(
    $stateDirectory . '/mcp-state.json',
    json_encode(
        ['entry' => $entry, 'created_file' => !$fileExisted],
        JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES
    ) . "\n"
);
