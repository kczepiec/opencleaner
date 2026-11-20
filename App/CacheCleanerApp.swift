import CleanKit
import SwiftUI

/// Zamknięcie okna chowa aplikację do paska menu (gdy ikona w pasku jest włączona), zamiast kończyć proces.
/// Kliknięcie ikony w Docku otwiera okno z powrotem. Wyjście: ⌘Q albo "Zakończ" w menu paska.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(UserDefaults.standard.object(forKey: "set.menubar") as? Bool ?? true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Task { @MainActor in StatusBar.shared.openMain?() } }
        return true
    }
}

@main
struct CzystoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = Model()
    @State private var mole = MoleModel()

    init() {
        installLanguageBundle()
        L10n.lookup = { tr($0) }
        L10n.english = Lang.current == .en
    }

    var body: some Scene {
        Window("OpenCleaner", id: "main") { RootView(model: model, mole: mole) }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentMinSize)
            .defaultSize(width: 1240, height: 880)
    }
}

struct RootView: View {
    let model: Model
    let mole: MoleModel
    @State private var area: Area = .dashboard
    @State private var cleaningSel = "clean"
    @State private var analysisSel = "large"
    @State private var appSel: String?
    @State private var tips = TipsModel()
    @State private var sim = SimModel()
    @State private var login = LoginModel()
    @State private var ai = AIModel()
    @State private var space = SpaceModel()
    @State private var photos = PhotosModel()
    @State private var updater = AppUpdater()
    @AppStorage("set.autoUpdate") private var autoUpdate = true
    @State private var query = ""
    @State private var settingsPage: SettingsPage = .scanning
    @AppStorage("set.motion") private var motion = true
    @AppStorage("set.theme") private var theme = "dark"
    @AppStorage("set.lang") private var lang = "pl"
    @AppStorage("set.splash") private var showSplash = true
    @AppStorage("set.hideDock") private var hideDock = false
    @AppStorage("set.menubar") private var menubarOn = true
    @State private var splash = (UserDefaults.standard.object(forKey: "set.splash") as? Bool ?? true) && !StatusBar.shared.started
    @State private var minimumElapsed = false
    @Namespace private var railSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    private var reduceMotion: Bool { systemReduce || !motion }

