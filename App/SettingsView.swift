import CleanKit
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case scanning, exceptions, appearance, mole, agents, about
    var id: String { rawValue }
    var title: String {
        switch self { case .scanning: "Skanowanie"; case .exceptions: "Wyjątki"; case .appearance: "Wygląd"; case .mole: "Mole"; case .agents: "Agenci (MCP)"; case .about: "O aplikacji" }
    }
    var symbol: String {
        switch self { case .scanning: "magnifyingglass"; case .exceptions: "lock.shield"; case .appearance: "paintpalette"; case .mole: "wrench.and.screwdriver"; case .agents: "point.3.connected.trianglepath.dotted"; case .about: "info.circle" }
    }
    var group: String {
        switch self { case .scanning, .exceptions, .appearance: "Aplikacja"; case .mole: "Silnik"; case .agents: "Integracje"; case .about: "Informacje" }
    }
    var keywords: String {
        switch self {
        case .scanning: "repozytoria duże pliki próg skan start git repositories large files threshold scan"
        case .exceptions: "wyjątki chronione foldery pliki wykluczenia nie usuwaj exceptions protected folders files exclude"
        case .appearance: "animacje ruch ekran startowy maskotka splash motyw jasny ciemny język animations motion theme light dark language"
        case .mole: "mo wersja aktualizacja historia operacje instalacja engine history install"
        case .agents: "mcp serwer agenci umiejętność skill claude narzędzia openbot server agents tools"
        case .about: "wersja logi domyślne reset version logs defaults update aktualizacje"
        }
    }
}

/// Lista kategorii ustawień z wyszukiwarką (panel listy).
struct SettingsList: View {
    @Binding var page: SettingsPage
    let query: String
    var updateDot = false
    var appUpdateDot = false

    private var pages: [SettingsPage] {
        query.isEmpty ? SettingsPage.allCases : SettingsPage.allCases.filter { ($0.title + " " + $0.keywords).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(["Aplikacja", "Silnik", "Integracje", "Informacje"], id: \.self) { g in
                let items = pages.filter { $0.group == g }
                if !items.isEmpty {
                    Text(g).font(.caption).foregroundStyle(Theme.secondary).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
                    ForEach(items) { p in
                        Button { page = p } label: {
                            HStack(spacing: 10) {
                                Image(systemName: p.symbol).frame(width: 20).foregroundStyle(page == p ? Theme.accent : Theme.secondary)
                                Text(tr(p.title))
                                Spacer()
                                if (p == .mole && updateDot) || (p == .about && appUpdateDot) { Circle().fill(Theme.accent).frame(width: 8, height: 8).accessibilityLabel("Dostępna aktualizacja") }
                            }
                            .padding(.horizontal, 10).frame(height: 34)
                            .background(page == p ? Theme.field : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityAddTraits(page == p ? .isSelected : [])
                    }
                }
            }
            if pages.isEmpty { Text(tr("Brak wyników")).foregroundStyle(Theme.secondary).padding(10) }
        }
    }
}

struct SettingGroup<Content: View>: View {
    let header: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr(header)).font(.headline).padding(.leading, 2)
            VStack(spacing: 0) { content }.cardStyle()
        }
    }
}

/// Wiersz ustawienia: tytuł i opis po lewej, kontrolka po prawej.
struct SettingRow<Control: View>: View {
    let title: String
    var desc: String = ""
    var divider = true
    @ViewBuilder let control: Control
    var body: some View {
        VStack(spacing: 0) {
            if divider { Divider().overlay(Theme.border.opacity(0.6)) }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr(title))
                    if !desc.isEmpty { Text(tr(desc)).font(.callout).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 12)
                control
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }
}

