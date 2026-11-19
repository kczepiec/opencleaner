import CleanKit
import SwiftUI

/// Pulpit w stylu makiety OpenCleaner: pierścień zajętości z wolnym miejscem, duży przycisk i cztery kafle.
struct DashboardView: View {
    let model: Model
    let mole: MoleModel
    let tips: TipsModel
    let open: (Area, String?) -> Void
    @State private var showDetails = false
    @State private var flow: Flow = .idle
    @State private var confirm = false
    @Environment(\.czystoMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    /// Czyszczenie na miejscu: podgląd, potwierdzenie, sprzątanie, wynik. Mole kasuje na stałe, więc zawsze jest potwierdzenie.
    enum Flow: Hashable { case idle, scanning, review(Int64), nothing, cleaning, done(Int64), failed(String) }
    private var busy: Bool { flow == .scanning || flow == .cleaning }

    private var scanning: Bool { model.phase != .ready || !model.reposReady }
    private var reposAll: Int64 { model.bytes(model.items.filter { $0.category == .repos }) }
    private var reclaim: Int64 { mole.total("clean") + model.bytes(model.rows(.repos).filter { model.selected.contains($0.url) }) }
    private var swapFraction: Double? {
        guard let s = mole.status, s.swapTotal > 0 else { return nil }
        return Double(s.swapUsed) / Double(s.swapTotal)
    }
    private var headline: String {
        switch flow {
        case .scanning: return "Szukam śmieci, nic jeszcze nie usuwam…"
        case .review(let b): return "Znalazłem \(Model.size(b)) do usunięcia. Mole usuwa na stałe, bez Kosza."
        case .nothing: return "Nie ma tu nic do wyczyszczenia"
        case .cleaning: return "Sprzątam…"
        case .done(let b): return "Gotowe, usunięto około \(Model.size(b))"
        case .failed(let m): return m
        case .idle: break
        }
        if scanning { return "Rozglądam się po dysku…" }
        if let v = model.volume, Double(v.available) / Double(max(v.total, 1)) < 0.1 { return "Dysk jest prawie pełny" }
        return reclaim > 50_000_000 ? "Mogę posprzątać \(Model.size(reclaim))" : "Mac jest w dobrej formie"
    }

    var body: some View {
        ScrollView {
            if let v = model.volume {
                VStack(spacing: 34) {
                    gauge(v)
                    startButton
                    Text(headline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: 440, minHeight: 40, alignment: .top)
                        .contentTransition(.opacity).animation(Theme.ease, value: headline)
                        .padding(.top, -14)
                    cards
                    tipsStrip
                    details(v)
                }
                .padding(.horizontal, 36).padding(.vertical, 34).frame(maxWidth: 940).frame(maxWidth: .infinity)
                .background(alignment: .top) {
                    RadialGradient(colors: [Theme.accent.opacity(0.11), .clear], center: .center, startRadius: 0, endRadius: 320)
                        .frame(width: 680, height: 680).offset(y: -90).allowsHitTesting(false)
                }
            } else {
                DashboardSkeleton()
            }
        }
        .scrollIndicators(.hidden)
        .task { if mole.status == nil, mole.engine == .ready { await mole.refreshStatus() } }
    }

    // MARK: pierścień

    private func gauge(_ v: Volume) -> some View {
        let used = Double(v.used) / Double(max(v.total, 1))
        let parts = Model.size(v.available).split(separator: " ").map(String.init)
        return ZStack {
            Circle().stroke(Theme.track, lineWidth: 14)
            Circle().trim(from: 0, to: used)
                .stroke(AngularGradient(colors: [Theme.accentLight, Theme.accent, Color(hex: 0x3F6FE0)], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * used)),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.accent.opacity(0.55), radius: 12)
                .animation(Theme.ease, value: used)
            if busy { SweepRing(sparkles: flow == .cleaning).transition(.opacity) }
            if isDone { BurstRing().id(flow) }
            VStack(spacing: 4) {
                Mascot(size: 34, mood: busy || scanning ? .busy : (isDone || reclaim > 50_000_000 ? .happy : .content))
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(parts.first ?? "").font(.system(size: 56, weight: .bold)).monospacedDigit()
                    Text(parts.dropFirst().first ?? "").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
                Text(busy ? (mole.runs["clean"]?.line.isEmpty == false ? mole.runs["clean"]!.line : (flow == .scanning ? "Skanuję…" : "Usuwam pliki…")) : "wolne z \(Model.size(v.total))")
                    .foregroundStyle(Theme.secondary).lineLimit(1).frame(maxWidth: 200).contentTransition(.opacity)
            }
        }
        .animation(Theme.ease, value: busy)
        .frame(width: 300, height: 300).padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wolne \(Model.size(v.available)) z \(Model.size(v.total)), zajęte \(Int((used * 100).rounded())) procent")
    }

