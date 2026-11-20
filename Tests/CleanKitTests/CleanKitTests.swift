import Foundation
import Testing
@testable import CleanKit

private func sandbox() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appending(path: "cleankit-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private func write(_ url: URL, bytes: Int) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(count: bytes).write(to: url)
}

@Test func scanListsChildrenBySizeAndSkipsEmpty() throws {
    let home = try sandbox(); defer { try? FileManager.default.removeItem(at: home) }
    try write(home.appending(path: "Library/Caches/big/a.bin"), bytes: 200_000)
    try write(home.appending(path: "Library/Caches/small/a.bin"), bytes: 20_000)
    try FileManager.default.createDirectory(at: home.appending(path: "Library/Caches/empty"), withIntermediateDirectories: true)
    let items = Scanner.scan(Scanner.locations(home: home))
    #expect(items.map(\.name) == ["big", "small"])
    #expect(items[0].bytes >= 200_000 && items[0].preselected)
}

@Test func symlinkIsNotFollowedWhenSizing() throws {
    let home = try sandbox(); defer { try? FileManager.default.removeItem(at: home) }
    let outside = try sandbox(); defer { try? FileManager.default.removeItem(at: outside) }
    try write(outside.appending(path: "huge.bin"), bytes: 5_000_000)
    let dir = home.appending(path: "Library/Caches/app")
    try write(dir.appending(path: "x.bin"), bytes: 10_000)
    try FileManager.default.createSymbolicLink(at: dir.appending(path: "link"), withDestinationURL: outside)
    #expect(Scanner.size(of: dir) < 1_000_000)
}

@Test func cleanerRefusesPathsOutsideAllowedLocations() throws {
    let home = try sandbox(); defer { try? FileManager.default.removeItem(at: home) }
    let precious = home.appending(path: "Documents/keep.txt")
    try write(precious, bytes: 100)
    try write(home.appending(path: "Library/Caches/app/x.bin"), bytes: 100)
    let locs = Scanner.locations(home: home)
    let rogue = Item(url: precious, category: .caches, bytes: 100, preselected: true)
    let root = Item(url: home.appending(path: "Library/Caches"), category: .caches, bytes: 1, preselected: true)
    let r = Cleaner.trash([rogue, root], within: locs, remove: { _ in Issue.record("nie powinno usuwać") })
    #expect(r.failures.count == 2 && r.freed == 0)
    #expect(FileManager.default.fileExists(atPath: precious.path))
    #expect(FileManager.default.fileExists(atPath: home.appending(path: "Library/Caches").path))
}

@Test func cleanerTrashesAllowedItem() throws {
    let home = try sandbox(); defer { try? FileManager.default.removeItem(at: home) }
    let target = home.appending(path: "Library/Caches/app")
    try write(target.appending(path: "x.bin"), bytes: 50_000)
    let item = try #require(Scanner.scan(Scanner.locations(home: home)).first)
    var removed: [URL] = []   // test nie dotyka prawdziwego Kosza
    let r = Cleaner.trash([item], within: Scanner.locations(home: home), remove: { removed.append($0) })
    #expect(r.failures.isEmpty && r.freed == item.bytes)
    #expect(removed.map(\.lastPathComponent) == ["app"])
}

@Test func singleItemLocationMayBeTrashedItself() throws {
    let home = try sandbox(); defer { try? FileManager.default.removeItem(at: home) }
    try write(home.appending(path: ".npm/_cacache/a.bin"), bytes: 30_000)
    let locs = Scanner.locations(home: home)
    let item = try #require(Scanner.scan(locs).first { $0.url.lastPathComponent == "_cacache" })
    #expect(item.name == "npm")
    #expect(Cleaner.allowed(item.url, in: locs))
}

