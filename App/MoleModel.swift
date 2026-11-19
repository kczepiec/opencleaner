import CleanKit
import Observation
import SwiftUI

/// Stan funkcji opartych na `mo`: instalacja, podglądy i uruchomienia, lista aplikacji, status systemu.
@MainActor @Observable
final class MoleModel {
    enum Engine { case checking, missing, installing, ready }
    struct Run {
        var preview: Mole.Preview?
        var report: Mole.OptimizeReport?
        var running = false
        var line = ""
        var seen: [String] = []
        var failed: String?
        var applied: String?
    }

    var engine: Engine = .checking
    var installLog: [String] = []
    var installError: String?
    var runs: [String: Run] = [:]
    var apps: [Mole.App] = []
    var appsLoaded = false
    var appPlan: [String: [Mole.PlanApp]] = [:]
    var systemParts: [SystemInfo.Part] = []
    var runtimes: [SystemInfo.Runtime] = []
    var assetsBytes: Int64?
    var protectedBytes: [String: Int64] = [:]
    var systemLoaded = false
    var deletingRuntime: String?
    var runtimeError: String?
    var appBusy: String?
    var status: Mole.Status?
    var version: String?
    var latestVersion: String?
    var history: [Mole.HistorySession] = []
    var updating = false
    var updateMessage: String?
    var memApps: [SystemInfo.MemApp] = []
    var purging = false
    var purgeMessage: String?

    /// Wiersz aktualizacji pokazujemy tylko wtedy, gdy wydanie na GitHubie jest nowsze niż zainstalowane.
    var updateAvailable: Bool {
        guard let l = latestVersion, let v = version else { return false }
        return Mole.isNewer(l, than: v)
    }

    func total(_ kind: String) -> Int64 { runs[kind]?.preview?.bytes ?? 0 }

    func check() { engine = Mole.executable == nil ? .missing : .ready }

    func install() async {
        engine = .installing; installLog = []; installError = nil
        let err = await Mole.install { line in Task { @MainActor in self.installLog.append(line) } }
        installError = err
        check()
    }

    /// `mo <kind> --dry-run`: nic nie jest zmieniane.
    func preview(_ kind: String) async {
        runs[kind, default: Run()].running = true
        runs[kind]?.failed = nil; runs[kind]?.applied = nil; runs[kind]?.seen = []; runs[kind]?.line = ""
        let r = await Mole.mo([kind, "--dry-run"]) { line in Task { @MainActor in self.note(kind, line) } }
        let p = Mole.parse(r.text)
        let report = kind == "optimize" ? Mole.parseOptimize(r.text) : nil
        withAnimation(Theme.ease) { runs[kind]?.preview = p; runs[kind]?.report = report }
        if p.groups.isEmpty, report == nil || report?.steps.isEmpty == true, r.status != 0 { runs[kind]?.failed = "mo \(kind) zakończyło się błędem (kod \(r.status))." }
        withAnimation(Theme.ease) { runs[kind]?.running = false }
    }

    /// Postęp na żywo: kategorie, które Mole już zaczął sprawdzać, i bieżąca pozycja (po polsku).
    private func note(_ kind: String, _ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("➤ ") {
            let t = Mole.pl(String(line.dropFirst(2)))
            if runs[kind]?.seen.last != t { runs[kind]?.seen.append(t) }
        } else if line.hasPrefix("→ ") {
            let body = String(line.dropFirst(2))
            runs[kind]?.line = Mole.pl(body.components(separatedBy: " · ").first ?? body)
        }
    }

    /// `mo <kind>`: prawdziwe wykonanie. Mole kasuje na stałe, bez Kosza.
    func apply(_ kind: String) async {
        runs[kind, default: Run()].running = true
        let r = await Mole.mo([kind]) { line in Task { @MainActor in self.runs[kind]?.line = line } }
        runs[kind]?.running = false
        runs[kind]?.preview = nil; runs[kind]?.report = nil
        runs[kind]?.applied = r.text.split(whereSeparator: \.isNewline).suffix(6).joined(separator: "\n")
    }