    private var isDone: Bool { if case .done = flow { return true }; return false }

    private var startButton: some View {
        VStack(spacing: 10) {
            Button(action: tapStart) {
                HStack(spacing: 10) {
                    Image(systemName: buttonSymbol)
                    Text(buttonTitle).font(.system(size: 18, weight: .semibold)).contentTransition(.opacity)
                }
                .foregroundStyle(.white).frame(width: 380, height: 54)
                .background(LinearGradient(colors: [Color(hex: 0x6BA2FA), Color(hex: 0x4B83F0)], startPoint: .leading, endPoint: .trailing), in: Capsule())
                .opacity(busy ? 0.7 : 1)
                .shadow(color: Theme.accent.opacity(0.38), radius: 16, y: 6)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain).disabled(busy || mole.engine != .ready)
            if case .review = flow {
                Button("Anuluj") { withAnimation(Theme.ease) { flow = .idle } }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
            }
        }
        .animation(Theme.ease, value: flow)
        .confirmationDialog("Wyczyścić teraz?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Wyczyść", role: .destructive) { Task { await runClean() } }
            Button("Anuluj", role: .cancel) {}
        } message: { Text("Mole usuwa pliki na stałe, bez Kosza.") }
    }

    private var buttonSymbol: String {
        switch flow {
        case .idle, .nothing, .failed: "wand.and.stars"
        case .scanning, .cleaning: "sparkles"
        case .review: "trash"
        case .done: "checkmark"
        }
    }

    private var buttonTitle: String {
        switch flow {
        case .idle: "Rozpocznij czyszczenie"
        case .scanning: "Szukam…"
        case .review(let b): "Wyczyść \(Model.size(b))"
        case .nothing, .failed: "Sprawdź jeszcze raz"
        case .cleaning: "Czyszczę…"
        case .done: "Gotowe"
        }
    }

    private func tapStart() {
        switch flow {
        case .review: confirm = true
        case .done: withAnimation(Theme.ease) { flow = .idle }
        default: Task { await runPreview() }
        }
    }

    private func runPreview() async {
        withAnimation(Theme.ease) { flow = .scanning }
        await mole.preview("clean")
        let r = mole.runs["clean"]
        withAnimation(Theme.ease) {
            if let f = r?.failed { flow = .failed(f) }
            else if mole.total("clean") > 0 { flow = .review(mole.total("clean")) }
            else { flow = .nothing }
        }
    }

    private func runClean() async {
        let b = mole.total("clean")
        withAnimation(Theme.ease) { flow = .cleaning }
        await mole.apply("clean")
        if let v = Volume.at(FileManager.default.homeDirectoryForCurrentUser) { model.volume = v }
        withAnimation(Theme.ease) { flow = .done(b) }
    }

    // MARK: kafle

    private var cards: some View {
        HStack(alignment: .top, spacing: 18) {
            StatCard(symbol: "trash", value: mole.runs["clean"]?.preview == nil ? "Podgląd" : Model.size(mole.total("clean")),
                     label: "Śmieci systemowe") { open(.cleaning, nil) }
            StatCard(symbol: "arrow.triangle.branch", value: model.reposReady ? Model.size(reposAll) : nil,
                     label: "Zależności w repozytoriach") { open(.analysis, "repos") }
            StatCard(symbol: "shippingbox", value: model.largeReady ? "\(model.large.count)" : nil,
                     label: "Duże pliki (od \(UserDefaults.standard.object(forKey: "set.largeMB") as? Int ?? 100) MB)") { open(.analysis, "large") }
            StatCard(symbol: "memorychip", value: swapFraction.map { "\(Int(($0 * 100).rounded()))%" }, label: "Swap",
                     bar: swapFraction) { open(.status, nil) }
        }
    }

    /// Pasek z poradami: ile da się odzyskać z cache narzędzi i Dockera, i przejście do widoku Porady.
    private var tipsStrip: some View {
        Button { open(.analysis, "tips") } label: {
            HStack(spacing: 14) {
                Image(systemName: "lightbulb").font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.accentLight)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Porady, jak odzyskać miejsce").font(.headline)
                    Text(tips.loaded ? (tips.total > 0 ? "Cache narzędzi i Docker: do \(Model.size(tips.total)). Nieużywane aplikacje: \(tips.apps.count)."
                                                       : "Cache narzędzi jest czysty. Nieużywane aplikacje: \(tips.apps.count).") : "Szukam…")
                        .font(.callout).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(20).cardStyle(radius: 18).contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func details(_ v: Volume) -> some View {
        DisclosureGroup(isExpanded: $showDetails) {
            storage(v).padding(.top, 18)
        } label: {
            HStack {
                Text("Podział zajętego miejsca").font(.headline)
                Spacer()
                Text("\(Model.size(v.used)) z \(Model.size(v.total))").foregroundStyle(Theme.secondary).monospacedDigit()
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Theme.ease) { showDetails.toggle() } }
        }
        .padding(22).cardStyle(radius: 18)
    }

    private func storage(_ v: Volume) -> some View {
        let used = model.slices.filter { $0.kind != .free }
        return VStack(alignment: .leading, spacing: 14) {
            StorageBar(slices: model.slices, total: v.total).frame(height: 14)
                .accessibilityLabel("Zajęte \(Model.size(v.used)) z \(Model.size(v.total))")
            if !model.diskReady {
                SkeletonScope {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 18)], spacing: 10) {
                        ForEach(0..<6, id: \.self) { _ in HStack(spacing: 8) { Bone(width: 9, height: 9, radius: 5); Bone(width: 110, height: 11); Spacer(); Bone(width: 50, height: 11) } }
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 18, alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(used) { s in
                        let isSystem = s.kind == .system
                        let label = HStack(spacing: 8) {
                            Circle().fill(s.kind.color).frame(width: 9, height: 9)
                            Text(s.kind.rawValue).lineLimit(1)
                            if isSystem { Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary) }
                            Spacer(minLength: 4)
                            Text(Model.size(s.bytes)).foregroundStyle(Theme.secondary).monospacedDigit()
                        }
                        .font(.callout).contentShape(Rectangle())
                        if isSystem {
                            Button { open(.analysis, "system") } label: { label }.buttonStyle(.plain)
                                .help("Zobacz, z czego składa się System i inne").accessibilityElement(children: .combine)
                        } else {
                            label.accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}

/// Kafel z makiety: ikona, wartość, podpis i strzałka; opcjonalnie pasek postępu. Brak wartości to szkielet.
struct StatCard: View {
    let symbol: String
    let value: String?
    let label: String
    var bar: Double? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                if let value { Text(value).font(.system(size: 24, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6) }
                else { InlineBone(width: 84, height: 24) }
                Text(label).font(.callout).foregroundStyle(Theme.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let bar {
                    Capsule().fill(Theme.track).frame(height: 5)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in Capsule().fill(Theme.accentLight).frame(width: g.size.width * min(max(bar, 0), 1)) }
                        }
                }
            }
            .padding(20).frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
            .cardStyle(radius: 18, fill: hover ? Theme.raised : Theme.card)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Theme.quick, value: hover)
        .accessibilityElement(children: .combine)
    }
}

