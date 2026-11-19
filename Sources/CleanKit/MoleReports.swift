import Foundation

/// Wyniki Mole zamienione na dane do wyświetlenia: bez surowego tekstu z terminala, z polskimi nazwami.
extension Mole {
    public enum StepStatus: String, Sendable { case apply, ok, attention, skipped, unavailable }

    public struct Step: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let title: String          // po polsku (albo oryginał, gdy nie znamy tłumaczenia)
        public var status: StepStatus
        public var notes: [String]        // uwagi wymagające uwagi, po polsku jeśli się da
        public var original: String       // surowa linia, tylko do podpowiedzi po najechaniu
    }
    public struct ProcessUse: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let name: String
        public let bytes: Int64
    }
    public struct OptimizeReport: Equatable, Sendable {
        public var findings: [String] = []
        public var processes: [ProcessUse] = []
        public var steps: [Step] = []
        public var toApply = 0, unchanged = 0, skipped = 0, unavailable = 0, attention = 0
    }

    public struct PlanFile: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let path: String
        public let bytes: Int64
    }
    public struct PlanApp: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public var name: String
        public var bytes: Int64
        public var lastUsed: String
        public var files: [PlanFile]
    }

    /// Grupy dopasowania wyrażenia regularnego (0 to całość).
    static func cap(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
    }

    // MARK: optimize

    public static func parseOptimize(_ text: String) -> OptimizeReport {
        var r = OptimizeReport()
        var inDiagnosis = false
        for raw in strip(text).split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Performance diagnosis") { inDiagnosis = true; continue }
            if line.hasPrefix("➤ ") {
                inDiagnosis = false
                let t = String(line.dropFirst(2))
                r.steps.append(Step(title: pl(t), status: .ok, notes: [], original: t))
                continue
            }
            if inDiagnosis {
                if line.hasPrefix("◎ ") { r.findings.append(plDiagnosis(String(line.dropFirst(2)))) }
                else if let m = cap("^(.+?)\\s{2,}([0-9.]+\\s?(?:B|KB|MB|GB))$", line), let b = parseSize(m[2]) {
                    r.processes.append(ProcessUse(name: m[1], bytes: b))
                }
                continue
            }
            guard !r.steps.isEmpty else { continue }
            let i = r.steps.count - 1
            if line.hasPrefix("→ ") {
                let msg = String(line.dropFirst(2)); r.steps[i].original = msg
                r.steps[i].status = classify(msg, current: r.steps[i].status)
            } else if line.hasPrefix("◎ ") {
                r.steps[i].notes.append(plNote(String(line.dropFirst(2))))
                r.steps[i].status = .attention
            }
        }
        // podsumowanie: "Would apply 2 optimizations" i "12 unchanged | 3 skipped | 1 unavailable | 1 need attention"
        for raw in strip(text).split(whereSeparator: \.isNewline) {
            let l = String(raw)
            if let m = cap("(?:Would apply|Applied)\\s+(\\d+)\\s+optimi", l) { r.toApply = Int(m[1]) ?? 0 }
            if l.contains(" unchanged"), l.contains("|") {
                for seg in l.split(separator: "|") {
                    let parts = seg.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init)
                    guard parts.count == 2, let n = Int(parts[0]) else { continue }
                    if parts[1].hasPrefix("unchanged") { r.unchanged = n } else if parts[1].hasPrefix("skipped") { r.skipped = n }
                    else if parts[1].hasPrefix("unavailable") { r.unavailable = n } else if parts[1].hasPrefix("need") { r.attention = n }
                }
            }
        }
        return r
    }

    static func classify(_ msg: String, current: StepStatus) -> StepStatus {
        if current == .attention { return .attention }
        let m = msg.lowercased()
        if m.contains("not available") || m.contains("unavailable") { return .unavailable }
        if m.contains("skipped") { return .skipped }
        if ["already", "healthy", "optimal", "valid", "clean", "no legacy", "all "].contains(where: m.contains) { return .ok }
        return .apply
    }

    // MARK: odinstalowanie

    public static func parseUninstallPlan(_ text: String) -> [PlanApp] {
        var apps: [PlanApp] = []
        for raw in strip(text).split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let m = cap("^\\d+\\.\\s+(.+?)\\s{2,}([0-9.]+\\s?(?:B|KB|MB|GB|TB))\\s+\\|\\s+Last:\\s+(.+)$", line) {
                apps.append(PlanApp(name: m[1], bytes: parseSize(m[2]) ?? 0, lastUsed: plAgo(m[3]), files: []))
            } else if line.hasPrefix("✓ "), !apps.isEmpty {
                let body = String(line.dropFirst(2))
                let parts = body.components(separatedBy: " , ")
                if parts.count == 2 {
                    apps[apps.count - 1].files.append(PlanFile(path: parts[0].replacingOccurrences(of: "~", with: NSHomeDirectory(), options: .anchored), bytes: parseSize(parts[1]) ?? 0))
                }
            }
        }
        return apps
    }

    // MARK: polskie nazwy

    static let titles: [String: String] = [
        // optimize
        "Finder Cache Refresh": "Odświeżenie cache Findera", "App State Cleanup": "Porządkowanie stanów aplikacji",
        "Broken Config Repair": "Naprawa uszkodzonych ustawień", "Network Cache Refresh": "Odświeżenie cache sieci",
        "Database Optimization": "Optymalizacja baz danych", "Prevent Finder .DS_Store": "Blokada plików .DS_Store",
        "Legacy Overrides": "Stare nadpisania systemowe", "Network Stack Refresh": "Odświeżenie stosu sieciowego",
        "Permission Repair": "Naprawa uprawnień", "Spotlight Optimization": "Optymalizacja Spotlight",
        "Spotlight Orphan Rules": "Osierocone reguły Spotlight", "Periodic Maintenance": "Okresowa konserwacja",
        "Shared File Lists": "Listy plików udostępnionych", "Disk Health": "Zdrowie dysku", "Login Items": "Elementy logowania",
        "Quarantine Database Cleanup": "Baza kwarantanny", "Launch Agents Cleanup": "Agenci uruchamiania",
        "Notifications": "Powiadomienia", "Usage Data": "Dane użycia",
        // clean: grupy
        "User essentials": "Podstawy użytkownika", "App caches": "Cache aplikacji", "Logs": "Logi", "Browsers": "Przeglądarki",
        "Cloud & Office": "Chmura i biuro", "Developer tools": "Narzędzia deweloperskie", "Large files": "Duże pliki",
        "Applications": "Aplikacje", "System": "System", "Orphaned data": "Osierocone dane",
        "Apps & utilities": "Aplikacje i narzędzia", "Virtualization": "Wirtualizacja", "Application Support": "Dane aplikacji",
        "App leftovers": "Pozostałości po aplikacjach", "Apple Silicon updates": "Aktualizacje Apple Silicon",
        "Device backups & firmware": "Kopie urządzeń i firmware", "Time Machine": "Time Machine",
        // clean: pozycje
        "User app cache": "Cache aplikacji użytkownika", "User app logs": "Logi aplikacji użytkownika", "Trash": "Kosz",
        "Siri suggestions cache": "Sugestie Siri", "Messages preview attachment cache": "Podglądy załączników Wiadomości",
        "Media analysis temp files": "Pliki tymczasowe analizy mediów", "Geod temp files": "Pliki tymczasowe lokalizacji",
        "Maps geo tile cache": "Kafelki map", "Apple Media Services cache": "Cache usług Apple Media",
        "Handoff clipboard cache": "Schowek Handoff", "Chrome cache": "Cache Chrome", "Chrome Service Worker": "Service Worker Chrome",
        "GoogleUpdater CRX cache": "Cache aktualizacji Google", "CoreSimulator logs": "Logi symulatora Xcode",
    ]
    public static func pl(_ s: String) -> String { titles[s] ?? s }

    /// "8.35GB" na "8,35 GB": polski zapis liczb i jednostek w tekstach z Mole.
    public static func plUnits(_ s: String) -> String {
        var out = s
        for (pattern, template) in [("([0-9]+)\\.([0-9]+)\\s?(KB|MB|GB|TB)\\b", "$1,$2 $3"), ("([0-9]+)(KB|MB|GB|TB)\\b", "$1 $2")] {
            out = out.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return out
    }

    static func plAgo(_ s: String) -> String {
        guard let m = cap("^(\\d+)([hdwmy]) ago$", s) else { return s == "never" ? "nigdy" : s }
        let unit = ["h": "godz.", "d": "dni", "w": "tyg.", "m": "mies.", "y": "lat"][m[2]] ?? m[2]
        return "\(m[1]) \(unit) temu"
    }

    static func plDiagnosis(_ s: String) -> String {
        if let m = cap("Likely bottleneck:\\s+(.+?)\\s+\\(~([0-9.]+)% CPU sustained\\)", s) {
            return "Prawdopodobne wąskie gardło: \(m[1]) (około \(m[2].replacingOccurrences(of: ".", with: ","))% procesora przez dłuższy czas)"
        }
        if let m = cap("Memory pressure:\\s+swap\\s+(\\S+)\\s+of\\s+(\\S+)\\s+used\\s+\\((\\d+)%\\),\\s+(\\d+)% free", s) {
            return "Presja pamięci: swap \(plUnits(m[1])) z \(plUnits(m[2])) (\(m[3])%), wolne \(m[4])%"
        }
        return s
    }

    /// Uwagi z `mo clean`; nieznane zostają po angielsku, żeby nie ukrywać informacji.
    public static func plCleanNote(_ s: String) -> String {
        if s.hasPrefix("System caches need sudo") { return "Cache systemowe wymagają uprawnień administratora, więc podgląd ich nie obejmuje." }
        return s
    }

    static func plNote(_ s: String) -> String {
        if let m = cap("Close these apps before database optimization:\\s+(.+)", s) { return "Zamknij przed optymalizacją baz danych: \(m[1])" }
        if let m = cap("Launch Agent (\\S+):\\s+program missing at", s) { return "Agent uruchamiania \(m[1]) wskazuje na program, którego już nie ma" }
        if let m = cap("(\\d+) Launch Agent\\(s\\) point at a missing program", s) { return "\(m[1]) agent(ów) uruchamiania wskazuje na brakujący program. Zostawiam je bez zmian." }
        return s
    }
}

