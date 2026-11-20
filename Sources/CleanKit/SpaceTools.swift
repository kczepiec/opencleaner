import CryptoKit
import Foundation

/// Stare instalatory i archiwa w Pobranych, kopie iOS i lokalne migawki Time Machine.
public enum SpaceTools {
    public struct Group: Identifiable, Equatable, Sendable {
        public let id: String
        public var entries: [AICleanup.Entry]
        public var bytes: Int64 { entries.reduce(0) { $0 + $1.bytes } }
    }

    // MARK: instalatory

    static let installerKinds: [(id: String, exts: Set<String>)] = [
        ("installers", ["dmg", "pkg", "xip", "mpkg"]), ("images", ["iso", "img"]), ("archives", ["zip", "7z", "rar", "tar", "gz", "tgz"]),
    ]

    /// Pliki z najwyższego poziomu Pobranych starsze niż `olderThanDays`.
    public static func installers(home: URL = FileManager.default.homeDirectoryForCurrentUser, olderThanDays: Int = 30, now: Date = Date(),
                                  protected: [String] = Protected.list()) -> [Group] {
        let dir = home.appending(path: "Downloads")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])) ?? []
        let cutoff = now.addingTimeInterval(-Double(olderThanDays) * 86_400)
        return installerKinds.compactMap { kind in
            let e = files.filter { kind.exts.contains($0.pathExtension.lowercased()) && AICleanup.mtime($0) < cutoff && !Protected.contains($0, in: protected) }
                .compactMap { AICleanup.entry($0) }.sorted { $0.bytes > $1.bytes }
            return e.isEmpty ? nil : Group(id: kind.id, entries: e)
        }
    }

    // MARK: kopie iOS

    public struct Backups: Sendable {
        public var groups: [Group] = []
        public var needsAccess = false
        public init(groups: [Group] = [], needsAccess: Bool = false) { self.groups = groups; self.needsAccess = needsAccess }
    }

    /// Foldery kopii urządzeń z `MobileSync/Backup`. Nazwa urządzenia i data z `Info.plist` kopii.
    public static func iosBackups(home: URL = FileManager.default.homeDirectoryForCurrentUser, protected: [String] = Protected.list()) -> Backups {
        let dir = home.appending(path: "Library/Application Support/MobileSync/Backup")
        guard FileManager.default.fileExists(atPath: dir.path) else { return Backups() }
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return Backups(needsAccess: true) }
        var out: [AICleanup.Entry] = []
        for u in items where !u.lastPathComponent.hasPrefix(".") && !Protected.contains(u, in: protected) {
            guard let e = AICleanup.entry(u) else { continue }
            let info = (try? Data(contentsOf: u.appending(path: "Info.plist"))).flatMap { try? PropertySerializationShim.dict($0) }
            let date = (info?["Last Backup Date"] as? Date) ?? e.date
            out.append(AICleanup.Entry(url: u, bytes: e.bytes, date: date, label: info?["Device Name"] as? String))
        }
        return Backups(groups: out.isEmpty ? [] : [Group(id: "ios", entries: out.sorted { $0.bytes > $1.bytes })])
    }

    // MARK: migawki Time Machine

    /// Daty z `tmutil listlocalsnapshots /` (wiersze `com.apple.TimeMachine.2026-11-19-123456.local`).
    public static func parseSnapshots(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { l in
            l.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression).map { String(l[$0]) }
        }
    }

    public static func snapshots() async -> [String] {
        parseSnapshots(await Mole.run(URL(fileURLWithPath: "/usr/bin/tmutil"), ["listlocalsnapshots", "/"]).text)
    }

    /// Usuwa migawki jednym oknem hasła administratora. Daty przechodzą walidację, więc nic innego nie trafi do polecenia.
    public static func deleteSnapshots(_ dates: [String]) async -> Bool {
        let ok = dates.filter { $0.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) != nil }
        guard !ok.isEmpty else { return false }
        let cmd = ok.map { "/usr/bin/tmutil deletelocalsnapshots \($0)" }.joined(separator: "; ")
        return await Mole.run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", "do shell script \"\(cmd)\" with administrator privileges"]).status == 0
    }

    // MARK: duplikaty

    /// Zestawy identycznych plików (rozmiar, potem skrót początku, potem pełny SHA-256). W każdym zestawie pierwszy to najstarszy.
    public static func duplicates(roots: [URL], minBytes: Int64 = 1_000_000, protected: [String] = Protected.list(), limit: Int = 200) -> [Group] {
        var bySize: [Int64: [URL]] = [:]
        for root in roots {
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            for case let u as URL in e {
                autoreleasepool {
                    if Scanner.isOffLimits(u) || Protected.contains(u, in: protected) { e.skipDescendants(); return }
                    guard let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]), v.isRegularFile == true, v.isSymbolicLink != true,
                          let s = v.fileSize, Int64(s) >= minBytes else { return }
                    bySize[Int64(s), default: []].append(u)
                }
            }
        }
        var groups: [Group] = []
        for (size, urls) in bySize where urls.count > 1 {
            var byHead: [String: [URL]] = [:]
            for u in urls { if let h = hash(u, head: true) { byHead[h, default: []].append(u) } }
            for (_, same) in byHead where same.count > 1 {
                var byFull: [String: [URL]] = [:]
                for u in same { if let h = hash(u, head: false) { byFull[h, default: []].append(u) } }
                for (h, dup) in byFull where dup.count > 1 {
                    let es = dup.map { AICleanup.Entry(url: $0, bytes: size, date: AICleanup.mtime($0) == .distantPast ? nil : AICleanup.mtime($0)) }
                        .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
                    groups.append(Group(id: h, entries: es))
                }
            }
        }
        return Array(groups.sorted { $0.bytes - $0.entries[0].bytes > $1.bytes - $1.entries[0].bytes }.prefix(limit))
    }

    static func hash(_ url: URL, head: Bool) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var sha = SHA256()
        if head { guard let d = try? h.read(upToCount: 65_536) else { return nil }; sha.update(data: d) }
        else { while let d = try? h.read(upToCount: 1 << 20), !d.isEmpty { sha.update(data: d) } }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum PropertySerializationShim {
    static func dict(_ d: Data) throws -> [String: Any]? { try PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] }
}

/// Dzienny zapis wolnego miejsca do wykresu na Pulpicie. Plik leży obok `mcp.json`.
public enum SpaceHistory {
    public struct Point: Codable, Equatable, Sendable { public let day: String; public let free: Int64; public let total: Int64 }
    public static var file: URL { MCPConfig.directory.appending(path: "space-history.json") }

    public static func load(file: URL = SpaceHistory.file) -> [Point] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([Point].self, from: $0) } ?? []
    }

    /// Dopisuje (albo nadpisuje) punkt z danego dnia i zostawia ostatnie 365.
    @discardableResult
    public static func record(free: Int64, total: Int64, day: Date = Date(), file: URL = SpaceHistory.file) -> [Point] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        var pts = load(file: file).filter { $0.day != f.string(from: day) }
        pts.append(Point(day: f.string(from: day), free: free, total: total))
        pts = Array(pts.sorted { $0.day < $1.day }.suffix(365))
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(pts).write(to: file, options: .atomic)
        return pts
    }
}
