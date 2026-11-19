import SwiftUI

/// Ekran startowy: logo, napis marki i status.
struct SplashView: View {
    let status: String
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.frame.ignoresSafeArea()
            VStack(spacing: 18) {
                Mascot(size: 120, mood: .busy)
                Wordmark(size: 36)
                Text(status).foregroundStyle(Theme.secondary)
            }
            .scaleEffect(shown ? 1 : 0.94).opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.65)) { shown = true } }
    }
}
