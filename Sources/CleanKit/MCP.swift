import Foundation

/// Konfiguracja serwera MCP: zapisuje ją aplikacja (Ustawienia), czyta serwer przy każdym żądaniu, więc zmiany działają od razu.
public struct MCPConfig: Codable, Equatable, Sendable {
    public var enabled = true
    /// Narzędzia, które zmieniają dysk (czyszczenie, optymalizacja). Domyślnie wyłączone.
    public var allowDestructive = false
    public var disabledTools: [String] = []

    public init() {}

    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/OpenCleaner")
    }
    public static var defaultURL: URL { directory.appending(path: "mcp.json") }

    public static func load(from url: URL = defaultURL) -> MCPConfig {
        guard let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(MCPConfig.self, from: d) else { return MCPConfig() }
        return c
    }

    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}

public struct MCPTool {
    public let name: String
    public let summary: String
    public let schema: [String: Any]
    public let destructive: Bool
    let handler: ([String: Any]) async -> String
}

/// Serwer MCP (JSON-RPC 2.0 po stdio, wiadomości rozdzielone nową linią). Cała logika jest tu, żeby dało się ją testować.
public final class MCPServer {
    public static let version = "1.0.0"
    let configURL: URL
    public private(set) var tools: [MCPTool] = []

    public init(configURL: URL = MCPConfig.defaultURL) {
        self.configURL = configURL
        self.tools = MCPServer.makeTools()
    }

    /// Nazwy i opisy narzędzi do wyświetlenia w Ustawieniach (bez uruchamiania serwera).
    public static var catalog: [(name: String, summary: String, destructive: Bool)] {
        makeTools().map { ($0.name, $0.summary, $0.destructive) }
    }

    func allowed(_ t: MCPTool, _ c: MCPConfig) -> Bool {
        c.enabled && !c.disabledTools.contains(t.name) && (!t.destructive || c.allowDestructive)
    }

    // MARK: protokół

    /// Zwraca odpowiedź (jedna linia JSON) albo nil dla powiadomień.
    public func handle(_ line: String) async -> String? {
        guard let data = line.data(using: .utf8), let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = msg["method"] as? String else { return Self.error(nil, -32700, "Invalid JSON") }
        let id = msg["id"]
        let params = msg["params"] as? [String: Any] ?? [:]
        if id == nil { return nil } // powiadomienie (np. notifications/initialized)
        let config = MCPConfig.load(from: configURL)
        switch method {
        case "initialize":
            return Self.result(id, ["protocolVersion": params["protocolVersion"] as? String ?? "2024-11-05",
                                    "capabilities": ["tools": [String: Any]()],
                                    "serverInfo": ["name": "opencleaner", "version": Self.version]])
        case "ping": return Self.result(id, [String: Any]())
        case "tools/list":
            let list = tools.filter { allowed($0, config) }.map { ["name": $0.name, "description": $0.summary, "inputSchema": $0.schema] as [String: Any] }
            return Self.result(id, ["tools": list])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            guard let tool = tools.first(where: { $0.name == name }) else { return Self.result(id, Self.content("Unknown tool: \(name)", error: true)) }
            guard allowed(tool, config) else {
                let why = !config.enabled ? "The server is disabled in OpenCleaner settings." :
                    (tool.destructive && !config.allowDestructive ? "This tool changes the disk and is disabled. The user can enable it in Settings, Agents (MCP)." : "The tool is disabled in settings.")
                return Self.result(id, Self.content(why, error: true))
            }
            return Self.result(id, Self.content(await tool.handler(args), error: false))
        default: return Self.error(id, -32601, "Nieznana metoda: \(method)")
        }
    }

