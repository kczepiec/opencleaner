# Changelog

All notable changes are listed here. Format based on [Keep a Changelog](https://keepachangelog.com/).

## [1.6] - 2026-11-20

### Added
- Exceptions: folders and files OpenCleaner never offers to delete (Settings, Exceptions; shield button in Large files). Enforced in scans, Large files, Repositories, Tips and the built-in cleaning; the list is shared with the MCP server. Cleaning through Mole is outside this list.

### Changed
- Menu bar popover shows a full status panel: health score, chip, RAM, uptime, CPU, memory (with pressure), disk, swap, network, battery and the top apps by memory, refreshed every 3 s while open. Without Mole only disk and top apps are shown.
- MCP server is English by default: tool descriptions, errors and the bundled SKILL.md.
- All UI strings now follow the language chosen in the app, not the system language.
- Full English translation: texts produced by the library (tips, Docker, messages, system parts) and all messages with values are translated; Mole output stays in Mole's own English. Switching language reloads Tips; results of scans already done refresh on the next scan.

## [1.5] - 2026-11-19

### Changed
- Large files: search box, modified date, Finder and Trash buttons per row (Trash asks first), live "Searching: <folder>" while scanning. The scan now includes ~/Library (Application Support, Caches; iCloud and Trash excluded). Rows are tagged "Cache, safe" or "App data", and the confirmation text differs.
- Analysis, System redesigned: one total with a segmented bar, a clean parts list and measure tiles for protected folders; the duplicate simulators card is replaced by a link to the Simulators tab.

## [1.4] - 2026-11-19

### Added
- Analysis, Login items: programs that start at login (login items and user LaunchAgents) with removal after confirmation; removed agents go to the Trash.

### Changed
- Mole is only mentioned in Settings. Without Mole, cleaning runs on a built-in engine (app caches, logs, Xcode DerivedData, npm cache; permanent delete after confirmation); Optimization, Apps and Status are hidden until Mole is installed.
- Cleaning progress view redesigned: last five steps, a step counter, skeleton rows.

## [1.3] - 2026-11-19

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
