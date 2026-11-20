import CleanKit
import SwiftUI

/// Wnętrze "System i inne": z czego składa się miejsce, którego nie widać w katalogu domowym.
struct SystemView: View {
    let mole: MoleModel
    let model: Model
    var openSimulators: (() -> Void)? = nil

    private struct Row: Identifiable { let title: String; let note: String; let bytes: Int64; let isAssets: Bool; var id: String { title } }

    private static let hues = [Color(hex: 0x5892F7), Color(hex: 0x6F7DF0), Color(hex: 0x45B5C9), Color(hex: 0x9A7CE8), Color(hex: 0x7FB06A)]

    private var rows: [Row] {
        var r = mole.systemParts.map { Row(title: $0.title, note: $0.note, bytes: $0.bytes, isAssets: false) }
        if let a = mole.assetsBytes { r.append(Row(title: "Zasoby systemowe i symulatory", note: "Obrazy symulatorów Xcode i zasoby pobierane przez system (AssetsV2).", bytes: a, isAssets: true)) }
        return r.sorted { $0.bytes > $1.bytes }
    }
    private var total: Int64 { max(rows.reduce(0) { $0 + $1.bytes }, 1) }
    private let protected: [(key: String, title: String, symbol: String)] = [("Pictures", "Zdjęcia", "photo"), ("Music", "Muzyka", "music.note"), ("Movies", "Filmy", "film"), ("Desktop", "Pulpit", "menubar.dock.rectangle")]

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "System", subtitle: "Z czego składa się miejsce poza Twoim katalogiem domowym.") { EmptyView() }
            Divider()
            if !mole.systemLoaded {
                SystemSkeleton()
            } else {
                ScrollView {
                    VStack(spacing: 22) {
                        summary
                        partsList
                        protectedSection
                    }.padding(26).frame(maxWidth: 820).frame(maxWidth: .infinity)
                }.scrollIndicators(.hidden)
            }
        }
        .task { await mole.loadSystem() }
    }

    /// Jedna liczba i jeden pasek z segmentami: proporcje widać od razu, bez paska przy każdym wierszu.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Razem poza katalogiem domowym")).font(.callout).foregroundStyle(Theme.secondary)
                Text(Model.size(total)).font(.system(size: 34, weight: .semibold)).monospacedDigit()
            }
            GeometryReader { g in
                HStack(spacing: 3) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Self.hues[i % Self.hues.count])
                            .frame(width: max((g.size.width - CGFloat(rows.count - 1) * 3) * CGFloat(Double(r.bytes) / Double(total)), 4))
                    }
                }
            }.frame(height: 12)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 18)
    }

    private var partsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Części systemu")).font(.headline).padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Divider().overlay(Theme.border.opacity(0.6)) }
                    HStack(alignment: .top, spacing: 14) {
                        Circle().fill(Self.hues[i % Self.hues.count]).frame(width: 10, height: 10).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr(r.title)).font(.body.weight(.medium))
                            Text(tr(r.note)).font(.callout).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                            if r.isAssets, let open = openSimulators {
                                Button(tr("Zarządzaj symulatorami")) { open() }.buttonStyle(.link).padding(.top, 2)
                            }
                        }
                        Spacer(minLength: 12)
                        Text(Model.size(r.bytes)).font(.body.weight(.medium)).monospacedDigit()
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .accessibilityElement(children: .combine)
                }
            }.cardStyle(radius: 16)
        }
    }

    private var protectedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Foldery chronione przez macOS")).font(.headline)
                    Text(tr("Zdjęcia, Muzyka, Filmy i Pulpit nie są domyślnie liczone, bo macOS pyta o zgodę na dostęp. Możesz je zmierzyć jednorazowo."))
                        .font(.callout).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                Button(tr("Zmierz te foldery")) { Task { await mole.measureProtected() } }
                    .disabled(mole.protectedBytes.count == protected.count)
            }.padding(.leading, 2)
            HStack(spacing: 12) {
                ForEach(protected, id: \.key) { p in
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: p.symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr(p.title)).font(.callout).foregroundStyle(Theme.secondary)
                            if let b = mole.protectedBytes[p.key] { Text(Model.size(b)).font(.title3.weight(.semibold)).monospacedDigit() }
                            else { Text(tr("nie zmierzono")).font(.callout).foregroundStyle(Theme.secondary) }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading).cardStyle(radius: 14)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
