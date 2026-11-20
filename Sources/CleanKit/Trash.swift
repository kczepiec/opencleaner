import Foundation

/// Przenoszenie do Kosza. Najpierw bezpośrednio; gdy macOS odmawia dostępu (pliki z ograniczeniem `com.apple.macl`, foldery Dokumenty
/// i Pobrane bez zgody dla tej aplikacji), robi to Finder, który ma własne uprawnienia (macOS raz zapyta o zgodę na sterowanie Finderem).
public enum Trash {
    public static func move(_ url: URL) throws {
        do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        catch let e as NSError where e.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(e.code) {
            guard finder(url) else { throw e }
        }
    }

    /// Ścieżka idzie jako argument skryptu (nie jest sklejana z tekstem), więc nazwy pliku nie da się wykorzystać do wstrzyknięcia.
    static func finder(_ url: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "on run argv", "-e", "tell application \"Finder\" to delete (POSIX file (item 1 of argv) as alias)", "-e", "end run", url.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
