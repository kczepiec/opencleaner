import CleanKit
import SwiftUI

/// Stan zakładki Autostart. Skan tylko czyta; usuwanie idzie po potwierdzeniu.
@MainActor @Observable
final class LoginModel {
    var items: [LoginItems.Item] = []
    var loaded = false
    var needsPermission = false
    var busy: String?
    var message: String?

    func load() async {
        let r = await LoginItems.load()
        withAnimation(Theme.ease) { items = r.items; needsPermission = r.needsPermission; loaded = true }
    }

    func remove(_ i: LoginItems.Item) async {
        busy = i.id; message = nil
        let ok = await LoginItems.remove(i)
        message = ok ? nil : trf("Nie udało się usunąć %@.", "\(i.name)")
        busy = nil; await load()
    }
}

struct LoginItemsView: View {
    let model: LoginModel
    @State private var confirm: LoginItems.Item?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Autostart", subtitle: model.loaded ? trf("Programy uruchamiane przy logowaniu: %@", "\(model.items.count)") : "Sprawdzam…") {
                Button("Odśwież") { model.message = nil; Task { await model.load() } }.disabled(model.busy != nil)
            }
            Divider()
            if !model.loaded { ScrollView { ListSkeleton(rows: 5).padding(14) } }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let m = model.message { note(m) }
                        if model.needsPermission {
                            note("Zezwól OpenCleaner na sterowanie System Events (Ustawienia systemowe, Prywatność i ochrona, Automatyzacja), żeby zobaczyć elementy logowania.")
                        }
                        if model.items.isEmpty {
                            EmptyState(title: "Nic nie startuje samo", text: "Nie znalazłem programów uruchamianych przy logowaniu.").frame(height: 260)
                        }
                        ForEach(model.items) { i in row(i) }
                        if !model.items.isEmpty {
                            Text("Pokazuję elementy logowania i agenty z Twojej Biblioteki. Usunięty agent trafia do Kosza. Programy systemowe i działające w tle za zgodą aplikacji są w Ustawieniach systemowych, Ogólne, Rzeczy otwierane po zalogowaniu.")
                                .font(.callout).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                        }
                    }.padding(22)
                }.scrollIndicators(.hidden)
            }
        }
        .task { await model.load() }
        .confirmationDialog(trf("Usunąć %@ z autostartu?", "\(confirm?.name ?? "")"), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            Button("Usuń", role: .destructive) { if let i = confirm { Task { await model.remove(i) } } }
            Button("Anuluj", role: .cancel) {}
        } message: { Text(confirm?.kind == .launchAgent ? "Agent zostanie zatrzymany, a jego plik przeniesiony do Kosza. Program zostaje zainstalowany." : "Program zostaje zainstalowany, tylko przestanie uruchamiać się przy logowaniu.") }
    }

    private func note(_ t: String) -> some View {
        Text(t).font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 12, fill: Theme.raised)
    }

    private func row(_ i: LoginItems.Item) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: i.path.isEmpty ? "/System/Library/CoreServices/Finder.app" : i.path))
                .resizable().interpolation(.high).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(i.name).font(.body.weight(.medium)).lineLimit(1)
                Text((i.kind == .launchAgent ? tr("Agent w tle") : tr("Element logowania")) + (i.path.isEmpty ? "" : " · " + i.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")))
                    .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if model.busy == i.id { ProgressView().controlSize(.small) }
            else { Button("Usuń…") { confirm = i }.disabled(model.busy != nil) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).cardStyle(radius: 14)
    }
}
