#!/bin/sh
# Użycie: tools/update-cask.sh 1.9  -> wpisuje wersję i SHA-256 zipa z wydania do Casks/opencleaner.rb
# Zip bierze z GitHub Releases (to ten plik pobierze brew), więc najpierw opublikuj wydanie.
set -e
V="${1:?podaj wersję, np. 1.9}"; cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/a.zip" "https://github.com/kczepiec/opencleaner/releases/download/v$V/OpenCleaner-$V.zip"
SHA="$(shasum -a 256 "$TMP/a.zip" | cut -d' ' -f1)"
sed -i '' -e "s/^  version \".*\"/  version \"$V\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/opencleaner.rb
echo "Casks/opencleaner.rb: $V $SHA"
