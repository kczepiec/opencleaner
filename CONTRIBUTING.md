# Contributing to OpenCleaner

Thanks for helping. Small, focused pull requests are easiest to review.

## Setup

```sh
brew install xcodegen
swift test
xcodegen generate
open OpenCleaner.xcodeproj
```

## Ground rules

- **Safety beats features.** Anything that deletes must preview first, ask for confirmation and prefer the Trash. Never run a destructive command in a test.
- **Logic goes in `Sources/CleanKit`** (no UI) with a test in `Tests/CleanKitTests`. Views in `App/` stay thin.
- **Both CLI output parsers and scanners need tests** using sample data, not your own machine.
- **No new dependencies** without discussing it in an issue first.
- **UI** follows the existing dark theme (`App/Theme.swift`, `App/Palette.swift`). Respect Reduce Motion and keep labels accessible.
- **App text is Polish today.** Keep new strings consistent with the surrounding ones; localization is welcome as a separate PR.
- Match the existing code style. Do not reformat unrelated code.

## Pull requests

1. Fork and create a branch from `main`.
2. Make the change, add or update tests, run `swift test`.
3. Describe what changed and how you checked it (screenshots for UI).
4. Keep commits readable. Use imperative messages, for example `Add Bun cache card`.

## Reporting bugs

Use the issue templates. Include macOS version, OpenCleaner version (Settings, About) and, for cleaning problems, the preview output. Security issues go through [SECURITY.md](SECURITY.md), not public issues.
