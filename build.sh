#!/bin/zsh
# Compila "What's Going On.app" (universale arm64 + x86_64, macOS 14+) con gli strumenti a riga di comando:
# niente progetto Xcode, come Nod.
#   ./build.sh              build/What's Going On.app
#   ./build.sh --install    e la copia in /Applications (chiude la copia aperta) e la apre
#   ./build.sh --dmg        e crea dist/WhatsGoingOn-<versione>.dmg
#   WGO_ICON=classic ./build.sh …   usa l'icona classica anche se c'è Xcode
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
plist_set() { /usr/bin/plutil -insert "$1" -string "$2" "$PLIST"; }   # chiave, valore (spazi ammessi)

grep -q "^## $VERSION " CHANGELOG.md || { echo "Manca la sezione '## $VERSION · <data>' in CHANGELOG.md" >&2; exit 1; }

# Traduzioni: ogni L("…") deve avere la sua voce in inglese (avviso, non blocca).
if command -v python3 >/dev/null; then
  python3 -I tools/check-strings.py >/dev/null || echo "Attenzione: traduzioni incomplete (python3 tools/check-strings.py)."
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$PLIST"
cp -R Localization/*.lproj "$APP/Contents/Resources/"
cp CHANGELOG.md "$APP/Contents/Resources/CHANGELOG.md"   # Impostazioni › Aggiornamenti › Novità di questa versione

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

# Icona Liquid Glass (Resources/Icon/WhatsGoingOn.icon, formato Icon Composer): serve actool di Xcode, con le stesse
# opzioni che usa Xcode. Poi tools/icon-check la disegna come il Dock (IconServices): se risulta vuota, o uguale
# all'icona generica, si resta sulla classica. Anteprime in build/icon-preview.png e build/icon-actool.png. Come in Nod.
ICON_TIER=classic
ICON_CHECK=""
if [ "${WGO_ICON:-}" != classic ]; then
  if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # Xcode anche se è selezionato solo CLT
  fi
  ACTOOL=$(xcrun --find actool 2>/dev/null || true)
  if [ -n "$ACTOOL" ]; then
    rm -rf "$BUILD/icon-out"; mkdir -p "$BUILD/icon-out"
    if "$ACTOOL" Resources/Icon/WhatsGoingOn.icon --compile "$BUILD/icon-out" --output-format human-readable-text \
         --notices --warnings --platform macosx --target-device mac --minimum-deployment-target 14.0 \
         --app-icon WhatsGoingOn --include-all-app-icons --development-region en \
         --output-partial-info-plist "$BUILD/icon-partial.plist" >"$BUILD/actool.log" 2>&1 \
       && [ -f "$BUILD/icon-out/Assets.car" ]; then
      ICON_NAME=$(/usr/bin/plutil -extract CFBundleIconName raw "$BUILD/icon-partial.plist" 2>/dev/null || echo WhatsGoingOn)
      cp "$BUILD/icon-out/Assets.car" "$APP/Contents/Resources/"
      plist_set CFBundleIconName "$ICON_NAME"
      ICON_TIER="liquid-glass"
      if swiftc -O -swift-version 5 tools/icon-check/main.swift tools/icon-check/IconMetrics.swift -o "$BUILD/icon-check" \
           >>"$BUILD/actool.log" 2>&1; then
        ICON_CHECK=$("$BUILD/icon-check" "$APP" "$BUILD/icon-out" "$BUILD" 2>>"$BUILD/actool.log") && rc=0 || rc=$?
        if [ "$rc" -eq 1 ]; then
          echo "Icona Liquid Glass vuota ($ICON_CHECK): uso l'icona classica. Anteprime in $BUILD/icon-preview.png."
          rm -f "$APP/Contents/Resources/Assets.car"
          /usr/bin/plutil -remove CFBundleIconName "$PLIST"
          ICON_TIER=classic
        elif [ "$rc" -ne 0 ]; then
          ICON_CHECK="controllo non riuscito: $ICON_CHECK"
        fi
      else
        ICON_CHECK="controllo non compilato (dettagli in $BUILD/actool.log)"
      fi
    else
      echo "Icona Liquid Glass non compilata (dettagli in $BUILD/actool.log): uso l'icona classica."
    fi
  else
    echo "actool non trovato (serve Xcode): icona classica."
  fi
fi

# Dati per la diagnostica e per gli aggiornamenti (Sources/App/Diagnostics.swift, Sources/App/Updater.swift).
plist_set WGOGitCommit "$COMMIT"
plist_set WGOIconTier "$ICON_TIER"
[ -n "$ICON_CHECK" ] && plist_set WGOIconCheck "$ICON_CHECK"
[ "$MODE" = dmg ] || plist_set WGOSourcePath "$PWD"
plutil -lint "$PLIST" >/dev/null
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Pronto: $APP ($VERSION, build $BUILD_NUMBER, commit $COMMIT, icona $ICON_TIER${ICON_CHECK:+: $ICON_CHECK})"

case "$MODE" in
  install)
    /usr/bin/pkill -x "$EXE" 2>/dev/null || true
    rm -rf "/Applications/$NAME.app"
    cp -R "$APP" "/Applications/$NAME.app"
    # Il Finder tiene in cache l'icona vecchia: registra di nuovo l'app.
    touch "/Applications/$NAME.app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
      -f "/Applications/$NAME.app" 2>/dev/null || true
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
