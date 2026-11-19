import CleanKit
import SwiftUI

/// `mo clean` i `mo optimize`: podgląd (dry-run) i uruchomienie. Wyniki są prezentowane, nie wypisywane.
struct MoleTaskView: View {
    let kind: String
    let title: String
    let blurb: String
    let mole: MoleModel
    @State private var confirm = false

    private var run: MoleModel.Run { mole.runs[kind] ?? .init() }
    private var hasResult: Bool { kind == "optimize" ? (run.report?.steps.isEmpty == false) : (run.preview?.groups.isEmpty == false) }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: title, subtitle: subtitle) {
                Button("Podgląd") { Task { await mole.preview(kind) } }.disabled(!mole.available(kind) || run.running)
                Button("Uruchom…") { confirm = true }.buttonStyle(.borderedProminent)
                    .disabled(!mole.available(kind) || run.running || !canRun)
            }
            Divider()
            content
        }
        // Podgląd niczego nie zmienia, więc uruchamia się sam przy pierwszym wejściu.
        .task { if mole.available(kind), run.preview == nil, run.report == nil, !run.running, run.applied == nil { await mole.preview(kind) } }
        .confirmationDialog("Uruchomić \(title.lowercased())?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Uruchom", role: .destructive) { Task { await mole.apply(kind) } }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text(kind == "clean" ? "Usuwa pliki na stałe, bez Kosza. Sprawdź podgląd przed uruchomieniem." : "Zastosuję zmiany pokazane w podglądzie.")
        }
    }

    private var canRun: Bool { kind == "optimize" ? (run.report?.toApply ?? 0) > 0 : hasResult }

    private var subtitle: String {
        if run.running { return "Pracuję…" }
        if kind == "optimize", let r = run.report, !r.steps.isEmpty { return r.toApply > 0 ? "Do zastosowania: \(r.toApply)" : "Nic do zastosowania" }
        if let p = run.preview, kind == "clean" { return p.groups.isEmpty || p.bytes == 0 ? "Nic do wyczyszczenia." : "Do odzyskania: \(Model.size(p.bytes))" }
        return blurb
    }

    @ViewBuilder private var content: some View {
        if !mole.available(kind) { EmptyState(title: "Funkcja niedostępna", text: "Ta funkcja wymaga dodatkowego silnika. Zainstaluj go w Ustawieniach, Silnik.", mood: .content) }
        else if run.running {
            VStack(spacing: 26) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.16)).frame(width: 170, height: 170).blur(radius: 34)
                    Mascot(size: 96, mood: .busy)
                }
                VStack(spacing: 6) {
                    Text("Sprawdzam Twojego Maca").font(.title3.weight(.semibold))
                    Text(run.seen.count > 1 ? "Sprawdzone kategorie: \(run.seen.count - 1)" : "To potrwa chwilę.").font(.callout).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                VStack(spacing: 0) {
                    ForEach(Array(run.seen.enumerated().suffix(5)), id: \.offset) { i, name in
                        let current = i == run.seen.count - 1
                        HStack(spacing: 12) {
                            if current { ScanDot() } else { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok).frame(width: 20) }
                            Text(name).fontWeight(current ? .medium : .regular).foregroundStyle(current ? .primary : Theme.secondary)
                            Spacer(minLength: 8)
                            if current { ScanBar() }
                        }
                        .padding(.horizontal, 16).frame(height: 44)
                        .background(current ? Theme.accent.opacity(0.10) : .clear)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                    ForEach(0..<min(2, max(0, 5 - run.seen.count)), id: \.self) { i in
                        HStack(spacing: 12) {
                            Circle().fill(Theme.ghost).frame(width: 20, height: 20)
                            InlineBone(width: i == 0 ? 150 : 110, height: 12)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16).frame(height: 44)
                    }
                }
                .frame(width: 360).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border.opacity(0.7)))
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .animation(Theme.ease, value: run.seen.count)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            // Widok pracy znika od razu, żeby nie prześwitywał pod wynikiem, który wchodzi płynnie.
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
        } else if let done = run.applied { AppliedView(summary: done) }
        else if let err = run.failed { EmptyState(title: "Coś poszło nie tak", text: err, mood: .content) }
        else if kind == "optimize", let r = run.report, !r.steps.isEmpty { OptimizeReportView(report: r) }
        else if kind == "clean", let p = run.preview, !p.groups.isEmpty { CleanResultsView(preview: p) }
        else if run.preview != nil || run.report != nil { EmptyState(title: "Nic do zrobienia", text: "Nie znalazłem niczego do tej operacji.") }
        else { EmptyState(title: "Zacznij od podglądu", text: "Podgląd niczego nie zmienia. Pokażę, co zostanie zrobione.", mood: .content) }
    }
}

