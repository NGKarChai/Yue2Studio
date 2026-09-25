#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_PATH="$PROJECT_ROOT/Yue2Studio.app"
BUILD_NO="2026092502"
DMG_NAME="Yue2Studio-${BUILD_NO}.dmg"
DMG_OUTPUT="$PROJECT_ROOT/$DMG_NAME"
STAGING_DIR="/tmp/Yue2Studio_DMG_Staging"

echo "=== Creating macOS DMG Installer for Yue2Studio (Build $BUILD_NO) ==="

# 1. Clean staging directory
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# 2. Copy App bundle and strip extended attributes
echo "-> Copying Yue2Studio.app to staging area..."
cp -R "$APP_PATH" "$STAGING_DIR/Yue2Studio.app"
xattr -cr "$STAGING_DIR/Yue2Studio.app"

# 3. Ad-hoc sign app bundle
echo "-> Signing app bundle..."
codesign --force --deep --sign - "$STAGING_DIR/Yue2Studio.app"

# 4. Create Applications symlink for drag-and-drop installation
echo "-> Creating /Applications symlink..."
ln -s /Applications "$STAGING_DIR/Applications"

# 5. Create Install Readme
cat << EOF > "$STAGING_DIR/INSTALL_INSTRUCTIONS.txt"
============================================================
              Yue2Studio - Native Apple Silicon Music Studio
                          Build: ${BUILD_NO}
============================================================

HOW TO INSTALL:
1. Drag the "Yue2Studio" application icon into the "Applications" folder.
2. Open Applications and double-click Yue2Studio to launch.

FIRST LAUNCH ON OTHER MACS (macOS Gatekeeper):
If macOS displays a warning that the developer cannot be verified:
- Right-click (or Control-click) "Yue2Studio" in your Applications folder
  and select "Open" from the context menu.
- Click "Open" in the security prompt.
This only needs to be done once on the first launch.

REQUIREMENTS:
- macOS 14.0 (Sonoma) or newer
- Apple Silicon Mac (M1, M2, M3, M4 or later)
- Unified Memory: 16 GB minimum (32 GB+ recommended for large models)

FEATURES:
- Pure native Swift & Apple Silicon Metal MLX execution (Zero Python).
- 5 official YuE2 generation modes (Full/Melody with generated or supplied score).
- Full SheetSage2/MERT2 multi-window audio transcription (ABC, MIDI, LAB).
- 1-click End-to-End Cover Song pipeline with style morphing presets.
============================================================
EOF

# 6. Build compressed DMG
echo "-> Packaging DMG with hdiutil..."
rm -f "$DMG_OUTPUT" "$PROJECT_ROOT/Yue2Studio.dmg"
hdiutil create -volname "Yue2Studio" \
               -srcfolder "$STAGING_DIR" \
               -ov \
               -format UDZO \
               "$DMG_OUTPUT"

# 7. Create convenient symlink
ln -sf "$DMG_NAME" "$PROJECT_ROOT/Yue2Studio.dmg"

# 8. Clean up staging directory
rm -rf "$STAGING_DIR"

echo "=== DMG Successfully Created! ==="
echo "Artifact: $DMG_OUTPUT"
ls -lh "$DMG_OUTPUT"