/// Pasek zajętości: segmenty kategorii na torze; wolne miejsce to puste miejsce toru.
struct StorageBar: View {
    let slices: [DiskSlice]
    let total: Int64
    var body: some View {
        GeometryReader { geo in
            let used = slices.filter { $0.kind != .free }
            let usable = max(geo.size.width - CGFloat(max(used.count - 1, 0)) * 2, 0)
            ZStack(alignment: .leading) {
                Theme.ghost
                HStack(spacing: 2) {
                    ForEach(used) { s in
                        Rectangle().fill(s.kind.color).frame(width: usable * CGFloat(Double(s.bytes) / Double(max(total, 1))))
                    }
                }
            }.clipShape(Capsule())
        }
        .animation(Theme.ease, value: slices)
    }
}

/// Animacja pracy wokół pierścienia: oddychająca poświata, dwie komety w przeciwnych kierunkach,
/// a przy czyszczeniu iskry z lekkim śladem, wciągane do środka.
struct SweepRing: View {
    let sparkles: Bool
    @Environment(\.czystoMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    private func comet(_ width: CGFloat, _ opacity: Double) -> some View {
        Circle().trim(from: 0, to: 0.3)
            .stroke(AngularGradient(colors: [.clear, Theme.accentLight.opacity(opacity)], center: .center, startAngle: .degrees(0), endAngle: .degrees(108)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round))
            .shadow(color: Theme.accent.opacity(0.7 * opacity), radius: 14)
    }

    var body: some View {
        TimelineView(.animation(paused: !motion || systemReduce)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let breath = 0.5 + 0.5 * sin(t * 2.2)
            ZStack {
                Circle().fill(RadialGradient(colors: [Theme.accent.opacity(0.10 + 0.14 * breath), .clear], center: .center, startRadius: 40, endRadius: 170))
                    .scaleEffect(1.08 + 0.06 * breath)
                comet(14, 1).rotationEffect(.degrees((t * 230).truncatingRemainder(dividingBy: 360) - 90))
                comet(7, 0.55).scaleEffect(0.92).rotationEffect(.degrees(-(t * 150).truncatingRemainder(dividingBy: 360) - 90))
                if sparkles {
                    ForEach(0..<14, id: \.self) { i in
                        let phase = ((t * 0.5) + Double(i) / 14).truncatingRemainder(dividingBy: 1)
                        let ang = Double(i) * (360.0 / 14) + t * 36
                        ForEach(0..<3, id: \.self) { k in
                            let ph = max(phase - Double(k) * 0.035, 0)
                            let r = 150 * pow(1 - ph, 1.4) + 22
                            Image(systemName: "sparkle").font(.system(size: (11 + 6 * CGFloat(i % 3)) * (1 - CGFloat(k) * 0.28)))
                                .foregroundStyle(Theme.accentLight)
                                .opacity(sin(ph * .pi) * (1 - Double(k) * 0.35))
                                .offset(x: r * cos(ang * .pi / 180), y: r * sin(ang * .pi / 180))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Jednorazowy błysk po zakończeniu: pierścień rozchodzi się i gaśnie.
struct BurstRing: View {
    @State private var go = false
    var body: some View {
        Circle().stroke(Theme.accentLight, lineWidth: 3)
            .scaleEffect(go ? 1.32 : 0.96).opacity(go ? 0 : 0.85)
            .onAppear { withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.1)) { go = true } }
            .allowsHitTesting(false)
    }
}
