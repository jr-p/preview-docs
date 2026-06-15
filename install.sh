#!/bin/bash
set -euo pipefail

APP_NAME="PreviewDocs"
BUNDLE="${APP_NAME}.app"
DEST="/Applications/${BUNDLE}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

if [ ! -f "./build.sh" ]; then
    echo "Error: ./build.sh not found."
    exit 1
fi

echo "Building ${APP_NAME} from current source..."
bash ./build.sh

if [ ! -d "${BUNDLE}" ]; then
    echo "Error: ${BUNDLE} was not created by ./build.sh."
    exit 1
fi

echo "Installing ${APP_NAME} to /Applications..."
rm -rf "${DEST}"
cp -r "${BUNDLE}" "${DEST}"

echo "Registering file types..."
"${LSREGISTER}" -f "${DEST}"

echo ""
echo "✓ Installed to ${DEST}"
echo ""
echo "To set as default app for .md files:"
echo "  Right-click a .md file → Get Info → Open with → PreviewDocs → Change All…"