/// Informacje o wnętrzu systemu: woluminy APFS i symulatory Xcode.
public enum SystemInfo {
    public struct Part: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let title: String
        public let note: String
        public let bytes: Int64
    }
    public struct Runtime: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
    }

    static func plist(_ text: String) -> [String: Any]? {
        guard let d = text.data(using: .utf8) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: Any]
    }

    /// Wolumin z rolą System i Data to nasz dysk: z niego składamy części zajętego miejsca.
    public static func apfsParts(_ text: String) -> [Part] {
        let names = ["System": ("macOS (wolumin System)", "Sam system. Nie da się go zmniejszyć."),
                     "Preboot": ("Rozruch (Preboot)", "Pliki potrzebne do uruchomienia systemu."),
                     "Recovery": ("Odzyskiwanie (Recovery)", "Środowisko naprawy systemu."),
                     "VM": ("Pamięć wirtualna (swap)", "Rośnie, gdy brakuje pamięci. Maleje po zamknięciu ciężkich aplikacji."),
                     "Update": ("Aktualizacje", "Pliki aktualizacji systemu.")]
        guard let root = plist(text), let containers = root["Containers"] as? [[String: Any]] else { return [] }
        for c in containers {
            let vols = c["Volumes"] as? [[String: Any]] ?? []
            let roles = vols.compactMap { ($0["Roles"] as? [String])?.first }
            guard roles.contains("System"), roles.contains("Data") else { continue }
            return vols.compactMap { v in
                guard let role = (v["Roles"] as? [String])?.first, let t = names[role],
                      let b = (v["CapacityInUse"] as? NSNumber)?.int64Value, b > 50_000_000 else { return nil }
                return Part(title: t.0, note: t.1, bytes: b)
            }
        }
        return []
    }

    /// Wiersze `xcrun simctl runtime list`: "iOS 27.2 (24B8117) - UUID (Ready)".
    public static func parseRuntimes(_ text: String) -> [Runtime] {
        Mole.strip(text).split(whereSeparator: \.isNewline).compactMap { raw in
            let l = raw.trimmingCharacters(in: .whitespaces)
            guard let m = Mole.cap("^(.+?)\\s+-\\s+([0-9A-Fa-f-]{36})\\s+\\(.*\\)$", l) else { return nil }
            return Runtime(id: m[2], name: m[1])
        }
    }

    public static func apfs() async -> [Part] {
        let r = await Mole.run(URL(fileURLWithPath: "/usr/sbin/diskutil"), ["apfs", "list", "-plist"])
        return apfsParts(r.text)
    }
    public static func runtimes() async -> [Runtime] {
        let r = await Mole.run(URL(fileURLWithPath: "/usr/bin/xcrun"), ["simctl", "runtime", "list"])
        return parseRuntimes(r.text)
    }
    /// Usuwa środowisko symulatora (Xcode pobierze je ponownie, jeśli będzie potrzebne).
    public static func deleteRuntime(_ id: String) async -> Bool {
        await Mole.run(URL(fileURLWithPath: "/usr/bin/xcrun"), ["simctl", "runtime", "delete", id]).status == 0
    }
}

