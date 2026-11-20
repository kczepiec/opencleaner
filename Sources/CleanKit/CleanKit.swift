import Foundation

public enum Category: String, CaseIterable, Sendable {
    case caches = "Pamięć podręczna aplikacji"
    case logs = "Logi"
    case developer = "Narzędzia deweloperskie"
    case repos = "Nieużywane repozytoria"
}

public struct Item: Identifiable, Hashable, Sendable {
    public let url: URL
    public let category: Category
    public let bytes: Int64
    /// Zaznaczone domyślnie: tylko rzeczy, które system lub narzędzie odtworzy samo i szybko.
    public let preselected: Bool
    /// Czytelna nazwa, gdy nazwa folderu nic nie mówi (np. `uv` zamiast `.cache/uv`).
    public var title: String? = nil
    /// Dla zależności z repozytoriów: folder repozytorium i liczba dni bez aktywności w git.
    public var repo: URL? = nil
    public var idleDays: Int? = nil
    public var id: URL { url }
    public var name: String { title ?? url.lastPathComponent }
}

public struct Location: Sendable {
    public let url: URL
    public let category: Category
    /// true: każdy element folderu to osobna pozycja; false: cały folder to jedna pozycja.
    public let perChild: Bool
    public let preselected: Bool
    public var title: String? = nil

    public init(url: URL, category: Category, perChild: Bool, preselected: Bool, title: String? = nil) {
        self.url = url; self.category = category; self.perChild = perChild; self.preselected = preselected; self.title = title
    }
}

public enum Scanner {
    public static func locations(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Location] {
        func loc(_ p: String, _ c: Category, perChild: Bool = true, pre: Bool = true, title: String? = nil) -> Location {
            Location(url: home.appending(path: p), category: c, perChild: perChild, preselected: pre, title: title)
        }
        return [
            loc("Library/Caches", .caches),
            loc("Library/Logs", .logs),
            loc("Library/Developer/Xcode/DerivedData", .developer),
            loc("Library/Developer/Xcode/iOS DeviceSupport", .developer, pre: false), // pobiera się długo od nowa
            loc("Library/Developer/Xcode/Archives", .developer, pre: false),          // archiwa buildów do wydania
            loc(".npm/_cacache", .developer, perChild: false, title: "npm"),
            loc(".cache/uv", .developer, perChild: false, title: "uv (Python)"),
            loc(".cache/pip", .developer, perChild: false, title: "pip (Python)"),
            loc(".bun/install/cache", .developer, perChild: false, title: "Bun"),
            loc(".cache/huggingface", .developer, perChild: false, pre: false, title: "Hugging Face (modele)"),
            loc(".cargo/registry", .developer, perChild: false, pre: false, title: "Cargo (Rust)"),
            loc(".local/share/pnpm/store", .developer, perChild: false, pre: false, title: "pnpm"),
            loc(".gradle/caches", .developer, perChild: false, pre: false, title: "Gradle"),
        ]
    }

    public static func scan(_ locs: [Location]) -> [Item] {
        var out: [Item] = []
        let fm = FileManager.default
        let keep = Protected.list()
        for l in locs {
            guard fm.fileExists(atPath: l.url.path) else { continue }
            let targets: [URL]
            if l.perChild {
                targets = (try? fm.contentsOfDirectory(at: l.url, includingPropertiesForKeys: nil, options: [])) ?? []
            } else {
                targets = [l.url]
            }
            for t in targets where !Protected.contains(t, in: keep) {
                let b = size(of: t)
                if b > 0 { out.append(Item(url: t, category: l.category, bytes: b, preselected: l.preselected, title: l.perChild ? nil : l.title)) }
            }
        }
        return out.sorted { $0.bytes > $1.bytes }
    }

    /// Foldery mediów (Zdjęcia, Muzyka, Filmy) i Pulpit (w iCloud potrafi prowadzić do Zdjęć) chroni macOS: samo wejście tam wywołuje okno zgody
    /// ("dostęp do biblioteki zdjęć") i zatrzymuje skan. Sprzątanie cache ich nie potrzebuje, więc nigdy tam nie wchodzimy
    /// (w rozmiarach liczą się jako 0).
    /// Ścieżki chronionych folderów w katalogu domowym liczone raz (to wywołanie leci dla każdego pliku).
    private static let offLimitPaths: Set<String> = {
        let h = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return Set(["Pictures", "Music", "Movies", "Desktop"].map { h + "/" + $0 })
    }()

    public static func isOffLimits(_ url: URL, home: URL? = nil) -> Bool {
        if url.pathExtension.lowercased() == "photoslibrary" { return true }
        guard let home else { return offLimitPaths.contains(url.path) }
        let h = home.standardizedFileURL.path
        return ["Pictures", "Music", "Movies", "Desktop"].contains { url.standardizedFileURL.path == h + "/" + $0 }
    }

    /// Rozmiar na dysku. Dowiązań symbolicznych nie śledzimy, więc nie wyjdziemy poza folder.
    public static func size(of url: URL, force: Bool = false) -> Int64 {
        if !force && isOffLimits(url) { return 0 }
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        let fm = FileManager.default
        if let v = try? url.resourceValues(forKeys: keys), v.isSymbolicLink != true, v.isRegularFile == true {
            return Int64(v.totalFileAllocatedSize ?? 0)
        }
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        // autoreleasepool na każdy plik: Foundation tworzy tu masę obiektów, które bez tego zbierają się do końca skanu.
        while let obj = e.nextObject() {
            autoreleasepool {
                guard let f = obj as? URL else { return }
                if !force && isOffLimits(f) { e.skipDescendants(); return }
                guard let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true else { return }
                total += Int64(v.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}

public struct Failure: Sendable { public let item: Item; public let reason: String }

public enum Cleaner {
    /// Wolno usuwać tylko to, co leży wewnątrz lokalizacji ze skanu; sam folder lokalizacji tylko wtedy,
    /// gdy jest jedną pozycją (`perChild == false`). Wszystko inne jest odrzucane, nawet przy błędzie wywołującego.
    static func allowed(_ url: URL, in locs: [Location]) -> Bool {
        let p = url.standardizedFileURL.path
        return locs.contains { l in
            let r = l.url.standardizedFileURL.path
            return p.hasPrefix(r + "/") || (p == r && !l.perChild)
        }
    }

    /// Przenosi do Kosza (odwracalnie).
    public static func trash(_ items: [Item], within locs: [Location],
                             remove: (URL) throws -> Void = { try Trash.move($0) })
        -> (freed: Int64, failures: [Failure]) {
        var freed: Int64 = 0
        var failures: [Failure] = []
        let keep = Protected.list()
        for item in items {
            guard !Protected.contains(item.url, in: keep) else { failures.append(Failure(item: item, reason: L10n.t("Chronione wyjątkiem."))); continue }
            guard allowed(item.url, in: locs) else {
                failures.append(Failure(item: item, reason: L10n.t("Poza dozwolonymi folderami.")))
                continue
            }
            do { try remove(item.url); freed += item.bytes }
            catch { failures.append(Failure(item: item, reason: error.localizedDescription)) }
        }
        return (freed, failures)
    }
}
