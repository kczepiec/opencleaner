import Foundation

/// Pozostałości aplikacji w `~/Library` (dane, cache, ustawienia, kontenery, logi). Skan tylko czyta.
/// Dopasowanie jest ostrożne: dokładny identyfikator pakietu albo dokładna nazwa aplikacji w znanych folderach.
/// Nigdy nie dotyka aplikacji z `/System`, a nazwy krótsze niż 4 znaki nie służą do dopasowania.
public enum AppLeftovers {
    public struct Item: Identifiable, Equatable, Sendable {
        public var id: URL { url }
        public let url: URL
        public let bytes: Int64
        /// Rodzaj do wyświetlenia (nazwa folderu w Library, np. "Caches").
        public let kind: String
        /// Dane, których utrata boli (np. archiwa Xcode): domyślnie niezaznaczone.
        public let risky: Bool
    }

    public static func info(appPath: String) -> (bundleID: String?, name: String) {
        let url = URL(fileURLWithPath: appPath)
        let plist = (try? Data(contentsOf: url.appending(path: "Contents/Info.plist"))).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        return (plist?["CFBundleIdentifier"] as? String, url.deletingPathExtension().lastPathComponent)
    }

    /// Dodatkowe, znane miejsca dużych pozostałości: (ścieżka od katalogu domowego, czy ryzykowne).
    static let known: [String: [(String, Bool)]] = [
        "com.apple.dt.Xcode": [("Library/Developer/Xcode/DerivedData", false), ("Library/Developer/Xcode/iOS DeviceSupport", false),
                               ("Library/Developer/CoreSimulator", false), ("Library/Developer/Xcode/Archives", true), ("Library/Developer/Xcode/UserData", true)],
    ]

    public static func find(appPath: String, home: URL = FileManager.default.homeDirectoryForCurrentUser, protected: [String] = Protected.list()) -> [Item] {
        guard !appPath.hasPrefix("/System/") else { return [] }
        let (b, name) = info(appPath: appPath)
        let fm = FileManager.default
        let lib = home.appending(path: "Library")
        var found: [(URL, String, Bool)] = []
        func add(_ u: URL, _ kind: String, _ risky: Bool = false) {
            if fm.fileExists(atPath: u.path), !found.contains(where: { $0.0 == u }) { found.append((u, kind, risky)) }
        }
        let nameOK = name.count >= 4
        // foldery, w których szukamy po nazwie i po identyfikatorze
        for dir in ["Application Support", "Caches", "Logs"] {
            if nameOK { add(lib.appending(path: "\(dir)/\(name)"), dir) }
            if let b { add(lib.appending(path: "\(dir)/\(b)"), dir) }
        }
        if let b {
            add(lib.appending(path: "Preferences/\(b).plist"), "Preferences")
            for dir in ["Containers", "HTTPStorages", "WebKit", "Application Scripts"] { add(lib.appending(path: "\(dir)/\(b)"), dir) }
            add(lib.appending(path: "Saved Application State/\(b).savedState"), "Saved Application State")
            add(lib.appending(path: "Cookies/\(b).binarycookies"), "Cookies")
            add(lib.appending(path: "HTTPStorages/\(b).binarycookies"), "HTTPStorages")
            add(lib.appending(path: "LaunchAgents/\(b).plist"), "LaunchAgents")
            // Group Containers: "group.<id>" albo "<TEAM>.<id>"
            let groups = (try? fm.contentsOfDirectory(at: lib.appending(path: "Group Containers"), includingPropertiesForKeys: nil)) ?? []
            for g in groups where g.lastPathComponent == b || g.lastPathComponent.hasSuffix("." + b) { add(g, "Group Containers") }
            for (rel, risky) in known[b] ?? [] { add(home.appending(path: rel), URL(fileURLWithPath: rel).deletingLastPathComponent().lastPathComponent, risky) }
        }
        return found.filter { !Protected.contains($0.0, in: protected) }
            .compactMap { u, kind, risky in
                let size = Scanner.size(of: u, force: true)
                return size > 0 ? Item(url: u, bytes: size, kind: kind, risky: risky) : nil
            }.sorted { $0.bytes > $1.bytes }
    }

    /// Przenosi do Kosza aplikację i wskazane pozostałości. Tylko ścieżki pod `/Applications`, `~/Applications` i `~/Library`/`~/.` w katalogu domowym.
    public static func uninstall(app: URL, leftovers: [URL], home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                 remove: (URL) throws -> Void = { try Trash.move($0) }) -> (done: Int, failed: Int, error: String?) {
        let h = home.standardizedFileURL.path + "/"
        let appPath = app.standardizedFileURL.path
        let appOK = (appPath.hasPrefix("/Applications/") || appPath.hasPrefix(h + "Applications/")) && app.pathExtension == "app"
        var done = 0, failed = 0
        var firstError: String?
        func go(_ u: URL, allowed: Bool) {
            guard allowed else { failed += 1; firstError = firstError ?? "\(u.lastPathComponent): outside allowed folders"; return }
            do { try remove(u); done += 1 } catch { failed += 1; firstError = firstError ?? "\(u.lastPathComponent): \(error.localizedDescription)" }
        }
        for l in leftovers { go(l, allowed: l.standardizedFileURL.path.hasPrefix(h + "Library/") && !Protected.contains(l, in: Protected.list())) }
        go(app, allowed: appOK && !Protected.contains(app, in: Protected.list()))
        return (done, failed, firstError)
    }
}
