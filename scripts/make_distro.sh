#!/bin/bash
# Builds the distributable universal bundle + DMG + ZIP for other Macs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/tmp .build-x86/tmp .build/module-cache
export TMPDIR="$ROOT/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"

# 1. Both architectures (CLT has no xcbuild: build each triple separately).
swift build -c release --scratch-path .build
TMPDIR="$ROOT/.build-x86/tmp" swift build -c release --triple x86_64-apple-macos13.0 --scratch-path .build-x86
test -f "$ROOT/.build-x86/release/M"
lipo -create "$(swift build -c release --show-bin-path)/M" "$ROOT/.build-x86/release/M" -output .build/m-fat
lipo -info .build/m-fat

# 2. Bundle (make_app rebuilds arm64 then we swap in the fat binary and re-sign).
bash scripts/make_app.sh >/dev/null
APP="$ROOT/dist/M.app"
cp .build/m-fat "$APP/Contents/MacOS/M"
chmod 755 "$APP/Contents/MacOS/M"
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"
lipo -info "$APP/Contents/MacOS/M"

# 3. DMG with Applications shortcut and a first-launch helper (Gatekeeper).
DIST="$ROOT/dist"; STAGE="$DIST/stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/M.app"
ln -s /Applications "$STAGE/Applicazioni"
cat > "$STAGE/LEGGIMI.txt" <<'TXT'
M — scarico schede di memoria
================================
1. Trascina «M.app» dentro «Applicazioni».
2. Prima apertura: siccome M non è firmata con certificato Apple ($99/anno),
   macOS la bloccherà. Due modi per sbloccarla:
   a) fai doppio clic su «Apri M alla prima volta.command» in questo disco, oppure
   b) tasto destro su M.app → Apri → Apri.
Dopo il primo via libera, M si apre normalmente.
TXT
cat > "$STAGE/Apri M alla prima volta.command" <<'CMD'
#!/bin/bash
# Rimuove il attributo di quarantena da /Applications/M.app (solo alla prima apertura).
xattr -dr com.apple.quarantine /Applications/M.app 2>/dev/null
echo "Fatto: ora apri M dalle Applicazioni."
CMD
chmod +x "$STAGE/Apri M alla prima volta.command"
hdiutil create -volname "M" -srcfolder "$STAGE" -ov -format UDZO "$DIST/M-installer.dmg" >/dev/null
hdiutil verify "$DIST/M-installer.dmg" >/dev/null && echo "DMG verificato"
ditto -c -k --keepParent "$APP" "$DIST/M.zip"
ls -la "$DIST/M-installer.dmg" "$DIST/M.zip"
