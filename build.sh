#!/bin/bash
set -euo pipefail

APP_NAME="PreviewDocs"
BUNDLE="${APP_NAME}.app"
SDK=$(xcrun --show-sdk-path --sdk macosx)
TARGET="arm64-apple-macos14.0"

# Download marked.min.js if not present
if [ ! -f "Resources/marked.min.js" ]; then
    echo "Downloading marked.min.js..."
    curl -s -L -o Resources/marked.min.js \
        "https://cdn.jsdelivr.net/npm/marked@12/marked.min.js"
fi

echo "Compiling ${APP_NAME}..."
swiftc \
    -sdk "$SDK" \
    -target "$TARGET" \
    -framework AppKit \
    -framework WebKit \
    Sources/*.swift \
    -o "${APP_NAME}"

echo "Bundling..."
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

cp "${APP_NAME}"            "${BUNDLE}/Contents/MacOS/"
cp Resources/Info.plist     "${BUNDLE}/Contents/"
cp Resources/marked.min.js  "${BUNDLE}/Contents/Resources/"
cp Resources/PreviewDocs.icns "${BUNDLE}/Contents/Resources/"

rm "${APP_NAME}"

echo ""
echo "✓ Built ${BUNDLE}"
echo ""
echo "  To run:    open ${BUNDLE}"
echo "  To install: ./install.sh"
