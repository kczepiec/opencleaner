import CleanKit
import SwiftUI

/// Ikona w pasku menu: logo ("C" z miotłą i iskrą) jako obraz szablonowy, więc system maluje je na biało lub czarno.
/// Rysujemy je czystym AppKitem z tych samych krzywych co logo w aplikacji (`LogoPaths`). Nie wolno tego robić przez
/// ImageRenderer: renderowanie SwiftUI wewnątrz definicji sceny zapętla aktualizację grafu i zawiesza cały interfejs.
enum MenuIcon {
    static let image: NSImage = {
        let s: CGFloat = 0.118                        // 194 x 152 jednostek logo na około 23 x 18 pt
        let img = NSImage(size: NSSize(width: 23, height: 18), flipped: true) { _ in
            guard let g = NSGraphicsContext.current?.cgContext else { return false }
            g.translateBy(x: -106 * s + 0.5, y: -30 * s)
            g.scaleBy(x: s, y: s)
            g.setFillColor(NSColor.black.cgColor)
            g.addPath(LogoPaths.crescent.cgPath); g.fillPath()
            // przerwa wokół miotły, jak w logo
            g.saveGState()
            g.setBlendMode(.clear); g.setLineWidth(11); g.setLineJoin(.round)
            g.addPath(LogoPaths.broom.cgPath); g.strokePath()
            g.restoreGState()
            g.addPath(LogoPaths.broom.cgPath); g.fillPath()
            g.addPath(LogoPaths.sparkle.cgPath); g.fillPath()
            return true
        }
        img.isTemplate = true
        return img
    }()
}

/// Okienko z paska menu: stan Maca na jedno spojrzenie (zdrowie, procesor, pamięć, dysk, swap, sieć, bateria, najcięższe aplikacje).
/// Dane z `mo status --json` odświeżają się co 3 s, gdy okienko jest otwarte. Bez Mole zostają dysk i aplikacje.
struct MenuBarView: View {
    let model: Model
    let mole: MoleModel
    let open: () -> Void

    private var swapFraction: Double? {
        guard let s = mole.status, s.swapTotal > 0 else { return nil }
        return Double(s.swapUsed) / Double(s.swapTotal)
    }
    private var swapHigh: Bool { (swapFraction ?? 0) > 0.7 }
    private var lowSpace: Bool { model.volume.map { Double($0.available) / Double(max($0.total, 1)) < 0.1 } ?? false }
    private var mood: Mascot.Mood { lowSpace || swapHigh ? .content : .happy }
    private var headline: String { lowSpace ? "Dysk jest prawie pełny" : (swapHigh ? "Swap prawie pełny" : "Wszystko w porządku") }
    private let warn = Theme.warn

