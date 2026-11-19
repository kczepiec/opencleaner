import Foundation

/// Własny silnik czyszczenia, gdy Mole nie jest zainstalowany: cache i logi z Biblioteki użytkownika oraz Xcode DerivedData.
/// Rusza tylko foldery z białej listy poniżej (nic poza `~/Library` i `~/.npm`), pomija `com.apple.*` i usuwa na stałe.
public enum NativeClean {
    /// Katalogi, z których czyścimy zawartość (każdy podfolder lub plik osobno), i tytuł grupy.
    static func roots(_ home: URL) -> [(title: String, dir: URL, skipApple: Bool)] {
        [("App caches", home.appending(path: "Library/Caches"), true),
         ("Logs", home.appending(path: "Library/Logs"), true),
         ("Developer tools", home.appending(path: "Library/Developer/Xcode/DerivedData"), false),
         ("Developer tools", home.appending(path: ".npm/_cacache"), false)]
    }

    static func targets(_ home: URL) -> [(title: String, url: URL)] {
        var out: [(String, URL)] = []
        for r in roots(home) {
            let items = (try? FileManager.default.contentsOfDirectory(at: r.dir, includingPropertiesForKeys: nil)) ?? []
            for u in items {
                let n = u.lastPathComponent
                if r.skipApple && n.hasPrefix("com.apple.") { continue }
                if n == "pl.kc.cachecleaner" || n.hasPrefix(".") { continue }
                out.append((r.title, u))
            }
        }
        return out
    }

    /// Podgląd: grupy z rozmiarami. Nic nie jest zmieniane.
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Mole.Preview {
        var by: [String: [Mole.Entry]] = [:]
        for t in targets(home) {
            let b = Scanner.size(of: t.url, force: true)
            if b > 0 { by[t.title, default: []].append(Mole.Entry(name: t.url.lastPathComponent, detail: t.url.path, bytes: b)) }
        }
        let order = ["App caches", "Logs", "Developer tools"]
        return Mole.Preview(groups: order.compactMap { t in
            guard var e = by[t] else { return nil }
            e.sort { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
            return Mole.Group(title: t, entries: e, nothing: false)
        })
    }

    /// Usuwa cele z listy i zwraca zwolnione bajty. Linki symboliczne są usuwane jako linki, bez wchodzenia w cel.
    @discardableResult
    public static func run(home: URL = FileManager.default.homeDirectoryForCurrentUser, progress: (String) -> Void = { _ in }) -> Int64 {
        var freed: Int64 = 0
        for t in targets(home) {
            let b = Scanner.size(of: t.url, force: true)
            progress(t.url.lastPathComponent)
            if (try? FileManager.default.removeItem(at: t.url)) != nil { freed += b }
        }
        return freed
    }
}
