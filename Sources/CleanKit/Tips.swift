import CoreServices
import Foundation

/// Porady oszczędzania miejsca: cache narzędzi (npm, yarn, pnpm, Homebrew, pip, uv, Cargo, Gradle...), Docker i dawno nieużywane aplikacje.
/// Skan niczego nie zmienia. Akcje wykonuje dopiero `Tips.run`, po potwierdzeniu w UI.
public enum Tips {
    public enum Action: Sendable, Equatable {
        /// Polecenie narzędzia (np. `npm cache clean --force`): to ono wie, co jest bezpieczne.
        case command(exe: String, args: [String])
        /// Folder odtwarzany przez narzędzie: trafia do Kosza.
        case trash([URL])
    }

    public struct Tip: Identifiable, Sendable, Equatable {
        public let id: String
        public let symbol: String
        public let title: String
        public let detail: String
        public let bytes: Int64
        public let action: Action?
        public var warning: String? = nil

        public init(id: String, symbol: String, title: String, detail: String, bytes: Int64, action: Action?, warning: String? = nil) {
            self.id = id; self.symbol = symbol; self.title = title; self.detail = detail; self.bytes = bytes; self.action = action; self.warning = warning
        }

        /// Polecenie albo opis akcji po polsku, do okna potwierdzenia.
        public var actionText: String {
            switch action {
            case .command(let exe, let args): ([URL(fileURLWithPath: exe).lastPathComponent] + args).joined(separator: " ")
            case .trash(let urls): "Do Kosza: \(urls.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }.joined(separator: ", "))"
            case nil: ""
            }
        }
    }

    public struct UnusedApp: Identifiable, Sendable, Equatable {
        public let url: URL
        public let name: String
        public let bytes: Int64
        public let lastUsed: Date?
        public var id: URL { url }
        public func days(now: Date = Date()) -> Int? { lastUsed.map { max(0, Calendar.current.dateComponents([.day], from: $0, to: now).day ?? 0) } }
    }

    public struct Result: Sendable {
        public var tips: [Tip] = []
        public var apps: [UnusedApp] = []
    }

    // MARK: narzędzia z własnym cache

    private struct Tool {
        let id, symbol, title, detail: String
        let paths: [String]
        let exe: String?
        let args: [String]
        var warning: String? = nil
    }

    private static let tools: [Tool] = [
        Tool(id: "npm", symbol: "shippingbox", title: "npm", detail: "Pobrane paczki. npm pobierze je ponownie, gdy będą potrzebne.",
             paths: [".npm/_cacache"], exe: "npm", args: ["cache", "clean", "--force"]),
        Tool(id: "yarn", symbol: "shippingbox", title: "Yarn", detail: "Cache paczek Yarn. Odtwarza się przy następnej instalacji.",
             paths: ["Library/Caches/Yarn", ".yarn/berry/cache"], exe: "yarn", args: ["cache", "clean"]),
        Tool(id: "pnpm", symbol: "shippingbox", title: "pnpm", detail: "Magazyn paczek pnpm. Polecenie prune usuwa tylko paczki, których nie używa żaden projekt, więc zwolni mniej niż pokazany rozmiar.",
             paths: [".local/share/pnpm/store", "Library/pnpm/store"], exe: "pnpm", args: ["store", "prune"]),
        Tool(id: "brew", symbol: "mug", title: "Homebrew", detail: "Pobrane pakiety i stare wersje. Polecenie cleanup zostawia to, co jest zainstalowane.",
             paths: ["Library/Caches/Homebrew"], exe: "brew", args: ["cleanup", "--prune=all"]),
        Tool(id: "pip", symbol: "shippingbox", title: "pip (Python)", detail: "Pobrane paczki Python. Odtwarzają się przy instalacji.",
             paths: ["Library/Caches/pip", ".cache/pip"], exe: "python3", args: ["-m", "pip", "cache", "purge"]),
        Tool(id: "uv", symbol: "shippingbox", title: "uv (Python)", detail: "Cache uv. Odtwarza się przy następnym uruchomieniu.",
             paths: [".cache/uv"], exe: "uv", args: ["cache", "clean"]),
        Tool(id: "bun", symbol: "shippingbox", title: "Bun", detail: "Cache paczek Bun. Odtwarza się przy instalacji.",
             paths: [".bun/install/cache"], exe: "bun", args: ["pm", "cache", "rm"]),
        Tool(id: "cargo", symbol: "gearshape.2", title: "Cargo (Rust)", detail: "Pobrane źródła paczek. Cargo pobierze je ponownie przy następnym buildzie.",
             paths: [".cargo/registry/cache", ".cargo/registry/src"], exe: nil, args: [],
             warning: "Następny build pobierze zależności od nowa."),
        Tool(id: "gradle", symbol: "gearshape.2", title: "Gradle", detail: "Cache zależności i buildów. Gradle odtworzy go sam.",
             paths: [".gradle/caches"], exe: nil, args: [], warning: "Następny build potrwa dłużej."),
        Tool(id: "pods", symbol: "gearshape.2", title: "CocoaPods", detail: "Pobrane specyfikacje i paczki. Odtwarzają się przy `pod install`.",
             paths: ["Library/Caches/CocoaPods"], exe: nil, args: []),
        Tool(id: "xcode", symbol: "hammer", title: "Xcode: DerivedData", detail: "Pliki pośrednie buildów. Xcode zbuduje je od nowa.",
             paths: ["Library/Developer/Xcode/DerivedData"], exe: nil, args: [], warning: "Następny build projektu będzie pełny."),
        Tool(id: "hf", symbol: "brain", title: "Hugging Face (modele)", detail: "Pobrane modele i zbiory danych. Biblioteki pobiorą je ponownie.",
             paths: [".cache/huggingface"], exe: nil, args: [], warning: "Modele potrafią mieć dziesiątki GB i pobierają się długo."),
    ]