/// Wynik czyszczenia: grupy z polskimi nazwami i rozmiarami.
struct CleanResultsView: View {
    let preview: Mole.Preview

    private func symbol(_ title: String) -> String {
        switch title {
        case "User essentials": "person.crop.circle"
        case "App caches": "app.badge"
        case "Browsers": "globe"
        case "Developer tools": "hammer"
        case "Cloud & Office": "icloud"
        case "Large files": "shippingbox"
        default: "folder"
        }
    }

    var body: some View {
        let groups = preview.groups.filter { !$0.entries.isEmpty }
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 18) {
                    Mascot(size: 72, mood: .happy)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview.bytes > 0 ? Model.size(preview.bytes) : "Wszystko czyste").font(.system(size: 34, weight: .semibold)).monospacedDigit()
                        Text(preview.bytes > 0 ? "do odzyskania" : "Nie znalazłem nic do wyczyszczenia").foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        StatChip(value: groups.count, label: "kategorii", tint: Theme.accent).frame(width: 120)
                        StatChip(value: groups.reduce(0) { $0 + $1.entries.count }, label: "pozycji", tint: Theme.accent).frame(width: 120)
                    }
                }
                .padding(18).cardStyle()
                ForEach(preview.groups) { g in
                    Card {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(g.title)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                                .frame(width: 34, height: 34).background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(Mole.pl(g.title)).font(.headline)
                            Spacer()
                            if g.bytes > 0 { Text(Model.size(g.bytes)).foregroundStyle(Theme.secondary).monospacedDigit() }
                        }
                        if g.nothing { Text("Nic do zrobienia").foregroundStyle(Theme.secondary) }
                        ForEach(g.entries) { e in
                            HStack(spacing: 10) {
                                Text(Mole.pl(e.name)).lineLimit(1)
                                Spacer()
                                Text(e.bytes.map(Model.size) ?? "do wyczyszczenia").foregroundStyle(Theme.secondary).monospacedDigit()
                            }.font(.callout).help(e.name)
                        }
                    }
                }
                let notes = preview.notes.map(Mole.plCleanNote)
                if !notes.isEmpty {
                    Label { Text(notes.joined(separator: " ")).font(.callout).foregroundStyle(Theme.secondary) } icon: {
                        Image(systemName: "lock").foregroundStyle(Theme.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                }
            }.padding(22)
        }
    }
}

/// Wynik optymalizacji: liczby, diagnoza wydajności i lista kroków ze statusami.
struct OptimizeReportView: View {
    let report: Mole.OptimizeReport