@Test func slicesDoNotDoubleCountScannedItemsAndSumToVolume() {
    let home = URL(fileURLWithPath: "/Users/t")
    let cacheItem = Item(url: home.appending(path: "Library/Caches/app"), category: .caches, bytes: 300, preselected: true)
    let devItem = Item(url: home.appending(path: ".npm/_cacache"), category: .developer, bytes: 50, preselected: true)
    let vol = Volume(total: 1000, available: 400)
    let s = DiskUsage.slices(volume: vol, apps: 100, homeChildren: ["Library": 500, "Documents": 20, ".npm": 50, "Downloads": 10, "stuff": 5],
                             scanned: [cacheItem, devItem], home: home)
    func b(_ k: SliceKind) -> Int64 { s.first { $0.kind == k }?.bytes ?? 0 }
    #expect(b(.library) == 200 && b(.cache) == 300 && b(.developer) == 50)
    #expect(b(.otherHome) == 5 && b(.apps) == 100 && b(.free) == 400)
    // 100+20+10+200+300+50+5 = 685 > used 600, więc system = 0; razem z wolnym: 1085.
    #expect(s.reduce(0) { $0 + $1.bytes } == 685 + 400)
    #expect(b(.system) == 0)
}

@Test func largeFilesIncludeLibraryClassifyKindAndSkipICloud() throws {
    let home = try sandbox(); defer { try? FileManager.default.removeItem(at: home) }
    try write(home.appending(path: "Movies/big.bin"), bytes: 3_000_000)
    try write(home.appending(path: "Movies/small.bin"), bytes: 1_000)
    try write(home.appending(path: "Library/Caches/huge.bin"), bytes: 5_000_000)
    try write(home.appending(path: "Library/Application Support/App/db.bin"), bytes: 4_000_000)
    try write(home.appending(path: "Library/Mobile Documents/cloud.bin"), bytes: 6_000_000)
    let r = Scanner.largeFiles(home: home, minBytes: 1_000_000)
    #expect(r.allSatisfy { $0.modified != nil })
    #expect(r.map { $0.url.lastPathComponent } == ["huge.bin", "db.bin", "big.bin"])
    #expect(r.map(\.kind) == [.cache, .appData, .other])
}

private func git(_ args: [String], in dir: URL) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-C", dir.path] + args
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    try p.run(); p.waitUntilExit()
}

@Test func reposFindsOnlyIgnoredArtifactsWithManifestAndReportsIdleDays() async throws {
    let home = try sandbox(); defer { try? FileManager.default.removeItem(at: home) }
    let repo = home.appending(path: "Sites/app")
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    try git(["init", "-q"], in: repo)
    try write(repo.appending(path: "package.json"), bytes: 10)
    try Data("node_modules/\n".utf8).write(to: repo.appending(path: ".gitignore"))
    try write(repo.appending(path: "node_modules/x/a.bin"), bytes: 200_000)
    try write(repo.appending(path: "build/out.bin"), bytes: 100_000)          // nie ignorowany przez git: zostaje
    let loose = home.appending(path: "Sites/notrepo")                        // poza repozytorium: zostaje
    try write(loose.appending(path: "package.json"), bytes: 10)
    try write(loose.appending(path: "node_modules/y/b.bin"), bytes: 200_000)
    let old = Date().addingTimeInterval(-100 * 86_400)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: repo.appending(path: ".git/HEAD").path)
    let items = await Repos.scan(home: home)
    #expect(items.map(\.name) == ["node_modules"])
    #expect(items[0].repo?.lastPathComponent == "app")
    #expect((items[0].idleDays ?? 0) >= 99 && items[0].preselected)
}

@Test func reposSkipsArtifactWithoutManifest() async throws {
    let home = try sandbox(); defer { try? FileManager.default.removeItem(at: home) }
    let repo = home.appending(path: "r")
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    try git(["init", "-q"], in: repo)
    try Data("node_modules/\n".utf8).write(to: repo.appending(path: ".gitignore"))
    try write(repo.appending(path: "node_modules/x.bin"), bytes: 200_000)    // brak package.json
    #expect(await Repos.scan(home: home).isEmpty)
}

@Test func photosLibraryIsNeverEntered() throws {
    let home = try sandbox(); defer { try? FileManager.default.removeItem(at: home) }
    let lib = home.appending(path: "Pictures/Photos Library.photoslibrary")
    try write(lib.appending(path: "originals/a.heic"), bytes: 2_000_000)
    #expect(Scanner.isOffLimits(lib))
    #expect(Scanner.size(of: lib) == 0)
    #expect(Scanner.size(of: home.appending(path: "Pictures")) == 0)
    #expect(Scanner.largeFiles(home: home, minBytes: 1_000_000).isEmpty)
}

