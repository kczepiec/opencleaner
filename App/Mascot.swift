import SwiftUI

enum Brand {
    static let starLight = Color(hex: 0x6F9DEB)
    static let starMid = Color(hex: 0x5E8CDA)
    static let starDark = Color(hex: 0x4B6CB5)
    static let wordGray = Color(light: 0x5A6A8A, dark: 0xB8C4DC)
}

/// Czterokątna gwiazdka z wklęsłymi bokami.
struct SparkleShape: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), R = min(r.width, r.height) / 2, k = R * 0.16
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - R))
        p.addQuadCurve(to: CGPoint(x: c.x + R, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + R), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x - R, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - R), control: CGPoint(x: c.x - k, y: c.y - k))
        p.closeSubpath()
        return p
    }
}

/// Logo OpenCleaner (jak `Branding/opencleaner-logo.svg`): niebieskie "C", miotła i iskra. Współrzędne w układzie SVG,
/// pole 200 x 200 wokół znaku. Nastrój animuje całość: praca to zamiatanie miotłą, radość to jeden podskok,
/// spokój to delikatne oddychanie.
struct Mascot: View {
    enum Mood { case happy, content, busy }
    var size: CGFloat = 64
    var mood: Mood = .happy
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.czystoMotion) private var motionOn
    @State private var sweep = 0.0
    @State private var breathe = false
    @State private var pop: CGFloat = 1

    private var moving: Bool { animated && !reduceMotion && motionOn }

    var body: some View {
        let k = size * 1.1 / 200
        ZStack(alignment: .topLeading) {
            LogoPaths.crescent.fill(LinearGradient(stops: [.init(color: Color(hex: 0x7ABEEA), location: 0), .init(color: Color(hex: 0x5F90F6), location: 0.38),
                                                           .init(color: Color(hex: 0x3A5CF0), location: 0.72), .init(color: Color(hex: 0x2A4FD0), location: 1)],
                                                   startPoint: UnitPoint(x: 150 / 384, y: 40 / 296), endPoint: UnitPoint(x: 190 / 384, y: 180 / 296)))
            LogoPaths.crescent.fill(RadialGradient(colors: [.white.opacity(0.22), .clear], center: UnitPoint(x: 150 / 384, y: 70 / 296), startRadius: 0, endRadius: 70))
            LogoPaths.broom.fill(LinearGradient(colors: [Color(light: 0x7C8AAE, dark: 0xE4E8F3), Color(light: 0x56648A, dark: 0xC6CEE2)], startPoint: UnitPoint(x: 0.5, y: 62 / 296), endPoint: UnitPoint(x: 0.5, y: 160 / 296)))
                .rotationEffect(.degrees(sweep), anchor: UnitPoint(x: 252.0 / 384, y: 118.0 / 296))
            LogoPaths.sparkle.fill(Color(hex: 0x509AF0))
        }
        .frame(width: 384, height: 296, alignment: .topLeading)
        .offset(x: -10, y: 43)
        .scaleEffect(k)
        .frame(width: size * 1.1, height: size * 1.1)
        .scaleEffect(pop * (moving && breathe ? 1.035 : 1))
        .accessibilityHidden(true)
        .onChange(of: mood) { _, new in
            guard moving, new == .happy else { return }
            withAnimation(.easeOut(duration: 0.14)) { pop = 1.14 }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.45).delay(0.14)) { pop = 1 }
        }
        .task {
            guard moving else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
        }
        .task(id: mood) {
            guard moving, mood == .busy else { withAnimation(Theme.ease) { sweep = 0 }; return }
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { sweep = 9 }
        }
    }
}

/// Napis marki: "Open" pogrubiony i biały, "Cleaner" lżejszy i szary.
struct Wordmark: View {
    var size: CGFloat = 15
    var body: some View {
        (Text("Open").fontWeight(.bold).foregroundColor(.primary) + Text("Cleaner").fontWeight(.regular).foregroundColor(Brand.wordGray))
            .font(.system(size: size))
            .accessibilityLabel("OpenCleaner")
    }
}

/// Pusty widok z logo zamiast ikony systemowej.
struct EmptyState: View {
    let title: String
    let text: String
    var mood: Mascot.Mood = .happy
    var body: some View {
        VStack(spacing: 10) {
            Mascot(size: 64, mood: mood)
            Text(tr(title)).font(.title3.weight(.semibold))
            Text(tr(text)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
