import CleanKit
import Observation
import SwiftUI

@MainActor @Observable
final class Model {
    enum Phase { case scanning, ready, cleaning }
    var phase: Phase = .scanning
    var status = "Skanuję cache…"
    var selected: Set<URL> = []
    var result: String?
    var volume: Volume? {
        didSet { if let v = volume, v != oldValue { history = SpaceHistory.record(free: v.available, total: v.total) } }
    }
    var history: [SpaceHistory.Point] = SpaceHistory.load()
    var slices: [DiskSlice] = []
    var diskReady = false
    var reposReady = false
    var large: [LargeFile] = []
    var largeReady = false
    var largeScanning = ""
    /// Repozytorium uznajemy za nieużywane po tylu dniach bez aktywności w git.
    var idleDays = UserDefaults.standard.object(forKey: "set.idleDays") as? Int ?? 60

    private var base: [Item] = []
    private var repoItems: [Item] = []
    private var measured: DiskUsage.Measured?
    private var measureTask: Task<Void, Never>?
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let locations = Scanner.locations()

    var items: [Item] { base + repoItems }
    func rows(_ c: CleanKit.Category) -> [Item] {
        let all = items.filter { $0.category == c }
        return c == .repos ? all.filter { ($0.idleDays ?? 0) >= idleDays } : all
    }
    func bytes(_ items: [Item]) -> Int64 { items.reduce(0) { $0 + $1.bytes } }
    var reclaimable: Int64 { bytes(items.filter { selected.contains($0.url) && $0.preselected }) }
    var trashBytes: Int64 { slices.first { $0.kind == .trash }?.bytes ?? 0 }

    func setIdle(_ days: Int) {
        idleDays = days
        let repos = items.filter { $0.category == .repos }
        selected.subtract(repos.map(\.url))
        // "Wszystkie" (0 dni) niczego nie zaznacza: zaznaczanie całości trzeba zrobić świadomie.
        if days > 0 { selected.formUnion(rows(.repos).map(\.url)) }
    }

    func refresh() async {
        phase = .scanning
        status = "Skanuję cache…"
        let locs = locations
        base = await Task.detached(priority: .userInitiated) { Scanner.scan(locs) }.value
        selected = Set(base.filter(\.preselected).map(\.url)).union(selected.filter { u in repoItems.contains { $0.url == u } })
        phase = .ready
        measureTask?.cancel()
        measureTask = Task { await measure() }
    }

    private func measure() async {
        diskReady = false; reposReady = false; repoItems = []
        let h = home
        // Zajęte i wolne miejsce znamy od razu; podział doliczamy w tle.
        if let v = Volume.at(h) {
            volume = v
            if slices.isEmpty { slices = [DiskSlice(kind: .system, bytes: v.used), DiskSlice(kind: .free, bytes: v.available)] }
        }
        // Każdy folder repozytoriów skanuje się osobno, a wyniki lądują na liście po kolei: jeden folder zatrzymany
        // przez okno zgody macOS (np. Pulpit w iCloud) nie wstrzymuje reszty.
        status = "Szukam repozytoriów…"
        let diskTask = Task.detached(priority: .utility) { await DiskUsage.measure(home: h) }
        let scanRepos = UserDefaults.standard.object(forKey: "set.scanRepos") as? Bool ?? true
        let roots = scanRepos ? Repos.roots(home: h) : []
        await withTaskGroup(of: [Item].self) { group in
            for r in roots { group.addTask(priority: .userInitiated) { await Repos.scan(root: r) } }
            for await batch in group {
                guard !Task.isCancelled else { return }
                let known = Set(repoItems.map(\.url))
                repoItems = (repoItems + batch.filter { !known.contains($0.url) }).sorted { $0.bytes > $1.bytes }
                selected.formUnion(batch.filter { ($0.idleDays ?? 0) >= idleDays }.map(\.url))
                rebuildSlices()
            }
        }
        reposReady = true
        status = "Liczę miejsce na dysku…"
        if let m = await diskTask.value { measured = m; rebuildSlices() }
        diskReady = true
        if !largeReady {
            let mb = UserDefaults.standard.object(forKey: "set.largeMB") as? Int ?? 100
            large = await Task.detached(priority: .utility) {
                Scanner.largeFiles(home: h, minBytes: Int64(mb) * 1_000_000) { dir in Task { @MainActor in self.largeScanning = dir } }
            }.value
            largeReady = true
        }
    }

    var protectedPaths = Protected.list()

    /// Dodaje wyjątek i od razu chowa pasujące pozycje z list.
    func protect(_ url: URL) {
        let p = url.standardizedFileURL.path
        guard !protectedPaths.contains(p) else { return }
        protectedPaths.append(p); Protected.save(protectedPaths)
        large.removeAll { Protected.contains($0.url, in: [p]) }
        base.removeAll { Protected.contains($0.url, in: [p]) }; repoItems.removeAll { Protected.contains($0.url, in: [p]) }
    }

    func unprotect(_ path: String) {
        protectedPaths.removeAll { $0 == path }; Protected.save(protectedPaths)
        largeReady = false; Task { await refresh() }
    }

    /// Duży plik do Kosza (da się przywrócić); z listy znika tylko po powodzeniu.
    func trashLarge(_ url: URL) -> Bool {
        guard (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil else { return false }
        large.removeAll { $0.url == url }
        return true
    }

    private func rebuildSlices() {
        guard let m = measured else { return }
        volume = m.volume
        slices = DiskUsage.slices(volume: m.volume, apps: m.apps, homeChildren: m.homeChildren, scanned: items, home: home)
    }

    func clean(_ chosen: [Item]) async {
        phase = .cleaning
        // Zależności z repozytoriów mają własne, dokładne zezwolenia (tylko te foldery, które znalazł skan).
        let locs = locations + repoItems.map { Location(url: $0.url, category: .repos, perChild: false, preselected: false) }
        let r = await Task.detached(priority: .userInitiated) { Cleaner.trash(chosen, within: locs) }.value
        repoItems.removeAll { i in chosen.contains { $0.url == i.url } }
        result = r.failures.isEmpty
            ? trf("Przeniesiono do Kosza: %@. Opróżnij Kosz, żeby odzyskać miejsce.", "\(Self.size(r.freed))")
            : trf("Przeniesiono %@. Nie udało się usunąć %@ pozycji (np. %@: %@).", "\(Self.size(r.freed))", "\(r.failures.count)", "\(r.failures[0].item.name)", "\(r.failures[0].reason)")
        await refresh()
    }

    static func size(_ b: Int64) -> String {
        b <= 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}
