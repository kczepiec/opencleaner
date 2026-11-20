import Foundation

/// Reguła przypomnienia o sprzątaniu: kiedy wolno wysłać powiadomienie. Samo powiadomienie niczego nie usuwa.
public enum Reminder {
    /// Wysyłamy, gdy minął interwał od ostatniego przypomnienia i jest co odzyskać (domyślnie od 1 GB).
    public static func due(last: Date?, now: Date = Date(), intervalDays: Int, reclaimable: Int64, minBytes: Int64 = 1_000_000_000) -> Bool {
        guard reclaimable >= minBytes else { return false }
        guard let last else { return true }
        return now.timeIntervalSince(last) >= Double(intervalDays) * 86_400
    }
}
