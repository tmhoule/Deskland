#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/mac/build"
STAGING="$(mktemp -d "$ROOT/mac/build/staging.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Deskland Preview.app"
DEST="$ROOT/mac/build/Deskland Preview.app"
ARCH="$(uname -m)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/prototype/assets"
xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macos14.0" \
  -framework AppKit -framework WebKit -framework ApplicationServices \
  "$ROOT"/mac/Sources/*.swift -o "$APP/Contents/MacOS/DesklandPreviewP0"
cp "$ROOT/mac/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/mac/Resources/bridge.js" "$APP/Contents/Resources/bridge.js"
# Explicit P1 allowlist: two free implementations and locked-theme metadata/art only.
mkdir -p "$APP/Contents/Resources/prototype/thumbs" "$APP/Contents/Resources/prototype/i18n"
for FILE in settings.html themes.json thumbs-data.js flat.html beach-palms.js meadow.html meadow-boy.js meadow-cat.js share.js; do
  cp "$ROOT/prototype/$FILE" "$APP/Contents/Resources/prototype/$FILE"
done
for FILE in beach-coconut-palm-v2.png beach-coconut-palm-curved.png beach-coconut-palm-airy.png beach-coconut-palm-windswept.png beach-coconut-palm-arch.png meadow-black-kitten.png meadow-kite-boy-level-face.png meadow-kite-boy-diagonal-run.png; do
  cp "$ROOT/prototype/assets/$FILE" "$APP/Contents/Resources/prototype/assets/$FILE"
done
for FILE in beach.webp 'colorful city.webp' forest.webp 'hand draw city.webp' lake.webp lotus.webp maldives.webp meadow.webp 'nautical chart.webp' ocean.webp 'old map.webp' 'pink forest.webp' sky.webp; do
  cp "$ROOT/prototype/thumbs/$FILE" "$APP/Contents/Resources/prototype/thumbs/$FILE"
done
for FILE in en.json zh-CN.json; do
  cp "$ROOT/prototype/i18n/$FILE" "$APP/Contents/Resources/prototype/i18n/$FILE"
done
# Optional stable local development identity helps macOS recognize the app across rebuilds.
# Supply a certificate name or SHA-1 in the environment; never commit signing credentials.
# Defaults to ad-hoc signing. Developer ID notarization remains a separate release step.
codesign --force --sign "${DESKLAND_SIGNING_IDENTITY:--}" "$APP"
# Replace only this generated output, never merge old resources into the bundle.
rm -rf "$DEST"
mv "$APP" "$DEST"
printf 'Built %s (%s, macOS 14+)\n' "$DEST" "$ARCH"