    private func rate(_ mbs: Double) -> String { mbs >= 1 ? String(format: "%.1f MB/s", mbs) : String(format: "%.0f KB/s", mbs * 1024) }
    private func pressureText(_ p: String) -> String {
        switch p { case "warn": tr("Podwyższony"); case "critical": tr("Krytyczny"); default: tr("Prawidłowy") }
    }
    private func batteryStatus(_ b: Mole.Battery) -> String {
        switch b.status { case "charging": tr("Ładuje się"); case "charged": tr("Naładowana"); default: tr("Na baterii") }
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            if let st = mole.status {
                chips(st)
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        tile("Procesor", "\(Int(st.cpu.rounded()))%", st.cpu / 100, trf("Obciążenie %@ · %@ rdzeni", String(format: "%.1f", st.load1), "\(st.cores)"), tint: st.cpu > 85 ? warn : Theme.accent)
                        tile("Pamięć", "\(Int((Double(st.memUsed) / Double(max(st.memTotal, 1)) * 100).rounded()))%", Double(st.memUsed) / Double(max(st.memTotal, 1)),
                             "\(Model.size(st.memUsed)) / \(Model.size(st.memTotal))", tint: st.pressure == "normal" || st.pressure.isEmpty ? Theme.accent : warn,
                             badge: st.pressure.isEmpty ? nil : pressureText(st.pressure))
                    }
                    GridRow {
                        if let v = model.volume {
                            tile("Dysk", Model.size(v.available), Double(v.used) / Double(max(v.total, 1)), trf("zajęte %@ z %@", Model.size(v.used), Model.size(v.total)), tint: lowSpace ? warn : Theme.accent, unit: tr("wolne"))
                        }
                        if let f = swapFraction {
                            tile("Swap", Model.size(mole.status?.swapUsed ?? 0), f, trf("z %@", Model.size(mole.status?.swapTotal ?? 0)), tint: swapHigh ? warn : Theme.accent)
                        }
                    }
                    GridRow {
                        infoTile("Sieć", symbol: "arrow.up.arrow.down") {
                            Text("↓ \(rate(st.netDown))").monospacedDigit()
                            Text("↑ \(rate(st.netUp))").monospacedDigit().foregroundStyle(Theme.secondary)
                        }
                        if let b = st.battery {
                            infoTile("Bateria", symbol: b.charging ? "battery.100.bolt" : "battery.75") {
                                Text("\(b.percent)%").font(.system(size: 22, weight: .semibold)).monospacedDigit()
                                Text(batteryStatus(b) + (b.timeLeft.isEmpty || b.charging ? "" : " · \(b.timeLeft)")).font(.caption).foregroundStyle(Theme.secondary)
                                Text(trf("Stan %@ · %@ cykli", b.health, "\(b.cycles)")).font(.caption).foregroundStyle(Theme.secondary)
                            }
                        } else { Color.clear.frame(height: 1) }
                    }
                }
            } else if let v = model.volume {
                meterRow("Wolne na dysku", Model.size(v.available), Double(v.used) / Double(max(v.total, 1)), tint: lowSpace ? warn : Theme.accent,
                         note: trf("zajęte %@ z %@", Model.size(v.used), Model.size(v.total)))
            }
            if !mole.memApps.isEmpty { topApps }
            if mole.updateAvailable {
                Label(trf("Dostępna aktualizacja silnika %@", "\(mole.latestVersion ?? "")"), systemImage: "arrow.down.circle.fill")
                    .font(.callout).foregroundStyle(Theme.accent).frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 2) {
                action("Otwórz OpenCleaner", "arrow.up.forward.app", "O", open)
                action("Zakończ OpenCleaner", "power", "Q") { NSApp.terminate(nil) }
            }
        }
        .padding(16).frame(width: 360)
        .background(Theme.panel).environment(\.colorScheme, .dark)
        .task {
            model.volume = Volume.at(FileManager.default.homeDirectoryForCurrentUser) ?? model.volume
            guard mole.engine == .ready || Mole.executable != nil else { await mole.loadMemory(); return }
            var tick = 0
            while !Task.isCancelled {
                await mole.refreshStatus()
                if tick % 3 == 0 { await mole.loadMemory() }
                tick += 1
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Mascot(size: 40, mood: mood, animated: false).frame(width: 52, height: 52)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border.opacity(0.7)))
            VStack(alignment: .leading, spacing: 2) {
                Text(tr(headline)).font(.headline)
                Wordmark(size: 12)
            }
            Spacer(minLength: 0)
            if let st = mole.status, st.health > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(st.health)").font(.system(size: 30, weight: .semibold)).monospacedDigit().foregroundStyle(st.health < 60 ? warn : Theme.ok)
                    Text(Mole.plHealth(st.healthMessage)).font(.caption).foregroundStyle(Theme.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func chips(_ st: Mole.Status) -> some View {
        HStack(spacing: 6) {
            ForEach([st.chip, Model.size(st.memTotal), st.uptime.isEmpty ? "" : trf("działa %@", st.uptime)].filter { !$0.isEmpty }, id: \.self) { t in
                Text(t).font(.caption).lineLimit(1).padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Theme.field, in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private func tile(_ title: String, _ value: String, _ fraction: Double, _ sub: String, tint: Color, unit: String? = nil, badge: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tr(title)).font(.caption).foregroundStyle(Theme.secondary)
                Spacer(minLength: 4)
                if let badge { Text(badge).font(.caption2.weight(.semibold)).foregroundStyle(tint).padding(.horizontal, 6).padding(.vertical, 2).background(tint.opacity(0.14), in: Capsule()) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                if let unit { Text(unit).font(.caption).foregroundStyle(Theme.secondary) }
            }
            Capsule().fill(Theme.track).frame(height: 5)
                .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(tint).frame(width: g.size.width * min(max(fraction, 0), 1)) } }
            Text(sub).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.85)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 12)
        .accessibilityElement(children: .combine)
    }

    private func infoTile<C: View>(_ title: String, symbol: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.caption2).foregroundStyle(Theme.secondary)
                Text(tr(title)).font(.caption).foregroundStyle(Theme.secondary)
            }
            content()
        }
        .font(.callout).padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).cardStyle(radius: 12)
        .accessibilityElement(children: .combine)
    }

    private var topApps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Najwięcej pamięci zajmują")).font(.caption).foregroundStyle(Theme.secondary)
            ForEach(mole.memApps.prefix(5)) { a in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 18, height: 18)
                    Text(a.name).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Model.size(a.bytes)).foregroundStyle(Theme.secondary).monospacedDigit()
                }.font(.callout)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 12)
    }

    private func meterRow(_ title: String, _ value: String, _ fraction: Double, tint: Color, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr(title)).foregroundStyle(Theme.secondary)
                Spacer()
                Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
            }
            Capsule().fill(Theme.track).frame(height: 7)
                .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(tint).frame(width: g.size.width * min(max(fraction, 0), 1)) } }
            if let note { Text(note).font(.caption).foregroundStyle(Theme.secondary) }
        }
        .font(.callout).padding(14).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 14)
    }

    private func action(_ title: String, _ symbol: String, _ key: KeyEquivalent, _ run: @escaping () -> Void) -> some View {
        MenuAction(title: title, symbol: symbol, key: key, run: run)
    }
}

