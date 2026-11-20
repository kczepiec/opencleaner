cask "opencleaner" do
  version "1.8"
  sha256 "25177afd9835ab4afa6dd3e8f206221c4fabfe3515fa51a66f0543ea1420fe2f"

  url "https://github.com/kczepiec/opencleaner/releases/download/v#{version}/OpenCleaner-#{version}.zip"
  name "OpenCleaner"
  desc "Native cleaner and system monitor with an MCP server for AI agents"
  homepage "https://github.com/kczepiec/opencleaner"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The app updates itself from GitHub Releases, so brew must not fight it.
  auto_updates true
  depends_on macos: :sonoma

  app "OpenCleaner.app"

  # Releases are ad hoc signed and not notarized, so macOS would block the quarantined download.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/OpenCleaner.app"]
  end

  zap trash: [
    "~/.claude/skills/opencleaner",
    "~/Library/Application Support/OpenCleaner",
    "~/Library/Caches/pl.kc.cachecleaner",
    "~/Library/Preferences/pl.kc.cachecleaner.plist",
    "~/Library/Saved Application State/pl.kc.cachecleaner.savedState",
  ]

  caveats <<~EOS
    OpenCleaner is ad hoc signed and not notarized. This cask removes the quarantine flag,
    so it opens without the "unidentified developer" prompt.
  EOS
end
