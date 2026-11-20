import ObjectiveC
import SwiftUI

enum Lang: String, CaseIterable, Identifiable {
    case pl, en
    var id: String { rawValue }
    var name: String { self == .pl ? "Polski" : "English" }
    static var current: Lang { Lang(rawValue: UserDefaults.standard.string(forKey: "set.lang") ?? "pl") ?? .pl }
}

private let enBundle: Bundle? = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))

/// Bundle aplikacji kieruje wszystkie wyszukiwania tekstów (także literały `Text("...")`) do języka wybranego w aplikacji,
/// a nie do języka systemu. Polski to klucz, więc dla "pl" zwraca go bez zmian.
private final class LangBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if Lang.current == .en, let b = enBundle { return b.localizedString(forKey: key, value: value, table: tableName) }
        return value.flatMap { $0.isEmpty ? nil : $0 } ?? key
    }
}
func installLanguageBundle() { object_setClass(Bundle.main, LangBundle.self) }

/// Tłumaczy polski napis (klucz) na wybrany język. Brak wpisu zostawia polski tekst.
/// Dla literałów w `Text("...")` SwiftUI robi to samo przez środowisko `locale`; `tr` jest dla napisów trzymanych w `String`.
func tr(_ pl: String) -> String {
    guard Lang.current == .en, let b = enBundle else { return pl }
    return b.localizedString(forKey: pl, value: pl, table: nil)
}

/// To samo z podstawieniem argumentów: klucz ma `%@` w miejscu wartości (np. "Znalazłem %@ do usunięcia").
func trf(_ pl: String, _ args: String...) -> String { String(format: tr(pl), arguments: args) }

/// Flagi rysowane wektorowo (te same kształty co `Branding/flags/*.svg`).
struct Flag: View {
    let lang: Lang
    var body: some View {
        Canvas { c, s in
            switch lang {
            case .pl:
                c.fill(Path(CGRect(x: 0, y: 0, width: s.width, height: s.height / 2)), with: .color(.white))
                c.fill(Path(CGRect(x: 0, y: s.height / 2, width: s.width, height: s.height / 2)), with: .color(Color(red: 0.86, green: 0.08, blue: 0.24)))
            case .en:
                let navy = Color(red: 0.004, green: 0.129, blue: 0.412), red = Color(red: 0.784, green: 0.063, blue: 0.18)
                let w = s.width, h = s.height
                c.fill(Path(CGRect(origin: .zero, size: s)), with: .color(navy))
                var d = Path(); d.move(to: .zero); d.addLine(to: CGPoint(x: w, y: h)); d.move(to: CGPoint(x: w, y: 0)); d.addLine(to: CGPoint(x: 0, y: h))
                c.stroke(d, with: .color(.white), lineWidth: h * 0.2)
                c.stroke(d, with: .color(red), lineWidth: h * 0.075)
                var p = Path(); p.move(to: CGPoint(x: w / 2, y: 0)); p.addLine(to: CGPoint(x: w / 2, y: h)); p.move(to: CGPoint(x: 0, y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2))
                c.stroke(p, with: .color(.white), lineWidth: h * 0.325)
                c.stroke(p, with: .color(red), lineWidth: h * 0.2)
            }
        }
        .frame(width: 24, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.black.opacity(0.18)))
    }
}

/// Lista wyboru języka: przycisk z flagą i nazwą, po kliknięciu okienko z opcjami.
struct LanguageSelect: View {
    @Binding var lang: String
    @State private var open = false
    private var current: Lang { Lang(rawValue: lang) ?? .pl }
    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 10) {
                Flag(lang: current)
                Text(current.name)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 12).frame(width: 190, height: 34)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Język")).accessibilityValue(current.name)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 2) {
                ForEach(Lang.allCases) { l in
                    Button { lang = l.rawValue; open = false } label: {
                        HStack(spacing: 10) {
                            Flag(lang: l)
                            Text(l.name)
                            Spacer(minLength: 8)
                            if l == current { Image(systemName: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent) }
                        }
                        .padding(.horizontal, 10).frame(width: 190, height: 32)
                        .background(l == current ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6).background(Theme.panel)
        }
    }
}