    private func style(_ s: Mole.StepStatus) -> (symbol: String, text: String, tint: Color) {
        switch s {
        case .apply: ("arrow.triangle.2.circlepath", "Zostanie zastosowane", Theme.accent)
        case .ok: ("checkmark.circle.fill", "W porządku", Theme.ok)
        case .attention: ("exclamationmark.triangle.fill", "Wymaga uwagi", Theme.warn)
        case .skipped: ("minus.circle", "Pominięte", Theme.secondary)
        case .unavailable: ("slash.circle", "Niedostępne", Theme.secondary)
        }
    }
    private var steps: [Mole.Step] {
        let order: [Mole.StepStatus] = [.attention, .apply, .ok, .skipped, .unavailable]
        return report.steps.sorted { (order.firstIndex(of: $0.status) ?? 9) < (order.firstIndex(of: $1.status) ?? 9) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    StatChip(value: report.toApply, label: "Do zastosowania", tint: Theme.accent)
                    StatChip(value: report.unchanged, label: "W porządku", tint: Theme.ok)
                    StatChip(value: report.attention, label: "Wymaga uwagi", tint: Theme.warn)
                    StatChip(value: report.skipped + report.unavailable, label: "Pominięte", tint: Theme.secondary)
                }
                if !report.findings.isEmpty || !report.processes.isEmpty { diagnosis }
                Card {
                    Text("Kroki").font(.headline)
                    ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                        let st = style(step.status)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                Image(systemName: st.symbol).foregroundStyle(st.tint).frame(width: 20)
                                Text(step.title)
                                Spacer()
                                Text(st.text).font(.callout).foregroundStyle(st.tint)
                            }
                            ForEach(step.notes, id: \.self) { n in
                                Text(n).font(.callout).foregroundStyle(Theme.secondary).padding(.leading, 30)
                            }
                        }
                        .help(step.original).accessibilityElement(children: .combine)
                        if i < steps.count - 1 { Divider().opacity(0.4) }
                    }
                }
            }.padding(22)
        }
    }

    private var diagnosis: some View {
        Card {
            Text("Diagnoza wydajności").font(.headline)
            ForEach(report.findings, id: \.self) { f in
                Label { Text(f).fixedSize(horizontal: false, vertical: true) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                }
            }
            if !report.processes.isEmpty {
                Text("Najwięcej pamięci zajmują").font(.callout).foregroundStyle(Theme.secondary).padding(.top, 4)
                let maxB = max(report.processes.map(\.bytes).max() ?? 1, 1)
                ForEach(report.processes) { p in
                    HStack(spacing: 12) {
                        Text(p.name).lineLimit(1).frame(width: 190, alignment: .leading)
                        GeometryReader { g in
                            Capsule().fill(Theme.accent.opacity(0.85)).frame(width: g.size.width * CGFloat(Double(p.bytes) / Double(maxB)), height: 6)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }.frame(height: 14)
                        Text(Model.size(p.bytes)).foregroundStyle(Theme.secondary).monospacedDigit().frame(width: 80, alignment: .trailing)
                    }.font(.callout)
                }
            }
        }
    }
}

/// Po uruchomieniu: krótkie potwierdzenie, a surowy log tylko w zwiniętych szczegółach.
struct AppliedView: View {
    let summary: String
    var body: some View {
        VStack(spacing: 12) {
            EmptyState(title: "Gotowe", text: "Skończyłem. Uruchom podgląd jeszcze raz, żeby sprawdzić stan.")
            DisclosureGroup("Szczegóły techniczne") {
                Text(summary).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.secondary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            }
            .padding(.horizontal, 22).padding(.bottom, 18)
        }
    }
}

/// Szczegóły aplikacji: plan odinstalowania z listą plików do usunięcia (podgląd, nic nie jest usuwane).
struct AppDetailView: View {
    let app: Mole.App?
    let mole: MoleModel

    var body: some View {
        Group { content }
            .task(id: app?.id) { await autoPlan() }
    }

    @ViewBuilder private var content: some View {
        if let app {
            VStack(spacing: 0) {
                PanelHeader(title: app.name, subtitle: "\(Mole.parseSize(app.size).map(Model.size) ?? "brak danych") · \(app.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))",
                            icon: NSWorkspace.shared.icon(forFile: app.path)) {
                    Button("Pokaż w Finderze") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)]) }
                    Button("Odśwież plan") { Task { await mole.previewUninstall(app) } }.disabled(mole.appBusy == app.id)
                }
                Divider()
                if mole.appBusy == app.id || (mole.appPlan[app.id] == nil) {
                    PlanSkeleton()
                } else if let plan = mole.appPlan[app.id] {
                    if let p = plan.first { PlanView(plan: p) }
                    else { EmptyState(title: "Nie udało się odczytać planu", text: "Nie dostałem listy plików dla tej aplikacji.", mood: .content) }
                } else {
                    EmptyState(title: "Podgląd odinstalowania", text: "Pokaże aplikację i jej pozostałości, bez usuwania czegokolwiek.", mood: .content)
                }
            }
        } else {
            EmptyState(title: "Wybierz aplikację", text: "Wybierz aplikację z listy po lewej.", mood: .content)
        }
    }
}

