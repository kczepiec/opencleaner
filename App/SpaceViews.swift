import CleanKit
import SwiftUI

/// Stan widoków Instalatory, Kopie i migawki oraz Duplikaty. Skany tylko czytają; usuwanie idzie do Kosza po potwierdzeniu.
@MainActor @Observable
final class SpaceModel {
    var installers: [SpaceTools.Group] = []
    var installersLoaded = false
    var installSel: Set<URL> = []
    var backups = SpaceTools.Backups()
    var snapshots: [String] = []
    var backupsLoaded = false
    var backupSel: Set<URL> = []
    var dupes: [SpaceTools.Group] = []
    var dupesLoaded = false
    var dupesRunning = false
    var dupSel: Set<URL> = []
    var message: String?

    func bytes(_ urls: Set<URL>, in groups: [SpaceTools.Group]) -> Int64 { groups.flatMap(\.entries).filter { urls.contains($0.url) }.reduce(0) { $0 + $1.bytes } }

    func loadInstallers(days: Int) async {
        let g = await Task.detached(priority: .utility) { SpaceTools.installers(olderThanDays: days) }.value
        withAnimation(Theme.ease) { installers = g; installersLoaded = true; installSel = Set(g.filter { $0.id != "archives" }.flatMap(\.entries).map(\.url)) }
    }

    func loadBackups() async {
        let b = await Task.detached(priority: .utility) { SpaceTools.iosBackups() }.value
        let s = await SpaceTools.snapshots()
        withAnimation(Theme.ease) { backups = b; snapshots = s; backupsLoaded = true; backupSel = [] }
    }

    func loadDuplicates(minMB: Int) async {
        dupesRunning = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let g = await Task.detached(priority: .utility) {
            SpaceTools.duplicates(roots: [home.appending(path: "Documents"), home.appending(path: "Downloads")], minBytes: Int64(minMB) * 1_000_000)
        }.value
        withAnimation(Theme.ease) {
            dupes = g; dupesLoaded = true; dupesRunning = false
            dupSel = Set(g.flatMap { $0.entries.dropFirst().map(\.url) })   // najstarszy egzemplarz zostaje
        }
    }

    /// Zestaw, w którym zaznaczono wszystkie kopie: usunięcie zabrałoby ostatni egzemplarz.
    var allSelectedSet: Bool { dupes.contains { $0.entries.allSatisfy { dupSel.contains($0.url) } } }

    func trash(_ urls: Set<URL>, then reload: () async -> Void) async {
        let r = await Task.detached { [urls] in AICleanup.trash(Array(urls)) }.value
        message = r.failed == 0 ? trf("Przeniesiono do Kosza: %@ pozycji. Opróżnij Kosz, żeby odzyskać miejsce.", "\(r.done)") : trf("Przeniesiono %@ pozycji, %@ się nie udało. %@", "\(r.done)", "\(r.failed)", r.error ?? "")
        await reload()
    }

    func deleteSnapshots() async {
        let ok = await SpaceTools.deleteSnapshots(snapshots)
        message = ok ? tr("Migawki usunięte.") : tr("Nie usunięto migawek (anulowano albo brak uprawnień).")
        await loadBackups()
    }
}

/// Lista grup z checkboxami i rozwijaniem; wspólna dla widoków przenoszących pliki do Kosza.
struct ChecklistGroup: Identifiable {
    let id: String, title: String, subtitle: String
    let entries: [AICleanup.Entry]
    var bytes: Int64 { entries.reduce(0) { $0 + $1.bytes } }
}

struct ChecklistBody: View {
    let groups: [ChecklistGroup]
    @Binding var selection: Set<URL>
    var name: (AICleanup.Entry) -> String = { $0.label ?? $0.url.lastPathComponent }
    var showGroupSize = true
    @State private var expanded: Set<String> = []

