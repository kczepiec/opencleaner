#!/bin/sh
# Użycie: tools/release.sh 1.1  -> dist/OpenCleaner-1.1.zip (publikacja: gh release create v1.1 dist/OpenCleaner-1.1.zip)
set -e
V="${1:?podaj wersję, np. 1.1}"; cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project OpenCleaner.xcodeproj -scheme OpenCleaner -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY=- MARKETING_VERSION="$V" CURRENT_PROJECT_VERSION="$V" build -quiet
mkdir -p dist; ditto -c -k --keepParent build/Build/Products/Release/OpenCleaner.app "dist/OpenCleaner-$V.zip"
echo "dist/OpenCleaner-$V.zip"
