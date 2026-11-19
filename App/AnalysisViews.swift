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
                    Text("Wszystkie").tag(0)
                    ForEach([14, 30, 60, 90, 180], id: \.self) { Text("\($0) dni").tag($0) }
                }.pickerStyle(.menu).frame(width: 140)
                Button("Do Kosza…") { confirm = true }.buttonStyle(.borderedProminent)
                    .disabled(chosen.isEmpty || model.phase != .ready)
            }
            Divider()
            content
            Divider()
            HStack {
                Text("Zaznaczono \(chosen.count) z \(rows.count), \(Model.size(model.bytes(chosen)))").foregroundStyle(Theme.secondary).monospacedDigit()
                Spacer()
            }.font(.callout).padding(.horizontal, 22).padding(.vertical, 10)
        }
        .confirmationDialog("Przenieść \(chosen.count) pozycji (\(Model.size(model.bytes(chosen)))) do Kosza?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Przenieś do Kosza", role: .destructive) { let c = chosen; Task { await model.clean(c) } }
            Button("Anuluj", role: .cancel) {}
        } message: { Text("Usuwam tylko foldery ignorowane przez git (np. node_modules). Da się je przywrócić z Kosza albo odtworzyć instalacją.") }
    }

    private var subtitle: String {
        if !model.reposReady { return "Szukam repozytoriów…" }
        return "\(rows.count) pozycji, \(Model.size(model.bytes(rows)))"
    }

    @ViewBuilder private var content: some View {
        if model.phase == .cleaning { TableSkeleton() }
        else if rows.isEmpty {
            let all = model.items.filter { $0.category == .repos }
            if all.isEmpty && !model.reposReady { TableSkeleton() }
            else if all.isEmpty { EmptyState(title: "Brak repozytoriów z zależnościami", text: "Nie znalazłem folderów git z node_modules, target, .venv ani podobnych.") }
            else { EmptyState(title: "Nic nieużywanego od \(model.idleDays) dni", text: "Są \(all.count) foldery zależności (\(Model.size(model.bytes(all)))) w repozytoriach używanych niedawno. Wybierz krótszy okres.") }
        } else {
            let ids = Set(rows.map(\.id))
            let selection = Binding<Set<URL>>(get: { model.selected.intersection(ids) },
                                              set: { model.selected = model.selected.subtracting(ids).union($0) })
            FileList(rows: rows.map { item in
                FileRow(id: item.url, title: item.name, icon: nil, bytes: item.bytes,
                        subtitle: "\(item.repo.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") } ?? ""), bez zmian od \(item.idleDays ?? 0) dni")
            }, selection: selection, checks: true)
        }
    }
}

/// Największe pliki w katalogu domowym. Tylko podgląd: usuwanie zostaje w Finderze.
struct LargeFilesView: View {
    let model: Model
    @AppStorage("set.largeMB") private var largeMB = 100
    @State private var selection: Set<URL> = []

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Duże pliki", subtitle: model.largeReady ? "Powyżej \(largeMB) MB, bez Biblioteki i Kosza. Usuwanie w Finderze." : "Szukam…") {
                Button("Pokaż w Finderze") { NSWorkspace.shared.activateFileViewerSelecting(Array(selection)) }.disabled(selection.isEmpty)
            }
            Divider()
            if !model.largeReady { TableSkeleton() }
            else if model.large.isEmpty { EmptyState(title: "Brak dużych plików", text: "Nie ma tu niczego powyżej \(largeMB) MB.") }
            else {
                FileList(rows: model.large.map { f in
                    FileRow(id: f.url, title: f.url.lastPathComponent, icon: NSWorkspace.shared.icon(forFile: f.url.path), bytes: f.bytes,
                            subtitle: f.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                }, selection: $selection, checks: false)
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
}

/// Lista plików w stylu reszty aplikacji: wiersze na jednolitym tle, bez systemowej tabeli i nagłówka.
struct FileList: View {
    let rows: [FileRow]
    @Binding var selection: Set<URL>
    let checks: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(rows) { r in
                    let on = selection.contains(r.id)
                    HStack(spacing: 12) {
                        if checks {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 18))
                                .foregroundStyle(on ? Theme.accent : Theme.secondary.opacity(0.6))
                        }
                        if let icon = r.icon { Image(nsImage: icon).resizable().interpolation(.high).frame(width: 28, height: 28) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.body.weight(.medium)).lineLimit(1)
                            Text(r.subtitle).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 12)
                        Text(Model.size(r.bytes)).monospacedDigit().foregroundStyle(Theme.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(on ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { if on { selection.remove(r.id) } else if checks { selection.insert(r.id) } else { selection = [r.id] } }
                    .help(r.id.path)
                    .contextMenu { Button("Pokaż w Finderze") { NSWorkspace.shared.activateFileViewerSelecting([r.id]) } }
                }
            }.padding(10)
        }
    }
}
