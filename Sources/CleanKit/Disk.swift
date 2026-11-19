import Foundation

public struct Volume: Sendable, Equatable {
    public let total: Int64
    /// Miejsce, które system uzna za dostępne (wolne plus to, co sam zwolni przy potrzebie).
    public let available: Int64
    public var used: Int64 { max(0, total - available) }

    public init(total: Int64, available: Int64) { self.total = total; self.available = available }

    public static func at(_ url: URL) -> Volume? {
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let t = v.volumeTotalCapacity, let a = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return Volume(total: Int64(t), available: a)
    }
}

public enum SliceKind: String, CaseIterable, Sendable {
    case apps = "Aplikacje", documents = "Dokumenty", downloads = "Pobrane", media = "Multimedia"
    case library = "Biblioteka", cache = "Cache i logi", developer = "Narzędzia deweloperskie", repos = "Zależności repozytoriów"
    case trash = "Kosz", otherHome = "Inne w katalogu domowym", system = "System i inne", free = "Wolne"
}

public struct DiskSlice: Identifiable, Sendable, Equatable {
    public let kind: SliceKind
    public let bytes: Int64
    public var id: SliceKind { kind }
    public init(kind: SliceKind, bytes: Int64) { self.kind = kind; self.bytes = bytes }
}

public enum DiskUsage {
    /// Składa podział dysku. `homeChildren`: rozmiary pozycji najwyższego poziomu w katalogu domowym.
    /// Zeskanowane pozycje cache są wyjmowane z folderu, w którym leżą, i liczone osobno, więc nic nie liczy się dwa razy.
    public static func slices(volume: Volume, apps: Int64, homeChildren: [String: Int64], scanned: [Item], home: URL) -> [DiskSlice] {
        var children = homeChildren
        var cache: Int64 = 0, dev: Int64 = 0, repos: Int64 = 0
        let prefix = home.standardizedFileURL.path + "/"
        for item in scanned {
            let p = item.url.standardizedFileURL.path
            if p.hasPrefix(prefix), let top = p.dropFirst(prefix.count).split(separator: "/").first.map(String.init) {
                children[top] = max(0, (children[top] ?? 0) - item.bytes)
            }
            switch item.category { case .developer: dev += item.bytes; case .repos: repos += item.bytes; default: cache += item.bytes }
        }
        func sum(_ names: [String]) -> Int64 { names.reduce(0) { $0 + (children[$1] ?? 0) } }
        let known = ["Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies", "Library", ".Trash"]
        let other = children.filter { !known.contains($0.key) }.values.reduce(0, +)
        var out: [(SliceKind, Int64)] = [
            (.apps, apps), (.documents, sum(["Documents", "Desktop"])), (.downloads, sum(["Downloads"])),
            (.media, sum(["Pictures", "Music", "Movies"])), (.library, sum(["Library"])),
            (.cache, cache), (.developer, dev), (.repos, repos), (.trash, sum([".Trash"])), (.otherHome, other),
        ]
        let counted = out.reduce(0) { $0 + $1.1 }
        out.append((.system, max(0, volume.used - counted)))
        out.append((.free, volume.available))
        return out.filter { $0.1 > 0 }.map { DiskSlice(kind: $0.0, bytes: $0.1) }
    }

    public struct Measured: Sendable {
        public let volume: Volume
        public let apps: Int64
        public let homeChildren: [String: Int64]
    }

    /// Mierzy dysk: aplikacje i pozycje katalogu domowego (równolegle). Podział składa `slices`.
    public static func measure(home: URL) async -> Measured? {
        guard let volume = Volume.at(home) else { return nil }
        let children = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil, options: [])) ?? []
        var sizes: [String: Int64] = [:]
        var apps: Int64 = 0
        await withTaskGroup(of: (String, Int64).self) { group in
            group.addTask { ("/Applications", Scanner.size(of: URL(fileURLWithPath: "/Applications"))) }
            for c in children { group.addTask { (c.lastPathComponent, Scanner.size(of: c)) } }
            for await (name, bytes) in group {
                if name == "/Applications" { apps = bytes } else { sizes[name] = bytes }
            }
        }
        return Measured(volume: volume, apps: apps, homeChildren: sizes)
    }
}

public struct LargeFile: Identifiable, Sendable, Hashable {
    public let url: URL
    public let bytes: Int64
    public var id: URL { url }
}

extension Scanner {
    /// Największe pliki w katalogu domowym (bez ~/Library i Kosza). Tylko do podglądu: aplikacja ich nie usuwa.
    public static func largeFiles(home: URL, minBytes: Int64 = 100_000_000, limit: Int = 60) -> [LargeFile] {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        let skip = [home.appending(path: "Library").standardizedFileURL.path, home.appending(path: ".Trash").standardizedFileURL.path]
        guard let e = FileManager.default.enumerator(at: home, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { return [] }
        var found: [LargeFile] = []
        while let obj = e.nextObject() {
            autoreleasepool {
                guard let f = obj as? URL else { return }
                let p = f.standardizedFileURL.path
                if skip.contains(where: { p == $0 }) || Scanner.isOffLimits(f) { e.skipDescendants(); return }
                guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      let b = v.totalFileAllocatedSize, Int64(b) >= minBytes else { return }
                found.append(LargeFile(url: f, bytes: Int64(b)))
            }
        }
        return Array(found.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }
}
