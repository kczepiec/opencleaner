import Foundation

/// Najnowsze wydanie z GitHub Releases: wersja i adres pliku .zip z aplikacją.
public struct AppRelease: Equatable {
    public let version: String
    public let zipURL: URL
}

public enum AppUpdates {
    public static let repo = "kczepiec/opencleaner"

    /// Wydanie z adresu, na który GitHub przekierowuje `releases/latest` (`.../releases/tag/v1.2`).
    /// Bez API, więc bez limitu zapytań. Zip ma nazwę `OpenCleaner-<wersja>.zip` (patrz `tools/release.sh`).
    public static func release(fromLatestURL url: URL) -> AppRelease? {
        let comps = url.pathComponents
        guard comps.count >= 2, comps[comps.count - 2] == "tag", let tag = comps.last,
              tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).first?.isNumber == true else { return nil }
        let v = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard let zip = URL(string: "https://github.com/\(repo)/releases/download/\(tag)/OpenCleaner-\(v).zip") else { return nil }
        return AppRelease(version: v, zipURL: zip)
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