@Test func picturesFolderIsOffLimitsButOtherFoldersAreNot() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    #expect(Scanner.isOffLimits(home.appending(path: "Pictures")))
    #expect(Scanner.isOffLimits(home.appending(path: "Music")))
    #expect(Scanner.isOffLimits(home.appending(path: "Movies")))
    #expect(Scanner.isOffLimits(home.appending(path: "Desktop")))
    #expect(!Scanner.isOffLimits(home.appending(path: "Documents")))
    #expect(!Scanner.isOffLimits(home.appending(path: "Sites/Pictures")))
}

@Test func moleParsesCleanPreviewGroupsEntriesAndNotes() {
    let text = """
    Clean Your Mac
    ◎ System caches need sudo, run sudo -v && mo clean --dry-run for full preview
    ➤ User essentials
      → User app cache · 4 items, 122.5MB dry
      → Trash · would empty, 1 items
    ➤ Browsers
      → Chrome cache · 69.4MB dry
      → Chrome Service Worker, would clean 62.9MB, 0 protected
    ➤ Cloud & Office
      ✓ Nothing to clean
    ➤ Developer tools
      → npm cache · would clean
    """
    let p = Mole.parse(text)
    #expect(p.groups.map(\.title) == ["User essentials", "Browsers", "Cloud & Office", "Developer tools"])
    #expect(p.groups[0].entries[0].name == "User app cache" && p.groups[0].entries[0].bytes == 122_500_000)
    #expect(p.groups[0].entries[1].bytes == nil)
    #expect(p.groups[1].entries[1].name == "Chrome Service Worker" && p.groups[1].entries[1].bytes == 62_900_000)
    #expect(p.groups[2].nothing)
    #expect(p.bytes == 122_500_000 + 69_400_000 + 62_900_000)
    #expect(p.notes.count == 1)
}

