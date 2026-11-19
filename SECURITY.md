# Security Policy

OpenCleaner can delete files, so safety bugs matter. Examples: deleting outside the documented targets, skipping a confirmation, or the MCP server running a destructive tool without `confirm: true`.

## Reporting

Please do **not** open a public issue. Use GitHub's [private vulnerability reporting](https://github.com/kczepiec/opencleaner/security/advisories/new). Include steps to reproduce, the macOS and app version, and the impact.

You can expect an acknowledgement within a few days. Fixes ship in a new release, which installed apps pick up through the built-in updater.

## Supported versions

Only the latest release is supported.

## Notes

Releases are ad hoc signed and not notarized. The updater downloads over HTTPS from GitHub Releases and does not verify a separate signature.
