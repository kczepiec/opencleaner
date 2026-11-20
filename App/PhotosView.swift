import CleanKit
import Photos
import SwiftUI

extension PhotoSort.Category {
    var title: String {
        switch self {
        case .screenshots: "Zrzuty ekranu"; case .screenRecordings: "Nagrania ekranu"; case .social: "TikTok i pobrane wideo"
        case .messengers: "Z komunikatorów"; case .web: "Z internetu (prawdopodobne)"; case .gifs: "GIF-y"; case .largeVideos: "Duże wideo"; case .duplicates: "Duplikaty"; case .all: "Wszystkie"
        }
    }
    var symbol: String {
        switch self {
        case .screenshots: "camera.viewfinder"; case .screenRecordings: "record.circle"; case .social: "play.rectangle"
        case .messengers: "bubble.left.and.bubble.right"; case .web: "globe"; case .gifs: "sparkles.rectangle.stack"; case .largeVideos: "film.stack"; case .duplicates: "square.on.square"; case .all: "photo.on.rectangle.angled"
        }
    }
    var hint: String {
        switch self {
        case .screenshots: "Zrzuty ekranu zapisane w bibliotece."
        case .screenRecordings: "Nagrania ekranu zapisane w bibliotece."
        case .social: "Krótkie pionowe wideo i pliki z nazwą TikToka, Instagrama lub Reels, zapisane z internetu."
        case .messengers: "Zdjęcia i wideo zapisane z WhatsApp, Telegramu, Messengera, Signala lub Vibera."
        case .web: "Obrazy o nazwach z internetu (FB_IMG, download, received) i pionowe MP4 bez nazwy aparatu. Mniej pewne niż reszta: sprawdź przed usunięciem."
        case .largeVideos: "Wideo większe niż 100 MB, od największych."
        case .all: "Cała biblioteka, żeby zaznaczać dowolne pliki. Najechanie pokazuje nazwę oryginalnego pliku."
        case .gifs: "Animowane obrazy (GIF-y)."
        case .duplicates: "Te same wymiary, czas utworzenia i rozmiar pliku. Najstarsza kopia w zestawie zostaje."
        }
    }
}