    var body: some View {
        ZStack {
            Theme.frame.ignoresSafeArea()
            HStack(spacing: 8) {
                rail
                if area.hasList { Panel { listPanel }.frame(width: 272) }
                Panel { mainPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).id(panelKey).transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity)) }
                    .animation(reduceMotion ? nil : Theme.ease, value: panelKey)
            }
            .padding(.top, 2).padding([.horizontal, .bottom], 8)
            .id(lang)
            if splash { SplashView(status: model.status).transition(.opacity.combined(with: .scale(scale: 1.03))).zIndex(1) }
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(ScrollerStyle())   // cienkie paski nakładkowe zamiast jasnych pasków z torem
        .preferredColorScheme(theme == "light" ? .light : .dark)
        .tint(Theme.accent)
        .environment(\.czystoMotion, motion)
        .environment(\.locale, Locale(identifier: lang))
        .transaction { if !motion { $0.animation = nil } }
        .task {
            StatusBar.shared.configure(model: model, mole: mole, open: { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) })
            StatusBar.shared.setVisible(menubarOn)
            applyDock(); mole.check()
            // Okno otwarte ponownie po schowaniu do paska menu nie skanuje dysku od nowa.
            if !StatusBar.shared.started { StatusBar.shared.started = true; await model.refresh() }
        }
        .onChange(of: lang) { _, l in L10n.english = l == "en"; Task { await tips.load(days: UserDefaults.standard.object(forKey: "set.unusedDays") as? Int ?? 90) } }
        .onChange(of: hideDock) { _, _ in applyDock() }
        .onChange(of: menubarOn) { _, on in StatusBar.shared.setVisible(on); if !on { hideDock = false }; applyDock() }
        .task { await mole.loadMoleInfo() }
        .task { await tips.load(days: UserDefaults.standard.object(forKey: "set.unusedDays") as? Int ?? 90) }
        .task { await sim.load() }
        .task { await login.load() }
        .task {
            // Co pół godziny sprawdza, czy czas na przypomnienie (liczy cache narzędzi i bezpieczne cache narzędzi AI).
            while !Task.isCancelled {
                let safe = ai.groups.filter { $0.kind == .cache || $0.kind == .oldVersions }.reduce(Int64(0)) { $0 + $1.bytes }
                await Notifier.remindIfDue(reclaimable: tips.total + safe)
                try? await Task.sleep(for: .seconds(1800))
            }
        }
        .task { if autoUpdate { await updater.check(auto: true) } }
        .task { try? await Task.sleep(for: .seconds(1.2)); minimumElapsed = true }
        .onChange(of: model.phase == .ready && minimumElapsed) { _, ready in
            if ready { withAnimation(reduceMotion ? nil : Theme.ease) { splash = false } }
        }
        .onChange(of: area) { _, a in
            query = ""
            if a == .apps { Task { await mole.loadApps(); if appSel == nil { appSel = mole.apps.first?.id } } }
        }
        .alert("Gotowe", isPresented: Binding(get: { model.result != nil }, set: { if !$0 { model.result = nil } })) {
            Button(tr("OK"), role: .cancel) {}
        } message: { Text(model.result ?? "") }
    }

    /// Ukrycie ikony z Docka ma sens tylko z włączonym paskiem menu (inaczej nie byłoby jak otworzyć aplikacji).
    private func applyDock() {
        let hide = hideDock && menubarOn
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
        if hide { NSApp.activate(ignoringOtherApps: true) }
    }

    private var panelKey: String { "\(area.rawValue)-\(cleaningSel)-\(analysisSel)-\(appSel ?? "")-\(settingsPage.rawValue)" }

    // MARK: pasek ikon

    private var rail: some View {
        VStack(spacing: 10) {
            ForEach(Area.allCases.filter { $0 != .settings && !(mole.engine == .missing && ($0 == .apps || $0 == .status)) }, id: \.self) { a in
                Button { withAnimation(reduceMotion ? nil : Theme.ease) { area = a } } label: {
                    RailIcon(area: a, color: area == a ? Theme.accent : Theme.secondary)
                        .frame(width: 40, height: 40)
                        .background {
                            if area == a {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised)
                                    .matchedGeometryEffect(id: "railHighlight", in: railSpace)
                            }
                        }
                }
                .buttonStyle(.plain).help(a.title).accessibilityLabel(a.title)
                .accessibilityAddTraits(area == a ? .isSelected : [])
            }
            Spacer()
            railButton(.settings)
            Mascot(size: 30).help("OpenCleaner")
        }
        .padding(.vertical, 12).frame(width: 54)
        .background(Theme.rail, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func railButton(_ a: Area) -> some View {
        Button { withAnimation(reduceMotion ? nil : Theme.ease) { area = a } } label: {
            RailIcon(area: a, color: area == a ? Theme.accent : Theme.secondary)
                .frame(width: 40, height: 40)
                .background {
                    if area == a {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised)
                            .matchedGeometryEffect(id: "railHighlight", in: railSpace)
                    }
                }
        }
        .buttonStyle(.plain).help(a.title).accessibilityLabel(a.title)
        .overlay(alignment: .topTrailing) {
            if a == .settings && (mole.updateAvailable || updater.available) { Circle().fill(Theme.accent).frame(width: 9, height: 9).offset(x: -4, y: 4) }
        }
        .accessibilityAddTraits(area == a ? .isSelected : [])
    }

    // MARK: panel listy

    @ViewBuilder private var listPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if area == .apps || area == .settings {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                    TextField(area == .apps ? "Szukaj aplikacji" : "Szukaj w ustawieniach", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).frame(height: 34)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text(tr(area.title)).font(.headline).padding(.horizontal, 6).frame(height: 34, alignment: .leading)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    switch area {
                    case .cleaning:
                        row("bubbles.and.sparkles", "Czyszczenie systemu", sub(for: "clean", "Cache, logi, przeglądarki"), cleaningSel == "clean") { cleaningSel = "clean" }
                        if mole.engine != .missing { row("wrench.and.screwdriver", "Optymalizacja", sub(for: "optimize", "Usługi i cache systemu"), cleaningSel == "optimize") { cleaningSel = "optimize" } }
                    case .analysis:
                        row("shippingbox", "Duże pliki", model.largeReady ? trf("%@ plików", "\(model.large.count)") : "Szukam…", analysisSel == "large") { analysisSel = "large" }
                        row("arrow.triangle.branch", "Repozytoria", model.reposReady ? (model.rows(.repos).isEmpty ? "Nic nieużywanego" : Model.size(model.bytes(model.rows(.repos)))) : "Szukam…", analysisSel == "repos") { analysisSel = "repos" }
                        row("cpu", "System", "Woluminy, symulatory, zasoby", analysisSel == "system") { analysisSel = "system" }
                        row("lightbulb", "Porady", tips.loaded ? (tips.total > 0 ? trf("Do %@", "\(Model.size(tips.total))") : "Wszystko czyste") : "Szukam…", analysisSel == "tips") { analysisSel = "tips" }
                        row("brain", "Sprzątanie AI", ai.loaded ? (ai.total > 0 ? trf("Do %@", Model.size(ai.total)) : "Wszystko czyste") : "Szukam…", analysisSel == "ai") { analysisSel = "ai" }
                        row("arrow.down.app", "Instalatory", space.installersLoaded ? (space.installers.isEmpty ? "Wszystko czyste" : trf("Do %@", Model.size(space.installers.reduce(0) { $0 + $1.bytes }))) : "Szukam…", analysisSel == "installers") { analysisSel = "installers" }
                        row("doc.on.doc", "Duplikaty", space.dupesLoaded ? (space.dupes.isEmpty ? "Brak duplikatów" : trf("Do %@", Model.size(space.dupes.reduce(Int64(0)) { $0 + $1.bytes - $1.entries[0].bytes }))) : "Dokumenty i Pobrane", analysisSel == "dupes") { analysisSel = "dupes" }
                        row("externaldrive.badge.timemachine", "Kopie i migawki", space.backupsLoaded ? (space.backups.groups.isEmpty && space.snapshots.isEmpty ? "Brak kopii" : trf("Kopie iOS: %@", Model.size(space.backups.groups.reduce(0) { $0 + $1.bytes }))) : "Szukam…", analysisSel == "backups") { analysisSel = "backups" }
                        row("power", "Autostart", login.loaded ? trf("Programów: %@", "\(login.items.count)") : "Szukam…", analysisSel == "login") { analysisSel = "login" }
                        if sim.available {
                            row("iphone", "Symulatory", sim.loaded ? trf("%@ środowisk, %@", "\(sim.snap.runtimes.count)", "\(Model.size(sim.runtimeBytes))") : "Xcode", analysisSel == "sim") { analysisSel = "sim" }
                        }
                    case .apps:
                        if !mole.appsLoaded && mole.engine == .ready { ListSkeleton(rows: 10) }
                        ForEach(filteredApps) { app in
                            row("app", app.name, Mole.parseSize(app.size).map(Model.size) ?? "brak danych", appSel == app.id,
                                image: NSWorkspace.shared.icon(forFile: app.path)) { appSel = app.id }
                        }
                    case .settings: SettingsList(page: $settingsPage, query: query, updateDot: mole.updateAvailable, appUpdateDot: updater.available)
                    default: EmptyView()
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(10)
    }

    /// Wyjątek z dowolnego widoku: zapis na liście i natychmiastowe ukrycie pozycji we wszystkich listach.
    private func protectEverywhere(_ url: URL) {
        withAnimation(Theme.ease) { model.protect(url); space.drop(url); ai.drop(url) }
    }

    private var filteredApps: [Mole.App] {
        query.isEmpty ? mole.apps : mole.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func sub(for kind: String, _ idle: String) -> String {
        if let r = mole.runs[kind], r.running { return "Pracuję…" }
        if let p = mole.runs[kind]?.preview, !p.groups.isEmpty { return p.bytes > 0 ? trf("Do odzyskania %@", "\(Model.size(p.bytes))") : "Nic do wyczyszczenia" }
        return idle
    }

    private func row(_ symbol: String, _ title: String, _ subtitle: String, _ selected: Bool, image: NSImage? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { ListRow(symbol: symbol, image: image, title: title, subtitle: subtitle, selected: selected) }
            .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : []).animation(Theme.quick, value: selected)
    }

    // MARK: panel treści

    @ViewBuilder private var mainPanel: some View {
        switch area {
        case .dashboard: DashboardView(model: model, mole: mole, tips: tips, open: { a, sub in area = a; if let sub { analysisSel = sub } })
        case .cleaning:
            if cleaningSel == "clean" {
                MoleTaskView(kind: "clean", title: "Czyszczenie systemu", blurb: "Cache aplikacji, logi, przeglądarki i narzędzia deweloperskie.", mole: mole)
            } else {
                MoleTaskView(kind: "optimize", title: "Optymalizacja", blurb: "Odświeża cache i usługi systemu, naprawia bezpieczne drobiazgi.", mole: mole)
            }
        case .apps: AppDetailView(app: mole.apps.first { $0.id == appSel }, mole: mole)
        case .analysis:
            switch analysisSel {
            case "large": AnyView(LargeFilesView(model: model))
            case "system": AnyView(SystemView(mole: mole, model: model, openSimulators: sim.available ? { analysisSel = "sim" } : nil))
            case "sim": AnyView(SimulatorsView(sim: sim))
            case "login": AnyView(LoginItemsView(model: login))
            case "ai": AnyView(AICleanupView(model: ai, protect: protectEverywhere))
            case "installers": AnyView(InstallersView(model: space, protect: protectEverywhere))
            case "dupes": AnyView(DuplicatesView(model: space, protect: protectEverywhere))
            case "backups": AnyView(BackupsView(model: space))
            case "tips": AnyView(TipsView(model: model, tips: tips, open: { a, sub in area = a; if let sub { analysisSel = sub } }, openApp: { url in
                area = .apps; Task { await mole.loadApps(); appSel = url.path } }))
            default: AnyView(ReposView(model: model))
            }
        case .photos: PhotosView(model: photos)
        case .status: StatusView(mole: mole)
        case .settings: SettingsDetail(page: settingsPage, model: model, mole: mole, updater: updater)
        }
    }
}
