<?php

// Mirrors DDEV's strict-mode preamble: its handler ignores error_reporting(),
// so `@` suppresses nothing. Without this the suite tests a different program.
error_reporting(E_ALL);
ini_set('display_errors', 1);
set_error_handler(function ($severity, $message, $file, $line) {
    throw new ErrorException($message, 0, $severity, $file, $line);
});

$script = $argv[1];

array_splice($argv, 0, 1);
$argc = count($argv);

require $script;