    func loadApps() async {
        guard !appsLoaded else { return }
        let r = await Mole.mo(["uninstall", "--list"])
        apps = Mole.parseApps(r.text).sorted { (Mole.parseSize($0.size) ?? 0) > (Mole.parseSize($1.size) ?? 0) }
        appsLoaded = true
    }

    func previewUninstall(_ app: Mole.App) async {
        appBusy = app.id
        let r = await Mole.mo(["uninstall", "--dry-run", app.uninstallName])
        withAnimation(Theme.ease) { appPlan[app.id] = Mole.parseUninstallPlan(r.text) }
        appBusy = nil
    }

    /// Części systemu (APFS), symulatory Xcode i rozmiar zasobów systemowych.
    func loadSystem() async {
        guard !systemLoaded else { return }
        async let parts = SystemInfo.apfs()
        async let rts = SystemInfo.runtimes()
        let assets = Task.detached(priority: .utility) { Scanner.size(of: URL(fileURLWithPath: "/System/Library/AssetsV2")) }
        systemParts = await parts
        runtimes = await rts
        let a = await assets.value
        assetsBytes = a > 0 ? a : nil
        systemLoaded = true
    }

    func deleteRuntime(_ rt: SystemInfo.Runtime) async {
        deletingRuntime = rt.id; runtimeError = nil
        let ok = await SystemInfo.deleteRuntime(rt.id)
        if ok { runtimes.removeAll { $0.id == rt.id }; systemLoaded = false; await loadSystem() }
        else { runtimeError = "Nie udało się usunąć \(rt.name). Spróbuj w Xcode: Settings, Components." }
        deletingRuntime = nil
    }

    /// Opt-in: liczy foldery, do których macOS pyta o zgodę (Zdjęcia, Muzyka, Filmy, Pulpit).
    func measureProtected() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for name in ["Pictures", "Music", "Movies", "Desktop"] {
            let url = home.appending(path: name)
            let b = await Task.detached(priority: .utility) { Scanner.size(of: url, force: true) }.value
            protectedBytes[name] = b
        }
    }

    func refreshStatus() async {
        let r = await Mole.mo(["status", "--json"])
        if let s = Mole.parseStatus(r.text) { status = s }
    }

    func loadMoleInfo() async {
        guard Mole.executable != nil else { return }
        async let v = Mole.mo(["--version"])
        async let h = Mole.mo(["history", "--json"])
        version = Mole.parseVersion(await v.text)
        latestVersion = await Mole.latestVersion()
        history = Array(Mole.parseHistory(await h.text).prefix(12))
    }

    func updateMole() async {
        updating = true; updateMessage = nil
        let r = await Mole.mo(["update"])
        updateMessage = r.status == 0 ? "Gotowe. Mole jest aktualny." : "Aktualizacja nie powiodła się."
        updating = false
        await loadMoleInfo()
    }

    func loadMemory() async { memApps = await SystemInfo.topApps() }

    /// Aplikacje, które wolno zamknąć stąd: zwykłe, uruchomione, bez Findera, OpenBota i samego Czysto.
    func runningApp(_ a: SystemInfo.MemApp) -> NSRunningApplication? {
        let blocked: Set<String> = ["com.apple.finder", "app.openbot.desktop", Bundle.main.bundleIdentifier ?? ""]
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.path == a.path && $0.activationPolicy == .regular && !blocked.contains($0.bundleIdentifier ?? "")
        }
    }

    func quit(_ a: SystemInfo.MemApp) async {
        runningApp(a)?.terminate()
        try? await Task.sleep(for: .seconds(2))
        await loadMemory()
        await refreshStatus()
    }

    func purge() async {
        purging = true; purgeMessage = nil
        let ok = await SystemInfo.purge()
        purgeMessage = ok ? "Zwolniono pamięć podręczną plików." : "Nie zwolniono (anulowano albo brak uprawnień)."
        purging = false
        await refreshStatus()
    }
}
