import CleanKit
import Observation
import SwiftUI

/// Stan porad: cache narzędzi, Docker i nieużywane aplikacje. Skan tylko czyta; akcje idą po potwierdzeniu.
@MainActor @Observable
final class TipsModel {
    var tips: [Tips.Tip] = []
    var apps: [Tips.UnusedApp] = []
    var loaded = false
    var running: String?
    var message: String?
    /// Wynik akcji na karcie: ile było i ile zostało po odświeżeniu. Karta pokazuje zielony znacznik zamiast przycisku.
    struct Done: Equatable { let before: Int64; let after: Int64; let title: String; let symbol: String; let detail: String }
    var done: [String: Done] = [:]

    var total: Int64 { tips.reduce(0) { $0 + $1.bytes } }

    func load(days: Int) async {
        let r = await Tips.scan(minDays: days)
        withAnimation(Theme.ease) { tips = r.tips; apps = r.apps; loaded = true }
    }

    func run(_ tip: Tips.Tip, days: Int) async {
        guard let action = tip.action else { return }
        running = tip.id; message = nil
        let r = await Tips.run(action)
        await load(days: days)
        if r.ok {
            let after = tips.first { $0.id == tip.id }?.bytes ?? 0
            withAnimation(Theme.ease) { done[tip.id] = Done(before: tip.bytes, after: after, title: tip.title, symbol: tip.symbol, detail: tip.detail) }
        } else { message = "\(tip.title): \(r.message)" }
        running = nil
    }
}

struct TipsView: View {
    let model: Model
    let tips: TipsModel
    let open: (Area, String?) -> Void
    let openApp: (URL) -> Void
    @AppStorage("set.unusedDays") private var days = 90
    @State private var pending: Tips.Tip?

