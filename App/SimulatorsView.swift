import CleanKit
import Observation
import SwiftUI

/// Stan zakładki Symulatory: środowiska i urządzenia z `simctl`. Skan tylko czyta; usuwanie idzie po potwierdzeniu.
@MainActor @Observable
final class SimModel {
    var snap = Simulators.Snapshot()
    var loaded = false
    var busy: String?
    var message: String?
    let available = Simulators.isAvailable()

    var runtimeBytes: Int64 { snap.runtimes.reduce(0) { $0 + ($1.bytes ?? 0) } }
    var unavailable: [Simulators.Device] { snap.devices.filter { !$0.available } }

    func load() async {
        guard available else { return }
        let s = await Simulators.load()
        withAnimation(Theme.ease) { snap = s; loaded = true }
    }

    func deleteRuntime(_ rt: Simulators.Runtime) async {
        busy = rt.id; message = nil
        let ok = await SystemInfo.deleteRuntime(rt.id)
        message = ok ? "Usunięto \(rt.name)." : "Nie udało się usunąć \(rt.name). Spróbuj w Xcode: Settings, Components."
        busy = nil; await load()
    }

    func deleteDevice(_ d: Simulators.Device) async {
        busy = d.id; message = nil
        let ok = await Simulators.deleteDevice(d.udid)
        message = ok ? nil : "Nie udało się usunąć \(d.name)."
        busy = nil; await load()
    }

    func deleteUnavailable() async {
        busy = "unavailable"; message = nil
        let n = unavailable.count
        let ok = await Simulators.deleteUnavailable()
        message = ok ? "Usunięto \(n) niedostępnych symulatorów." : "Nie udało się usunąć niedostępnych symulatorów."
        busy = nil; await load()
    }
}

struct SimulatorsView: View {
    let sim: SimModel
    @State private var confirmRuntime: Simulators.Runtime?
    @State private var confirmUnavailable = false
    @State private var confirmDevice: Simulators.Device?
    @State private var showAvailable = false

