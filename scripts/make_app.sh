#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# Keep build caches and temporary compiler files inside the repository.
mkdir -p .build/tmp .build/module-cache .build/cache .build/config .build/security
export TMPDIR="$ROOT/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"
swift build -c release --cache-path "$ROOT/.build/cache" --config-path "$ROOT/.build/config" --security-path "$ROOT/.build/security"
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/M.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Remove an earlier signature before replacing the payload (idempotent).
rm -rf "$APP/Contents/_CodeSignature"
cp "$BIN_DIR/M" "$APP/Contents/MacOS/M"
chmod 755 "$APP/Contents/MacOS/M"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>M</string>
    <key>CFBundleDisplayName</key><string>M</string>
    <key>CFBundleExecutable</key><string>M</string>
    <key>CFBundleIdentifier</key><string>it.marco.m</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --force --deep -s - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
printf 'Bundle creato e firma ad-hoc verificata: %s\n' "$APP"