struct SettingsDetail: View {
    let page: SettingsPage
    let model: Model
    let mole: MoleModel
    let updater: AppUpdater
    @AppStorage("set.autoUpdate") private var autoUpdate = true
    @AppStorage("set.scanRepos") private var scanRepos = true
    @AppStorage("set.idleDays") private var idleDays = 60
    @AppStorage("set.largeMB") private var largeMB = 100
    @AppStorage("set.motion") private var motion = true
    @AppStorage("set.theme") private var theme = "dark"
    @AppStorage("set.lang") private var lang = "pl"
    @AppStorage("set.splash") private var splash = true
    @AppStorage("set.menubar") private var menubar = true
    @AppStorage("set.hideDock") private var hideDock = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(page.title).font(.system(size: 26, weight: .semibold))
                switch page {
                case .scanning: scanning
                case .exceptions: exceptions
                case .appearance: appearance
                case .mole: moleSettings
                case .agents: AgentsSettings()
                case .about: about
                }
            }
            .padding(.horizontal, 36).padding(.vertical, 26).frame(maxWidth: 780, alignment: .leading).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func menu<T: Hashable>(_ selection: Binding<T>, _ options: [(T, String)]) -> some View {
        Picker("", selection: selection) { ForEach(options, id: \.0) { Text($0.1).tag($0.0) } }
            .labelsHidden().pickerStyle(.menu).frame(width: 150)
    }

    private var scanning: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingGroup(header: "Skanowanie przy starcie") {
                SettingRow(title: "Szukaj nieużywanych repozytoriów", desc: "Przeszukuje katalog domowy pod kątem node_modules, .venv i podobnych. Wyłącz, jeśli start jest za wolny.", divider: false) {
                    Toggle("", isOn: $scanRepos).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: "Nieużywane od", desc: "Od ilu dni bez zmian w git repozytorium trafia na listę do posprzątania.") {
                    menu($idleDays, [(14, "14 dni"), (30, "30 dni"), (60, "60 dni"), (90, "90 dni"), (180, "180 dni")])
                }
                SettingRow(title: "Duże pliki powyżej", desc: "Najmniejszy rozmiar pliku pokazywany w Analizie.") {
                    menu($largeMB, [(50, "50 MB"), (100, "100 MB"), (250, "250 MB"), (500, "500 MB"), (1000, "1 GB")])
                }
            }
            SettingGroup(header: "Zastosowanie") {
                SettingRow(title: "Skanuj z nowymi ustawieniami", desc: "Zmiany działają od następnego skanu.", divider: false) {
                    Button(tr("Skanuj teraz")) { Task { await model.refresh() } }.disabled(model.phase != .ready)
                }
            }
        }
    }

    private var exceptions: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingGroup(header: "Chronione foldery i pliki") {
                if model.protectedPaths.isEmpty {
                    SettingRow(title: "Brak wyjątków", desc: "Dodaj folder albo plik, którego OpenCleaner nigdy nie pokaże do usunięcia. Tarczą w widoku Duże pliki chronisz pojedynczy plik.", divider: false) { EmptyView() }
                }
                ForEach(Array(model.protectedPaths.enumerated()), id: \.element) { i, p in
                    SettingRow(title: URL(fileURLWithPath: p).lastPathComponent, desc: p.replacingOccurrences(of: NSHomeDirectory(), with: "~"), divider: i > 0) {
                        Button(tr("Usuń z listy")) { withAnimation(Theme.ease) { model.unprotect(p) } }
                    }
                }
            }
            SettingGroup(header: "Dodaj") {
                SettingRow(title: "Dodaj folder lub plik", desc: "Wyjątki działają w skanach, Dużych plikach, Repozytoriach, Poradach i własnym czyszczeniu OpenCleaner. Czyszczenie przez Mole (mo clean) działa poza tą listą.", divider: false) {
                    Button(tr("Wybierz…")) {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
                        if panel.runModal() == .OK { for u in panel.urls { model.protect(u) } }
                    }
                }
            }
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingGroup(header: "Motyw") {
                HStack(spacing: 14) {
                    ThemeTile(title: "Jasny", scheme: .light, selected: theme == "light") { theme = "light" }
                    ThemeTile(title: "Ciemny", scheme: .dark, selected: theme == "dark") { theme = "dark" }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            SettingGroup(header: "Język") {
                SettingRow(title: "Język aplikacji", desc: "Zmiana działa od razu. Wyniki już wykonanych skanów odświeżą się po następnym skanie.", divider: false) {
                    LanguageSelect(lang: $lang)
                }
            }
            SettingGroup(header: "Ruch") {
                SettingRow(title: "Animacje", desc: "Wyłącz, żeby zniknęły przejścia i ruch maskotki. Systemowe „Ogranicz ruch” zawsze ma pierwszeństwo.", divider: false) {
                    Toggle("", isOn: $motion).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: "Ekran startowy", desc: "Pokazuj maskotkę przy uruchamianiu. Zmiana działa od następnego uruchomienia.") {
                    Toggle("", isOn: $splash).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingGroup(header: "Okno i ikony") {
                SettingRow(title: "Ikona w pasku menu", desc: "Maskotka w pasku menu pokazuje wolne miejsce i swap oraz otwiera okno aplikacji.", divider: false) {
                    Toggle("", isOn: $menubar).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: "Ukryj ikonę w Docku", desc: menubar ? "Aplikacja zostaje w pasku menu, a okno otwierasz z jego menu." : "Wymaga włączonej ikony w pasku menu.") {
                    Toggle("", isOn: $hideDock).labelsHidden().toggleStyle(.switch).disabled(!menubar)
                }
            }
        }
    }

    private var moleSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingGroup(header: "Silnik czyszczenia") {
                SettingRow(title: "Mole", desc: Mole.executable.map { trf("Wersja %@%@ · %@", "\(mole.version ?? "…")", "\(mole.latestVersion != nil && !mole.updateAvailable ? tr(" (aktualna)") : "")", "\($0.path)") } ?? "Nie znaleziono. OpenCleaner potrzebuje Mole do czyszczenia i optymalizacji.", divider: false) {
                    if Mole.executable == nil {
                        Button(tr("Zainstaluj")) { Task { await mole.install(); await mole.loadMoleInfo() } }.disabled(Mole.brew == nil || mole.engine == .installing)
                    } else {
                        Label(tr("Zainstalowany"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.ok)
                    }
                }
                if mole.updateAvailable || mole.updating || mole.updateMessage != nil {
                    SettingRow(title: "Dostępna aktualizacja", desc: mole.updateMessage ?? trf("Nowa wersja %@ (masz %@).", "\(mole.latestVersion ?? "")", "\(mole.version ?? "?")")) {
                        if mole.updating { ProgressView().controlSize(.small) }
                        else if mole.updateAvailable { Button(tr("Aktualizuj")) { Task { await mole.updateMole() } }.buttonStyle(.borderedProminent) }
                    }
                }
                SettingRow(title: "Dokumentacja") {
                    Button(tr("Otwórz mole.fit")) { NSWorkspace.shared.open(URL(string: "https://mole.fit")!) }
                }
            }
            SettingGroup(header: "Ostatnie operacje") {
                if mole.history.isEmpty {
                    SettingRow(title: "Brak historii", desc: "Operacje Mole pojawią się tutaj.", divider: false) { EmptyView() }
                }
                ForEach(Array(mole.history.enumerated()), id: \.element.id) { i, h in
                    SettingRow(title: h.command + (h.dryRun ? " (podgląd)" : ""), desc: h.startedAt, divider: i > 0) {
                        Text(h.dryRun || h.items == 0 ? "bez zmian" : "\(Mole.plItems(h.items)) · \(Mole.parseSize(h.size).map(Model.size) ?? h.size)").foregroundStyle(Theme.secondary).monospacedDigit()
                    }
                }
            }
        }
        .task { await mole.loadMoleInfo() }
    }

    private var updateText: String {
        switch updater.state {
        case .idle: trf("Wersja %@.", "\(AppUpdater.current)")
        case .checking: "Sprawdzam…"
        case .upToDate: trf("Masz najnowszą wersję (%@).", "\(AppUpdater.current)")
        case .available: trf("Dostępna wersja %@ (masz %@).", "\(updater.release?.version ?? "")", "\(AppUpdater.current)")
        case .installing: "Pobieram i instaluję…"
        case .failed(let m): m
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingGroup(header: "OpenCleaner") {
                SettingRow(title: "Wersja", divider: false) {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0").foregroundStyle(Theme.secondary)
                }
                SettingRow(title: "Aktualizacje", desc: updateText) {
                    switch updater.state {
                    case .checking, .installing: ProgressView().controlSize(.small)
                    case .available: Button(tr("Zainstaluj i uruchom ponownie")) { Task { await updater.install() } }.buttonStyle(.borderedProminent)
                    default: Button(tr("Sprawdź teraz")) { Task { await updater.check() } }
                    }
                }
                SettingRow(title: "Sprawdzaj automatycznie", desc: "Raz na dobę, przy uruchomieniu. Instalacja zawsze wymaga Twojego kliknięcia.") {
                    Toggle("", isOn: $autoUpdate).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: "Logi Mole", desc: "Zapis tego, co Mole zrobił na tym Macu.") {
                    Button(tr("Pokaż w Finderze")) {
                        NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/mole")])
                    }
                }
                SettingRow(title: "Przywróć ustawienia domyślne", desc: "Resetuje wszystkie ustawienia z tej listy.") {
                    Button(tr("Przywróć")) {
                        for k in ["set.scanRepos", "set.idleDays", "set.largeMB", "set.motion", "set.splash", "set.menubar", "set.hideDock", "set.autoUpdate", "set.theme", "set.lang"] { UserDefaults.standard.removeObject(forKey: k) }
                    }
                }
            }
            Text(tr("OpenCleaner czyści przez Mole, który kasuje na stałe, oraz przez Kosz (repozytoria). Przed każdym czyszczeniem pokazuje podgląd i prosi o potwierdzenie."))
                .font(.callout).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Kafelek wyboru motywu: miniatura okna w palecie danego motywu.
struct ThemeTile: View {
    let title: String
    let scheme: ColorScheme
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.rail).frame(width: 14)
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(Theme.accent).frame(width: 30, height: 5)
                        Capsule().fill(Theme.secondary.opacity(0.5)).frame(width: 52, height: 4)
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.card).overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.border)).frame(height: 22)
                    }
                    .padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .padding(5).frame(width: 150, height: 86)
                .background(Theme.frame, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .environment(\.colorScheme, scheme)
                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Theme.accent : Theme.secondary)
                    Text(tr(title)).fontWeight(selected ? .semibold : .regular)
                }
            }
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel(trf("Motyw %@", "\(title)"))
    }
}
