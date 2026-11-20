import CleanKit
import SwiftUI

/// Nieużywane repozytoria (natywny skan, odtwarzalne zależności; usuwa do Kosza).
struct ReposView: View {
    let model: Model
    @State private var confirm = false

    private var rows: [Item] { model.rows(.repos).sorted { $0.bytes > $1.bytes } }
    private var chosen: [Item] { rows.filter { model.selected.contains($0.url) } }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Nieużywane repozytoria", subtitle: subtitle) {
                Picker("Nieużywane od", selection: Binding(get: { model.idleDays }, set: { model.setIdle($0) })) {
                    Text(tr("Wszystkie")).tag(0)
                    ForEach([14, 30, 60, 90, 180], id: \.self) { Text(trf("%@ dni", "\($0)")).tag($0) }
                }.pickerStyle(.menu).frame(width: 140)
                Button(tr("Do Kosza…")) { confirm = true }.buttonStyle(.borderedProminent)
                    .disabled(chosen.isEmpty || model.phase != .ready)
            }
            Divider()
            content
            Divider()
            HStack {
                Text(trf("Zaznaczono %@ z %@, %@", "\(chosen.count)", "\(rows.count)", "\(Model.size(model.bytes(chosen)))")).foregroundStyle(Theme.secondary).monospacedDigit()
                Spacer()
            }.font(.callout).padding(.horizontal, 22).padding(.vertical, 10)
        }
        .confirmationDialog(trf("Przenieść %@ pozycji (%@) do Kosza?", "\(chosen.count)", "\(Model.size(model.bytes(chosen)))"), isPresented: $confirm, titleVisibility: .visible) {
            Button(tr("Przenieś do Kosza"), role: .destructive) { let c = chosen; Task { await model.clean(c) } }
            Button(tr("Anuluj"), role: .cancel) {}
        } message: { Text(tr("Usuwam tylko foldery ignorowane przez git (np. node_modules). Da się je przywrócić z Kosza albo odtworzyć instalacją.")) }
    }

    private var subtitle: String {
        if !model.reposReady { return "Szukam repozytoriów…" }
        return trf("%@ pozycji, %@", "\(rows.count)", "\(Model.size(model.bytes(rows)))")
    }

    @ViewBuilder private var content: some View {
        if model.phase == .cleaning { TableSkeleton() }
        else if rows.isEmpty {
            let all = model.items.filter { $0.category == .repos }
            if all.isEmpty && !model.reposReady { TableSkeleton() }
            else if all.isEmpty { EmptyState(title: "Brak repozytoriów z zależnościami", text: "Nie znalazłem folderów git z node_modules, target, .venv ani podobnych.") }
            else { EmptyState(title: trf("Nic nieużywanego od %@ dni", "\(model.idleDays)"), text: trf("Są %@ foldery zależności (%@) w repozytoriach używanych niedawno. Wybierz krótszy okres.", "\(all.count)", "\(Model.size(model.bytes(all)))")) }
        } else {
            let ids = Set(rows.map(\.id))
            let selection = Binding<Set<URL>>(get: { model.selected.intersection(ids) },
                                              set: { model.selected = model.selected.subtracting(ids).union($0) })
            FileList(rows: rows.map { item in
                FileRow(id: item.url, title: item.name, icon: nil, bytes: item.bytes,
                        subtitle: trf("%@, bez zmian od %@ dni", "\(item.repo.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") } ?? "")", "\(item.idleDays ?? 0)"))
            }, selection: selection, checks: true)
        }
    }
}

/// Największe pliki w katalogu domowym: szukanie po nazwie i ścieżce, w wierszu Finder i Kosz (z potwierdzeniem).
struct LargeFilesView: View {
    let model: Model
    @AppStorage("set.largeMB") private var largeMB = 100
    @State private var selection: Set<URL> = []
    @State private var query = ""
    @State private var confirm: LargeFile?
    @State private var failed: String?

    /// "Przeszukuję: ~/Sites/app/…/cache": początek i koniec ścieżki, żeby mieściła się w jednej linii.
    private var scanningText: String {
        guard !model.largeScanning.isEmpty else { return model.status }
        let parts = model.largeScanning.replacingOccurrences(of: NSHomeDirectory(), with: "~").split(separator: "/").map(String.init)
        let short = parts.count > 4 ? (parts.prefix(2) + ["…", parts.last ?? ""]).joined(separator: "/") : parts.joined(separator: "/")
        return tr("Przeszukuję:") + " " + short
    }