extension AppDetailView {
    /// Plan odinstalowania ładuje się sam po wybraniu aplikacji (to tylko podgląd).
    func autoPlan() async { if let app, mole.appPlan[app.id] == nil { await mole.previewUninstall(app) } }
}

struct PlanView: View {
    let plan: Mole.PlanApp
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    StatChip(value: plan.files.count, label: "plików do usunięcia", tint: Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Model.size(plan.bytes)).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                        Text("do odzyskania").font(.callout).foregroundStyle(Theme.secondary)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle(radius: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.lastUsed).font(.system(size: 28, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                        Text("ostatnio używana").font(.callout).foregroundStyle(Theme.secondary)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle(radius: 16)
                }
                Card {
                    Text("Zostanie usunięte").font(.headline)
                    ForEach(plan.files) { f in
                        let url = URL(fileURLWithPath: f.path)
                        HStack(spacing: 12) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: f.path)).resizable().frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent).lineLimit(1)
                                Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(Model.size(f.bytes)).foregroundStyle(Theme.secondary).monospacedDigit()
                            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.borderless).help("Pokaż w Finderze").accessibilityLabel("Pokaż w Finderze")
                        }
                    }
                    Text("To tylko podgląd. Nic nie zostało usunięte.").font(.callout).foregroundStyle(Theme.secondary).padding(.top, 4)
                }
            }.padding(22)
        }
    }
}

/// Status systemu z `mo status --json`, odświeżany co 3 s.
struct StatusView: View {
    let mole: MoleModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Status", subtitle: mole.status.map { "\($0.model), \($0.chip), \($0.os)" } ?? "") { EmptyView() }
            Divider()
            if mole.engine != .ready { EmptyState(title: "Funkcja niedostępna", text: "Ta funkcja wymaga dodatkowego silnika. Zainstaluj go w Ustawieniach, Silnik.", mood: .content) }
            else if let s = mole.status {
                ScrollView {
                    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            tile("Zdrowie", "\(s.health)", Mole.plHealth(s.healthMessage), Double(s.health) / 100)
                            tile("Procesor", "\(Int(s.cpu.rounded()))%", "\(s.cores) rdzeni", s.cpu / 100)
                        }
                        GridRow {
                            tile("Pamięć", "\(Model.size(s.memUsed))", "z \(Model.size(s.memTotal))", s.memTotal > 0 ? Double(s.memUsed) / Double(s.memTotal) : 0)
                            tile("Swap", Model.size(s.swapUsed), "z \(Model.size(s.swapTotal)) · wymiana na dysk", s.swapTotal > 0 ? Double(s.swapUsed) / Double(s.swapTotal) : nil)
                        }
                        GridRow {
                            tile("Czas pracy", s.uptime, "bez restartu", nil)
                            tile("Procesy", "\(s.procs)", "uruchomionych", nil)
                        }
                    }
                    .padding(22)
                    MemoryCard(mole: mole, status: s).padding(.horizontal, 22).padding(.bottom, 22)
                }
            } else {
                StatusSkeleton()
            }
        }
        .task {
            while !Task.isCancelled {
                if mole.engine == .ready { await mole.refreshStatus() }
                await mole.loadMemory()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ sub: String, _ fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr(title)).font(.callout).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 30, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            if let f = fraction { ProgressView(value: min(max(f, 0), 1)).tint(Theme.accent) }
            Text(sub).font(.caption).foregroundStyle(Theme.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: 14)
        .accessibilityElement(children: .combine)
    }
}

