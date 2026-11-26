#!/bin/sh
# muguet - make-ios.sh
# Constantin Clerc (c22dev) - 0.1

set -eu
cd "$(dirname "$0")"

ZIP=""
MODE=""
DEVICE=""
for a in "$@"; do
  case "$a" in
    *.zip|*.wasm) ZIP="$a" ;;
    --install|--ipa) MODE="$a" ;;
    *) DEVICE="$a" ;;
  esac
done

TEAM="${TEAM:-}"
if [ "$MODE" != "--ipa" ] && [ -z "$TEAM" ]; then echo "set TEAM=<your Apple developer team id>"; exit 1; fi
BUNDLE_ID="${BUNDLE_ID:-ch.cclerc.muguet.ios}"
ENTITLEMENTS=Muguet.entitlements
if [ "${FREE:-0}" = 1 ] || [ "$MODE" = "--ipa" ]; then
  ENTITLEMENTS=Muguet-free.entitlements
fi
# NOTE: there used to be a HEAP_GB / MUGUET_IOS_HEAP_GB knob here (8 paid,
# 5 free) that no code ever read — the heap cap lives in
# src/performance.rs (IOS_HEAP_MAX, 3 GB) and the runtime env override
# MUGUET_HEAP_GB_MB. Worse, Muguet-free.entitlements has no
# increased-memory-limit entitlement, so a free/sideload build jetsams
# well below 3 GB whatever this script says. Do not re-add the knob
# without wiring it into performance.rs and the entitlements.
TOOLCHAIN=1.98.1
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
export RUSTFLAGS="${RUSTFLAGS:-} --remap-path-prefix=$HOME=/home --remap-path-prefix=$PWD=/muguet"

if [ -n "$ZIP" ]; then
  cargo build --locked --release
  mkdir -p target/ios-game
  case "$ZIP" in
    *.zip)
      ENTRY="$(unzip -Z1 "$ZIP" | grep -E '(^|/)b/[^/]+/game\.wasm$' | head -1)"
      [ -n "$ENTRY" ] || { echo "$ZIP has no b/<build>/game.wasm"; exit 1; }
      unzip -p "$ZIP" "$ENTRY" > target/ios-game/game.wasm ;;
    *) cp "$ZIP" target/ios-game/game.wasm ;;
  esac
  ./target/release/muguet --patch target/ios-game/game.wasm target/ios-game/game.patched.wasm
  mv target/ios-game/game.patched.wasm target/ios-game/game.wasm
  if command -v wasm-opt >/dev/null; then
    SUM="$(shasum -a 256 target/ios-game/game.wasm | cut -c1-16)"
    if [ ! -f "target/ios-game/game.opt-$SUM.wasm" ]; then
      echo "optimizing the game's code with wasm-opt -O3 (a few minutes, once)…"
      # The old script wiped the cache first, then aborted under set -e
      # on a wasm-opt failure — destroying the only good copy. Keep
      # the old cache until the new file verifies, and fall back to
      # the unoptimised wasm instead of aborting.
      if wasm-opt target/ios-game/game.wasm -O3 -g --enable-memory64 --enable-threads --enable-bulk-memory --enable-mutable-globals \
        --enable-sign-ext --enable-nontrapping-float-to-int --enable-simd --enable-multivalue --enable-reference-types --enable-multimemory \
        -o "target/ios-game/game.opt-$SUM.wasm.tmp" && [ -s "target/ios-game/game.opt-$SUM.wasm.tmp" ]; then
        mv "target/ios-game/game.opt-$SUM.wasm.tmp" "target/ios-game/game.opt-$SUM.wasm"
      else
        echo "warning: wasm-opt failed; continuing with the unoptimised game.wasm"
        rm -f "target/ios-game/game.opt-$SUM.wasm.tmp"
      fi
    fi
    [ -f "target/ios-game/game.opt-$SUM.wasm" ] && cp "target/ios-game/game.opt-$SUM.wasm" target/ios-game/game.wasm
  else
    echo "wasm-opt not found (brew install binaryen): building without the extra optimization"
  fi
  ./target/release/muguet --precompile-ios target/ios-game/game.wasm target/ios-game/game.cwasm
  rm target/ios-game/game.wasm
  export MUGUET_GAME_CODE="$PWD/target/ios-game/game.cwasm"
else
  echo "no game zip given: building without the game's code"
  unset MUGUET_GAME_CODE || true
fi

IPHONEOS_DEPLOYMENT_TARGET=15.0 cargo "+$TOOLCHAIN" build --locked --release --no-default-features --target aarch64-apple-ios --target-dir target/ios

command -v xcodegen >/dev/null || { echo "xcodegen not found (brew install xcodegen)"; exit 1; }
(cd ios && xcodegen generate --quiet)
rm -rf target/ios-xcode/Build/Products
APP="$PWD/target/ios-xcode/Build/Products/Release-iphoneos/Muguet.app"
# No -quiet on xcodebuild: the old script hid the very errors needed
# when a build fails.
if [ "$MODE" = "--ipa" ]; then
  xcodebuild -project ios/Muguet.xcodeproj -scheme Muguet -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath target/ios-xcode build \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" CODE_SIGNING_ALLOWED=NO
  rm -f "$APP/embedded.mobileprovision"
  codesign --force --sign - --entitlements ios/Muguet-sideload.entitlements --generate-entitlement-der "$APP"
else
  xcodebuild -project ios/Muguet.xcodeproj -scheme Muguet -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath target/ios-xcode -allowProvisioningUpdates build \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" DEVELOPMENT_TEAM="$TEAM"
fi
codesign --verify --deep --strict "$APP"
echo "built: $APP ($(du -sh "$APP" | cut -f1))"

if [ "$MODE" = "--ipa" ]; then
  STAGE="$(mktemp -d)"
  mkdir "$STAGE/Payload"
  cp -cRp "$APP" "$STAGE/Payload/"
  mkdir -p build
  IPA="$PWD/build/Muguet.ipa"
  rm -f "$IPA"
  (cd "$STAGE" && zip -qry "$IPA" Payload)
  rm -rf "$STAGE"
  echo "built: $IPA ($(du -h "$IPA" | cut -f1))"
fi

if [ "$MODE" = "--install" ]; then
  if [ -z "$DEVICE" ]; then
    DEVICE="$(xcrun devicectl list devices 2>/dev/null | awk '/available \(paired\)|connected/ && /iPhone|iPad/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')"
  fi
  [ -n "$DEVICE" ] || { echo "no iPhone / iPad connected (unlocked, Developer Mode on)"; exit 1; }
  xcrun devicectl device install app --device "$DEVICE" "$APP"
  echo "installed on $DEVICE"
fi