    private func state(_ g: ChecklistGroup) -> Int {
        let n = g.entries.filter { selection.contains($0.url) }.count
        return n == 0 ? 0 : (n == g.entries.count ? 2 : 1)
    }
    private func check(_ s: Int) -> some View {
        Image(systemName: s == 2 ? "checkmark.square.fill" : (s == 1 ? "minus.square.fill" : "square")).font(.system(size: 18))
            .foregroundStyle(s == 0 ? Theme.secondary.opacity(0.6) : Theme.accent)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                if i > 0 { Divider().overlay(Theme.border.opacity(0.6)) }
                let open = expanded.contains(g.id)
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button { let u = g.entries.map(\.url); if state(g) == 2 { selection.subtract(u) } else { selection.formUnion(u) } } label: { check(state(g)) }
                            .buttonStyle(.plain).accessibilityLabel(g.title)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.title).font(.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
                            Text(g.subtitle).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if showGroupSize { Text(Model.size(g.bytes)).font(.body.weight(.medium)).monospacedDigit() }
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary).rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13).contentShape(Rectangle())
                    .onTapGesture { withAnimation(Theme.quick) { if open { expanded.remove(g.id) } else { expanded.insert(g.id) } } }
                    if open {
                        VStack(spacing: 0) {
                            ForEach(g.entries.prefix(80)) { e in
                                HStack(spacing: 12) {
                                    Button { if selection.contains(e.url) { selection.remove(e.url) } else { selection.insert(e.url) } } label: { check(selection.contains(e.url) ? 2 : 0) }.buttonStyle(.plain)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(name(e)).font(.callout).lineLimit(1).truncationMode(.middle)
                                        HStack(spacing: 6) {
                                            if let d = e.date { Text(d, format: .dateTime.day().month(.abbreviated).year()) }
                                            Text(e.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).lineLimit(1).truncationMode(.middle)
                                        }.font(.caption).foregroundStyle(Theme.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Text(Model.size(e.bytes)).font(.callout).foregroundStyle(Theme.secondary).monospacedDigit()
                                    Button { NSWorkspace.shared.activateFileViewerSelecting([e.url]) } label: {
                                        Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(Theme.secondary).frame(width: 26, height: 26)
                                    }.buttonStyle(.plain).help(tr("Pokaż w Finderze")).accessibilityLabel(tr("Pokaż w Finderze"))
                                }
                                .padding(.leading, 46).padding(.trailing, 16).padding(.vertical, 7)
                            }
                        }.padding(.bottom, 8).background(Theme.field.opacity(0.35))
                    }
                }
            }
        }.cardStyle(radius: 16)
    }
}

struct TrashBar: View {
    let count: Int, bytes: Int64
    var warning: String? = nil
    var label: String? = nil
    var summary: String? = nil
    let action: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Text(warning ?? summary ?? trf("Zaznaczono: %@", "\(count)")).foregroundStyle(warning == nil ? Theme.secondary : Theme.warn).lineLimit(1)
            Spacer()
            Button(action: action) {
                Text("\(label ?? tr("Przenieś do Kosza")) · \(Model.size(bytes))").font(.body.weight(.semibold)).padding(.horizontal, 18).frame(height: 38)
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(count == 0 || warning != nil)
        }
        .padding(.horizontal, 22).padding(.vertical, 12).background(Theme.panel).overlay(alignment: .top) { Divider() }
    }
}

@MainActor private func notice(_ t: String) -> some View {
    Text(t).font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 12, fill: Theme.raised)
}

@MainActor private func trashDialog(_ count: Int, _ bytes: Int64) -> String { trf("Przenieść %@ pozycji (%@) do Kosza?", "\(count)", Model.size(bytes)) }

// MARK: Instalatory

struct InstallersView: View {
    let model: SpaceModel
    @AppStorage("set.instDays") private var days = 30
    @State private var confirm = false

    private func title(_ id: String) -> String { id == "installers" ? tr("Instalatory (.dmg, .pkg)") : (id == "images" ? tr("Obrazy dysków (.iso)") : tr("Archiwa (.zip, .7z, .rar)")) }

