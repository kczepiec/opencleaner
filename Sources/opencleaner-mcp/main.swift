import CleanKit
import Foundation

// Serwer MCP OpenCleaner: JSON-RPC po stdio. Na stdout idą tylko odpowiedzi protokołu, diagnostyka na stderr.
L10n.english = true  // Mole's own English output, not the Polish glossary
let server = MCPServer()
while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { continue }
    if let reply = await server.handle(trimmed) {
        FileHandle.standardOutput.write(Data((reply + "\n").utf8))
    }
}