/// Miniatura zasobu z biblioteki Zdjęć. Pobierana przez PhotoKit w małym rozmiarze, bez ściągania z iCloud.
struct PhotoThumb: View {
    let asset: PHAsset?
    var side: CGFloat = 320
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Theme.field
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "photo").foregroundStyle(Theme.secondary.opacity(0.5)) }
        }
        .clipped()
        .task(id: asset?.localIdentifier) {
            guard let asset else { return }
            image = await withCheckedContinuation { c in
                let o = PHImageRequestOptions()
                o.deliveryMode = .highQualityFormat; o.resizeMode = .fast; o.isNetworkAccessAllowed = false
                var done = false
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, options: o) { img, _ in
                    guard !done else { return }; done = true; c.resume(returning: img)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct PhotosView: View {
    let model: PhotosModel
    @State private var confirm = false
    private let columns = [GridItem(.adaptive(minimum: 124, maximum: 170), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Porządek w zdjęciach", subtitle: subtitle) {
                if model.state == .ready {
                    Button(tr("Odśwież")) { Task { await model.load() } }.disabled(model.deleting)
                }
            }
            Divider()
            switch model.state {
            case .idle: ScrollView { PhotoGridSkeleton() }
            case .needsAccess: access(denied: false)
            case .denied: access(denied: true)
            case .loading: loading
            case .ready: content
            }
        }
        .task { await model.start() }
        .confirmationDialog(trf("Usunąć %@ z biblioteki Zdjęć?", "\(model.selection.count)"), isPresented: $confirm, titleVisibility: .visible) {
            Button(tr("Przenieś do Ostatnio usuniętych"), role: .destructive) { Task { await model.delete(model.selection) } }
            Button(tr("Anuluj"), role: .cancel) {}
        } message: { Text("Zasoby trafią do Ostatnio usuniętych w aplikacji Zdjęcia i zostaną tam 30 dni. macOS poprosi jeszcze o potwierdzenie.") }
    }

    private var subtitle: String {
        switch model.state {
        case .ready: trf("Zasobów w bibliotece: %@", "\(model.total)")
        case .loading: tr("Czytam bibliotekę…")
        default: tr("Zrzuty ekranu, nagrania, TikToki i duplikaty")
        }
    }

    // MARK: dostęp i ładowanie

    private func access(denied: Bool) -> some View {
        VStack(spacing: 14) {
            Mascot(size: 76, mood: .content)
            Text(tr(denied ? "Brak dostępu do Zdjęć" : "OpenCleaner potrzebuje dostępu do Zdjęć")).font(.title3.weight(.semibold))
            Text(tr(denied ? "Włącz dostęp do Zdjęć dla OpenCleaner w Ustawieniach systemowych, Prywatność i ochrona, Zdjęcia."
                           : "Biblioteka jest czytana przez system, nie przez pliki. Nic nie jest usuwane bez Twojego wyboru, a usunięte zasoby trafiają do Ostatnio usuniętych na 30 dni."))
                .foregroundStyle(Theme.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            if denied {
                Button(tr("Otwórz Ustawienia systemowe")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Button(tr("Zezwól na dostęp")) { Task { await model.requestAccess() } }.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    private var loading: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(trf("Przeglądam bibliotekę: %@ z %@", "\(model.scanned)", "\(model.total)")).foregroundStyle(Theme.secondary).monospacedDigit()
                Spacer()
            }.padding(.horizontal, 24).padding(.vertical, 14)
            ScrollView { PhotoGridSkeleton() }.scrollIndicators(.hidden)
        }
    }

    // MARK: zawartość

    private var content: some View {
        VStack(spacing: 0) {
            if model.limited {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                    Text("Masz ograniczony dostęp: widzę tylko zdjęcia wybrane w ustawieniach systemowych, więc lista jest niepełna.").font(.callout)
                    Spacer(minLength: 8)
                    Button(tr("Zmień dostęp")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!) }
                }.padding(12).cardStyle(radius: 12, fill: Theme.raised).padding(.horizontal, 24).padding(.top, 12)
            }
            chips
            if let m = model.message {
                Text(m).font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 12, fill: Theme.raised).padding(.horizontal, 24).padding(.bottom, 8)
            }
            hintRow
            if pending(model.category) {
                VStack(spacing: 12) { ProgressView(); Text(trf("Sprawdzam nazwy i rozmiary plików: %@ z %@", "\(model.detailsDone)", "\(model.total)")).foregroundStyle(Theme.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.count(model.category) == 0 {
                EmptyState(title: "Nic tu nie ma", text: "W tej kategorii nie znalazłem żadnych zasobów.", mood: .happy)
            } else {
                ScrollView { model.category == .duplicates ? AnyView(duplicates) : AnyView(grid) }.scrollIndicators(.hidden)
                bottomBar
            }
        }
    }

    /// Liczby tych kategorii znamy dopiero po przejrzeniu nazw i rozmiarów plików.
    private func pending(_ c: PhotoSort.Category) -> Bool { !model.sizesReady && [.social, .messengers, .web, .largeVideos, .duplicates].contains(c) }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(PhotoSort.Category.allCases, id: \.self) { c in
                    let on = model.category == c
                    Button { withAnimation(Theme.quick) { model.category = c; model.selection = c == .duplicates ? defaultDupSelection : [] } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: c.symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(on ? Theme.accent : Theme.secondary)
                                Text(tr(c.title)).font(.callout.weight(.medium)).lineLimit(1)
                            }
                            HStack(spacing: 6) {
                                Text(pending(c) ? "…" : "\(model.count(c))").font(.title3.weight(.semibold)).monospacedDigit()
                                if !pending(c) { Text(Model.size(model.bytes(c))).font(.caption).foregroundStyle(Theme.secondary).monospacedDigit() }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10).frame(minWidth: 150, alignment: .leading)
                        .background(on ? Theme.raised : Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Theme.accent.opacity(0.8) : Theme.border.opacity(0.7), lineWidth: on ? 1.5 : 1))
                    }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                }
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }.scrollIndicators(.hidden)
    }

    private var hintRow: some View {
        HStack(spacing: 12) {
            Text(tr(model.category.hint)).font(.callout).foregroundStyle(Theme.secondary).lineLimit(2)
            Spacer(minLength: 12)
            Picker("", selection: Binding(get: { model.sortBySize }, set: { model.sortBySize = $0 })) {
                Text("Najnowsze").tag(false); Text("Największe").tag(true)
            }.labelsHidden().pickerStyle(.segmented).frame(width: 170).disabled(model.category == .duplicates || model.category == .largeVideos || (!model.sizesReady))
            if model.category == .all {
                Button(tr("Odznacz")) { model.selection = [] }.disabled(model.selection.isEmpty)
            } else if model.category != .duplicates {
                Button(tr("Zaznacz wszystko")) { model.selection = Set(model.items(model.category).filter { !$0.isFavorite }.map(\.id)) }
                Button(tr("Odznacz")) { model.selection = [] }.disabled(model.selection.isEmpty)
            } else {
                Button(tr("Zaznacz wszystkie kopie")) { model.selection = defaultDupSelection }
                Button(tr("Odznacz")) { model.selection = [] }.disabled(model.selection.isEmpty)
            }
        }.padding(.horizontal, 24).padding(.bottom, 10)
    }

    private var defaultDupSelection: Set<String> { Set(model.sets.flatMap { $0.dropFirst().filter { !$0.isFavorite }.map(\.id) }) }

    // MARK: siatka

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(model.items(model.category), id: \.id) { m in cell(m, side: nil) }
        }.padding(.horizontal, 24).padding(.bottom, 20)
    }

    private func cell(_ m: PhotoSort.Meta, side: CGFloat?, keeper: Bool = false) -> some View {
        let on = model.selection.contains(m.id)
        return Button {
            if keeper { return }
            if on { model.selection.remove(m.id) } else { model.selection.insert(m.id) }
        } label: {
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay { PhotoThumb(asset: model.assets[m.id]) }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if keeper {
                        Text(tr("Zostaje")).font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 3).background(Theme.ok, in: Capsule()).padding(7)
                    } else {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).symbolRenderingMode(.palette)
                            .foregroundStyle(on ? .white : .white.opacity(0.85), on ? Theme.accent : .black.opacity(0.35)).padding(7)
                    }
                }
                .overlay(alignment: .bottomTrailing) { badge(m) }
                .overlay(alignment: .topTrailing) { if m.isFavorite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(.white).padding(7).shadow(radius: 2) } }
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.accent : .clear, lineWidth: 3))
                .opacity(keeper ? 0.92 : 1)
        }
        .buttonStyle(.plain)
        .help(([m.filename.isEmpty ? nil : m.filename, m.created.map { $0.formatted(date: .abbreviated, time: .shortened) }, model.sizes[m.id].map { Model.size($0) }].compactMap { $0 }).joined(separator: " · "))
        .accessibilityLabel(m.filename.isEmpty ? tr("Zasób") : m.filename)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func badge(_ m: PhotoSort.Meta) -> some View {
        HStack(spacing: 4) {
            if m.isVideo { Image(systemName: "play.fill").font(.system(size: 8)); Text(duration(m.duration)) }
            else if let s = model.sizes[m.id] { Text(Model.size(s)) }
        }
        .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 3).background(.black.opacity(0.55), in: Capsule()).padding(7)
        .opacity(m.isVideo || model.sizes[m.id] != nil ? 1 : 0)
    }

    private func duration(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

    // MARK: duplikaty

    private var duplicates: some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(model.sets.enumerated()), id: \.offset) { _, set in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if let d = set.first?.created { Text(d, format: .dateTime.day().month(.abbreviated).year().hour().minute()).font(.callout.weight(.medium)) }
                        Spacer()
                        Text(trf("%@ kopii po %@", "\(set.count)", Model.size(model.sizes[set[0].id] ?? 0))).font(.callout).foregroundStyle(Theme.secondary)
                    }
                    HStack(spacing: 10) {
                        ForEach(Array(set.enumerated()), id: \.element.id) { i, m in cell(m, side: 110, keeper: i == 0) }
                        Spacer(minLength: 0)
                    }
                }.padding(14).cardStyle(radius: 16)
            }
        }.padding(.horizontal, 24).padding(.bottom, 20)
    }

    // MARK: pasek usuwania

    private var bottomBar: some View {
        let allCopies = model.sets.contains { s in s.allSatisfy { model.selection.contains($0.id) } }
        return TrashBar(count: model.selection.count, bytes: model.bytes(model.selection),
                        warning: allCopies ? tr("W jednym zestawie zaznaczono wszystkie kopie") : nil,
                        label: tr("Usuń z biblioteki"), summary: trf("Zaznaczono: %@", "\(model.selection.count)")) { confirm = true }
    }
}

/// Szkielet siatki miniatur.
struct PhotoGridSkeleton: View {
    var body: some View {
        SkeletonScope {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 124, maximum: 170), spacing: 10)], spacing: 10) {
                ForEach(0..<18, id: \.self) { _ in Bone(height: 130, radius: 12).frame(maxWidth: .infinity) }
            }.padding(24)
        }
    }
}