    private var devices: [Simulators.Device] { sim.snap.devices.filter(\.available) }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Symulatory", subtitle: subtitle) {
                Button("Odśwież") { sim.message = nil; Task { await sim.load() } }.disabled(sim.busy != nil)
            }
            Divider()
            if !sim.loaded { ScrollView { ListSkeleton(rows: 6).padding(14) } }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if let m = sim.message { Text(m).font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 12, fill: Theme.raised) }
                        runtimes
                        unavailableSection
                        devicesSection
                    }.padding(22)
                }.scrollIndicators(.hidden)
            }
        }
        .task { await sim.load() }
        .confirmationDialog("Usunąć \(confirmRuntime?.name ?? "")?", isPresented: Binding(get: { confirmRuntime != nil }, set: { if !$0 { confirmRuntime = nil } }), titleVisibility: .visible) {
            Button("Usuń środowisko", role: .destructive) { if let r = confirmRuntime { Task { await sim.deleteRuntime(r) } } }
            Button("Anuluj", role: .cancel) {}
        } message: { Text("Zwolni około \(confirmRuntime?.bytes.map(Model.size) ?? "kilka GB"). Xcode pobierze to środowisko ponownie, gdy będzie potrzebne do buildów lub symulatora.") }
        .confirmationDialog("Usunąć \(sim.unavailable.count) niedostępnych symulatorów?", isPresented: $confirmUnavailable, titleVisibility: .visible) {
            Button("Usuń niedostępne", role: .destructive) { Task { await sim.deleteUnavailable() } }
            Button("Anuluj", role: .cancel) {}
        } message: { Text("Wykona: xcrun simctl delete unavailable. To symulatory, których środowiska już nie ma, więc Xcode i tak ich nie uruchomi.") }
        .confirmationDialog("Usunąć \(confirmDevice?.name ?? "")?", isPresented: Binding(get: { confirmDevice != nil }, set: { if !$0 { confirmDevice = nil } }), titleVisibility: .visible) {
            Button("Usuń symulator", role: .destructive) { if let d = confirmDevice { Task { await sim.deleteDevice(d) } } }
            Button("Anuluj", role: .cancel) {}
        } message: { Text("Znikną dane aplikacji zainstalowanych w tym symulatorze. Xcode może utworzyć nowy, pusty.") }
    }

    private var subtitle: String {
        guard sim.loaded else { return "Sprawdzam Xcode…" }
        return "\(sim.snap.runtimes.count) środowisk (\(Model.size(sim.runtimeBytes))), \(sim.snap.devices.count) symulatorów"
    }

    private func tile(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .medium)).frame(width: 38, height: 38)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func symbol(_ platform: String, _ name: String = "") -> String {
        if name.contains("iPad") { return "ipad" }
        if name.contains("Watch") { return "applewatch" }
        if platform.hasPrefix("watchOS") { return "applewatch" }
        if platform.hasPrefix("tvOS") { return "appletv" }
        if platform.hasPrefix("visionOS") { return "visionpro" }
        return "iphone"
    }

    private func section(_ title: String, _ note: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(note).font(.callout).foregroundStyle(Theme.secondary)
            }
            content()
        }
    }

    // MARK: sekcje

    @ViewBuilder private var runtimes: some View {
        section("Środowiska", "Obrazy systemów do symulatorów. To zwykle największa część i Xcode pobierze je ponownie.") {
            if sim.snap.runtimes.isEmpty {
                Text("Brak zainstalowanych środowisk symulatora.").foregroundStyle(Theme.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 14)
            }
            ForEach(sim.snap.runtimes) { rt in
                HStack(spacing: 12) {
                    tile(symbol(rt.name))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rt.name).font(.body.weight(.medium))
                        Text("Symulatory z tym środowiskiem: \(sim.snap.devices.filter { $0.platform == rt.name.components(separatedBy: " (").first && $0.available }.count)")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 12)
                    Text(rt.bytes.map(Model.size) ?? "brak danych").font(.body.weight(.semibold)).monospacedDigit()
                    if sim.busy == rt.id { ProgressView().controlSize(.small) }
                    else if rt.deletable { Button("Usuń…") { confirmRuntime = rt }.disabled(sim.busy != nil) }
                }
                .padding(14).cardStyle(radius: 14)
            }
            let names = sim.snap.runtimes.map { $0.name.components(separatedBy: " (").first ?? "" }
            if Set(names).count < names.count {
                Label("Masz dwa środowiska tej samej wersji. Jedno zwykle wystarczy.", systemImage: "info.circle").font(.callout).foregroundStyle(Theme.secondary)
            }
        }
    }

    @ViewBuilder private var unavailableSection: some View {
        let list = sim.unavailable
        if !list.isEmpty {
            section("Niedostępne symulatory", "Ich środowisko zostało usunięte, więc Xcode ich nie uruchomi. Bezpieczne do usunięcia.") {
                HStack(spacing: 12) {
                    tile("exclamationmark.triangle")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(list.count) niedostępnych").font(.body.weight(.medium))
                        Text(list.prefix(3).map(\.name).joined(separator: ", ") + (list.count > 3 ? " i inne" : "")).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    Text(Model.size(list.reduce(0) { $0 + $1.bytes })).font(.body.weight(.semibold)).monospacedDigit()
                    if sim.busy == "unavailable" { ProgressView().controlSize(.small) }
                    else { Button("Usuń wszystkie…") { confirmUnavailable = true }.disabled(sim.busy != nil) }
                }
                .padding(14).cardStyle(radius: 14)
            }
        }
    }

    @ViewBuilder private var devicesSection: some View {
        let groups = Dictionary(grouping: devices, by: \.platform).sorted { $0.key > $1.key }
        section("Symulatory", "Urządzenia, które Xcode może uruchomić. Usunięcie kasuje dane aplikacji w danym symulatorze.") {
            if devices.isEmpty {
                Text("Brak dostępnych symulatorów.").foregroundStyle(Theme.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 14)
            }
            ForEach(groups, id: \.key) { platform, list in
                VStack(alignment: .leading, spacing: 6) {
                    Text(platform).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.leading, 4)
                    ForEach(list) { d in
                        HStack(spacing: 12) {
                            Image(systemName: symbol(platform, d.name)).frame(width: 24).foregroundStyle(Theme.secondary)
                            Text(d.name).lineLimit(1)
                            if d.booted { Text("uruchomiony").font(.caption).foregroundStyle(Color(hex: 0x3FCB7E)) }
                            Spacer(minLength: 12)
                            Text(Model.size(d.bytes)).foregroundStyle(Theme.secondary).monospacedDigit()
                            if sim.busy == d.id { ProgressView().controlSize(.small) }
                            else { Button("Usuń…") { confirmDevice = d }.disabled(sim.busy != nil || d.booted).help(d.booted ? "Najpierw zamknij symulator" : "") }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9).cardStyle(radius: 12)
                    }
                }
            }
        }
    }
}
