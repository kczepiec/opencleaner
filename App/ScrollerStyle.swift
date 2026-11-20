import AppKit
import SwiftUI

/// Wymusza cienkie paski przewijania nakładkowe z jasną gałką we wszystkich przewijanych widokach okna.
/// Przy podłączonej myszy macOS używa starych, jasnych pasków z torem, których `scrollIndicators(.hidden)` nie wyłącza,
/// a SwiftUI nie ma API do ich stylu, więc ustawiamy je na NSScrollView (co 0,8 s, bo widoki pojawiają się i znikają).
struct ScrollerStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Styler() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Styler: NSView {
        private var timer: Timer?

        override func viewDidMoveToWindow() {
            timer?.invalidate()
            guard window != nil else { return }
            apply()
            timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.apply() }
        }

        private func apply() {
            guard let root = window?.contentView else { return }
            walk(root)
        }

        private func walk(_ v: NSView) {
            if let s = v as? NSScrollView, s.scrollerStyle != .overlay || s.scrollerKnobStyle != .light {
                s.scrollerStyle = .overlay
                s.scrollerKnobStyle = .light
                s.autohidesScrollers = true
            }
            v.subviews.forEach(walk)
        }
    }
}