/// Zwalnianie pamięci: ciężkie aplikacje do zamknięcia i zwolnienie pamięci podręcznej plików.
struct MemoryCard: View {
    let mole: MoleModel
    let status: Mole.Status
    @State private var confirmPurge = false
    @State private var confirmQuit: SystemInfo.MemApp?

    private var swapHigh: Bool { status.swapTotal > 0 && Double(status.swapUsed) / Double(status.swapTotal) > 0.7 }

    var body: some View {
        Card {
            HStack {
                Text("Pamięć i swap").font(.headline)
                Spacer()
                if swapHigh {
                    Label("Swap prawie pełny", systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(Theme.warn)
                }
            }
            Text("Swap to pamięć na dysku, której system używa, gdy brakuje RAM. macOS sam go zwalnia, gdy aplikacje przestają go potrzebować. Najszybciej pomaga zamknięcie ciężkich aplikacji.")
                .font(.callout).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            if !mole.memApps.isEmpty {
                Text("Najwięcej pamięci zajmują").font(.callout).foregroundStyle(Theme.secondary).padding(.top, 2)
                ForEach(mole.memApps) { a in
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 26, height: 26)
                        Text(a.name).lineLimit(1)
                        Spacer()
                        Text(Model.size(a.bytes)).foregroundStyle(Theme.secondary).monospacedDigit()
                        if mole.runningApp(a) != nil {
                            Button("Zamknij…") { confirmQuit = a }.controlSize(.small)
                        } else {
                            Color.clear.frame(width: 70, height: 1)
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                Button("Zwolnij pamięć podręczną…") { confirmPurge = true }.disabled(mole.purging)
                if mole.purging { ProgressView().controlSize(.small) }
                if let m = mole.purgeMessage { Text(m).font(.callout).foregroundStyle(Theme.secondary) }
            }.padding(.top, 4)
            Text("Zwolnienie pamięci podręcznej zmniejsza zajętość RAM, ale nie opróżnia swapu od razu. Najpewniej czyści go restart komputera.")
                .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("Zwolnić pamięć podręczną?", isPresented: $confirmPurge, titleVisibility: .visible) {
            Button("Zwolnij") { Task { await mole.purge() } }
            Button("Anuluj", role: .cancel) {}
        } message: { Text("macOS poprosi o hasło administratora. Komputer może przez chwilę działać wolniej, gdy odbuduje pamięć podręczną.") }
        .confirmationDialog("Zamknąć \(confirmQuit?.name ?? "")?", isPresented: Binding(get: { confirmQuit != nil }, set: { if !$0 { confirmQuit = nil } }), titleVisibility: .visible) {
            Button("Zamknij aplikację", role: .destructive) { if let a = confirmQuit { Task { await mole.quit(a) } } }
            Button("Anuluj", role: .cancel) {}
        } message: { Text("Aplikacja dostanie zwykłe polecenie zamknięcia. Jeśli ma niezapisane zmiany, sama o to zapyta.") }
    }
}

/// Pulsujący znacznik bieżącego kroku (zamiast systemowego kręciołka).
private struct ScanDot: View {
    @State private var on = false
    @Environment(\.czystoMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 2)
            Circle().fill(Theme.accent).frame(width: 8, height: 8).scaleEffect(on ? 1 : 0.6)
        }
        .frame(width: 20, height: 20)
        .task { guard motion && !reduce else { return }; withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true } }
    }
}

/// Nieokreślony pasek postępu bieżącego kroku: krótki odcinek jeździ po torze.
private struct ScanBar: View {
    @State private var x = false
    @Environment(\.czystoMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        Capsule().fill(Theme.track).frame(width: 64, height: 4)
            .overlay(alignment: .leading) { Capsule().fill(Theme.accent).frame(width: 22, height: 4).offset(x: x ? 42 : 0) }
            .clipShape(Capsule())
            .task { guard motion && !reduce else { return }; withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { x = true } }
    }
}
