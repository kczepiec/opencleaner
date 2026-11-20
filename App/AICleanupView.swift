import CleanKit
import SwiftUI

/// Stan widoku Sprzątanie AI. Skan tylko czyta; usuwanie przenosi do Kosza po potwierdzeniu.
@MainActor @Observable
final class AIModel {
    var groups: [AICleanup.Group] = []
    var loaded = false
    var selection: Set<URL> = []
    var expanded: Set<String> = []
    var message: String?

    var total: Int64 { groups.reduce(0) { $0 + $1.bytes } }
    var tools: Int { Set(groups.map(\.tool)).count }
    func bytes(of urls: Set<URL>) -> Int64 { groups.flatMap(\.entries).filter { urls.contains($0.url) }.reduce(0) { $0 + $1.bytes } }

    func load(days: Int) async {
        let g = await Task.detached(priority: .utility) { AICleanup.scan(olderThanDays: days) }.value
        withAnimation(Theme.ease) {
            groups = g; loaded = true
            // Domyślnie zaznaczone tylko to, co się odtworzy samo; sesji nie da się wznowić po usunięciu.
            selection = Set(g.filter { $0.kind == .cache || $0.kind == .oldVersions }.flatMap(\.entries).map(\.url))
        }
    }

    func trashSelected(days: Int) async {
        let urls = Array(selection)
        let r = await Task.detached { AICleanup.trash(urls) }.value
        message = r.failed == 0 ? trf("Przeniesiono do Kosza: %@ pozycji. Opróżnij Kosz, żeby odzyskać miejsce.", "\(r.done)")
                                : trf("Przeniesiono %@ pozycji, %@ się nie udało. %@", "\(r.done)", "\(r.failed)", r.error ?? "")
        await load(days: days)
    }
}

struct AICleanupView: View {
    let model: AIModel
    @AppStorage("set.aiDays") private var days = 90
    @State private var confirm = false

