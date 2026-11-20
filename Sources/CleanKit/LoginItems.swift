import Foundation

/// Programy uruchamiane przy logowaniu: elementy logowania (System Events) i agenty użytkownika z `~/Library/LaunchAgents`.
/// Agenty systemowe (`/Library`) i elementy tła zarejestrowane przez aplikacje (SMAppService) zostają poza zakresem.
public enum LoginItems {
    public enum Kind: Sendable { case loginItem, launchAgent }
    public struct Item: Identifiable, Equatable, Sendable {
        public var id: String { (kind == .loginItem ? "login:" : "agent:") + key }
        public let kind: Kind
        public let name: String
        public let path: String
        let key: String        // nazwa elementu logowania albo etykieta agenta
        let plist: URL?
    }

    /// Wiersze `nazwa<TAB>ścieżka` z AppleScriptu.
    public static func parseLoginItems(_ out: String) -> [Item] {
        out.split(whereSeparator: \.isNewline).compactMap { line in
            let p = line.components(separatedBy: "\t")
            guard let name = p.first, !name.isEmpty else { return nil }
            return Item(kind: .loginItem, name: name, path: p.count > 1 ? p[1] : "", key: name, plist: nil)
        }
    }

    /// Agenty z RunAtLoad, bez Apple i bez wyłączonych.
    public static func launchAgents(in dir: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents")) -> [Item] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "plist" }.compactMap { url in
            guard let d = try? Data(contentsOf: url),
                  let o = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any],
                  let label = o["Label"] as? String, !label.hasPrefix("com.apple."),
                  o["RunAtLoad"] as? Bool == true, o["Disabled"] as? Bool != true else { return nil }
            let prog = (o["Program"] as? String) ?? (o["ProgramArguments"] as? [String])?.first ?? ""
            let name = prog.isEmpty ? label : URL(fileURLWithPath: prog).deletingPathExtension().lastPathComponent
            return Item(kind: .launchAgent, name: name, path: prog, key: label, plist: url)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// `needsPermission`: macOS nie dało dostępu do System Events (Ustawienia, Prywatność, Automatyzacja).
    public static func load() async -> (items: [Item], needsPermission: Bool) {
        let script = "tell application \"System Events\"\nset o to \"\"\nrepeat with i in login items\nset o to o & (name of i) & tab & (path of i) & linefeed\nend repeat\nreturn o\nend tell"
        let r = await Mole.run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script])
        let login = r.status == 0 ? parseLoginItems(r.text) : []
        let items = (login + launchAgents()).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (items, r.status != 0 && r.text.contains("-1743"))
    }

    /// Element logowania znika z listy; agent jest zatrzymywany, a jego plik trafia do Kosza (da się przywrócić).
    public static func remove(_ item: Item) async -> Bool {
        switch item.kind {
        case .loginItem:
            let n = item.key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let r = await Mole.run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", "tell application \"System Events\" to delete (first login item whose name is \"\(n)\")"])
            return r.status == 0
        case .launchAgent:
            guard let plist = item.plist else { return false }
            _ = await Mole.run(URL(fileURLWithPath: "/bin/launchctl"), ["bootout", "gui/\(getuid())/\(item.key)"])
            return (try? Trash.move(plist)) != nil
        }
    }
}
