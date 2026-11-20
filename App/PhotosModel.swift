import CleanKit
import Photos
import SwiftUI

private struct Loaded: @unchecked Sendable { let metas: [PhotoSort.Meta]; let assets: [String: PHAsset] }
private struct Box<T>: @unchecked Sendable { let value: T }

/// Stan widoku Zdjęcia. Biblioteka jest czytana przez PhotoKit (nigdy przez pliki pakietu), a usunięte zasoby trafiają do
/// "Ostatnio usuniętych" w aplikacji Zdjęcia (30 dni), więc da się je przywrócić.
@MainActor @Observable
final class PhotosModel {
    enum State { case idle, needsAccess, denied, loading, ready }
    var state = State.idle
    var scanned = 0
    var total = 0
    var byCategory: [PhotoSort.Category: [PhotoSort.Meta]] = [:]
    var sets: [[PhotoSort.Meta]] = []
    var sizes: [String: Int64] = [:]
    var sizesReady = false
    var detailsDone = 0
    var selection: Set<String> = []
    var category: PhotoSort.Category = .screenshots
    var message: String?
    var deleting = false
    var limited = false
    private(set) var assets: [String: PHAsset] = [:]
    private var metas: [PhotoSort.Meta] = []

    func start() async {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: if state == .idle || state == .needsAccess || state == .denied { await load() }
        case .notDetermined: state = .needsAccess
        default: state = .denied
        }
    }

    func requestAccess() async {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if s == .authorized || s == .limited { await load() } else { state = .denied }
    }

    func items(_ c: PhotoSort.Category) -> [PhotoSort.Meta] { c == .duplicates ? sets.flatMap { $0 } : byCategory[c] ?? [] }
    func count(_ c: PhotoSort.Category) -> Int { c == .duplicates ? sets.flatMap { $0.dropFirst() }.count : byCategory[c]?.count ?? 0 }
    func bytes(_ ids: some Sequence<String>) -> Int64 { ids.reduce(0) { $0 + (sizes[$1] ?? 0) } }
    func bytes(_ c: PhotoSort.Category) -> Int64 { c == .duplicates ? bytes(sets.flatMap { $0.dropFirst() }.map(\.id)) : bytes((byCategory[c] ?? []).map(\.id)) }

    func load() async {
        limited = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited
        state = .loading; scanned = 0; sizesReady = false; selection = []; message = nil
        let box = await Task.detached(priority: .utility) { [weak self] () -> Loaded in
            let opt = PHFetchOptions()
            opt.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            opt.includeHiddenAssets = true          // album Ukryte też zajmuje miejsce
            opt.includeAllBurstAssets = true        // wszystkie klatki serii, nie tylko reprezentant
            opt.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
            let fetch = PHAsset.fetchAssets(with: opt)
            var out: [PhotoSort.Meta] = [], map: [String: PHAsset] = [:]
            out.reserveCapacity(fetch.count); map.reserveCapacity(fetch.count)
            let n = fetch.count
            fetch.enumerateObjects { a, i, _ in
                let sub = a.mediaSubtypes
                out.append(PhotoSort.Meta(id: a.localIdentifier, filename: (a.value(forKey: "filename") as? String) ?? "", isVideo: a.mediaType == .video,
                                          width: a.pixelWidth, height: a.pixelHeight, duration: a.duration, created: a.creationDate,
                                          isScreenshot: sub.contains(.photoScreenshot), isScreenRecording: sub.contains(.videoScreenRecording),
                                          isAnimated: a.playbackStyle == .imageAnimated, isFavorite: a.isFavorite))
                map[a.localIdentifier] = a
                if i % 3000 == 0 { Task { @MainActor in self?.scanned = i; self?.total = n } }
            }
            return Loaded(metas: out, assets: map)
        }.value
        metas = box.metas; assets = box.assets; total = box.metas.count; scanned = total
        byCategory = [:]
        for m in metas { for c in PhotoSort.categories(m) { byCategory[c, default: []].append(m) } }
        sets = []
        for m in metas { for c in PhotoSort.categories(m) { byCategory[c, default: []].append(m) } }
        state = .ready
        await loadDetails()
    }

    private struct Detail: Sendable { let name: String; let size: Int64; let mpeg4: Bool }

    /// Jeden przebieg po zasobach: prawdziwa nazwa pliku (PhotoKit zwraca w `filename` wewnętrzny UUID), rozmiar i typ pliku.
    /// Dopiero po nim da się rozpoznać TikToki i grafiki z komunikatorów oraz odróżnić duplikaty od zdjęć seryjnych z tej samej sekundy.
    private func loadDetails() async {
        let pick = Box(value: metas.compactMap { assets[$0.id] })
        let result = await Task.detached(priority: .utility) { [weak self] () -> [String: Detail] in
            var out: [String: Detail] = [:]
            out.reserveCapacity(pick.value.count)
            for (i, a) in pick.value.enumerated() {
                let res = PHAssetResource.assetResources(for: a)
                guard let r = res.first(where: { $0.type == .photo || $0.type == .video }) ?? res.first else { continue }
                out[a.localIdentifier] = Detail(name: r.originalFilename, size: (r.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0,
                                                mpeg4: r.uniformTypeIdentifier == "public.mpeg-4")
                if i % 1000 == 0 { Task { @MainActor in self?.detailsDone = i } }
            }
            return out
        }.value
        for i in metas.indices {
            guard let d = result[metas[i].id] else { continue }
            metas[i].filename = d.name; metas[i].isMPEG4 = d.mpeg4
            if d.size > 0 { metas[i].fileSize = d.size; sizes[metas[i].id] = d.size }
        }
        byCategory = [:]
        for m in metas { for c in PhotoSort.categories(m) { byCategory[c, default: []].append(m) } }
        sets = PhotoSort.duplicateSets(metas.filter { $0.fileSize != nil })
        let alive = Set(metas.map(\.id)); selection = selection.filter { alive.contains($0) }
        sizesReady = true
    }

    func delete(_ ids: Set<String>) async {
        let pick = Box(value: ids.compactMap { assets[$0] })
        guard !pick.value.isEmpty else { return }
        deleting = true
        defer { deleting = false }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(pick.value as NSArray) }
            metas.removeAll { ids.contains($0.id) }
            for k in byCategory.keys { byCategory[k]?.removeAll { ids.contains($0.id) } }
            sets = sets.map { $0.filter { !ids.contains($0.id) } }.filter { $0.count > 1 }
            selection.subtract(ids); total = metas.count
            message = trf("Przeniesiono do Ostatnio usuniętych w aplikacji Zdjęcia: %@.", "\(pick.value.count)")
        } catch {
            message = tr("Nic nie usunięto (anulowano w oknie systemowym albo brak uprawnień).")
        }
    }
}
