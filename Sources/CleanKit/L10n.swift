import Foundation

/// Język tekstów z biblioteki. Klucze są po polsku; aplikacja podaje `lookup` (tłumaczenie) i `english`.
/// Teksty z Mole przy `english` zostają w oryginale, bo Mole mówi po angielsku.
public enum L10n {
    public static var english = false
    public static var lookup: (String) -> String = { $0 }
    public static func t(_ key: String, _ args: String...) -> String { String(format: lookup(key), arguments: args) }
}
