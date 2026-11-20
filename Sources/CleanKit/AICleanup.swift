import Foundation

/// Sprzątanie śladów narzędzi AI (Claude Code, Codex, Cursor, Claude Desktop, Gemini): cache, stare wersje i stare sesje.
/// Skan tylko czyta. Usuwanie przenosi do Kosza i rusza wyłącznie to, co skan wskazał w katalogu domowym.
public enum AICleanup {
    public enum Kind: String, Sendable { case cache, oldVersions, oldSessions, goneSessions }

    public struct Entry: Identifiable, Equatable, Sendable {
        public var id: URL { url }
        public let url: URL
        public let bytes: Int64
        public let date: Date?
        public var label: String? = nil
    }

    public struct Group: Identifiable, Equatable, Sendable {
        public var id: String { kind.rawValue + ":" + tool }
        public let kind: Kind
        public let tool: String
        public var entries: [Entry]
        public var bytes: Int64 { entries.reduce(0) { $0 + $1.bytes } }
    }

    /// Foldery cache, które narzędzie odtwarza samo: (narzędzie, ścieżka od katalogu domowego).
    static let caches: [(tool: String, path: String)] = [
        ("Claude Code", ".claude/cache"), ("Claude Code", ".claude/paste-cache"), ("Claude Code", ".claude/shell-snapshots"),
        ("Claude Code", ".claude/telemetry"), ("Claude Code", ".claude/image-cache"),
        ("Cursor", "Library/Application Support/Cursor/Cache"), ("Cursor", "Library/Application Support/Cursor/CachedData"),
        ("Cursor", "Library/Application Support/Cursor/Code Cache"), ("Cursor", "Library/Application Support/Cursor/GPUCache"),
        ("Cursor", "Library/Application Support/Cursor/DawnGraphiteCache"), ("Cursor", "Library/Application Support/Cursor/DawnWebGPUCache"),
        ("Cursor", "Library/Application Support/Cursor/CachedExtensionVSIXs"), ("Cursor", "Library/Application Support/Cursor/logs"),
        ("Claude Desktop", "Library/Application Support/Claude/Cache"), ("Claude Desktop", "Library/Application Support/Claude/Code Cache"),
        ("Claude Desktop", "Library/Application Support/Claude/GPUCache"), ("Claude Desktop", "Library/Application Support/Claude/DawnGraphiteCache"),
        ("Codex", "Library/Application Support/Codex/Cache"), ("Codex", "Library/Application Support/Codex/Code Cache"),
        ("Codex", "Library/Application Support/Codex/GPUCache"),
        ("Gemini CLI", ".gemini/tmp"),
    ]

    static func entry(_ url: URL, force: Bool = true) -> Entry? {
        let b = Scanner.size(of: url, force: force)
        guard b > 0 else { return nil }
        return Entry(url: url, bytes: b, date: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)
    }

    /// Katalog roboczy zapisany w sesji (`"cwd":"..."`) szukany w pierwszych 256 KB pliku.
    static func sessionCwd(_ file: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 262_144), let s = String(data: d, encoding: .utf8),
              let r = s.range(of: #""cwd":"([^"\\]*)""#, options: .regularExpression) else { return nil }
        return String(s[r]).dropFirst(7).dropLast().description
    }

    static func mtime(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }

    /// Pliki `.jsonl` sesji (do dwóch poziomów w dół), bez zmodyfikowanych w ostatniej dobie (mogą być w użyciu).
    static func sessionFiles(_ root: URL, now: Date) -> [URL] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let u as URL in e {
            if e.level > 4 { e.skipDescendants(); continue }
            guard u.pathExtension == "jsonl", now.timeIntervalSince(mtime(u)) > 86_400 else { continue }
            out.append(u)
        }
        return out
    }

    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, olderThanDays: Int = 90, now: Date = Date(),
                            protected: [String] = Protected.list()) -> [Group] {
        let fm = FileManager.default
        var groups: [Group] = []
        func keep(_ e: Entry?) -> Entry? { e.flatMap { Protected.contains($0.url, in: protected) ? nil : $0 } }

        // cache
        var byTool: [String: [Entry]] = [:]
        for c in caches {
            let u = home.appending(path: c.path)
            if fm.fileExists(atPath: u.path), let e = keep(entry(u)) { byTool[c.tool, default: []].append(e) }
        }
        for (tool, e) in byTool.sorted(by: { $0.key < $1.key }) { groups.append(Group(kind: .cache, tool: tool, entries: e.sorted { $0.bytes > $1.bytes })) }

        // stare wersje Claude Code: zostaje wersja, na którą wskazuje `claude`, i najnowsza
        let versions = home.appending(path: ".local/share/claude/versions")
        if let vs = try? fm.contentsOfDirectory(at: versions, includingPropertiesForKeys: nil), vs.count > 2 {
            let active = (try? fm.destinationOfSymbolicLink(atPath: home.appending(path: ".local/bin/claude").path)).map { URL(fileURLWithPath: $0).lastPathComponent }
            let newest = vs.max { mtime($0) < mtime($1) }?.lastPathComponent
            let old = vs.filter { $0.lastPathComponent != active && $0.lastPathComponent != newest }.compactMap { keep(entry($0)) }
            if !old.isEmpty { groups.append(Group(kind: .oldVersions, tool: "Claude Code", entries: old.sorted { $0.bytes > $1.bytes })) }
        }

        // sesje: Claude Code (~/.claude/projects) i Codex (~/.codex/sessions)
        let cutoff = now.addingTimeInterval(-Double(olderThanDays) * 86_400)
        for (tool, rel, readCwd) in [("Claude Code", ".claude/projects", true), ("Codex", ".codex/sessions", false)] {
            var old: [Entry] = [], gone: [Entry] = []
            for f in sessionFiles(home.appending(path: rel), now: now) {
                guard let e = keep(entry(f, force: true)) else { continue }
                if readCwd, let cwd = sessionCwd(f), !fm.fileExists(atPath: cwd) { gone.append(e) }
                else if mtime(f) < cutoff { old.append(e) }
            }
            if !old.isEmpty { groups.append(Group(kind: .oldSessions, tool: tool, entries: old.sorted { $0.bytes > $1.bytes })) }
            if !gone.isEmpty { groups.append(Group(kind: .goneSessions, tool: tool, entries: gone.sorted { $0.bytes > $1.bytes })) }
        }
        return groups
    }

    /// Przenosi do Kosza tylko to, co leży w katalogu domowym i nie jest chronione wyjątkiem.
    public static func trash(_ urls: [URL], home: URL = FileManager.default.homeDirectoryForCurrentUser,
                             remove: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> (done: Int, failed: Int, error: String?) {
        let h = home.standardizedFileURL.path + "/"
        let keep = Protected.list()
        var done = 0, failed = 0
        var firstError: String?
        for u in urls {
            guard u.standardizedFileURL.path.hasPrefix(h), !Protected.contains(u, in: keep) else {
                failed += 1; firstError = firstError ?? "\(u.lastPathComponent): outside home or protected"; continue
            }
            do { try remove(u); done += 1 } catch { failed += 1; firstError = firstError ?? "\(u.lastPathComponent): \(error.localizedDescription)" }
        }
        return (done, failed, firstError)
    }
}
