#!/bin/sh
# muguet - make-app.sh
# Constantin Clerc (c22dev) - 0.1

set -eu
cd "$(dirname "$0")"
APP="$PWD/build/Muguet.app"
GAME="${1:-}"
export RUSTFLAGS="${RUSTFLAGS:-} --remap-path-prefix=$HOME=/home --remap-path-prefix=$PWD=/muguet"

cargo build --locked --release
BIN=target/release/muguet
SERVER_BIN=target/release/muguet-server
EMBEDDED=false
if [ -n "$GAME" ]; then
  mkdir -p target/mac-game
  case "$GAME" in
    *.zip)
      # Pin the known build first; sorted fallback keeps the choice
      # deterministic if the zip ever holds more than one build.
      ENTRY="$(unzip -Z1 "$GAME" | grep -E '(^|/)b/8b0b5899ed/game\.wasm$' | head -1)"
      [ -n "$ENTRY" ] || ENTRY="$(unzip -Z1 "$GAME" | grep -E '(^|/)b/[^/]+/game\.wasm$' | sort | head -1)"
      [ -n "$ENTRY" ] || { echo "$GAME has no b/<build>/game.wasm"; exit 1; }
      unzip -p "$GAME" "$ENTRY" > target/mac-game/game.wasm ;;
    *) cp "$GAME" target/mac-game/game.wasm ;;
  esac
  ./target/release/muguet --precompile target/mac-game/game.wasm target/mac-game/game.cwasm
  test -s target/mac-game/game.cwasm || { echo "precompile produced an empty game.cwasm"; exit 1; }
  rm target/mac-game/game.wasm
  MUGUET_GAME_CODE="$PWD/target/mac-game/game.cwasm" cargo build --locked --release --no-default-features --target-dir target/embed
  BIN=target/embed/release/muguet
  # The server binary used to come from target/release (the
  # non-embedded build) even for the embedded app — a mismatched
  # pairing. Take it from the same target dir as muguet.
  SERVER_BIN=target/embed/release/muguet-server
  EMBEDDED=true
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
[ -f "$BIN" ] || { echo "missing binary: $BIN"; exit 1; }
[ -f "$SERVER_BIN" ] || { echo "missing binary: $SERVER_BIN"; exit 1; }
cp "$BIN" "$SERVER_BIN" "$APP/Contents/MacOS/"
swiftc -O -parse-as-library -target arm64-apple-macos14 launcher/Launcher.swift -o "$APP/Contents/MacOS/Launcher"
# An unmatched glob stays literal in sh, so this cp used to fail with
# a bare "No such file" when there are no mp3s.
if ls assets/*.mp3 >/dev/null 2>&1; then cp assets/*.mp3 "$APP/Contents/Resources/"; else echo "no mp3 assets found, skipping"; fi

xcrun actool assets/muguet.icon --compile "$APP/Contents/Resources" --app-icon muguet --platform macosx \
  --minimum-deployment-target 14.0 --output-partial-info-plist "$(mktemp -d)/icon.plist" >/dev/null

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Muguet</string>
  <key>CFBundleDisplayName</key><string>Muguet</string>
  <key>CFBundleIdentifier</key><string>ch.cclerc.muguet</string>
  <key>CFBundleExecutable</key><string>Launcher</string>
  <key>CFBundleIconFile</key><string>muguet</string>
  <key>CFBundleIconName</key><string>muguet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>8</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>GCSupportsGameMode</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Multiplayer connects to a game server on your local network.</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><false/>
  <key>MuguetEmbeddedCode</key><EMBEDDED/>
</dict>
</plist>
PLIST
sed -i '' "s|<EMBEDDED/>|<$EMBEDDED/>|" "$APP/Contents/Info.plist"

codesign --force --deep --sign - "$APP"
echo "built: $APP ($(du -sh "$APP" | cut -f1))"
