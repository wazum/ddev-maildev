<?php

#ddev-generated

$projectRoot = getenv('DDEV_APPROOT');
$hostname = strtok(getenv('DDEV_HOSTNAME'), ',');

$file = $projectRoot . '/.mcp.json';

$configuration = [];

if (file_exists($file)) {
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

$configuration['mcpServers']['maildev'] = [
    'type' => 'http',
    'url' => sprintf('https://%s:1081/mcp', $hostname),
];

file_put_contents(
    $file,
    json_encode($configuration, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n"
);
