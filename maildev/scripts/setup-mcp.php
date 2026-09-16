<?php

#ddev-generated

$projectRoot = getenv('DDEV_APPROOT');
$hostname = strtok(getenv('DDEV_HOSTNAME'), ',');

$configuration = [
    'mcpServers' => [
        'maildev' => [
            'type' => 'http',
            'url' => sprintf('https://%s:1081/mcp', $hostname),
        ],
    ],
];

file_put_contents(
    $projectRoot . '/.mcp.json',
    json_encode($configuration, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n"
);