    var body: some View {
        let groups = model.installers.map { ChecklistGroup(id: $0.id, title: title($0.id), subtitle: trf("Pozycji: %@", "\($0.entries.count)"), entries: $0.entries) }
        VStack(spacing: 0) {
            PanelHeader(title: "Instalatory i archiwa", subtitle: model.installersLoaded ? trf("W Pobranych, starsze niż %@ dni: %@", "\(days)", Model.size(model.installers.reduce(0) { $0 + $1.bytes })) : "Sprawdzam…") {
                Picker("", selection: $days) { ForEach([14, 30, 60, 90, 180], id: \.self) { Text(trf("%@ dni", "\($0)")).tag($0) } }.labelsHidden().pickerStyle(.menu).frame(width: 110)
                Button(tr("Odśwież")) { model.message = nil; Task { await model.loadInstallers(days: days) } }
            }
            Divider()
            if !model.installersLoaded { ScrollView { ListSkeleton(rows: 5).padding(14) } }
            else if groups.isEmpty { EmptyState(title: "Brak starych instalatorów", text: "W Pobranych nie ma instalatorów, obrazów dysków ani archiwów starszych niż wybrany okres.") }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let m = model.message { notice(m) }
                        ChecklistBody(groups: groups, selection: Bindable(model).installSel)
                        Text("Archiwa nie są zaznaczone domyślnie, bo mogą zawierać Twoje dane. Pliki trafiają do Kosza.").font(.callout).foregroundStyle(Theme.secondary)
                    }.padding(22)
                }.scrollIndicators(.hidden)
                TrashBar(count: model.installSel.count, bytes: model.bytes(model.installSel, in: model.installers)) { confirm = true }
            }
        }
        .task(id: days) { await model.loadInstallers(days: days) }
        .confirmationDialog(trashDialog(model.installSel.count, model.bytes(model.installSel, in: model.installers)), isPresented: $confirm, titleVisibility: .visible) {
            Button(tr("Przenieś do Kosza"), role: .destructive) { Task { await model.trash(model.installSel) { await model.loadInstallers(days: days) } } }
            Button(tr("Anuluj"), role: .cancel) {}
        } message: { Text("Pliki da się przywrócić z Kosza, dopóki go nie opróżnisz.") }
    }
}

// MARK: Kopie iOS i migawki Time Machine

struct BackupsView: View {
    let model: SpaceModel
    @State private var confirm = false
    @State private var confirmSnaps = false

    var body: some View {
        let groups = model.backups.groups.map { g in
            ChecklistGroup(id: g.id, title: tr("Kopie urządzeń iOS"), subtitle: trf("Pozycji: %@", "\(g.entries.count)"), entries: g.entries)
        }
        VStack(spacing: 0) {
            PanelHeader(title: "Kopie i migawki", subtitle: model.backupsLoaded ? trf("Kopie iOS: %@, migawki Time Machine: %@", Model.size(model.backups.groups.reduce(0) { $0 + $1.bytes }), "\(model.snapshots.count)") : "Sprawdzam…") {
                Button(tr("Odśwież")) { model.message = nil; Task { await model.loadBackups() } }
            }
            Divider()
            if !model.backupsLoaded { ScrollView { ListSkeleton(rows: 4).padding(14) } }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let m = model.message { notice(m) }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kopie urządzeń iOS").font(.headline).padding(.leading, 2)
                            if model.backups.needsAccess {
                                notice(tr("macOS nie daje dostępu do folderu kopii. Nadaj OpenCleaner Pełny dostęp do dysku (Ustawienia systemowe, Prywatność i ochrona), żeby je zobaczyć."))
                            } else if groups.isEmpty {
                                Text("Nie znalazłem kopii iPhone'a ani iPada.").foregroundStyle(Theme.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 14)
                            } else {
                                ChecklistBody(groups: groups, selection: Bindable(model).backupSel, name: { $0.label ?? $0.url.lastPathComponent })
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Migawki Time Machine na tym Macu").font(.headline).padding(.leading, 2)
                            VStack(alignment: .leading, spacing: 10) {
                                if model.snapshots.isEmpty { Text("Brak lokalnych migawek.").foregroundStyle(Theme.secondary) }
                                else {
                                    ForEach(model.snapshots, id: \.self) { s in Label(s.replacingOccurrences(of: "-", with: ".", options: [], range: nil), systemImage: "clock.arrow.circlepath").font(.callout) }
                                    Text("macOS sam usuwa migawki, gdy brakuje miejsca. Ręczne usunięcie jest nieodwracalne i wymaga hasła administratora.").font(.callout).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                                    Button(tr("Usuń migawki…")) { confirmSnaps = true }
                                }
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 14)
                        }
                    }.padding(22)
                }.scrollIndicators(.hidden)
                if !groups.isEmpty { TrashBar(count: model.backupSel.count, bytes: model.bytes(model.backupSel, in: model.backups.groups)) { confirm = true } }
            }
        }
        .task { await model.loadBackups() }
        .confirmationDialog(trashDialog(model.backupSel.count, model.bytes(model.backupSel, in: model.backups.groups)), isPresented: $confirm, titleVisibility: .visible) {
            Button(tr("Przenieś do Kosza"), role: .destructive) { Task { await model.trash(model.backupSel) { await model.loadBackups() } } }
            Button(tr("Anuluj"), role: .cancel) {}
        } message: { Text("Z kopii odtworzysz urządzenie. Po usunięciu ostatniej kopii nie będzie czego przywrócić, dopóki nie zrobisz nowej.") }
        .confirmationDialog(trf("Usunąć %@ migawek Time Machine?", "\(model.snapshots.count)"), isPresented: $confirmSnaps, titleVisibility: .visible) {
            Button(tr("Usuń migawki"), role: .destructive) { Task { await model.deleteSnapshots() } }
            Button(tr("Anuluj"), role: .cancel) {}
        } message: { Text("Tego nie da się cofnąć. macOS poprosi o hasło administratora. Kopie Time Machine na zewnętrznym dysku zostają.") }
    }
}