    static func content(_ text: String, error: Bool) -> [String: Any] { ["content": [["type": "text", "text": text]], "isError": error] }
    static func result(_ id: Any?, _ r: [String: Any]) -> String { encode(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": r]) }
    static func error(_ id: Any?, _ code: Int, _ message: String) -> String {
        encode(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
    }
    static func encode(_ o: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    static func json(_ o: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    // MARK: narzędzia

    static func schema(_ props: [String: [String: Any]] = [:], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": props, "required": required]
    }
    static func size(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static func makeTools() -> [MCPTool] {
        func tool(_ n: String, _ s: String, _ sc: [String: Any] = schema(), destructive: Bool = false, _ h: @escaping ([String: Any]) async -> String) -> MCPTool {
            MCPTool(name: n, summary: s, schema: sc, destructive: destructive, handler: h)
        }
        let noMole = "Mole (mo) is not installed. The user can install it in OpenCleaner (Settings, Mole)."
        return [
            tool("disk_usage", "Used and free space on the system disk (bytes and human readable). Fast, read only.") { _ in
                guard let v = Volume.at(home) else { return "Could not read the disk." }
                return json(["total_bytes": v.total, "used_bytes": v.used, "available_bytes": v.available,
                             "total": size(v.total), "used": size(v.used), "available": size(v.available)])
            },
            tool("memory_status", "Memory, swap, CPU and system health plus the apps using the most memory. Read only.") { _ in
                guard Mole.executable != nil else { return noMole }
                guard let s = Mole.parseStatus(await Mole.mo(["status", "--json"]).text) else { return "Could not read the status." }
                let apps = await SystemInfo.topApps().map { ["name": $0.name, "memory": size($0.bytes), "bytes": $0.bytes] as [String: Any] }
                return json(["health_score": s.health, "health": Mole.plHealth(s.healthMessage), "cpu_percent": Int(s.cpu.rounded()), "cpu_cores": s.cores,
                             "memory_used": size(s.memUsed), "memory_total": size(s.memTotal), "swap_used": size(s.swapUsed), "swap_total": size(s.swapTotal),
                             "swap_used_bytes": s.swapUsed, "swap_total_bytes": s.swapTotal, "uptime": s.uptime, "top_apps": apps])
            },
            tool("clean_preview", "PREVIEW of cleaning (mo clean --dry-run): what Mole would remove and how much space it would recover. Changes nothing. Takes about a minute.") { _ in
                guard Mole.executable != nil else { return noMole }
                let p = Mole.parse(await Mole.mo(["clean", "--dry-run"]).text)
                let groups = p.groups.map { g in ["category": Mole.pl(g.title), "total": size(g.bytes), "items": g.entries.map { ["name": Mole.pl($0.name), "size": $0.bytes.map(size) ?? "do wyczyszczenia"] }] as [String: Any] }
                return json(["total_reclaimable": size(p.bytes), "total_bytes": p.bytes, "categories": groups, "notes": p.notes.map(Mole.plCleanNote), "preview_only": true])
            },
            tool("optimize_preview", "PREVIEW of optimization (mo optimize --dry-run): steps, warnings and a performance diagnosis. Changes nothing.") { _ in
                guard Mole.executable != nil else { return noMole }
                let r = Mole.parseOptimize(await Mole.mo(["optimize", "--dry-run"]).text)
                return json(["to_apply": r.toApply, "unchanged": r.unchanged, "needs_attention": r.attention, "skipped": r.skipped, "findings": r.findings,
                             "steps": r.steps.map { ["step": $0.title, "status": $0.status.rawValue, "notes": $0.notes] as [String: Any] }, "preview_only": true])
            },
            tool("list_apps", "Installed apps with sizes, largest first.", schema(["limit": ["type": "integer", "description": "How many apps to return (default 30)."]])) { a in
                guard Mole.executable != nil else { return noMole }
                let limit = (a["limit"] as? Int) ?? 30
                let apps = Mole.parseApps(await Mole.mo(["uninstall", "--list"]).text).sorted { (Mole.parseSize($0.size) ?? 0) > (Mole.parseSize($1.size) ?? 0) }
                return json(["apps": apps.prefix(limit).map { ["name": $0.name, "size": Mole.parseSize($0.size).map(size) ?? $0.size, "path": $0.path] }])
            },
            tool("uninstall_preview", "PREVIEW of an app uninstall: the list of files that would be removed. Removes nothing.",
                 schema(["app": ["type": "string", "description": "Nazwa aplikacji z list_apps."]], required: ["app"])) { a in
                guard Mole.executable != nil else { return noMole }
                guard let name = a["app"] as? String, !name.isEmpty else { return "Provide the app name (argument app)." }
                guard let plan = Mole.parseUninstallPlan(await Mole.mo(["uninstall", "--dry-run", name]).text).first else { return "Nie znaleziono aplikacji o tej nazwie." }
                return json(["app": plan.name, "size": size(plan.bytes), "last_used": plan.lastUsed, "files": plan.files.map { ["path": $0.path, "size": size($0.bytes)] }, "preview_only": true])
            },
            tool("system_breakdown", "What the space outside the home folder is made of: APFS volumes and Xcode simulators. Read only.") { _ in
                async let parts = SystemInfo.apfs()
                async let rts = SystemInfo.runtimes()
                return json(["parts": await parts.map { ["name": $0.title, "size": size($0.bytes)] }, "simulator_runtimes": await rts.map { $0.name }])
            },
            tool("find_unused_repos", "Dependency folders (node_modules, .venv, target...) in git repositories unchanged for the given number of days. Read only, takes a few seconds.",
                 schema(["days": ["type": "integer", "description": "Minimum days without git activity (default 60)."]])) { a in
                let days = (a["days"] as? Int) ?? 60
                let items = await Repos.scan(home: home).filter { ($0.idleDays ?? 0) >= days }
                return json(["total": size(items.reduce(0) { $0 + $1.bytes }), "items": items.prefix(60).map { ["path": $0.url.path, "repo": $0.repo?.path ?? "", "size": size($0.bytes), "idle_days": $0.idleDays ?? 0] as [String: Any] }])
            },
            tool("large_files", "Largest files in the home folder, including Library (excluding Trash and iCloud). Field kind: cache (safe), appData (careful), other. Read only.",
                 schema(["min_mb": ["type": "integer", "description": "Minimum size in MB (default 100)."], "limit": ["type": "integer", "description": "How many files to return (default 30)."]])) { a in
                let files = Scanner.largeFiles(home: home, minBytes: Int64((a["min_mb"] as? Int) ?? 100) * 1_000_000, limit: (a["limit"] as? Int) ?? 30)
                return json(["files": files.map { ["path": $0.url.path, "size": size($0.bytes), "kind": "\($0.kind)"] }])
            },
            tool("clean_run", "WARNING: deletes permanently. Runs Mole cleaning (mo clean). Requires confirm=true and a prior clean_preview. Disabled by default.",
                 schema(["confirm": ["type": "boolean", "description": "Must be true only after the user explicitly agrees."]], required: ["confirm"]), destructive: true) { a in
                guard a["confirm"] as? Bool == true else { return "Refused: set confirm=true only after the user agrees to the cleaning." }
                guard Mole.executable != nil else { return noMole }
                let r = await Mole.mo(["clean"])
                return json(["exit_status": Int(r.status), "log_tail": r.text.split(whereSeparator: \.isNewline).suffix(8).map(String.init)])
            },
            tool("optimize_run", "WARNING: changes system settings. Runs Mole optimization (mo optimize). Requires confirm=true and a prior optimize_preview. Disabled by default.",
                 schema(["confirm": ["type": "boolean", "description": "Must be true only after the user explicitly agrees."]], required: ["confirm"]), destructive: true) { a in
                guard a["confirm"] as? Bool == true else { return "Refused: set confirm=true only after the user agrees to the optimization." }
                guard Mole.executable != nil else { return noMole }
                let r = await Mole.mo(["optimize"])
                return json(["exit_status": Int(r.status), "log_tail": r.text.split(whereSeparator: \.isNewline).suffix(8).map(String.init)])
            },
        ]
    }
}

/// Sprawdzenie zainstalowanego pliku serwera: wysyła initialize i tools/list po stdio.
public enum MCPSelfTest {
    public static func run(binary: URL) async -> (ok: Bool, tools: [String]) {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = binary
            let inPipe = Pipe(), outPipe = Pipe()
            p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = FileHandle.nullDevice
            let out = Locked(Data())
            outPipe.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; if !d.isEmpty { out.update { $0.append(d) } } }
            p.terminationHandler = { _ in
                outPipe.fileHandleForReading.readabilityHandler = nil
                let lines = String(decoding: out.value, as: UTF8.self).split(whereSeparator: \.isNewline)
                var names: [String] = []
                for l in lines {
                    if let d = String(l).data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                       let r = o["result"] as? [String: Any], let t = r["tools"] as? [[String: Any]] { names = t.compactMap { $0["name"] as? String } }
                }
                cont.resume(returning: (!lines.isEmpty, names))
            }
            do { try p.run() } catch { cont.resume(returning: (false, [])); return }
            let req = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\"}}\n{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}\n"
            inPipe.fileHandleForWriting.write(Data(req.utf8))
            try? inPipe.fileHandleForWriting.close()
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) { if p.isRunning { p.terminate() } }
        }
    }
}
