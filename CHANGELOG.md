# Changelog

All notable changes are listed here. Format based on [Keep a Changelog](https://keepachangelog.com/).

## [1.3] - 2026-11-19

### Changed
- Mole is only mentioned in Settings. Without Mole, cleaning runs on a built-in engine (app caches, logs, Xcode DerivedData, npm cache; permanent delete after confirmation); Optimization, Apps and Status are hidden until Mole is installed.
- Cleaning progress view redesigned: last five steps, a step counter, skeleton rows.

### Fixed
- Auto update no longer uses the rate-limited GitHub API (a limit hit looked like "up to date"). It reads the latest release page and shows an error when the check fails.

## [1.2] - 2026-11-19

### Added
- Light theme and a Light/Dark picker (tiles) in Settings, Appearance. The logo broom adapts to the light background.
- Language select with vector flags (Polski, English). Fixed UI labels are translated; text produced by Mole and CleanKit stays as is for now.

## [1.0] - 2026-11-19

### Added
- Dashboard, cleaning, optimization, app uninstall plans, large files and repositories views.
- Tips: tool caches (npm, Yarn, pnpm, Homebrew, pip, uv, Bun, Cargo, Gradle, CocoaPods, Docker, Xcode), app caches and unused apps.
- Simulators view for Xcode runtimes and devices.
- Menu bar widget, Dock hiding, dark theme.
- Embedded MCP server `opencleaner-mcp` with settings and agent skill.
- Auto update from GitHub Releases.
