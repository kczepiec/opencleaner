import CleanKit
import SwiftUI

extension SliceKind {
    /// Do odzyskania: ciepłe. Dane użytkownika: chłodne i rozróżnialne. System: szary. Wolne: puste miejsce toru.
    var color: Color {
        switch self {
        case .cache: Color(hex: 0xF0A04B)
        case .developer: Color(hex: 0xE8C25A)
        case .repos: Color(hex: 0xE9735F)
        case .trash: Color(hex: 0xD66A9C)
        case .apps: Color(hex: 0x4C8FEA)
        case .documents: Color(hex: 0x6F7DF0)
        case .downloads: Color(hex: 0x45B5C9)
        case .media: Color(hex: 0x9A7CE8)
        case .library: Color(hex: 0x5C9E8C)
        case .otherHome: Color(hex: 0x7FB06A)
        case .system: Color(hex: 0x6B6E75)
        case .free: .clear
        }
    }
}