    private var sections: [(title: String, note: String, groups: [AICleanup.Group])] {
        let a = model.groups.filter { $0.kind == .cache || $0.kind == .oldVersions }
        let b = model.groups.filter { $0.kind == .oldSessions || $0.kind == .goneSessions }
        return [("Cache i stare wersje", "Odtworzą się same po usunięciu", a), ("Sesje", "Usuniętych sesji nie da się wznowić. Trafiają do Kosza.", b)].filter { !$0.2.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Sprzątanie AI", subtitle: model.loaded ? trf("Narzędzi: %@, razem %@", "\(model.tools)", Model.size(model.total)) : "Sprawdzam…") {
                Picker("", selection: $days) { ForEach([30, 60, 90, 180], id: \.self) { Text(trf("%@ dni", "\($0)")).tag($0) } }
                    .labelsHidden().pickerStyle(.menu).frame(width: 110).help(tr("Sesje starsze niż"))
                Button(tr("Odśwież")) { model.message = nil; Task { await model.load(days: days) } }
            }
            Divider()
            if !model.loaded { ScrollView { ListSkeleton(rows: 6).padding(14) } }
            else if model.groups.isEmpty { EmptyState(title: "Brak śladów narzędzi AI", text: "Nie znalazłem cache ani starych sesji Claude Code, Codexa, Cursora, Claude Desktop i Gemini.") }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let m = model.message { Text(m).font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 12, fill: Theme.raised) }
                        ForEach(sections, id: \.title) { s in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(tr(s.title)).font(.headline)
                                    Text(Model.size(s.groups.reduce(0) { $0 + $1.bytes })).font(.callout).foregroundStyle(Theme.secondary).monospacedDigit()
                                    Spacer()
                                    Text(tr(s.note)).font(.callout).foregroundStyle(Theme.secondary)
                                }.padding(.leading, 2)
                                VStack(spacing: 0) {
                                    ForEach(Array(s.groups.enumerated()), id: \.element.id) { i, g in
                                        if i > 0 { Divider().overlay(Theme.border.opacity(0.6)) }
                                        groupRow(g)
                                    }
                                }.cardStyle(radius: 16)
                            }
                        }
                    }.padding(22).padding(.bottom, 6)
                }.scrollIndicators(.hidden)
                bottomBar
            }
        }
        .task(id: days) { await model.load(days: days) }
        .confirmationDialog(trf("Przenieść %@ pozycji (%@) do Kosza?", "\(model.selection.count)", Model.size(model.bytes(of: model.selection))), isPresented: $confirm, titleVisibility: .visible) {
            Button(tr("Przenieś do Kosza"), role: .destructive) { Task { await model.trashSelected(days: days) } }
            Button(tr("Anuluj"), role: .cancel) {}
        } message: { Text(tr("Pliki trafią do Kosza i da się je przywrócić, dopóki go nie opróżnisz. Zaznaczone sesje nie dadzą się wznowić po opróżnieniu Kosza.")) }
    }

    // MARK: wiersze

    private func title(_ g: AICleanup.Group) -> String {
        switch g.kind {
        case .cache: "\(g.tool): \(tr("cache i pliki tymczasowe"))"
        case .oldVersions: "\(g.tool): \(tr("stare wersje"))"
        case .oldSessions: "\(g.tool): " + trf("sesje nieotwierane od ponad %@ dni", "\(days)")
        case .goneSessions: "\(g.tool): \(tr("sesje usuniętych projektów"))"
        }
    }

    private func entryName(_ e: AICleanup.Entry, _ g: AICleanup.Group) -> String {
        guard g.kind == .oldSessions || g.kind == .goneSessions, g.tool == "Claude Code" else { return e.url.lastPathComponent }
        let p = e.url.deletingLastPathComponent().lastPathComponent
        let prefix = "-Users-\(NSUserName())-"
        return p.hasPrefix(prefix) ? "~/" + p.dropFirst(prefix.count) : p
    }

    private func state(_ g: AICleanup.Group) -> Int {
        let n = g.entries.filter { model.selection.contains($0.url) }.count
        return n == 0 ? 0 : (n == g.entries.count ? 2 : 1)
    }

    private func toggle(_ g: AICleanup.Group) {
        let urls = g.entries.map(\.url)
        if state(g) == 2 { model.selection.subtract(urls) } else { model.selection.formUnion(urls) }
    }

    private func check(_ s: Int) -> some View {
        Image(systemName: s == 2 ? "checkmark.square.fill" : (s == 1 ? "minus.square.fill" : "square")).font(.system(size: 18))
            .foregroundStyle(s == 0 ? Theme.secondary.opacity(0.6) : Theme.accent)
    }

    @ViewBuilder private func groupRow(_ g: AICleanup.Group) -> some View {
        let open = model.expanded.contains(g.id)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { toggle(g) } label: { check(state(g)) }.buttonStyle(.plain).accessibilityLabel(title(g))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(g)).font(.body.weight(.medium)).lineLimit(1)
                    Text(trf("Pozycji: %@, zaznaczone %@", "\(g.entries.count)", "\(g.entries.filter { model.selection.contains($0.url) }.count)"))
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 8)
                Text(Model.size(g.bytes)).font(.body.weight(.medium)).monospacedDigit()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary).rotationEffect(.degrees(open ? 90 : 0))
            }
            .padding(.horizontal, 16).padding(.vertical, 13).contentShape(Rectangle())
            .onTapGesture { withAnimation(Theme.quick) { if open { model.expanded.remove(g.id) } else { model.expanded.insert(g.id) } } }
            if open {
                VStack(spacing: 0) {
                    ForEach(g.entries.prefix(60)) { e in
                        HStack(spacing: 12) {
                            Button { if model.selection.contains(e.url) { model.selection.remove(e.url) } else { model.selection.insert(e.url) } } label: { check(model.selection.contains(e.url) ? 2 : 0) }
                                .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entryName(e, g)).font(.callout).lineLimit(1).truncationMode(.middle)
                                if let d = e.date { Text(d, format: .dateTime.day().month(.abbreviated).year()).font(.caption).foregroundStyle(Theme.secondary) }
                            }
                            Spacer(minLength: 8)
                            Text(Model.size(e.bytes)).font(.callout).foregroundStyle(Theme.secondary).monospacedDigit()
                            Button { NSWorkspace.shared.activateFileViewerSelecting([e.url]) } label: {
                                Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(Theme.secondary).frame(width: 26, height: 26)
                            }.buttonStyle(.plain).help(tr("Pokaż w Finderze")).accessibilityLabel(tr("Pokaż w Finderze"))
                        }
                        .padding(.leading, 46).padding(.trailing, 16).padding(.vertical, 7)
                    }
                    if g.entries.count > 60 { Text(trf("…i jeszcze %@ pozycji", "\(g.entries.count - 60)")).font(.caption).foregroundStyle(Theme.secondary).padding(.leading, 46).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading) }
                }
                .padding(.bottom, 8).background(Theme.field.opacity(0.35))
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            Text(trf("Zaznaczono: %@", "\(model.selection.count)")).foregroundStyle(Theme.secondary)
            Spacer()
            Button { confirm = true } label: {
                Text(trf("Przenieś do Kosza · %@", Model.size(model.bytes(of: model.selection)))).font(.body.weight(.semibold)).padding(.horizontal, 18).frame(height: 38)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.selection.isEmpty)
        }
        .padding(.horizontal, 22).padding(.vertical, 12).background(Theme.panel).overlay(alignment: .top) { Divider() }
    }
}
