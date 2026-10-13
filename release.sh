#!/bin/zsh
# Pubblica una versione, come Nod:
#   1. ./build.sh --dmg
#   2. release GitHub v<versione> con il DMG e le note prese da CHANGELOG.md (serve `gh auth login`)
#   3. aggiorna version e sha256 del cask, qui e nel clone del tap, e lo pubblica
# Prima: aumenta VERSION e aggiungi in cima a CHANGELOG.md la sezione "## <versione> · <data>".
# Repo (cambiabili): WGO_APP_REPO=GGuidotz/whats-going-on  WGO_TAP_DIR=~/Developer/homebrew-tap
set -euo pipefail
cd "${0:A:h}"
die() { echo "$*" >&2; exit 1; }

APP_REPO=${WGO_APP_REPO:-GGuidotz/whats-going-on}
TAP_DIR=${WGO_TAP_DIR:-$HOME/Developer/homebrew-tap}
VERSION=$(tr -d '[:space:]' < VERSION)
CASK=packaging/homebrew/Casks/whats-going-on.rb

command -v gh >/dev/null || die "Serve GitHub CLI: brew install gh && gh auth login"
[ -z "$(git status --porcelain -- .)" ] || die "Ci sono modifiche non salvate in git: fai prima il commit."
gh release view "v$VERSION" --repo "$APP_REPO" >/dev/null 2>&1 && die "La release v$VERSION esiste già: aumenta VERSION."

./build.sh --dmg
DMG="dist/WhatsGoingOn-$VERSION.dmg"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
NOTES=$(awk -v v="$VERSION" '$0 ~ "^## "v" " {f=1; next} /^## / {f=0} f' CHANGELOG.md)

gh release create "v$VERSION" "$DMG" --repo "$APP_REPO" --title "What's Going On $VERSION" --notes "$NOTES"

sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
git add "$CASK" && git commit -m "Cask whats-going-on $VERSION" -- "$CASK" >/dev/null || true
git push || true

if [ -d "$TAP_DIR/.git" ]; then
  git -C "$TAP_DIR" pull --ff-only
  mkdir -p "$TAP_DIR/Casks"
  cp "$CASK" "$TAP_DIR/Casks/whats-going-on.rb"
  git -C "$TAP_DIR" add Casks/whats-going-on.rb
  git -C "$TAP_DIR" commit -m "whats-going-on $VERSION" >/dev/null
  git -C "$TAP_DIR" push
  echo "Tap aggiornato."
else
  echo "Tap non trovato in $TAP_DIR: copia a mano $CASK in Casks/ del repo homebrew-tap."
fi
echo "Pubblicato What's Going On $VERSION. Installazione: brew install --cask gguidotz/tap/whats-going-on"
