# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-09-17

The first release. DDEV already catches mail with Mailpit, so catching mail is not the
point: MailDev 3 answers over the Model Context Protocol, and this add-on wires that up
so a coding agent can read the project's dev inbox instead of you opening a browser and
copying a link out by hand.

### Added

- The `maildev` service, running `maildev/maildev:3.0.0-rc.3` with the MCP server on.
  The web interface is published by the DDEV router on port 1081 over HTTPS, and SMTP
  stays on the Docker network with no host binding.

- PHP's `mail()` goes to MailDev. A generated `.ddev/php/maildev.ini` overrides
  `sendmail_path` to relay through the `mailpit` binary already in the web image, so
  nothing new is installed there. It names the container rather than the compose
  service, because every service also joins the shared `ddev_default` network, where a
  plain `maildev` is ambiguous as soon as a second project installs this add-on.

- `MAILDEV_SMTP_HOST` and `MAILDEV_SMTP_PORT` in the web container, for frameworks that
  speak SMTP themselves and never consult `sendmail_path`. The readme has a line for
  Symfony, Laravel and TYPO3.

- The `maildev` MCP server is merged into the project's `.mcp.json`, which Claude Code
  reads. Other clients keep their own config file and need the entry copied across. The
  add-on records what it wrote in `.ddev/maildev/mcp-state.json`, so removal takes out
  only its own entry and only while that entry still matches. An entry you edited is
  kept, and so is a `.mcp.json` that existed before you installed.

- A password, generated at install into `.ddev/.env.maildev.local` and required by both the
  API and `/mcp`. The `Authorization` header goes into `.mcp.json`, which is created
  readable only by its owner. Missing credentials stop the installation rather than
  configure MailDev without them.

- Captured mail survives `ddev restart` in a named volume. The upstream image has no
  mail directory, so a small derived image creates one the `node` user can write to,
  which a fresh volume then inherits.

- `ddev maildev` opens the inbox.

- Removal takes out the container, the volume and the generated files, and a restart
  returns PHP mail to Mailpit. `.ddev/.env.maildev.local` stays, in case you put your own
  settings in it, and a `maildev.ini` whose `#ddev-generated` marker you removed is
  left alone on both reinstall and removal.

[Unreleased]: https://github.com/wazum/ddev-maildev/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/wazum/ddev-maildev/releases/tag/v1.0.0
