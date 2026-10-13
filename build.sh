#!/bin/zsh
# Compila "What's Going On.app" (universale arm64 + x86_64, macOS 14+) con gli strumenti a riga di comando:
# niente progetto Xcode, come Nod.
#   ./build.sh              build/What's Going On.app
#   ./build.sh --install    e la copia in /Applications (chiude la copia aperta) e la apre
#   ./build.sh --dmg        e crea dist/WhatsGoingOn-<versione>.dmg
# Firma ad hoc: l'app non chiede permessi di privacy, quindi non serve un'identità di firma.
set -euo pipefail
cd "${0:A:h}"

MODE=build
case "${1:-}" in
  --install) MODE=install ;;
  --dmg) MODE=dmg ;;
  "") ;;
  *) echo "uso: ./build.sh [--install|--dmg]" >&2; exit 64 ;;
esac

NAME="What's Going On"
EXE=WhatsGoingOn
VERSION=$(tr -d '[:space:]' < VERSION)
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
BUILD=build
APP="$BUILD/$NAME.app"
PLIST="$APP/Contents/Info.plist"

grep -q "^## $VERSION " CHANGELOG.md || { echo "Manca la sezione '## $VERSION · <data>' in CHANGELOG.md" >&2; exit 1; }

# Traduzioni: ogni L("…") deve avere la sua voce in inglese (avviso, non blocca).
if command -v python3 >/dev/null; then
  python3 -I tools/check-strings.py >/dev/null || echo "Attenzione: traduzioni incomplete (python3 tools/check-strings.py)."
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$PLIST"
/usr/bin/plutil -insert WGOGitCommit -string "$COMMIT" "$PLIST"
cp -R Localization/*.lproj "$APP/Contents/Resources/"

SOURCES=(Sources/**/*.swift)
for arch in arm64 x86_64; do
  mkdir -p "$BUILD/$arch"
  swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macos14.0" "${SOURCES[@]}" -o "$BUILD/$arch/$EXE"
done
lipo -create "$BUILD/arm64/$EXE" "$BUILD/x86_64/$EXE" -output "$APP/Contents/MacOS/$EXE"

ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/Icon/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) Resources/Icon/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

plutil -lint "$PLIST" >/dev/null
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Pronto: $APP ($VERSION, build $BUILD_NUMBER, commit $COMMIT)"

case "$MODE" in
  install)
    /usr/bin/pkill -x "$EXE" 2>/dev/null || true
    rm -rf "/Applications/$NAME.app"
    cp -R "$APP" "/Applications/$NAME.app"
    touch "/Applications/$NAME.app"
    open "/Applications/$NAME.app"
    echo "Installato in /Applications e aperto: guarda la barra dei menu." ;;
  dmg)
    mkdir -p dist
    STAGE=$(mktemp -d)
    cp -R "$APP" "$STAGE/$NAME.app"
    ln -s /Applications "$STAGE/Applications"
    DMG="dist/WhatsGoingOn-$VERSION.dmg"
    rm -f "$DMG"
    hdiutil create -quiet -volname "$NAME $VERSION" -srcfolder "$STAGE" -format UDZO "$DMG"
    rm -rf "$STAGE"
    shasum -a 256 "$DMG"
    echo "DMG: $DMG" ;;
esac
