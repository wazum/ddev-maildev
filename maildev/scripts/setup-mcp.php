<?php

#ddev-generated

$projectRoot = getenv('DDEV_APPROOT');
$hostname = strtok(getenv('DDEV_HOSTNAME'), ',');

$file = $projectRoot . '/.mcp.json';

$configuration = file_exists($file)
    ? json_decode(file_get_contents($file), true)
    : [];

$configuration['mcpServers']['maildev'] = [
    'type' => 'http',
    'url' => sprintf('https://%s:1081/mcp', $hostname),
];

file_put_contents(
    $file,
    json_encode($configuration, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n"
);
