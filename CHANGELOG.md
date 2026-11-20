# Changelog

All notable changes are listed here. Format based on [Keep a Changelog](https://keepachangelog.com/).

## [1.8] - 2026-11-20

### Added
- Photos: a new view in the side rail that reads the Photos library through PhotoKit (never through the library package files) and sorts it into screenshots, screen recordings, TikTok and other downloaded videos, messenger images, GIFs and duplicates. Thumbnail grid, selection (favorites are never selected by "select all"), and removal to Recently Deleted in the Photos app (30 days, reversible). Also: "From the internet (probable)", large videos (over 100 MB) and an "All" view; sort by newest or largest; hovering a thumbnail shows the original file name. TikTok detection uses only service-specific names and ids, so ordinary phone videos are not caught; screenshots and screen recordings are also recognized by file name (Mac screenshots). Duplicates need the same dimensions, creation time and file size; the oldest copy stays.
- Analysis, Duplicates: a Photos mode that finds identical image files (including RAW) in the Pictures folder outside the Photos app library, with thumbnails. The Photos library itself is never entered; the view points to the built-in Duplicates album of the Photos app.

### Changed
- The "protect from cleaning" shield is now available in Duplicates, Installers, AI cleanup and Repositories, not only in Large files. Protected items disappear from all lists at once.
- Repositories shows "Nothing unused" instead of "0 KB" when no repository is idle for the chosen period.

## [1.7] - 2026-11-20

### Added
- Analysis, Installers: old .dmg/.pkg/.iso/archives in Downloads (older than N days), to the Trash.
- Analysis, Duplicates: identical files in Documents and Downloads (size, head hash, SHA-256); the oldest copy of each set stays and the last copy can never be selected.
- Analysis, Backups and snapshots: iOS device backups (to the Trash) and local Time Machine snapshots (removal needs the administrator password).
- Free space history: one point per day and a chart on the Dashboard.
- Reminders: optional weekly, biweekly or monthly notification when at least 1 GB of caches can be recovered (needs OpenCleaner running; removes nothing).

### Changed
- Uninstalling an app now also removes its leftovers in ~/Library (Application Support, Caches, Preferences, Containers, Group Containers, logs and more), listed with checkboxes; everything goes to the Trash. The app detail view is redesigned.
- Custom icon set for the side rail (one grid, one stroke weight).
- Consistent outline icons in the side rail (Cleaning and Analysis icons replaced); moving files to the Trash falls back to Finder when macOS denies direct access (fixes "no permission" on old files in Documents).

## [1.6] - 2026-11-20

### Added
- Analysis, AI cleanup: caches (Claude Code, Claude Desktop, Cursor, Codex, Gemini), old Claude Code versions and old or orphaned sessions (Claude Code, Codex) with checkboxes and a Move to Trash button. Sessions of projects that no longer exist and sessions older than N days are found; sessions touched in the last day are never listed. Only caches and old versions are preselected.
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
