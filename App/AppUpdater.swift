import AppKit
import CleanKit

/// Aktualizacje z GitHub Releases: sprawdza wydanie, pobiera .zip, podmienia aplikację po zamknięciu i uruchamia ją ponownie.
@MainActor @Observable final class AppUpdater {
    enum State: Equatable { case idle, checking, upToDate, available, installing, failed(String) }
    private(set) var state = State.idle
    private(set) var release: AppRelease?
    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    var available: Bool { state == .available }

    /// `auto` pomija sprawdzenie, jeśli było w ciągu ostatniej doby.
    func check(auto: Bool = false) async {
        let last = UserDefaults.standard.double(forKey: "update.lastCheck")
        if auto, Date().timeIntervalSince1970 - last < 86_400 { return }
        state = .checking
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(AppUpdates.repo)/releases/latest")!, timeoutInterval: 15)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await URLSession.shared.data(for: req)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "update.lastCheck")
            if (resp as? HTTPURLResponse)?.statusCode == 404 { release = nil; state = .upToDate; return }
            if let r = AppUpdates.parseRelease(data), AppUpdates.isNewer(r.version, than: Self.current) { release = r; state = .available }
            else { release = nil; state = .upToDate }
        } catch { state = auto ? .idle : .failed("Nie udało się sprawdzić: \(error.localizedDescription)") }
    }

    func install() async {
        guard let r = release else { return }
        let app = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            state = .failed("Brak uprawnień do zapisu w \(app.deletingLastPathComponent().path)."); return
        }
        state = .installing
        do {
            let (tmp, _) = try await URLSession.shared.download(from: r.zipURL)
            let dir = FileManager.default.temporaryDirectory.appending(path: "opencleaner-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let zip = dir.appending(path: "u.zip"); try FileManager.default.moveItem(at: tmp, to: zip)
            let unzip = Process(); unzip.executableURL = URL(filePath: "/usr/bin/ditto"); unzip.arguments = ["-x", "-k", zip.path, dir.path]
            try unzip.run(); unzip.waitUntilExit()
            let new = dir.appending(path: "OpenCleaner.app")
            guard unzip.terminationStatus == 0, FileManager.default.fileExists(atPath: new.appending(path: "Contents/MacOS").path) else { throw CocoaError(.fileReadCorruptFile) }
            // Osobny proces czeka na wyjście aplikacji, podmienia pakiet i otwiera nowy.
            let sh = Process(); sh.executableURL = URL(filePath: "/bin/sh")
            sh.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; rm -rf \"$2\" && mv \"$3\" \"$2\" && open \"$2\"; rm -rf \"$4\"",
                            "sh", "\(ProcessInfo.processInfo.processIdentifier)", app.path, new.path, dir.path]
            try sh.run()
            NSApp.terminate(nil)
        } catch { state = .failed("Aktualizacja nie powiodła się: \(error.localizedDescription)") }
    }
}
