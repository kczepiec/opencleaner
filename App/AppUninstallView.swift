import CleanKit
import SwiftUI

/// Szczegóły aplikacji: sama aplikacja i jej pozostałości w ~/Library do zaznaczenia, odinstalowanie do Kosza (da się cofnąć).
struct AppDetailView: View {
    let app: Mole.App?
    let mole: MoleModel
    @State private var leftovers: [AppLeftovers.Item] = []
    @State private var loaded = false
    @State private var selection: Set<URL> = []
    @State private var confirm = false
    @State private var message: String?

    private var appURL: URL? { app.map { URL(fileURLWithPath: $0.path) } }
    private var appBytes: Int64 { app.flatMap { Mole.parseSize($0.size) } ?? 0 }
    private var info: (bundleID: String?, name: String)? { app.map { AppLeftovers.info(appPath: $0.path) } }
    private var running: Bool {
        guard let id = info?.bundleID else { return false }
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == id }
    }
    private var selectedBytes: Int64 { appBytes + leftovers.filter { selection.contains($0.url) }.reduce(0) { $0 + $1.bytes } }
    private var lastUsed: String { app.flatMap { mole.appPlan[$0.id]?.first?.lastUsed } ?? "…" }

    var body: some View {
        if let app {
            VStack(spacing: 0) {
                PanelHeader(title: app.name, subtitle: "\(Mole.parseSize(app.size).map(Model.size) ?? tr("brak danych")) · \(app.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))",
                            icon: NSWorkspace.shared.icon(forFile: app.path)) {
                    Button(tr("Pokaż w Finderze")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)]) }
                    Button(tr("Odśwież")) { Task { await load(app, force: true) } }
                }
                Divider()
                if !loaded { PlanSkeleton() }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            summary
                            if let message { Text(message).font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 12, fill: Theme.raised) }
                            section(tr("Aplikacja")) { appRow(app) }
                            section(tr("Pozostałości w Library"), note: leftovers.isEmpty ? nil : trf("Pozycji: %@", "\(leftovers.count)")) {
                                if leftovers.isEmpty { Text("Nie znalazłem pozostałości w Library.").foregroundStyle(Theme.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
                                ForEach(Array(leftovers.enumerated()), id: \.element.id) { i, l in
                                    if i > 0 { Divider().overlay(Theme.border.opacity(0.6)) }
                                    leftoverRow(l)
                                }
                            }
                            Text("Wszystko trafia do Kosza i da się przywrócić, dopóki go nie opróżnisz. Dane, których utrata boli (np. archiwa Xcode), nie są zaznaczone domyślnie.")
                                .font(.callout).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        }.padding(22)
                    }.scrollIndicators(.hidden)
                    TrashBar(count: selection.count + 1, bytes: selectedBytes, warning: running ? tr("Zamknij aplikację, żeby ją odinstalować") : nil, label: tr("Odinstaluj"), summary: trf("Aplikacja i pozycje z Library: %@", "\(selection.count)")) { confirm = true }
                }
            }
            .task(id: app.id) { await load(app, force: false) }
            .confirmationDialog(trf("Odinstalować %@?", app.name), isPresented: $confirm, titleVisibility: .visible) {
                Button(tr("Odinstaluj"), role: .destructive) { Task { await uninstall(app) } }
                Button(tr("Anuluj"), role: .cancel) {}
            } message: { Text(trf("Aplikacja i %@ pozycji z Library (%@) trafią do Kosza.", "\(selection.count)", Model.size(selectedBytes))) }
        } else {
            EmptyState(title: "Wybierz aplikację", text: "Wybierz aplikację z listy po lewej.", mood: .content)
        }
    }

    // MARK: części widoku

    /// Jedna karta z trzema liczbami zamiast trzech osobnych kafli.
    private var summary: some View {
        HStack(spacing: 0) {
            stat(trf("%@", "\(leftovers.count + 1)"), tr("pozycji do usunięcia"))
            Divider().frame(height: 34)
            stat(Model.size(appBytes + leftovers.reduce(0) { $0 + $1.bytes }), tr("do odzyskania"))
            Divider().frame(height: 34)
            stat(lastUsed, tr("ostatnio używana"))
        }
        .padding(.vertical, 16).cardStyle(radius: 16)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(Theme.secondary)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }

    private func section<C: View>(_ title: String, note: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let note { Text(note).font(.callout).foregroundStyle(Theme.secondary) }
            }.padding(.leading, 2)
            VStack(spacing: 0) { content() }.cardStyle(radius: 16)
        }
    }

    private func appRow(_ app: Mole.App) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.square.fill").font(.system(size: 18)).foregroundStyle(Theme.accent.opacity(0.55)).accessibilityLabel(tr("Zawsze usuwane"))
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().interpolation(.high).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: app.path).lastPathComponent).font(.body.weight(.medium)).lineLimit(1)
                Text(URL(fileURLWithPath: app.path).deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Text(Model.size(appBytes)).foregroundStyle(Theme.secondary).monospacedDigit()
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func leftoverRow(_ l: AppLeftovers.Item) -> some View {
        let on = selection.contains(l.url)
        return HStack(spacing: 12) {
            Button { if on { selection.remove(l.url) } else { selection.insert(l.url) } } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 18)).foregroundStyle(on ? Theme.accent : Theme.secondary.opacity(0.6))
            }.buttonStyle(.plain).accessibilityLabel(l.url.lastPathComponent)
            Image(nsImage: NSWorkspace.shared.icon(forFile: l.url.path)).resizable().interpolation(.high).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(l.url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    if l.risky { Text(tr("Ostrożnie")).font(.caption2.weight(.semibold)).foregroundStyle(Theme.warn).padding(.horizontal, 6).padding(.vertical, 1).background(Theme.warn.opacity(0.14), in: Capsule()) }
                }
                Text(l.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(Model.size(l.bytes)).foregroundStyle(Theme.secondary).monospacedDigit()
            Button { NSWorkspace.shared.activateFileViewerSelecting([l.url]) } label: {
                Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(Theme.secondary).frame(width: 26, height: 26)
            }.buttonStyle(.plain).help(tr("Pokaż w Finderze")).accessibilityLabel(tr("Pokaż w Finderze"))
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: akcje

    private func load(_ app: Mole.App, force: Bool) async {
        loaded = false; message = nil
        let path = app.path
        let found = await Task.detached(priority: .userInitiated) { AppLeftovers.find(appPath: path) }.value
        leftovers = found
        selection = Set(found.filter { !$0.risky }.map(\.url))
        loaded = true
        if force || mole.appPlan[app.id] == nil { await mole.previewUninstall(app) }   // tylko po to, żeby poznać datę ostatniego użycia
    }

    private func uninstall(_ app: Mole.App) async {
        let url = URL(fileURLWithPath: app.path), picked = Array(selection)
        let r = await Task.detached { AppLeftovers.uninstall(app: url, leftovers: picked) }.value
        if r.failed == 0 {
            mole.apps.removeAll { $0.id == app.id }
            mole.appsLoaded = false
            await mole.loadApps()
        } else {
            message = trf("Przeniesiono %@ pozycji, %@ się nie udało. %@", "\(r.done)", "\(r.failed)", r.error ?? "")
            await load(app, force: false)
        }
    }
}
