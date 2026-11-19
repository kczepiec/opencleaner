import Foundation

/// Odtwarzalne zależności i artefakty buildów w repozytoriach git, które dawno nie były używane.
/// Bezpieczniki: folder musi mieć znaną nazwę, obok niego musi leżeć plik projektu, a git musi go ignorować
/// (czyli nie jest w historii ani w śledzonych plikach).
public enum Repos {
    static let python = ["pyproject.toml", "requirements.txt", "setup.py", "Pipfile"]
    static let kinds: [String: [String]] = [
        "node_modules": ["package.json"],
        "target": ["Cargo.toml", "pom.xml"],
        ".venv": python, "venv": python,
        ".next": ["package.json"], ".nuxt": ["package.json"],
        "dist": ["package.json"],
        "build": ["package.json", "build.gradle", "build.gradle.kts", "pom.xml", "CMakeLists.txt"],
        "Pods": ["Podfile"],
        ".build": ["Package.swift"],
        ".gradle": ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
        ".tox": ["tox.ini", "pyproject.toml"],
    ]
    static let skipDirs: Set<String> = ["Library", ".Trash", "Applications", "node_modules"]

    struct Found { let artifact: URL; let repo: URL }

    /// Foldery najwyższego poziomu do przeszukania. Każdy skanuje się osobno, bo macOS potrafi zatrzymać odczyt
    /// jednego z nich (np. Pulpit w iCloud) do czasu decyzji użytkownika, a reszta nie powinna na to czekać.
    public static func roots(home: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil, options: [])) ?? []
        return entries.filter { e in
            let n = e.lastPathComponent
            var isDir: ObjCBool = false
            return !n.hasPrefix(".") && !skipDirs.contains(n) && !Scanner.isOffLimits(e)
                && FileManager.default.fileExists(atPath: e.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    /// Szuka repozytoriów w katalogu domowym (do `maxDepth` poziomów, bez ukrytych folderów i Biblioteki).
    public static func scan(home: URL, now: Date = .now, maxDepth: Int = 6) async -> [Item] {
        var all: [Item] = []
        for root in roots(home: home) { all += await scan(root: root, now: now, maxDepth: maxDepth) }
        return all.sorted { $0.bytes > $1.bytes }
    }

    /// Szuka repozytoriów w jednym folderze (poziom 1 licząc od katalogu domowego).
    public static func scan(root: URL, now: Date = .now, maxDepth: Int = 6) async -> [Item] {
        var found: [Found] = []
        walk(root, repo: nil, depth: 1, maxDepth: maxDepth, out: &found)
        let byRepo = Dictionary(grouping: found, by: \.repo)
        var items: [Item] = []
        await withTaskGroup(of: Item?.self) { group in
            for (repo, list) in byRepo {
                let idle = idleDays(repo: repo, now: now)
                for f in list {
                    group.addTask {
                        guard isIgnored(f.artifact, repo: repo) else { return nil }
                        let b = Scanner.size(of: f.artifact)
                        guard b > 0 else { return nil }
                        return Item(url: f.artifact, category: .repos, bytes: b, preselected: idle >= 60,
                                    title: f.artifact.lastPathComponent, repo: repo, idleDays: idle)
                    }
                }
            }
            for await i in group { if let i { items.append(i) } }
        }
        return items.sorted { $0.bytes > $1.bytes }
    }

    static func walk(_ dir: URL, repo: URL?, depth: Int, maxDepth: Int, out: inout [Found]) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) else { return }
        let names = Set(entries.map(\.lastPathComponent))
        let current = names.contains(".git") ? dir : repo
        for e in entries {
            autoreleasepool {
                let name = e.lastPathComponent
                // Wykluczenie po nazwie idzie PIERWSZE: odczyt właściwości paczki (isPackage) już wywołuje okno zgody macOS.
                guard name != ".git", !Scanner.isOffLimits(e),
                      let v = try? e.resourceValues(forKeys: Set(keys)), v.isDirectory == true, v.isSymbolicLink != true, v.isPackage != true else { return }
                if let root = current, let manifests = kinds[name], manifests.contains(where: names.contains) {
                    out.append(Found(artifact: e, repo: root)); return
                }
                if depth >= maxDepth || name.hasPrefix(".") || skipDirs.contains(name) { return }
                walk(e, repo: current, depth: depth + 1, maxDepth: maxDepth, out: &out)
            }
        }
    }

    /// Dni od ostatniej aktywności w git (najnowsza zmiana HEAD, indeksu albo reflogu).
    static func idleDays(repo: URL, now: Date) -> Int {
        let git = repo.appending(path: ".git")
        let times = ["HEAD", "index", "logs/HEAD", "ORIG_HEAD"].compactMap {
            (try? FileManager.default.attributesOfItem(atPath: git.appending(path: $0).path))?[.modificationDate] as? Date
        }
        guard let last = times.max() else { return 0 }
        return max(0, Int(now.timeIntervalSince(last) / 86_400))
    }

    static func isIgnored(_ artifact: URL, repo: URL) -> Bool {
        let rel = String(artifact.standardizedFileURL.path.dropFirst(repo.standardizedFileURL.path.count + 1))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo.path, "check-ignore", "-q", "--", rel]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
