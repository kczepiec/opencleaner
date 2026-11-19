import Foundation

/// Symulatory Xcode: środowiska (obrazy dysków z iOS, watchOS...) i urządzenia symulatora. Skan tylko czyta (`xcrun simctl`).
public enum Simulators {
    public struct Runtime: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let bytes: Int64?
        public let deletable: Bool
        public init(id: String, name: String, bytes: Int64?, deletable: Bool) { self.id = id; self.name = name; self.bytes = bytes; self.deletable = deletable }
    }

    public struct Device: Identifiable, Equatable, Sendable {
        public let udid: String
        public let name: String
        /// "iOS 26.0": z klucza środowiska w `simctl list`.
        public let platform: String
        public let booted: Bool
        public let available: Bool
        public let bytes: Int64
        public var id: String { udid }
        public init(udid: String, name: String, platform: String, booted: Bool, available: Bool, bytes: Int64) {
            self.udid = udid; self.name = name; self.platform = platform; self.booted = booted; self.available = available; self.bytes = bytes
        }
    }

    public struct Snapshot: Sendable {
        public var runtimes: [Runtime] = []
        public var devices: [Device] = []
        public var cachesBytes: Int64 = 0
        public init() {}
    }

    private static let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")

    /// Xcode jest zainstalowany, gdy istnieje jakiś `Xcode*.app` (bez tego zakładka się nie pokazuje).
    public static func isAvailable(applications: URL = URL(fileURLWithPath: "/Applications")) -> Bool {
        let apps = (try? FileManager.default.contentsOfDirectory(atPath: applications.path)) ?? []
        return apps.contains { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-5" na "iOS 26.5"; "iOS-27-2-iPhone19-4" na "iOS 27.2".
    public static func platformName(_ key: String) -> String {
        let tail = (key.components(separatedBy: "SimRuntime.").last ?? key).split(separator: ".").last.map(String.init) ?? key
        let parts = tail.split(separator: "-").map(String.init)
        guard let first = parts.first else { return key }
        let nums = parts.dropFirst().prefix { $0.allSatisfy(\.isNumber) }
        return nums.isEmpty ? first : "\(first) \(nums.joined(separator: "."))"
    }

    private static func json(_ text: String) -> [String: Any]? {
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text[a...b].utf8))) as? [String: Any]
    }

    /// `simctl runtime list -j`: nazwa z identyfikatora i wersji, rozmiar tylko gdy go podano.
    public static func parseRuntimes(_ text: String) -> [Runtime] {
        guard let o = json(text) else { return [] }
        return o.compactMap { id, v -> Runtime? in
            guard let d = v as? [String: Any], let rid = d["runtimeIdentifier"] as? String else { return nil }
            let plat = platformName(rid).components(separatedBy: " ").first ?? "Środowisko"
            let version = d["version"] as? String ?? ""
            let build = d["build"] as? String
            let name = ["\(plat) \(version)".trimmingCharacters(in: .whitespaces), build.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
            return Runtime(id: id, name: name, bytes: (d["sizeBytes"] as? NSNumber)?.int64Value, deletable: d["deletable"] as? Bool ?? true)
        }.sorted { $0.name > $1.name }
    }

    /// `simctl list devices -j`.
    public static func parseDevices(_ text: String) -> [Device] {
        guard let o = json(text), let all = o["devices"] as? [String: [[String: Any]]] else { return [] }
        var out: [Device] = []
        for (key, list) in all {
            for d in list {
                guard let udid = d["udid"] as? String, let name = d["name"] as? String else { continue }
                out.append(Device(udid: udid, name: name, platform: platformName(key), booted: (d["state"] as? String) == "Booted",
                                  available: d["isAvailable"] as? Bool ?? true, bytes: (d["dataPathSize"] as? NSNumber)?.int64Value ?? 0))
            }
        }
        return out.sorted { ($0.platform, $0.name) > ($1.platform, $1.name) }
    }

    public static func load() async -> Snapshot {
        async let rt = Mole.run(xcrun, ["simctl", "runtime", "list", "-j"])
        async let dv = Mole.run(xcrun, ["simctl", "list", "devices", "-j"])
        var s = Snapshot()
        let (r, d) = (await rt, await dv)
        s.devices = parseDevices(d.text)
        let raw = json(r.text) ?? [:]
        s.runtimes = parseRuntimes(r.text).map { rt in
            guard rt.bytes == nil, let dict = raw[rt.id] as? [String: Any],
                  let p = dict["parentMountPath"] as? String ?? (dict["path"] as? String) else { return rt }
            let b = Scanner.size(of: URL(fileURLWithPath: p), force: true)
            return Runtime(id: rt.id, name: rt.name, bytes: b > 0 ? b : nil, deletable: rt.deletable)
        }
        let caches = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Developer/CoreSimulator/Caches")
        s.cachesBytes = Scanner.size(of: caches)
        return s
    }

    public static func deleteDevice(_ udid: String) async -> Bool {
        await Mole.run(xcrun, ["simctl", "delete", udid]).status == 0
    }

    /// Urządzenia bez środowiska (po jego usunięciu): Xcode sam by ich już nie uruchomił.
    public static func deleteUnavailable() async -> Bool {
        await Mole.run(xcrun, ["simctl", "delete", "unavailable"]).status == 0
    }
}
