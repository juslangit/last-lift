#!/usr/bin/env bash
## Publish the web build everywhere players get it. Run after every change to the game:
##   ./tools/publish_web.sh
## 1. exports the Web preset to build/web
## 2. pushes it to the gh-pages branch  -> https://juslangit.github.io/last-lift/
## 3. pushes it to itch.io with butler   -> https://juslangit.itch.io/last-lift  (channel html5)
## Needs GITHUB_TOKEN in ~/.claude/.env and a logged-in butler (~/.local/bin/butler).
set -euo pipefail
cd "$(dirname "$0")/.."
G="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
BUTLER="${BUTLER:-$HOME/.local/bin/butler}"
set -a; source "$HOME/.claude/.env"; set +a
VER="$(git rev-parse --short HEAD)$(git diff --quiet || echo -dirty)"

echo "== export ($VER)"
rm -rf build/web && mkdir -p build/web
"$G" --headless --path . --export-release "Web" build/web/index.html > /dev/null 2>&1
[ -s build/web/index.wasm ] || { echo "export failed"; exit 1; }
(cd build/web && rm -f ../last-lift-web.zip && zip -qr ../last-lift-web.zip .)

echo "== GitHub Pages"
TMP="$(mktemp -d)"
cp -R build/web/. "$TMP/" && touch "$TMP/.nojekyll"
git -C "$TMP" init -q -b gh-pages
git -C "$TMP" -c user.email=luqmanh1891@gmail.com -c user.name=juslangit add -A
git -C "$TMP" -c user.email=luqmanh1891@gmail.com -c user.name=juslangit commit -q -m "Web build $VER"
git -C "$TMP" -c "credential.helper=!f() { echo username=juslangit; echo password=$GITHUB_TOKEN; }; f" \
	push -q -f https://github.com/juslangit/last-lift.git gh-pages
rm -rf "$TMP"

echo "== itch.io"
"$BUTLER" push build/web juslangit/last-lift:html5 --userversion "$VER"
echo "done: $VER is going live on GitHub Pages and itch.io (both take a minute or two)"
