import Foundation

/// Najnowsze wydanie z GitHub Releases: wersja i adres pliku .zip z aplikacją.
public struct AppRelease: Equatable {
    public let version: String
    public let zipURL: URL
    public let notes: String
}

public enum AppUpdates {
    public static let repo = "kczepiec/opencleaner"

    /// Parsuje odpowiedź `releases/latest`. Zwraca nil dla szkicu, prerelease albo wydania bez .zip.
    public static func parseRelease(_ data: Data) -> AppRelease? {
        struct R: Decodable {
            struct A: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String; let draft: Bool?; let prerelease: Bool?; let body: String?; let assets: [A]
        }
        guard let r = try? JSONDecoder().decode(R.self, from: data), r.draft != true, r.prerelease != true,
              let zip = r.assets.first(where: { $0.name.hasSuffix(".zip") }) else { return nil }
        return AppRelease(version: r.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), zipURL: zip.browser_download_url, notes: r.body ?? "")
    }

    /// Porównanie numeryczne po kropkach ("1.10" > "1.9"); brakujące części to 0.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
