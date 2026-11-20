import SwiftUI

extension Color {
    /// Kolor z wartości docelowej (takiej, jaką ma OpenBot). Na tym ekranie macOS rozjaśnia ciemne tony przy renderowaniu
    /// aplikacji natywnych (zmierzone: #0E0E0E daje #101010, #222222 daje #2D2D2D, a w OpenBocie Electron daje dokładnie
    /// #222222). Odwracamy tę krzywą w jednym miejscu, żeby wyświetlone kolory zgadzały się z OpenBotem.
    init(hex: UInt32) {
        func fix(_ v: UInt32) -> Double {
            let o = Double(v)
            let i: Double
            switch o {
            case ..<16: i = o * 14 / 16
            case ..<45: i = 14 + (o - 16) * 20 / 29
            default: i = 34 + (o - 45) * 221 / 210
            }
            return min(max(i, 0), 255) / 255
        }
        self.init(red: fix((hex >> 16) & 255), green: fix((hex >> 8) & 255), blue: fix(hex & 255))
    }
}

extension Color {
    /// Kolor zależny od motywu okna. `dark` przechodzi przez korektę `init(hex:)`, `light` jest czystym sRGB.
    init(light: NSColor, dark: NSColor) {
        self = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    init(light: UInt32, dark: UInt32) {
        func rgb(_ v: UInt32) -> NSColor { NSColor(srgbRed: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255, alpha: 1) }
        self.init(light: rgb(light), dark: NSColor(Color(hex: dark)))
    }
}

/// Paleta i układ wzorowane na OpenBocie: czarna rama, ciemnoszare panele, niebieski akcent.
enum Theme {
    // Wartości docelowe z makiety OpenCleaner (granat i niebieski akcent); Color(hex:) koryguje renderowanie macOS.
    static let frame = Color(light: 0xDEE3EC, dark: 0x07090D)
    static let rail = Color(light: 0xEEF1F6, dark: 0x0B0E14)
    static let panel = Color(light: 0xFFFFFF, dark: 0x0F1218)
    static let raised = Color(light: 0xE8EDF6, dark: 0x1B202A)
    static let field = Color(light: 0xEDF0F6, dark: 0x212736)
    static let accent = Color(light: 0x2F6BDB, dark: 0x5892F7)
    static let accentLight = Color(light: 0x4F86E8, dark: 0x73A4F6)
    static let card = Color(light: 0xF5F7FB, dark: 0x171B24)
    static let border = Color(light: 0xD3DAE6, dark: 0x262D3C)
    static let track = Color(light: 0xDDE3EE, dark: 0x2A3144)
    static let secondary = Color(light: 0x566074, dark: 0x8E97AB)
    static let ok = Color(light: 0x23823F, dark: 0x6CC070)
    static let warn = Color(light: 0x9A6A00, dark: 0xE8C25A)
    /// Podkład szkieletów ładowania i delikatnych nakładek.
    static let ghost = Color(light: NSColor.black.withAlphaComponent(0.07), dark: NSColor.white.withAlphaComponent(0.07))
    /// Jedna krzywa dla całej aplikacji: szybki start, miękkie wyhamowanie (ease-out wykładniczy).
    static let ease = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.42)
    static let quick = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)
}

struct Panel<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PanelHeader<Trailing: View>: View {
    let title: String
    var subtitle: String = ""
    var icon: NSImage? = nil
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let icon { Image(nsImage: icon).resizable().interpolation(.high).frame(width: 46, height: 46) }
            VStack(alignment: .leading, spacing: 2) {
                Text(tr(title)).font(.title2.weight(.semibold))
                if !subtitle.isEmpty { Text(tr(subtitle)).font(.callout).foregroundStyle(Theme.secondary).lineLimit(2) }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }
}

/// Wiersz listy jak w OpenBocie: kafelek z ikoną, tytuł, podtytuł.
struct ListRow: View {
    let symbol: String
    var image: NSImage? = nil
    let title: String
    var subtitle: String = ""
    var selected = false
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image { Image(nsImage: image).resizable().interpolation(.high).frame(width: 30, height: 30) }
                else { Image(systemName: symbol).font(.system(size: 16, weight: .medium)) }
            }
            .frame(width: 38, height: 38)
            .background(image == nil ? Theme.field : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(tr(title)).font(.body.weight(.medium)).lineLimit(1)
                if !subtitle.isEmpty { Text(tr(subtitle)).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(selected ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

enum Area: String, CaseIterable, Hashable {
    case dashboard, cleaning, apps, analysis, photos, status, settings
    var title: String {
        switch self {
        case .dashboard: "Pulpit"
        case .cleaning: "Czyszczenie"
        case .apps: "Aplikacje"
        case .analysis: "Analiza"
        case .photos: "Zdjęcia"
        case .status: "Status"
        case .settings: "Ustawienia"
        }
    }
    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .cleaning: "bubbles.and.sparkles"
        case .apps: "square.grid.2x2"
        case .analysis: "chart.xyaxis.line"
        case .photos: "photo.on.rectangle"
        case .status: "waveform.path.ecg"
        case .settings: "gearshape"
        }
    }
    var hasList: Bool { self == .cleaning || self == .apps || self == .analysis || self == .settings }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(radius: 16)
    }
}

struct StatChip: View {
    let value: Int
    let label: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.system(size: 28, weight: .semibold)).monospacedDigit().foregroundStyle(value > 0 ? tint : Theme.secondary)
            Text(tr(label)).font(.callout).foregroundStyle(Theme.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: 16)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Karta jak w OpenBocie: jednolite tło i cienka ramka.
    func cardStyle(radius: CGFloat = 16, fill: Color = Theme.card) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.border.opacity(0.7)))
    }
}

/// Ustawienie "Animacje": wyłączone usuwa ruch dekoracyjny (maskotka, przejścia).
private struct MotionKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var czystoMotion: Bool { get { self[MotionKey.self] } set { self[MotionKey.self] = newValue } }
}
