import Foundation

/// Cienka warstwa nad `mo` (Mole, https://mole.fit): wykrywanie, instalacja, uruchamianie i parsowanie wyników.
public enum Mole {
    public struct Entry: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let name: String
        public let detail: String
        public let bytes: Int64?
    }
    public struct Group: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let title: String
        public var entries: [Entry]
        public var nothing: Bool
        public var bytes: Int64 { entries.reduce(0) { $0 + ($1.bytes ?? 0) } }
    }
    public struct Preview: Equatable, Sendable {
        public var groups: [Group] = []
        public var notes: [String] = []
        public var bytes: Int64 { groups.reduce(0) { $0 + $1.bytes } }
    }
    public struct App: Decodable, Identifiable, Hashable, Sendable {
        public let name: String
        public let uninstallName: String
        public let path: String
        public let size: String
        public var id: String { path }
        enum CodingKeys: String, CodingKey { case name, path, size, uninstallName = "uninstall_name" }
    }
    public struct Status: Equatable, Sendable {
        public var health: Int, healthMessage: String
        public var cpu: Double, cores: Int
        public var memUsed: Int64, memTotal: Int64, swapUsed: Int64, swapTotal: Int64
        public var uptime: String, model: String, chip: String, os: String, procs: Int
        public var gpuCores = 0, load1 = 0.0, pressure = "", netDown = 0.0, netUp = 0.0
        public var battery: Battery?
    }
    public struct Battery: Equatable, Sendable {
        public var percent: Int, status: String, timeLeft: String, health: String, cycles: Int
        public var charging: Bool { status == "charging" || status == "charged" }
    }

    // MARK: wykrywanie i instalacja

    static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }
    public static var executable: URL? {
        ["/opt/homebrew/bin/mo", "/usr/local/bin/mo", "\(home)/.local/bin/mo"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
    public static var brew: URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
    /// Komenda do ręcznej instalacji, gdy nie ma Homebrew.
    public static let manualInstall = "curl -fsSL https://raw.githubusercontent.com/tw93/Mole/main/install.sh | bash"

    /// Instaluje Mole przez Homebrew. Zwraca nil po sukcesie albo tekst błędu.
    public static func install(onLine: @escaping @Sendable (String) -> Void) async -> String? {
        guard let brew else { return L10n.t("Nie znalazłem Homebrew. Zainstaluj ręcznie: %@", manualInstall) }
        let r = await run(brew, ["install", "mole"], onLine: onLine)
        return r.status == 0 && executable != nil ? nil : L10n.t("Instalacja Mole nie powiodła się (kod %@).", "\(r.status)")
    }

    // MARK: uruchamianie

    public static func strip(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }

    /// Uruchamia program bez terminala (TERM=dumb, bez kolorów), przekazuje wiersze na bieżąco.
    public static func run(_ exe: URL, _ args: [String], onLine: (@Sendable (String) -> Void)? = nil) async -> (status: Int32, text: String) {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "dumb"; env["NO_COLOR"] = "1"
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(home)/.local/bin"
            p.environment = env
            p.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            let buffer = Locked("")
            pipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty, let chunk = String(data: d, encoding: .utf8) else { return }
                buffer.update { $0 += chunk }
                for line in strip(chunk).split(whereSeparator: \.isNewline) { onLine?(String(line)) }
            }
            p.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                if let rest = try? pipe.fileHandleForReading.readToEnd(), let s = String(data: rest, encoding: .utf8) { buffer.update { $0 += s } }
                cont.resume(returning: (proc.terminationStatus, strip(buffer.value)))
            }
            do { try p.run() } catch { cont.resume(returning: (-1, L10n.t("Nie udało się uruchomić: %@", error.localizedDescription))) }
        }
    }

    public static func mo(_ args: [String], onLine: (@Sendable (String) -> Void)? = nil) async -> (status: Int32, text: String) {
        guard let exe = executable else { return (-1, "Brak Mole.") }
        return await run(exe, args, onLine: onLine)
    }

    // MARK: wersje

    /// "V1.73.0" na "1.73.0".
    public static func normalizeVersion(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespaces).drop { $0 == "v" || $0 == "V" }.description
    }

    /// Porównanie liczbowe po składowych (1.10 jest nowsze niż 1.9).
    public static func isNewer(_ latest: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] { normalizeVersion(s).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let a = parts(latest), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Najnowsze wydanie Mole z GitHuba (bez logowania). nil, gdy brak sieci albo limit zapytań.
    public static func latestVersion() async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/tw93/Mole/releases/latest") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], o["prerelease"] as? Bool != true,
              let tag = o["tag_name"] as? String else { return nil }
        return normalizeVersion(tag)
    }

    // MARK: parsowanie

    static let sizePattern = try! NSRegularExpression(pattern: "([0-9]+(?:\\.[0-9]+)?)\\s?(B|KB|MB|GB|TB)\\b")

    public static func parseSize(_ s: String) -> Int64? {
        let range = NSRange(s.startIndex..., in: s)
        guard let m = sizePattern.firstMatch(in: s, range: range), let n = Range(m.range(at: 1), in: s),
              let u = Range(m.range(at: 2), in: s), let v = Double(s[n]) else { return nil }
        let mult: Double = ["B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12][String(s[u])] ?? 1
        return Int64((v * mult).rounded())
    }

    /// Wynik `mo clean` / `mo optimize` (tekst): grupy "➤ ...", pozycje "→ nazwa · szczegóły", uwagi "◎ ...".
    public static func parse(_ text: String) -> Preview {
        var out = Preview()
        for raw in strip(text).split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("➤ ") {
                out.groups.append(Group(title: String(line.dropFirst(2)), entries: [], nothing: false))
            } else if line.hasPrefix("→ "), !out.groups.isEmpty {
                let body = String(line.dropFirst(2))
                let name: String, detail: String
                if let r = body.range(of: " · ") { name = String(body[..<r.lowerBound]); detail = String(body[r.upperBound...]) }
                else if let r = body.range(of: ", ") { name = String(body[..<r.lowerBound]); detail = String(body[r.upperBound...]) }
                else { name = body; detail = "" }
                out.groups[out.groups.count - 1].entries.append(Entry(name: name, detail: detail.replacingOccurrences(of: " dry", with: ""), bytes: parseSize(detail)))
            } else if line.hasPrefix("✓ Nothing to clean"), !out.groups.isEmpty {
                out.groups[out.groups.count - 1].nothing = true
            } else if line.hasPrefix("◎ ") || line.hasPrefix("⚠ ") {
                out.notes.append(String(line.dropFirst(2)))
            }
        }
        out.groups.removeAll { $0.entries.isEmpty && !$0.nothing }
        return out
    }

    public static func parseApps(_ text: String) -> [App] {
        guard let start = text.firstIndex(of: "["), let data = String(text[start...]).data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([App].self, from: data)) ?? []
    }

    public static func parseStatus(_ text: String) -> Status? {
        guard let start = text.firstIndex(of: "{"), let data = String(text[start...]).data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let hw = o["hardware"] as? [String: Any] ?? [:], cpu = o["cpu"] as? [String: Any] ?? [:], mem = o["memory"] as? [String: Any] ?? [:]
        func i64(_ v: Any?) -> Int64 { (v as? NSNumber)?.int64Value ?? 0 }
        let net = o["network"] as? [[String: Any]] ?? []
        return Status(health: (o["health_score"] as? Int) ?? 0, healthMessage: o["health_score_msg"] as? String ?? "",
                      cpu: (cpu["usage"] as? Double) ?? 0, cores: (cpu["core_count"] as? Int) ?? 0,
                      memUsed: i64(mem["used"]), memTotal: i64(mem["total"]), swapUsed: i64(mem["swap_used"]), swapTotal: i64(mem["swap_total"]),
                      uptime: o["uptime"] as? String ?? "", model: hw["model"] as? String ?? "", chip: hw["cpu_model"] as? String ?? "",
                      os: hw["os_version"] as? String ?? "", procs: (o["procs"] as? Int) ?? 0,
                      gpuCores: ((o["gpu"] as? [[String: Any]])?.first?["core_count"] as? Int) ?? 0,
                      load1: (cpu["load1"] as? Double) ?? 0, pressure: mem["pressure"] as? String ?? "",
                      netDown: net.reduce(0) { $0 + (($1["rx_rate_mbs"] as? Double) ?? 0) },
                      netUp: net.reduce(0) { $0 + (($1["tx_rate_mbs"] as? Double) ?? 0) },
                      battery: (o["batteries"] as? [[String: Any]])?.first.flatMap { b in
                          (b["percent"] as? Int).map { Battery(percent: $0, status: b["status"] as? String ?? "", timeLeft: b["time_left"] as? String ?? "",
                                                              health: b["health"] as? String ?? "", cycles: (b["cycle_count"] as? Int) ?? 0) }
                      })
    }
}

/// Mała blokada na wartość współdzieloną z wątkami uchwytu rury.
final class Locked<T>: @unchecked Sendable {
    private var v: T
    private let lock = NSLock()
    init(_ v: T) { self.v = v }
    var value: T { lock.lock(); defer { lock.unlock() }; return v }
    func update(_ f: (inout T) -> Void) { lock.lock(); f(&v); lock.unlock() }
}
