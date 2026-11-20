import CleanKit
import SwiftUI

/// Instalacja serwera MCP i umiejętności dla agentów: kopiowanie pliku, rejestracja w Claude Code, SKILL.md.
enum MCPInstaller {
    static var helperInBundle: URL { Bundle.main.bundleURL.appending(path: "Contents/Helpers/opencleaner-mcp") }
    static var installedURL: URL { MCPConfig.directory.appending(path: "bin/opencleaner-mcp") }
    static var skillURL: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/skills/opencleaner/SKILL.md") }
    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: installedURL.path) }
    static var skillInstalled: Bool { FileManager.default.fileExists(atPath: skillURL.path) }

    /// Kopiuje serwer w stałe miejsce (niezależne od położenia aplikacji) i zakłada domyślną konfigurację.
    static func install() throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: helperInBundle.path) else { throw CocoaError(.fileNoSuchFile) }
        try fm.createDirectory(at: installedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: installedURL)
        try fm.copyItem(at: helperInBundle, to: installedURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedURL.path)
        if !fm.fileExists(atPath: MCPConfig.defaultURL.path) { try MCPConfig().save() }
    }

    static func uninstall() { try? FileManager.default.removeItem(at: installedURL) }

    static func claude(_ args: [String]) async -> (ok: Bool, text: String) {
        let r = await Mole.run(URL(fileURLWithPath: "/usr/bin/env"), ["claude"] + args)
        return (r.status == 0, r.text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static var snippet: String {
        """
        {
          "mcpServers": {
            "opencleaner": {
              "command": "\(installedURL.path)",
              "args": []
            }
          }
        }
        """
    }

    static func installSkill() throws {
        try FileManager.default.createDirectory(at: skillURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillText.write(to: skillURL, atomically: true, encoding: .utf8)
    }
    static func removeSkill() { try? FileManager.default.removeItem(at: skillURL.deletingLastPathComponent()) }

    static let skillText = """
    ---
    name: opencleaner
    description: Use when the user asks about Mac disk space, swap, memory, clearing caches, unused apps, node_modules, or "why is my Mac slow". Uses the OpenCleaner MCP server.
    ---

    # OpenCleaner

    The `opencleaner` MCP server tools show the state of the Mac and prepare cleanup. They are read only by default.

    ## Workflow

    1. Start with a read: `disk_usage` (space), `memory_status` (memory, swap, CPU, heavy apps).
    2. For cleanup use the previews: `clean_preview`, `optimize_preview`, `uninstall_preview`, `find_unused_repos`, `large_files`, `system_breakdown`, `list_apps`.
    3. Show the user the result in plain language: how much space, from what, what you recommend and why.
    4. Only after their explicit consent call `clean_run` or `optimize_run` with `confirm: true`. These tools are disabled by default; if they refuse, tell the user to enable them in OpenCleaner (Settings, Agents).

    ## Rules

    - `clean_run` deletes files permanently, without the Trash. Always run `clean_preview` first in the same conversation.
    - Never guess paths to delete. Show only what the tools returned.
    - `clean_preview` and `find_unused_repos` take from a few seconds to a minute. Warn the user.
    - Swap cannot be emptied by a command. Advise quitting heavy apps from `memory_status`, or a restart.
    - Report results in the user's language, with sizes in GB or MB.
    """
}

/// Ustawienia serwera MCP: instalacja, konfiguracja, podłączenie do agentów i umiejętność.
struct AgentsSettings: View {
    @State private var config = MCPConfig.load()
    @State private var installed = MCPInstaller.isInstalled
    @State private var skill = MCPInstaller.skillInstalled
    @State private var message: String?
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingGroup(header: "Serwer MCP") {
                SettingRow(title: "Serwer OpenCleaner", desc: installed ? MCPInstaller.installedURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                           : "Nie zainstalowany. Instalacja kopiuje plik serwera do ~/Library/Application Support/OpenCleaner/bin.", divider: false) {
                    if installed { Button(tr("Usuń")) { MCPInstaller.uninstall(); installed = false; testResult = nil } }
                    else { Button(tr("Zainstaluj")) { install() }.buttonStyle(.borderedProminent) }
                }
                SettingRow(title: "Włącz serwer", desc: "Wyłączony serwer odrzuca wszystkie wywołania agentów.") {
                    Toggle("", isOn: $config.enabled).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: "Zezwól na zmiany na dysku", desc: "Odblokowuje czyszczenie i optymalizację przez agentów. Czyszczenie kasuje na stałe i zawsze wymaga potwierdzenia po stronie agenta.") {
                    Toggle("", isOn: $config.allowDestructive).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: "Sprawdź serwer", desc: testResult ?? "Uruchamia zainstalowany plik i prosi go o listę narzędzi.") {
                    if testing { ProgressView().controlSize(.small) }
                    else { Button(tr("Sprawdź")) { Task { await test() } }.disabled(!installed) }
                }
            }
            SettingGroup(header: "Podłączenie do agentów") {
                SettingRow(title: "Claude Code", desc: message ?? "Dodaje serwer poleceniem claude mcp add (dla Twojego konta).", divider: false) {
                    HStack {
                        Button(tr("Dodaj")) { Task { await register() } }.disabled(!installed)
                        Button(tr("Usuń")) { Task { await unregister() } }.disabled(!installed)
                    }
                }
                SettingRow(title: "Inne programy, np. OpenBot", desc: "Skopiuj konfigurację i wklej ją w ustawieniach MCP agenta.") {
                    Button(tr("Skopiuj konfigurację")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(MCPInstaller.snippet, forType: .string)
                        message = "Skopiowano konfigurację do schowka."
                    }.disabled(!installed)
                }
            }
            SettingGroup(header: "Umiejętność dla agentów") {
                SettingRow(title: "OpenCleaner (SKILL.md)", desc: "Uczy agenta, kiedy i jak używać narzędzi: najpierw podgląd, potem zgoda. Instaluje się w ~/.claude/skills/opencleaner.", divider: false) {
                    if skill { Button(tr("Usuń")) { MCPInstaller.removeSkill(); skill = false } }
                    else { Button(tr("Zainstaluj")) { try? MCPInstaller.installSkill(); skill = MCPInstaller.skillInstalled }.buttonStyle(.borderedProminent) }
                }
            }
            SettingGroup(header: "Narzędzia") {
                ForEach(Array(MCPServer.catalog.enumerated()), id: \.element.name) { i, t in
                    SettingRow(title: t.name, desc: t.summary, divider: i > 0) {
                        Toggle("", isOn: Binding(get: { !config.disabledTools.contains(t.name) }, set: { on in
                            config.disabledTools.removeAll { $0 == t.name }
                            if !on { config.disabledTools.append(t.name) }
                        })).labelsHidden().toggleStyle(.switch).disabled(t.destructive && !config.allowDestructive)
                    }
                }
            }
        }
        .onChange(of: config) { _, c in try? c.save() }
    }

    private func install() {
        do { try MCPInstaller.install(); installed = true; message = nil }
        catch { message = "Nie udało się zainstalować serwera. Zbuduj aplikację od nowa (brakuje osadzonego pliku)." }
    }

    private func test() async {
        testing = true
        let r = await MCPSelfTest.run(binary: MCPInstaller.installedURL)
        testResult = r.ok ? trf("Działa. Narzędzi dostępnych dla agentów: %@.", "\(r.tools.count)") : "Serwer nie odpowiedział."
        testing = false
    }

    private func register() async {
        let r = await MCPInstaller.claude(["mcp", "add", "--scope", "user", "opencleaner", "--", MCPInstaller.installedURL.path])
        message = r.ok ? "Dodano do Claude Code. Uruchom ponownie agenta, żeby zobaczył narzędzia." : trf("Nie udało się (czy jest polecenie claude?): %@", "\(r.text.prefix(120))")
    }

    private func unregister() async {
        let r = await MCPInstaller.claude(["mcp", "remove", "--scope", "user", "opencleaner"])
        message = r.ok ? "Usunięto z Claude Code." : trf("Nie udało się usunąć: %@", "\(r.text.prefix(120))")
    }
}