    private var cacheItems: [Item] { model.rows(.caches) }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Porady", subtitle: subtitle) {
                Picker("Aplikacje nieużywane od", selection: $days) {
                    ForEach([14, 30, 60, 90, 180, 365], id: \.self) { Text("\($0) dni").tag($0) }
                }.pickerStyle(.menu).labelsHidden().frame(width: 110).help("Aplikacje nieużywane od")
                Button("Odśwież") { tips.done = [:]; tips.message = nil; Task { await tips.load(days: days) } }
            }
            Divider()
            if !tips.loaded { ScrollView { ListSkeleton(rows: 7).padding(14) } }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if let m = tips.message { Text(m).font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 12, fill: Theme.raised) }
                        toolsSection
                        cachesSection
                        appsSection
                        hintsSection
                    }.padding(22)
                }.scrollIndicators(.hidden)
            }
        }
        .task(id: days) { await tips.load(days: days) }
        .confirmationDialog(pending.map { "Wyczyścić: \($0.title)?" } ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let t = pending { Button(confirmLabel(t), role: .destructive) { Task { await tips.run(t, days: days) } } }
            Button("Anuluj", role: .cancel) {}
        } message: {
            if let t = pending { Text([t.warning, "Wykona: \(t.actionText)"].compactMap { $0 }.joined(separator: "\n")) }
        }
    }

    private var subtitle: String {
        guard tips.loaded else { return "Szukam sposobów na odzyskanie miejsca…" }
        return tips.total > 0 ? "Narzędzia i Docker: do odzyskania do \(Model.size(tips.total))" : "Cache narzędzi jest czysty"
    }

    private func confirmLabel(_ t: Tips.Tip) -> String { if case .trash = t.action { "Przenieś do Kosza" } else { "Wyczyść" } }

    private func section(_ title: String, _ note: String? = nil, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let note { Text(note).font(.callout).foregroundStyle(Theme.secondary) }
            }
            content()
        }
    }

    private func tile(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .medium)).frame(width: 38, height: 38)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: sekcje

    @ViewBuilder private var toolsSection: some View {
        section("Cache narzędzi i Docker", "Narzędzia same odtworzą te pliki. Polecenia (npm, pnpm, brew, docker) robią to najbezpieczniej.") {
            if tips.tips.isEmpty {
                Text("Nie znalazłem nic większego niż 20 MB w npm, Yarn, pnpm, Homebrew, pip, uv, Bun, Cargo, Gradle, CocoaPods, Xcode ani Hugging Face. Docker \(Tips.find("docker") == nil ? "nie jest zainstalowany" : "nie ma nic do zwolnienia").")
                    .foregroundStyle(Theme.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 14)
            }
            ForEach(toolRows) { t in
                HStack(spacing: 12) {
                    tile(t.symbol)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.title).font(.body.weight(.medium))
                        Text(t.detail).font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        if let w = t.warning { Label(w, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warn) }
                    }
                    Spacer(minLength: 12)
                    trailing(t)
                }
                .padding(14).cardStyle(radius: 14)
            }
        }
    }

    /// Aktualne porady plus karty, które po wyczyszczeniu zniknęły ze skanu (zostają z zielonym znacznikiem).
    private var toolRows: [Tips.Tip] {
        let live = tips.tips
        let gone = tips.done.filter { k, _ in !live.contains { $0.id == k } }.map { k, d in
            Tips.Tip(id: k, symbol: d.symbol, title: d.title, detail: d.detail, bytes: 0, action: nil)
        }
        return live + gone.sorted { $0.title < $1.title }
    }

    @ViewBuilder private func trailing(_ t: Tips.Tip) -> some View {
        if tips.running == t.id {
            ProgressView().controlSize(.small).frame(width: 20, height: 20)
            Text("Odświeżam…").foregroundStyle(Theme.secondary)
        } else if let d = tips.done[t.id] {
            let freed = max(d.before - d.after, 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Model.size(d.after)).font(.body.weight(.semibold)).monospacedDigit()
                Text(freed > 0 ? "Zwolniono \(Model.size(freed))" : "Nic więcej do zwolnienia").font(.caption).foregroundStyle(Theme.secondary)
            }
            Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundStyle(Theme.ok)
                .transition(.scale.combined(with: .opacity)).accessibilityLabel("Gotowe")
        } else {
            Text(Model.size(t.bytes)).font(.body.weight(.semibold)).monospacedDigit()
            if t.action != nil { Button("Wyczyść…") { pending = t }.disabled(tips.running != nil) }
        }
    }

    @ViewBuilder private var cachesSection: some View {
        let sum = model.bytes(cacheItems)
        section("Cache aplikacji", "Bezpieczne do usunięcia: aplikacje odbudowują je same.") {
            Button { open(.cleaning, nil) } label: {
                HStack(spacing: 12) {
                    tile("internaldrive")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cacheItems.isEmpty ? "Brak dużego cache" : cacheItems.filter { !$0.name.hasPrefix("com.apple.") }.prefix(3).map(\.name).joined(separator: ", "))
                            .font(.body.weight(.medium)).lineLimit(1)
                        Text("Największe foldery w Library/Caches. Podgląd i czyszczenie w Czyszczeniu.").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 12)
                    Text(model.reposReady || model.phase == .ready ? Model.size(sum) : "…").font(.body.weight(.semibold)).monospacedDigit()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(14).cardStyle(radius: 14).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private var appsSection: some View {
        section("Aplikacje nieużywane od \(days) dni", "Według Spotlight. Odinstalowanie w Aplikacjach usuwa też pozostałości.") {
            if tips.apps.isEmpty {
                Text("Wszystkie aplikacje były otwierane w ciągu ostatnich \(days) dni. Wybierz krótszy okres, żeby zobaczyć rzadziej używane.")
                    .foregroundStyle(Theme.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 14)
            }
            ForEach(tips.apps.prefix(25)) { a in
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: a.url.path)).resizable().interpolation(.high).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name).font(.body.weight(.medium)).lineLimit(1)
                        Text(a.days().map { "Ostatnio otwarta \($0) dni temu" } ?? "Brak danych o użyciu").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 12)
                    Text(Model.size(a.bytes)).font(.body.weight(.semibold)).monospacedDigit()
                    Button("Pokaż") { NSWorkspace.shared.activateFileViewerSelecting([a.url]) }
                    Button("Odinstaluj…") { openApp(a.url) }
                }
                .padding(12).cardStyle(radius: 14)
            }
        }
    }

    @ViewBuilder private var hintsSection: some View {
        section("Wskazówki") {
            hint("trash", "Opróżnij Kosz", "Pliki przeniesione do Kosza dalej zajmują miejsce, dopóki go nie opróżnisz w Finderze.")
            hint("shippingbox", "Zajrzyj do dużych plików", "Filmy, obrazy dysków i archiwa najszybciej zwalniają miejsce.", { open(.analysis, "large") })
            hint("arrow.triangle.branch", "Posprzątaj nieużywane repozytoria", "node_modules, target i .venv w projektach, których nie ruszasz, odtworzą się same.", { open(.analysis, "repos") })
            hint("photo.on.rectangle", "Zdjęcia w iCloud", "W aplikacji Zdjęcia, w ustawieniach iCloud, wybierz Optymalizuj miejsce na Macu: pełne zdjęcia zostają w chmurze.")
        }
    }

    private func hint(_ symbol: String, _ title: String, _ text: String, _ go: (() -> Void)? = nil) -> some View {
        let row = HStack(spacing: 12) {
            tile(symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(text).font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if go != nil { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
        }.padding(14).cardStyle(radius: 14).contentShape(Rectangle())
        return Group { if let go { Button(action: go) { row }.buttonStyle(.plain) } else { row } }
    }
}
