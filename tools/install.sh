#!/bin/sh
# Instaluje OpenCleaner w ~/Applications, dokłada Mole (mo) i serwer MCP dla agentów.
# Użycie: tools/install.sh [ścieżka do OpenCleaner.app]  (domyślnie build/Build/Products/Release/OpenCleaner.app)
set -e
DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$DIR/build/Build/Products/Release/OpenCleaner.app}"
[ -d "$APP" ] || { echo "Brak $APP. Zbuduj aplikację (patrz README)." >&2; exit 1; }
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/OpenCleaner.app"
cp -R "$APP" "$HOME/Applications/OpenCleaner.app"
echo "Zainstalowano: $HOME/Applications/OpenCleaner.app"

# Serwer MCP w stałym miejscu, niezależnie od położenia aplikacji.
MCP_DIR="$HOME/Library/Application Support/OpenCleaner/bin"
mkdir -p "$MCP_DIR"
cp -f "$HOME/Applications/OpenCleaner.app/Contents/Helpers/opencleaner-mcp" "$MCP_DIR/opencleaner-mcp"
chmod 755 "$MCP_DIR/opencleaner-mcp"
echo "Serwer MCP: $MCP_DIR/opencleaner-mcp"

if command -v mo >/dev/null 2>&1 || [ -x /opt/homebrew/bin/mo ] || [ -x /usr/local/bin/mo ]; then
  echo "Mole jest już zainstalowany."
elif command -v brew >/dev/null 2>&1; then
  echo "Instaluję Mole przez Homebrew..."
  brew install mole
else
  echo "Nie znalazłem Homebrew. Zainstaluj Mole ręcznie:" >&2
  echo "  curl -fsSL https://raw.githubusercontent.com/tw93/Mole/main/install.sh | bash" >&2
  exit 2
fi
echo "Podłączenie agentów i umiejętność: OpenCleaner, Ustawienia, Agenci (MCP)."
