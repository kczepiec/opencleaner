import Foundation

/// Wyjątki: foldery i pliki, których OpenCleaner nigdy nie pokazuje do usunięcia ani nie rusza.
/// Lista leży w pliku, bo czytają ją dwa procesy: aplikacja i serwer MCP. Jedna ścieżka na wiersz.
/// Uwaga: czyszczenie przez Mole (`mo clean`) działa poza tą listą.
public enum Protected {
    public static var file: URL { MCPConfig.directory.appending(path: "protected.txt") }

    public static func list(file: URL = Protected.file) -> [String] {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }

    public static func save(_ paths: [String], file: URL = Protected.file) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? paths.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// Chronione jest to, co leży w wyjątku, jest nim, albo go zawiera (usunięcie rodzica zabrałoby chroniony element).
    public static func contains(_ url: URL, in list: [String]) -> Bool {
        let p = url.standardizedFileURL.path
        return list.contains { e in p == e || p.hasPrefix(e + "/") || e.hasPrefix(p + "/") }
    }
}