// MARK: Duplikaty

struct DuplicatesView: View {
    let model: SpaceModel
    @AppStorage("set.dupMB") private var minMB = 10
    @State private var confirm = false

    var body: some View {
        let groups = model.dupes.map { g in
            ChecklistGroup(id: g.id, title: g.entries[0].url.lastPathComponent, subtitle: trf("%@ kopii po %@, do odzyskania %@", "\(g.entries.count)", Model.size(g.entries[0].bytes), Model.size(g.bytes - g.entries[0].bytes)), entries: g.entries)
        }
        let wasted = model.dupes.reduce(Int64(0)) { $0 + $1.bytes - $1.entries[0].bytes }
        VStack(spacing: 0) {
            PanelHeader(title: "Duplikaty", subtitle: model.dupesLoaded ? trf("Zestawów: %@, do odzyskania %@", "\(model.dupes.count)", Model.size(wasted)) : tr("W Dokumentach i Pobranych")) {
                Picker("", selection: $minMB) { ForEach([1, 10, 50, 100], id: \.self) { Text(trf("od %@ MB", "\($0)")).tag($0) } }.labelsHidden().pickerStyle(.menu).frame(width: 110)
                Button(model.dupesLoaded ? tr("Szukaj ponownie") : tr("Szukaj")) { model.message = nil; Task { await model.loadDuplicates(minMB: minMB) } }.disabled(model.dupesRunning)
            }
            Divider()
            if model.dupesRunning { VStack(spacing: 14) { ProgressView().controlSize(.large); Text("Porównuję pliki po rozmiarze i skrócie…").foregroundStyle(Theme.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if !model.dupesLoaded { EmptyState(title: "Szukanie duplikatów", text: "Porównam pliki w Dokumentach i Pobranych po rozmiarze i skrócie SHA-256. Nic nie jest usuwane bez Twojego potwierdzenia.", mood: .content) }
            else if groups.isEmpty { EmptyState(title: "Brak duplikatów", text: "Nie znalazłem identycznych plików większych niż wybrany rozmiar.") }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let m = model.message { notice(m) }
                        ChecklistBody(groups: groups, selection: Bindable(model).dupSel, showGroupSize: false)
                        Text("Najstarszy egzemplarz w każdym zestawie zostaje. Co najmniej jedna kopia musi zostać.").font(.callout).foregroundStyle(Theme.secondary)
                    }.padding(22)
                }.scrollIndicators(.hidden)
                TrashBar(count: model.dupSel.count, bytes: model.bytes(model.dupSel, in: model.dupes),
                         warning: model.allSelectedSet ? tr("W jednym zestawie zaznaczono wszystkie kopie") : nil) { confirm = true }
            }
        }
        .confirmationDialog(trashDialog(model.dupSel.count, model.bytes(model.dupSel, in: model.dupes)), isPresented: $confirm, titleVisibility: .visible) {
            Button(tr("Przenieś do Kosza"), role: .destructive) { Task { await model.trash(model.dupSel) { await model.loadDuplicates(minMB: minMB) } } }
            Button(tr("Anuluj"), role: .cancel) {}
        } message: { Text("Pliki da się przywrócić z Kosza, dopóki go nie opróżnisz.") }
    }
}