extension Mole {
    public struct HistorySession: Identifiable, Equatable, Sendable {
        public let id: String
        public let command: String     // po polsku
        public let startedAt: String
        public let items: Int
        public let size: String
        public let dryRun: Bool
    }

    static let commandNames: [String: String] = [
        "clean": "Czyszczenie", "optimize": "Optymalizacja", "uninstall": "Odinstalowanie", "purge": "Czyszczenie projektów",
        "installer": "Instalatory", "status": "Status", "analyze": "Analiza", "slim": "Odchudzanie aplikacji",
        "update": "Aktualizacja Mole", "touchid": "Touch ID", "completion": "Autouzupełnianie", "remove": "Usunięcie Mole",
    ]

    /// Z `mo history --json`: ostatnie operacje. "-dry-run" w nazwie oznacza sam podgląd.
    public static func parseHistory(_ text: String) -> [HistorySession] {
        guard let start = text.firstIndex(of: "{"), let data = String(text[start...]).data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessions = o["sessions"] as? [[String: Any]] else { return [] }
        return sessions.compactMap { s in
            guard let cmd = s["command"] as? String, let at = s["started_at"] as? String else { return nil }
            let dry = cmd.hasSuffix("-dry-run")
            let base = dry ? String(cmd.dropLast("-dry-run".count)) : cmd
            return HistorySession(id: (s["run_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? at + cmd,
                                  command: commandNames[base] ?? base, startedAt: at,
                                  items: (s["items"] as? Int) ?? 0, size: s["size"] as? String ?? "", dryRun: dry)
        }
    }

    /// Ocena zdrowia z `mo status`.
    public static func plHealth(_ s: String) -> String {
        let head = s.components(separatedBy: ":").first?.trimmingCharacters(in: .whitespaces) ?? s
        return ["Excellent": "Doskonałe", "Good": "Dobre", "Fair": "Średnie", "Poor": "Słabe", "Critical": "Krytyczne"][head] ?? s
    }

    /// Liczba pozycji z polską odmianą: 1 pozycja, 2 pozycje, 5 pozycji.
    public static func plItems(_ n: Int) -> String {
        let last = n % 10, tens = n % 100
        let word = n == 1 ? "pozycja" : ((2...4).contains(last) && !(12...14).contains(tens) ? "pozycje" : "pozycji")
        return "\(n) \(word)"
    }

    public static func parseVersion(_ text: String) -> String? {
        cap("Mole version\\s+(\\S+)", strip(text)).map { $0[1] }
    }
}

extension SystemInfo {
    /// Aplikacja z sumą pamięci wszystkich jej procesów (łącznie z pomocniczymi).
    public struct MemApp: Identifiable, Equatable, Sendable {
        public var id: String { path }
        public let name: String
        public let path: String
        public let bytes: Int64
    }

    /// Z `ps -axo rss=,comm=`: grupuje procesy po najbardziej zewnętrznym pakiecie .app.
    public static func parseProcesses(_ text: String) -> [MemApp] {
        var sums: [String: Int64] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let m = Mole.cap("^(\\d+)\\s+(.+?\\.app)/", line), let kb = Int64(m[1]) else { continue }
            sums[m[2], default: 0] += kb * 1024
        }
        return sums.map { MemApp(name: URL(fileURLWithPath: $0.key).deletingPathExtension().lastPathComponent, path: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }

    public static func topApps(limit: Int = 8) async -> [MemApp] {
        let r = await Mole.run(URL(fileURLWithPath: "/bin/ps"), ["-axo", "rss=,comm="])
        return Array(parseProcesses(r.text).prefix(limit))
    }

    /// `purge` zwalnia nieaktywną pamięć podręczną plików. Wymaga hasła administratora (systemowe okno).
    public static func purge() async -> Bool {
        let r = await Mole.run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", "do shell script \"/usr/sbin/purge\" with administrator privileges"])
        return r.status == 0
    }
}