    private static let searchDirs: [String] = {
        let h = NSHomeDirectory()
        return ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "\(h)/.local/bin", "\(h)/.bun/bin", "\(h)/.cargo/bin",
                "/Applications/Docker.app/Contents/Resources/bin"]
    }()

    /// Ścieżka programu w typowych katalogach (aplikacja z Docka nie widzi PATH z terminala).
    public static func find(_ exe: String) -> String? {
        let fm = FileManager.default
        for d in searchDirs where fm.isExecutableFile(atPath: "\(d)/\(exe)") { return "\(d)/\(exe)" }
        // nvm i podobne
        let nvm = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".nvm/versions/node")
        if let vs = try? fm.contentsOfDirectory(atPath: nvm.path).sorted(by: >) {
            for v in vs where fm.isExecutableFile(atPath: nvm.appending(path: "\(v)/bin/\(exe)").path) { return nvm.appending(path: "\(v)/bin/\(exe)").path }
        }
        return nil
    }

    // MARK: Docker

    /// "1.2GB (45%)" na bajty. Docker liczy dziesiętnie (1 kB = 1000 B).
    public static func parseBytes(_ s: String) -> Int64? {
        let head = s.split(separator: " ").first.map(String.init) ?? s
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("B", 1)]
        let up = head.uppercased()
        for (u, m) in units where up.hasSuffix(u) {
            guard let v = Double(up.dropLast(u.count)) else { return nil }
            return Int64(v * m)
        }
        return nil
    }

    /// Wynik `docker system df --format '{{json .}}'`: typ i ile da się odzyskać.
    public static func parseDockerDF(_ text: String) -> [(type: String, reclaimable: Int64)] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let t = o["Type"] as? String, let r = o["Reclaimable"] as? String, let b = parseBytes(r) else { return nil }
            return (t, b)
        }
    }

    private static func dockerTip() async -> Tip? {
        guard let docker = find("docker") else { return nil }
        let r = await Mole.run(URL(fileURLWithPath: docker), ["system", "df", "--format", "{{json .}}"])
        if r.status == 0 {
            let parts = parseDockerDF(r.text)
            let total = parts.reduce(Int64(0)) { $0 + $1.reclaimable }
            guard total > 50_000_000 else { return nil }
            let list = parts.filter { $0.reclaimable > 0 }.map { "\(dockerName($0.type)) \(fmt($0.reclaimable))" }.joined(separator: ", ")
            return Tip(id: "docker", symbol: "cube.box", title: "Docker", detail: L10n.t("Do odzyskania: %@. Woluminy z danymi zostają.", list),
                       bytes: total, action: .command(exe: docker, args: ["system", "prune", "-af"]),
                       warning: "Usuwa zatrzymane kontenery, nieużywane obrazy (trzeba je pobrać ponownie), sieci i cache buildów.")
        }
        // Docker wyłączony: pokazujemy tylko, ile zajmuje jego dysk.
        let raw = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        if let v = try? raw.resourceValues(forKeys: [.totalFileAllocatedSizeKey]), let b = v.totalFileAllocatedSize, b > 500_000_000 {
            return Tip(id: "docker", symbol: "cube.box", title: "Docker (wyłączony)",
                       detail: L10n.t("Dysk wirtualny Dockera zajmuje %@. Uruchom Docker i odśwież porady, a policzę, ile da się zwolnić.", fmt(Int64(b))), bytes: Int64(b), action: nil)
        }
        return nil
    }

    private static func dockerName(_ t: String) -> String {
        switch t {
        case "Images": L10n.t("obrazy")
        case "Containers": L10n.t("kontenery")
        case "Local Volumes": L10n.t("woluminy")
        case "Build Cache": L10n.t("cache buildów")
        default: t
        }
    }

    private static func fmt(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

    // MARK: nieużywane aplikacje

    /// Ostatnie użycie z Spotlight; gdy go brak, data dodania. Aplikacje Apple pomijamy.
    public static func unusedApps(minDays: Int, now: Date = Date(), roots: [URL]? = nil) -> [UnusedApp] {
        let fm = FileManager.default
        let dirs = roots ?? [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Applications")]
        var out: [UnusedApp] = []
        for d in dirs {
            let apps = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? []
            for a in apps where a.pathExtension == "app" {
                if Bundle(url: a)?.bundleIdentifier?.hasPrefix("com.apple.") == true { continue }
                guard let item = MDItemCreateWithURL(nil, a as CFURL) else { continue }
                let used = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date ?? MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
                guard let used else { continue }
                let days = Calendar.current.dateComponents([.day], from: used, to: now).day ?? 0
                guard days >= minDays else { continue }
                out.append(UnusedApp(url: a, name: a.deletingPathExtension().lastPathComponent, bytes: Scanner.size(of: a), lastUsed: used))
            }
        }
        return out.sorted { $0.bytes > $1.bytes }
    }

    // MARK: skan

    public static func scan(minDays: Int) async -> Result {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        async let docker = dockerTip()
        async let apps = Task.detached(priority: .utility) { unusedApps(minDays: minDays) }.value
        var tips: [Tip] = await Task.detached(priority: .utility) {
            tools.compactMap { t -> Tip? in
                let existing = t.paths.map { home.appending(path: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
                let bytes = existing.reduce(Int64(0)) { $0 + Scanner.size(of: $1) }
                guard bytes > 20_000_000 else { return nil }
                let action: Action = t.exe.flatMap(find).map { .command(exe: $0, args: t.args) } ?? .trash(existing)
                return Tip(id: t.id, symbol: t.symbol, title: t.title, detail: t.detail, bytes: bytes, action: action, warning: t.warning)
            }
        }.value
        if let d = await docker { tips.append(d) }
        return Result(tips: tips.sorted { $0.bytes > $1.bytes }, apps: await apps)
    }

    // MARK: wykonanie

    /// Wykonuje akcję porady. Do Kosza trafiają tylko foldery, które wskazał skan (wewnątrz katalogu domowego).
    public static func run(_ action: Action) async -> (ok: Bool, message: String) {
        switch action {
        case .command(let exe, let args):
            let r = await Mole.run(URL(fileURLWithPath: exe), args)
            let tail = r.text.split(whereSeparator: \.isNewline).suffix(2).joined(separator: " ")
            return r.status == 0 ? (true, L10n.t("Gotowe.")) : (false, L10n.t("Polecenie zakończyło się błędem (kod %@). %@", "\(r.status)", tail))
        case .trash(let urls):
            let home = NSHomeDirectory() + "/"
            var failed = 0
            let keep = Protected.list()
            for u in urls {
                guard u.standardizedFileURL.path.hasPrefix(home), !Protected.contains(u, in: keep) else { failed += 1; continue }
                do { try FileManager.default.trashItem(at: u, resultingItemURL: nil) } catch { failed += 1 }
            }
            return failed == 0 ? (true, L10n.t("Przeniesiono do Kosza. Opróżnij Kosz, żeby odzyskać miejsce.")) : (false, L10n.t("Nie udało się przenieść %@ pozycji.", "\(failed)"))
        }
    }
}