    private var shown: [LargeFile] {
        query.isEmpty ? model.large : model.large.filter { $0.url.path.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Duże pliki", subtitle: model.largeReady ? trf("Powyżej %@ MB, bez Kosza i iCloud.", "\(largeMB)") : scanningText) {
                if model.largeReady { Text(Model.size(model.large.reduce(0) { $0 + $1.bytes })).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.secondary) }
            }
            Divider()
            if !model.largeReady { TableSkeleton(search: true, actions: 2) }
            else if model.large.isEmpty { EmptyState(title: "Brak dużych plików", text: trf("Nie ma tu niczego powyżej %@ MB.", "\(largeMB)")) }
            else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                    TextField(tr("Szukaj w plikach"), text: $query).textFieldStyle(.plain)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondary) }.buttonStyle(.plain).accessibilityLabel("Wyczyść wyszukiwanie") }
                }
                .padding(.horizontal, 12).frame(height: 36)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 4)
                if let f = failed { Text(f).font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 12, fill: Theme.raised).padding(.horizontal, 22).padding(.top, 6) }
                if shown.isEmpty { EmptyState(title: "Brak wyników", text: "Żaden duży plik nie pasuje do tego, co wpisano.") }
                else {
                    FileList(rows: shown.map { f in
                        FileRow(id: f.url, title: f.url.lastPathComponent, icon: NSWorkspace.shared.icon(forFile: f.url.path), bytes: f.bytes,
                                subtitle: f.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), modified: f.modified, kind: f.kind)
                    }, selection: $selection, checks: false, onTrash: { url in confirm = model.large.first { $0.url == url } }, onProtect: { url in withAnimation(Theme.ease) { model.protect(url) } })
                }
            }
        }
        .confirmationDialog(trf("Przenieść do Kosza %@?", "\(confirm?.url.lastPathComponent ?? "")"), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            Button(tr("Przenieś do Kosza"), role: .destructive) {
                if let f = confirm { withAnimation(Theme.ease) { failed = model.trashLarge(f.url) ? nil : trf("Nie udało się przenieść %@ do Kosza.", "\(f.url.lastPathComponent)") } }
            }
            Button(tr("Anuluj"), role: .cancel) {}
        } message: {
            switch confirm?.kind {
            case .cache?: Text(tr("To cache: aplikacja odtworzy go sama. Plik trafi do Kosza, a miejsce zwolni się po jego opróżnieniu."))
            case .appData?: Text(tr("To dane aplikacji (ustawienia, bazy, wtyczki). Po usunięciu program może utracić dane lub poprosić o ponowną konfigurację. Plik trafi do Kosza i da się go przywrócić, dopóki go nie opróżnisz."))
            default: Text(trf("Plik trafi do Kosza i zwolni %@ dopiero po jego opróżnieniu. Da się go przywrócić.", "\(confirm.map { Model.size($0.bytes) } ?? "")"))
            }
        }
    }
}

struct FileRow: Identifiable {
    let id: URL
    let title: String
    let icon: NSImage?
    let bytes: Int64
    var subtitle = ""
    var modified: Date? = nil
    var kind: LargeFile.Kind = .other
}

/// Lista plików w stylu reszty aplikacji: wiersze na jednolitym tle, bez systemowej tabeli i nagłówka.
/// `onTrash` dodaje do wiersza kosz; folder (pokaż w Finderze) jest zawsze.
struct FileList: View {
    let rows: [FileRow]
    @Binding var selection: Set<URL>
    let checks: Bool
    var onTrash: ((URL) -> Void)? = nil
    var onProtect: ((URL) -> Void)? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(rows) { r in
                    FileListRow(row: r, on: selection.contains(r.id), checks: checks, onTrash: onTrash, onProtect: onProtect) {
                        if selection.contains(r.id) { selection.remove(r.id) } else if checks { selection.insert(r.id) } else { selection = [r.id] }
                    }
                }
            }.padding(10)
        }.scrollIndicators(.hidden)
    }
}

private struct FileListRow: View {
    let row: FileRow
    let on: Bool
    let checks: Bool
    let onTrash: ((URL) -> Void)?
    var onProtect: ((URL) -> Void)? = nil
    let tap: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            if checks {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 18))
                    .foregroundStyle(on ? Theme.accent : Theme.secondary.opacity(0.6))
            }
            if let icon = row.icon { Image(nsImage: icon).resizable().interpolation(.high).frame(width: 28, height: 28) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(row.title).font(.body.weight(.medium)).lineLimit(1)
                    if row.kind == .cache { tag("Cache, bezpieczne", Theme.ok) }
                    else if row.kind == .appData { tag("Dane aplikacji", Theme.warn) }
                }
                Text(row.subtitle).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Model.size(row.bytes)).monospacedDigit().foregroundStyle(Theme.secondary)
                if let d = row.modified { Text(d, format: .dateTime.day().month(.abbreviated).year()).font(.caption).foregroundStyle(Theme.secondary.opacity(0.8)) }
            }
            HStack(spacing: 4) {
                action("folder", "Pokaż w Finderze", tint: Theme.secondary) { NSWorkspace.shared.activateFileViewerSelecting([row.id]) }
                if let onProtect { action("lock.shield", "Chroń przed czyszczeniem", tint: Theme.accent) { onProtect(row.id) } }
                if let onTrash { action("trash", "Przenieś do Kosza", tint: Color(hex: 0xE9735F)) { onTrash(row.id) } }
            }
            .opacity(hover || on ? 1 : 0.55)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(on ? Theme.raised : (hover ? Theme.raised.opacity(0.5) : .clear), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .onHover { hover = $0 }
        .animation(Theme.quick, value: hover)
        .help(row.id.path)
        .contextMenu { Button(tr("Pokaż w Finderze")) { NSWorkspace.shared.activateFileViewerSelecting([row.id]) } }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(tr(text)).font(.caption2.weight(.semibold)).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2).background(color.opacity(0.14), in: Capsule())
    }

    private func action(_ symbol: String, _ label: String, tint: Color, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(tint).frame(width: 30, height: 30)
                .background(Theme.field.opacity(0.7), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).help(tr(label)).accessibilityLabel(tr(label))
    }
}
