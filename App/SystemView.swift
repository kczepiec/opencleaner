import CleanKit
import SwiftUI

/// Wnętrze "System i inne": z czego składa się miejsce, którego nie widać w katalogu domowym.
struct SystemView: View {
    let mole: MoleModel
    let model: Model
    @State private var confirmRuntime: SystemInfo.Runtime?

    private struct Row: Identifiable { let title: String; let note: String; let bytes: Int64; var id: String { title } }

    private var rows: [Row] {
        var r = mole.systemParts.map { Row(title: $0.title, note: $0.note, bytes: $0.bytes) }
        if let a = mole.assetsBytes { r.append(Row(title: "Zasoby systemowe i symulatory", note: "Obrazy symulatorów Xcode i zasoby pobierane przez system (AssetsV2).", bytes: a)) }
        return r.sorted { $0.bytes > $1.bytes }
    }
    private var maxBytes: Int64 { max(rows.map(\.bytes).max() ?? 1, 1) }
    private let protected: [(key: String, title: String)] = [("Pictures", "Zdjęcia"), ("Music", "Muzyka"), ("Movies", "Filmy"), ("Desktop", "Pulpit")]

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "System", subtitle: "Z czego składa się miejsce poza Twoim katalogiem domowym.") { EmptyView() }
            Divider()
            if !mole.systemLoaded {
                SystemSkeleton()
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        Card {
                            Text("Części systemu").font(.headline)
                            ForEach(rows) { r in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(r.title); Spacer(); Text(Model.size(r.bytes)).foregroundStyle(Theme.secondary).monospacedDigit() }
                                    Capsule().fill(Theme.accent.opacity(0.85))
                                        .frame(maxWidth: .infinity, alignment: .leading).frame(height: 5)
                                        .scaleEffect(x: CGFloat(Double(r.bytes) / Double(maxBytes)), y: 1, anchor: .leading)
                                    Text(r.note).font(.caption).foregroundStyle(Theme.secondary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        runtimesCard
                        protectedCard
                    }.padding(22)
                }
            }
        }
        .task { await mole.loadSystem() }
        .confirmationDialog("Usunąć \(confirmRuntime?.name ?? "")?", isPresented: Binding(get: { confirmRuntime != nil }, set: { if !$0 { confirmRuntime = nil } }), titleVisibility: .visible) {
            Button("Usuń symulator", role: .destructive) { if let rt = confirmRuntime { Task { await mole.deleteRuntime(rt) } } }
            Button("Anuluj", role: .cancel) {}
        } message: { Text("Zwolni kilkanaście GB. Xcode pobierze to środowisko ponownie, jeśli będzie potrzebne do buildów lub symulatora.") }
    }

    private var runtimesCard: some View {
        Card {
            Text("Symulatory Xcode").font(.headline)
            if mole.runtimes.isEmpty {
                Text("Brak zainstalowanych środowisk symulatora.").foregroundStyle(Theme.secondary)
            }
            ForEach(mole.runtimes) { rt in
                HStack(spacing: 12) {
                    Image(systemName: "iphone").frame(width: 30, height: 30)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text(rt.name)
                    Spacer()
                    if mole.deletingRuntime == rt.id { ProgressView().controlSize(.small) }
                    else { Button("Usuń…") { confirmRuntime = rt }.disabled(mole.deletingRuntime != nil) }
                }
            }
            if mole.runtimes.count > 1, Set(mole.runtimes.map { $0.name.components(separatedBy: " (").first ?? "" }).count < mole.runtimes.count {
                Label("Masz dwa środowiska tej samej wersji. Jedno zwykle wystarczy.", systemImage: "info.circle").font(.callout).foregroundStyle(Theme.secondary)
            }
            if let e = mole.runtimeError { Text(e).font(.callout).foregroundStyle(.red) }
        }
    }

    private var protectedCard: some View {
        Card {
            Text("Foldery chronione przez macOS").font(.headline)
            Text("Zdjęcia, Muzyka, Filmy i Pulpit nie są domyślnie liczone, bo macOS pyta o zgodę na dostęp. Możesz je zmierzyć jednorazowo.")
                .font(.callout).foregroundStyle(Theme.secondary)
            ForEach(protected, id: \.key) { p in
                HStack { Text(p.title); Spacer()
                    Text(mole.protectedBytes[p.key].map(Model.size) ?? "nie zmierzono").foregroundStyle(Theme.secondary).monospacedDigit() }
            }
            Button("Zmierz te foldery") { Task { await mole.measureProtected() } }
                .disabled(mole.protectedBytes.count == protected.count)
        }
    }
}
