import SwiftUI

/// Szkielet ładowania: kształty z delikatnym przesuwającym się połyskiem (shimmer) zamiast spinnera.
/// Połysk liczy się z zegara (TimelineView), więc nie zostawia animacji w grafie, gdy szkielet znika.
struct SkeletonScope<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.czystoMotion) private var motion

    var body: some View {
        Group {
            if reduce || !motion {
                content.foregroundStyle(Theme.ghost)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                    let p = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.9) / 1.9
                    content.foregroundStyle(Theme.ghost)
                        .overlay {
                            GeometryReader { g in
                                LinearGradient(colors: [.clear, Theme.accentLight.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: g.size.width * 0.45)
                                    .offset(x: g.size.width * (CGFloat(p) * 1.45 - 0.45))
                            }
                            .mask { content.foregroundStyle(.white) }
                        }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ładowanie")
    }
}

/// Pojedynczy blok szkieletu.
struct Bone: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var radius: CGFloat = 6
    var body: some View { RoundedRectangle(cornerRadius: radius, style: .continuous).frame(width: width, height: height) }
}

/// Zamiennik wartości w kaflu, gdy dane jeszcze się liczą.
struct InlineBone: View {
    var width: CGFloat = 90
    var height: CGFloat = 24
    var body: some View { SkeletonScope { Bone(width: width, height: height, radius: 7) }.fixedSize() }
}

/// Wiersze listy z ikoną (panel listy, np. aplikacje).
struct ListSkeleton: View {
    var rows = 9
    var body: some View {
        SkeletonScope {
            VStack(spacing: 2) {
                ForEach(0..<rows, id: \.self) { i in
                    HStack(spacing: 12) {
                        Bone(width: 38, height: 38, radius: 11)
                        VStack(alignment: .leading, spacing: 7) {
                            Bone(width: 80 + CGFloat((i * 41) % 70), height: 12)
                            Bone(width: 44, height: 9)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                }
            }
        }
    }
}

/// Tabela (duże pliki, repozytoria): nagłówek i wiersze z ikoną, nazwą, ścieżką i rozmiarem.
struct TableSkeleton: View {
    var rows = 9
    var body: some View {
        SkeletonScope {
            VStack(spacing: 0) {
                HStack { Bone(width: 64, height: 10); Spacer(); Bone(width: 54, height: 10) }
                    .padding(.horizontal, 22).padding(.vertical, 14)
                ForEach(0..<rows, id: \.self) { i in
                    HStack(spacing: 12) {
                        Bone(width: 22, height: 22, radius: 6)
                        VStack(alignment: .leading, spacing: 7) {
                            Bone(width: 150 + CGFloat((i * 53) % 150), height: 12)
                            Bone(width: 220 + CGFloat((i * 29) % 120), height: 9)
                        }
                        Spacer(minLength: 12)
                        Bone(width: 56, height: 12)
                    }
                    .padding(.horizontal, 22).padding(.vertical, 11)
                }
            }
        }
    }
}

/// Układ pulpitu: pierścień, przycisk i cztery kafle.
struct DashboardSkeleton: View {
    var body: some View {
        SkeletonScope {
            VStack(spacing: 28) {
                Circle().stroke(lineWidth: 14).frame(width: 270, height: 270).padding(.top, 20)
                Capsule().frame(width: 380, height: 54)
                HStack(spacing: 14) { ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 18, style: .continuous).frame(height: 112) } }
                RoundedRectangle(cornerRadius: 18, style: .continuous).frame(height: 58)
            }
            .padding(.horizontal, 30).padding(.vertical, 24).frame(maxWidth: 940)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Plan odinstalowania: trzy liczby i lista plików.
struct PlanSkeleton: View {
    var body: some View {
        SkeletonScope {
            VStack(spacing: 14) {
                HStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 16, style: .continuous).frame(height: 84) } }
                VStack(alignment: .leading, spacing: 16) {
                    Bone(width: 130, height: 14)
                    ForEach(0..<6, id: \.self) { i in
                        HStack(spacing: 12) {
                            Bone(width: 24, height: 24, radius: 6)
                            VStack(alignment: .leading, spacing: 6) { Bone(width: 140 + CGFloat((i * 47) % 130), height: 12); Bone(width: 230, height: 9) }
                            Spacer()
                            Bone(width: 50, height: 12)
                        }
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(22)
        }
    }
}

/// Status: sześć kafli i karta pamięci.
struct StatusSkeleton: View {
    var body: some View {
        SkeletonScope {
            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 12) { ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 14, style: .continuous).frame(height: 128) } }
                }
                RoundedRectangle(cornerRadius: 16, style: .continuous).frame(height: 200)
            }
            .padding(22)
        }
    }
}

/// Widok System: karty z paskami.
struct SystemSkeleton: View {
    var body: some View {
        SkeletonScope {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 18) {
                    Bone(width: 130, height: 14)
                    ForEach(0..<5, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Bone(width: 150 + CGFloat((i * 37) % 80), height: 12); Spacer(); Bone(width: 56, height: 12) }
                            Bone(height: 5, radius: 3)
                            Bone(width: 260, height: 9)
                        }
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous))
                RoundedRectangle(cornerRadius: 16, style: .continuous).frame(height: 120)
                RoundedRectangle(cornerRadius: 16, style: .continuous).frame(height: 150)
            }
            .padding(22)
        }
    }
}
