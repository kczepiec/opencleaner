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

/// Okienko z paska menu: stan dysku i swapu na jedno spojrzenie oraz skróty.
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

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Mascot(size: 40, mood: mood, animated: false).frame(width: 52, height: 52)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border.opacity(0.7)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.headline)
                    Wordmark(size: 12)
                }
                Spacer(minLength: 0)
            }
            if let v = model.volume {
                meter("Wolne na dysku", Model.size(v.available), Double(v.used) / Double(max(v.total, 1)), tint: lowSpace ? warn : Theme.accent,
                      note: "zajęte \(Model.size(v.used)) z \(Model.size(v.total))")
            }
            if let f = swapFraction, let st = mole.status {
                meter("Swap", "\(Model.size(st.swapUsed)) z \(Model.size(st.swapTotal))", f, tint: swapHigh ? warn : Theme.accent, note: nil)
            }
            if mole.updateAvailable {
                Label("Dostępna aktualizacja silnika \(mole.latestVersion ?? "")", systemImage: "arrow.down.circle.fill")
                    .font(.callout).foregroundStyle(Theme.accent).frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 2) {
                action("Otwórz OpenCleaner", "arrow.up.forward.app", "O", open)
                action("Zakończ OpenCleaner", "power", "Q") { NSApp.terminate(nil) }
            }
        }
        .padding(16).frame(width: 310)
        .background(Theme.panel).environment(\.colorScheme, .dark)
        .task {
            model.volume = Volume.at(FileManager.default.homeDirectoryForCurrentUser) ?? model.volume
            if mole.engine == .ready || Mole.executable != nil { await mole.refreshStatus() }
        }
    }

    private func meter(_ title: String, _ value: String, _ fraction: Double, tint: Color, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr(title)).foregroundStyle(Theme.secondary)
                Spacer()
                Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
            }
            Capsule().fill(Theme.track).frame(height: 7)
                .overlay(alignment: .leading) {
                    GeometryReader { g in Capsule().fill(tint).frame(width: g.size.width * min(max(fraction, 0), 1)) }
                }
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

    func configure(model: Model, mole: MoleModel, open: @escaping () -> Void) {
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