private struct MenuAction: View {
    let title: String, symbol: String, key: KeyEquivalent, run: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(Theme.secondary)
                Text(tr(title))
                Spacer()
                Text("⌘" + String(key.character).uppercased()).font(.caption).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(hover ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).keyboardShortcut(key).onHover { hover = $0 }.animation(Theme.quick, value: hover)
    }
}

/// Ikona w pasku menu jako zwykły NSStatusItem z popoverem. MenuBarExtra zapętlał aktualizację grafu SwiftUI
/// i zawieszał aplikację przy starcie, więc ten element jest czystym AppKitem.
@MainActor final class StatusBar: NSObject {
    static let shared = StatusBar()
    private var item: NSStatusItem?
    private let popover = NSPopover()

    /// Otwiera główne okno (też wtedy, gdy zostało zamknięte i aplikacja siedzi w pasku menu).
    var openMain: (() -> Void)?
    /// Pierwszy start tej sesji już się odbył (ekran startowy i skan dysku tylko raz).
    var started = false

    func configure(model: Model, mole: MoleModel, open: @escaping () -> Void) {
        openMain = open
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView(model: model, mole: mole, open: { [weak self] in
            self?.popover.performClose(nil)
            open()
        }))
    }

    func setVisible(_ on: Bool) {
        if on, item == nil {
            let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            it.button?.image = MenuIcon.image
            it.button?.target = self
            it.button?.action = #selector(toggle(_:))
            item = it
        } else if !on, let it = item {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(it)
            item = nil
        }
    }

    @objc private func toggle(_ sender: Any?) {
        guard let button = item?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
