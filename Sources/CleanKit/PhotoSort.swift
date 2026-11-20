import Foundation

/// Porządkowanie biblioteki Zdjęć: czysta logika bez PhotoKit, żeby dało się ją testować.
/// Aplikacja podaje metadane zasobów, a tu powstają kategorie "to nie jest prawdziwe zdjęcie lub wideo" i zestawy duplikatów.
public enum PhotoSort {
    public enum Category: String, CaseIterable, Sendable {
        case screenshots, screenRecordings, social, messengers, gifs, duplicates
    }

    public struct Meta: Equatable, Sendable {
        public let id: String
        /// Oryginalna nazwa pliku (z zasobu), nie wewnętrzny UUID biblioteki.
        public var filename: String
        public let isVideo: Bool
        public let width: Int
        public let height: Int
        public let duration: Double
        public let created: Date?
        public let isScreenshot: Bool
        public let isScreenRecording: Bool
        public let isAnimated: Bool
        public let isFavorite: Bool
        public var fileSize: Int64?
        /// Plik jest kontenerem MP4 (z internetu), a nie MOV z aparatu.
        public var isMPEG4: Bool

        public init(id: String, filename: String, isVideo: Bool, width: Int, height: Int, duration: Double = 0, created: Date? = nil,
                    isScreenshot: Bool = false, isScreenRecording: Bool = false, isAnimated: Bool = false, isFavorite: Bool = false, fileSize: Int64? = nil, isMPEG4: Bool = false) {
            self.id = id; self.filename = filename; self.isVideo = isVideo; self.width = width; self.height = height; self.duration = duration
            self.created = created; self.isScreenshot = isScreenshot; self.isScreenRecording = isScreenRecording; self.isAnimated = isAnimated
            self.isFavorite = isFavorite; self.fileSize = fileSize; self.isMPEG4 = isMPEG4
        }
    }

    /// Nazwy plików, które zostawiają komunikatory przy zapisie do Zdjęć (WhatsApp, Telegram, Messenger, Signal, Viber).
    static func isMessenger(_ name: String) -> Bool {
        let n = name.lowercased()
        if n.contains("whatsapp") || n.contains("telegram") || n.contains("messenger") || n.contains("signal-") || n.contains("viber") { return true }
        return n.range(of: #"^(img|vid|ptt|aud)-\d{8}-wa\d+"#, options: .regularExpression) != nil
    }

    /// Nazwy plików z aparatów i telefonów (IMG_0001.MOV, PXL_..., VID_...): to prawdziwe nagrania, nigdy "z internetu".
    static func isCameraName(_ name: String) -> Bool {
        name.range(of: #"^(img|mvi|mov|pxl|vid|dsc|dji|gopr|gx)[_-]?\d+"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Wideo zapisane z internetu (TikTok i podobne). Rozpoznajemy po nazwie z serwisu albo po MP4 w pionie, nigdy po samym formacie 9:16:
    /// zwykłe filmy z telefonu też są pionowe i krótkie.
    static func isSocialVideo(_ m: Meta) -> Bool {
        guard m.isVideo, !m.isScreenRecording, !isCameraName(m.filename) else { return false }
        let n = m.filename.lowercased()
        if ["tiktok", "ssstik", "snaptik", "musically", "instagram", "snapinsta", "reels", "youtube", "shorts"].contains(where: n.contains) { return true }
        if n.range(of: #"^v[0-9a-z]{25,35}\.mp4$"#, options: .regularExpression) != nil { return true }       // identyfikator z CDN TikToka
        if n.range(of: #"^[0-9a-f]{32}\.(mp4|mov)$"#, options: .regularExpression) != nil { return true }
        if n.range(of: #"^\d{15,20}\.(mp4|mov)$"#, options: .regularExpression) != nil { return true }
        let vertical = m.width > 0 && Double(m.height) / Double(max(m.width, 1)) > 1.7
        return m.isMPEG4 && vertical && m.duration > 0 && m.duration <= 300
    }

    /// Kategorie, do których należy zasób (zasób może być w kilku, np. zrzut ekranu będący duplikatem).
    public static func categories(_ m: Meta) -> [Category] {
        var c: [Category] = []
        if m.isScreenshot { c.append(.screenshots) }
        if m.isScreenRecording { c.append(.screenRecordings) }
        if isSocialVideo(m) { c.append(.social) }
        if isMessenger(m.filename) { c.append(.messengers) }
        if m.isAnimated && !m.isVideo { c.append(.gifs) }
        return c
    }

    /// Zestawy prawdopodobnych duplikatów: ten sam typ, wymiary, czas utworzenia (do sekundy), czas trwania i rozmiar pliku (jeśli znany).
    /// Pierwszy w zestawie to najstarszy w bibliotece i zostaje. Pliki bez daty utworzenia nigdy nie są łączone.
    public static func duplicateSets(_ all: [Meta]) -> [[Meta]] {
        var by: [String: [Meta]] = [:]
        for m in all {
            guard let d = m.created, m.width > 0 else { continue }
            let key = "\(m.isVideo)|\(m.width)x\(m.height)|\(Int(d.timeIntervalSince1970))|\(Int(m.duration.rounded()))|\(m.fileSize.map(String.init) ?? "?")"
            by[key, default: []].append(m)
        }
        return by.values.filter { $0.count > 1 }.map { $0.sorted { ($0.created ?? .distantFuture, $0.id) < ($1.created ?? .distantFuture, $1.id) } }
            .sorted { ($0.first?.created ?? .distantPast) > ($1.first?.created ?? .distantPast) }
    }
}