@Test func moleStripsAnsiAndParsesJson() {
    #expect(Mole.strip("\u{1B}[32m→ ok\u{1B}[0m") == "→ ok")
    let apps = Mole.parseApps("noise\n[{\"name\":\"Claude\",\"uninstall_name\":\"Claude\",\"path\":\"/Applications/Claude.app\",\"size\":\"656.2MB\"}]")
    #expect(apps.count == 1 && apps[0].path == "/Applications/Claude.app")
    let st = Mole.parseStatus(#"{"health_score":93,"health_score_msg":"Excellent","cpu":{"usage":26.3,"core_count":10},"memory":{"used":8,"total":16,"swap_used":2},"uptime":"3d","hardware":{"model":"MacBook Air","cpu_model":"Apple M4","os_version":"macOS"},"procs":5}"#)
    #expect(st?.health == 93 && st?.cores == 10 && st?.memTotal == 16 && st?.chip == "Apple M4")
}

@Test func moleOptimizeReportIsStructuredAndLocalized() {
    let text = """
    Optimize
    Performance diagnosis
      ◎ Likely bottleneck: WindowServer (~37.6% CPU sustained)
      ⊙ Desktop composition is busy.
      ◎ Memory pressure: swap 9.45GB of 10.74GB used (88%), 52% free
        Czysto                      2.03GB
        RobloxPlayer                476.8MB
    ➤ Finder Cache Refresh
      → QuickLook thumbnails refreshed
    ➤ Network Stack Refresh
      → Network stack already optimal
    ➤ Database Optimization
      ◎ Close these apps before database optimization: Mail Messages
    ➤ Disk Health
      → Disk verify skipped
    Would apply 2 optimizations
    12 unchanged | 3 skipped | 1 unavailable | 1 need attention
    """
    let r = Mole.parseOptimize(text)
    #expect(r.findings.count == 2 && r.findings[0].contains("WindowServer") && r.findings[1].hasPrefix("Presja pamięci"))
    #expect(r.processes.map(\.name) == ["Czysto", "RobloxPlayer"] && r.processes[0].bytes == 2_030_000_000)
    #expect(r.steps.map(\.title) == ["Odświeżenie cache Findera", "Odświeżenie stosu sieciowego", "Optymalizacja baz danych", "Zdrowie dysku"])
    #expect(r.steps.map(\.status) == [.apply, .ok, .attention, .skipped])
    #expect(r.steps[2].notes == ["Zamknij przed optymalizacją baz danych: Mail Messages"])
    #expect(r.toApply == 2 && r.unchanged == 12 && r.skipped == 3 && r.unavailable == 1 && r.attention == 1)
}

@Test func moleUninstallPlanAndSystemProbesParse() {
    let plan = Mole.parseUninstallPlan("""
    ◎ Matched 1 app(s):
    1. Claude Code URL Handler  4KB  |  Last: 3w ago
    Files to be removed:
    ◎ Claude Code URL Handler , 4KB
      ✓ ~/Applications/Claude Code URL Handler.app , 4KB
    """)
    #expect(plan.count == 1 && plan[0].lastUsed == "3 tyg. temu" && plan[0].files.count == 1)
    #expect(plan[0].files[0].path.hasSuffix("/Applications/Claude Code URL Handler.app") && !plan[0].files[0].path.hasPrefix("~"))
    let rt = SystemInfo.parseRuntimes("== Disk Images ==\n-- iOS --\niOS 27.2 (24B8117) - 28AF4373-F89E-4FC7-8323-83C13C3794E3 (Ready)\nTotal Disk Images: 1 (9G)")
    #expect(rt.count == 1 && rt[0].name == "iOS 27.2 (24B8117)")
}

@Test func moleHistoryVersionAndMemoryGroupingParse() {
    let h = Mole.parseHistory(#"{"sessions":[{"command":"clean","run_id":"r1","started_at":"2026-11-19 21:20:35","items":55,"size":"1.25GB"},{"command":"clean-dry-run","run_id":"","started_at":"2026-11-19 21:19:53","items":54,"size":"1.25GB"}]}"#)
    #expect(h.count == 2 && h[0].command == "Czyszczenie" && !h[0].dryRun && h[1].dryRun && h[1].id == "2026-11-19 21:19:53clean-dry-run")
    #expect(Mole.parseVersion("Mole version 1.65.0\nmacOS: 27.2.1") == "1.65.0")
    let ps = """
     204800 /Applications/OpenBot.app/Contents/MacOS/OpenBot
     102400 /Applications/OpenBot.app/Contents/Frameworks/OpenBot Helper (Renderer).app/Contents/MacOS/OpenBot Helper (Renderer)
      51200 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
       9999 /usr/sbin/WindowServer
    """
    let apps = SystemInfo.parseProcesses(ps)
    #expect(apps.map(\.name) == ["OpenBot", "Google Chrome"] && apps[0].bytes == (204800 + 102400) * 1024)
}

@Test func polishPluralsAndHealthLabels() {
    #expect(Mole.plItems(1) == "1 pozycja" && Mole.plItems(3) == "3 pozycje" && Mole.plItems(5) == "5 pozycji")
    #expect(Mole.plItems(12) == "12 pozycji" && Mole.plItems(22) == "22 pozycje" && Mole.plItems(0) == "0 pozycji")
    #expect(Mole.plHealth("Excellent") == "Doskonałe" && Mole.plHealth("Excellent: Memory Pressure") == "Doskonałe" && Mole.plHealth("Whatever") == "Whatever")
}

@Test func plUnitsUsesPolishDecimalsAndSpaces() {
    #expect(Mole.plUnits("swap 8.35GB z 9.66GB") == "swap 8,35 GB z 9,66 GB")
    #expect(Mole.plUnits("602KB") == "602 KB")
    #expect(Mole.plUnits("bez liczb") == "bez liczb")
}

@Test func moleVersionComparisonIsNumeric() {
    #expect(Mole.normalizeVersion("V1.73.0") == "1.73.0")
    #expect(Mole.isNewer("1.74.0", than: "1.73.0") && Mole.isNewer("V1.73.1", than: "1.73.0") && Mole.isNewer("1.10", than: "1.9"))
    #expect(!Mole.isNewer("1.73.0", than: "1.73.0") && !Mole.isNewer("1.9", than: "1.10") && !Mole.isNewer("1.72.9", than: "1.73.0"))
}

private func mcpConfig(_ c: MCPConfig) throws -> URL {
    let u = FileManager.default.temporaryDirectory.appending(path: "mcp-\(UUID().uuidString).json")
    try c.save(to: u); return u
}

@Test func mcpHandshakeToolsListAndGating() async throws {
    var c = MCPConfig()
    let url = try mcpConfig(c); defer { try? FileManager.default.removeItem(at: url) }
    let s = MCPServer(configURL: url)
    let initR = try #require(await s.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#))
    #expect(initR.contains("\"protocolVersion\":\"2025-03-26\"") && initR.contains("opencleaner"))
    #expect(await s.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    let list = try #require(await s.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
    #expect(list.contains("disk_usage") && list.contains("clean_preview") && !list.contains("clean_run") && !list.contains("optimize_run"))
    // destrukcyjne tylko po włączeniu
    c.allowDestructive = true; try c.save(to: url)
    let list2 = try #require(await s.handle(#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#))
    #expect(list2.contains("clean_run") && list2.contains("optimize_run"))
    // wyłączone narzędzie znika
    c.disabledTools = ["disk_usage"]; try c.save(to: url)
    let list3 = try #require(await s.handle(#"{"jsonrpc":"2.0","id":4,"method":"tools/list"}"#))
    #expect(!list3.contains("disk_usage"))
}

@Test func mcpRefusesDisabledUnknownAndUnconfirmedCalls() async throws {
    var c = MCPConfig()
    let url = try mcpConfig(c); defer { try? FileManager.default.removeItem(at: url) }
    let s = MCPServer(configURL: url)
    let denied = try #require(await s.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"clean_run","arguments":{"confirm":true}}}"#))
    #expect(denied.contains("\"isError\":true") && denied.contains("disabled"))
    let unknown = try #require(await s.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"nope"}}"#))
    #expect(unknown.contains("\"isError\":true"))
    c.allowDestructive = true; try c.save(to: url)
    let unconfirmed = try #require(await s.handle(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"clean_run","arguments":{}}}"#))
    #expect(unconfirmed.contains("Refused"))
    c.enabled = false; try c.save(to: url)
    let off = try #require(await s.handle(#"{"jsonrpc":"2.0","id":4,"method":"tools/list"}"#))
    #expect(!off.contains("disk_usage"))
    let bad = try #require(await s.handle("to nie jest json"))
    #expect(bad.contains("-32700"))
}

@Test func mcpDiskUsageToolReturnsRealNumbers() async throws {
    let url = try mcpConfig(MCPConfig()); defer { try? FileManager.default.removeItem(at: url) }
    let r = try #require(await MCPServer(configURL: url).handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"disk_usage"}}"#))
    #expect(r.contains("available_bytes") && r.contains("\"isError\":false"))
}

@Test func tipsParseDockerSizesAndDf() {
    #expect(Tips.parseBytes("1.2GB (45%)") == 1_200_000_000)
    #expect(Tips.parseBytes("512MB") == 512_000_000)
    #expect(Tips.parseBytes("3.5kB") == 3_500)
    #expect(Tips.parseBytes("0B") == 0)
    #expect(Tips.parseBytes("nic") == nil)
    let df = """
    {"Active":"3","Reclaimable":"2.1GB (60%)","Size":"3.5GB","TotalCount":"9","Type":"Images"}
    {"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Containers"}
    {"Active":"0","Reclaimable":"800MB","Size":"800MB","TotalCount":"12","Type":"Build Cache"}
    """
    let p = Tips.parseDockerDF(df)
    #expect(p.count == 3)
    #expect(p.reduce(Int64(0)) { $0 + $1.reclaimable } == 2_900_000_000)
}

@Test func tipsUnusedAppsRespectsThresholdAndSkipsNonApps() throws {
    let d = try sandbox(); defer { try? FileManager.default.removeItem(at: d) }
    try FileManager.default.createDirectory(at: d.appending(path: "Stara.app"), withIntermediateDirectories: true)
    try Data(count: 4096).write(to: d.appending(path: "Stara.app/x"))
    try Data(count: 10).write(to: d.appending(path: "notatka.txt"))
    // Świeżo utworzona aplikacja (data dodania dziś) nie jest "nieużywana od 90 dni".
    #expect(Tips.unusedApps(minDays: 90, roots: [d]).isEmpty)
    // Z progiem 0 dni pojawia się, a plik nie-aplikacja nie.
    let all = Tips.unusedApps(minDays: 0, roots: [d])
    #expect(all.map(\.name).contains("Stara") && all.count <= 1)
}

@Test func tipsFindsExecutableAndTrashActionStaysInHome() async {
    #expect(Tips.find("env") != nil)
    #expect(Tips.find("na-pewno-nie-ma-takiego-programu") == nil)
    let r = await Tips.run(.trash([URL(fileURLWithPath: "/etc/hosts")]))
    #expect(r.ok == false)
}

@Test func simulatorsParseRuntimesDevicesAndPlatforms() {
    #expect(Simulators.platformName("com.apple.CoreSimulator.SimRuntime.iOS-26-5") == "iOS 26.5")
    #expect(Simulators.platformName("com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4") == "iOS 27.2")
    #expect(Simulators.platformName("com.apple.CoreSimulator.SimRuntime.watchOS-27-2") == "watchOS 27.2")
    let rt = #"{"A":{"build":"23F73","deletable":true,"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-5","version":"26.5"},"B":{"build":"24B9","deletable":true,"runtimeIdentifier":"x.iOS-27-2","version":"27.2","sizeBytes":8338867041}}"#
    let r = Simulators.parseRuntimes(rt)
    #expect(r.map(\.name) == ["iOS 27.2 (24B9)", "iOS 26.5 (23F73)"])
    #expect(r[0].bytes == 8_338_867_041 && r[1].bytes == nil)
    let dv = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[{"udid":"U1","name":"iPhone 17","state":"Shutdown","isAvailable":false,"dataPathSize":100}],"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"udid":"U2","name":"iPad","state":"Booted","isAvailable":true,"dataPathSize":200}]}}"#
    let d = Simulators.parseDevices(dv)
    #expect(d.count == 2 && d[0].udid == "U2" && d[0].booted && !d[1].available && d[1].bytes == 100)
    #expect(Simulators.parseRuntimes("brak json").isEmpty && Simulators.parseDevices("").isEmpty)
}

@Test func appUpdateVersionsAndRelease() {
    #expect(AppUpdates.isNewer("1.10", than: "1.9"))
    #expect(AppUpdates.isNewer("1.0.1", than: "1.0"))
    #expect(!AppUpdates.isNewer("1.0", than: "1.0.0"))
    let r = AppUpdates.release(fromLatestURL: URL(string: "https://github.com/kczepiec/opencleaner/releases/tag/v1.2")!)
    #expect(r?.version == "1.2")
    #expect(r?.zipURL.absoluteString == "https://github.com/kczepiec/opencleaner/releases/download/v1.2/OpenCleaner-1.2.zip")
    #expect(AppUpdates.release(fromLatestURL: URL(string: "https://github.com/kczepiec/opencleaner/releases")!) == nil)
}

@Test func nativeCleanScansAndDeletesOnlyWhitelisted() throws {
    let home = try sandbox()
    try write(home.appending(path: "Library/Caches/foo/a.bin"), bytes: 4000)
    try write(home.appending(path: "Library/Caches/com.apple.bar/b.bin"), bytes: 4000)
    try write(home.appending(path: "Library/Logs/x.log"), bytes: 2000)
    try write(home.appending(path: "Documents/keep.txt"), bytes: 100)
    let p = NativeClean.scan(home: home)
    #expect(p.groups.map(\.title) == ["App caches", "Logs"])
    #expect(p.groups.first?.entries.map(\.name) == ["foo"])
    NativeClean.run(home: home)
    let fm = FileManager.default
    #expect(!fm.fileExists(atPath: home.appending(path: "Library/Caches/foo").path))
    #expect(!fm.fileExists(atPath: home.appending(path: "Library/Logs/x.log").path))
    #expect(fm.fileExists(atPath: home.appending(path: "Library/Caches/com.apple.bar/b.bin").path))
    #expect(fm.fileExists(atPath: home.appending(path: "Documents/keep.txt").path))
}

@Test func loginItemsParseAndLaunchAgents() throws {
    let items = LoginItems.parseLoginItems("Slack\t/Applications/Slack.app\nRaycast\t/Applications/Raycast.app\n")
    #expect(items.map(\.name) == ["Slack", "Raycast"])
    let dir = try sandbox()
    func agent(_ file: String, _ d: [String: Any]) throws {
        try PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0).write(to: dir.appending(path: file))
    }
    try agent("a.plist", ["Label": "com.x.helper", "ProgramArguments": ["/Applications/X.app/Contents/MacOS/Xhelper"], "RunAtLoad": true])
    try agent("b.plist", ["Label": "com.apple.thing", "RunAtLoad": true])
    try agent("c.plist", ["Label": "com.y.off", "RunAtLoad": true, "Disabled": true])
    try agent("d.plist", ["Label": "com.z.manual", "RunAtLoad": false])
    let found = LoginItems.launchAgents(in: dir)
    #expect(found.map(\.name) == ["Xhelper"])
}

@Test func protectedPathsAreSkippedByScansAndMatchAncestors() throws {
    let home = try sandbox(); defer { try? FileManager.default.removeItem(at: home) }
    try write(home.appending(path: "Keep/big.bin"), bytes: 3_000_000)
    try write(home.appending(path: "Other/big2.bin"), bytes: 3_000_000)
    try write(home.appending(path: "Library/Caches/safe/a.bin"), bytes: 4000)
    try write(home.appending(path: "Library/Caches/mine/a.bin"), bytes: 4000)
    let keep = [home.appending(path: "Keep").standardizedFileURL.path, home.appending(path: "Library/Caches/mine").standardizedFileURL.path]
    #expect(Scanner.largeFiles(home: home, minBytes: 1_000_000, protected: keep).map { $0.url.lastPathComponent } == ["big2.bin"])
    #expect(NativeClean.targets(home, protected: keep).map { $0.url.lastPathComponent } == ["safe"])
    #expect(Protected.contains(home.appending(path: "Library/Caches"), in: keep))  // rodzic chronionego
    #expect(!Protected.contains(home.appending(path: "Other"), in: keep))
    let f = home.appending(path: "p.txt"); Protected.save(keep, file: f)
    #expect(Protected.list(file: f) == keep)
}

@Test func moleStatusParsesGpuNetworkAndBattery() throws {
    let json = #"{"health_score":88,"health_score_msg":"Excellent: x","uptime":"9h","procs":5,"hardware":{"model":"Mac","cpu_model":"M4","os_version":"macOS 27"},"cpu":{"usage":14.4,"core_count":10,"load1":4.5},"gpu":[{"core_count":10}],"memory":{"used":8,"total":16,"swap_used":1,"swap_total":2,"pressure":"warn"},"network":[{"rx_rate_mbs":1.5,"tx_rate_mbs":0.5},{"rx_rate_mbs":0.5,"tx_rate_mbs":0.0}],"batteries":[{"percent":42,"status":"discharging","time_left":"3:15","health":"Good","cycle_count":277}]}"#
    let s = try #require(Mole.parseStatus(json))
    #expect(s.gpuCores == 10 && s.pressure == "warn" && s.load1 == 4.5)
    #expect(s.netDown == 2.0 && s.netUp == 0.5)
    #expect(s.battery == Mole.Battery(percent: 42, status: "discharging", timeLeft: "3:15", health: "Good", cycles: 277))
    #expect(Mole.parseStatus(#"{"health_score":1}"#)?.battery == nil)
}
