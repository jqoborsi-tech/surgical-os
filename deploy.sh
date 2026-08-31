#!/bin/bash
# Deploy the encrypted Surgical OS to GitHub Pages.
#
#   ./deploy.sh                  find the newest encrypted file in ~/Downloads
#   ./deploy.sh <file>           deploy a specific file
#   ./deploy.sh --force <file>   deploy even if the build stamp is stale
#
# Two guards, both learned the hard way:
#   1. the browser saves as "index (2).html" when index.html already exists,
#      so never assume the filename
#   2. an encrypted file made from an OLD protect page silently publishes the
#      OLD app — the build stamp catches that
set -e
APP="$HOME/Documents/surgical-os/app/index.html"

# A ~12 MB push over HTTPS fails with "RPC failed; HTTP 400" on git's 1 MB default
# buffer. Set per-repo so the push does not silently leave the commit unpushed.
git -C "$(dirname "$0")" config http.postBuffer 524288000
git -C "$(dirname "$0")" config http.version HTTP/1.1

FORCE=0
[ "$1" = "--force" ] && { FORCE=1; shift; }

SRC="$1"
if [ -z "$SRC" ]; then
  # newest .html in Downloads that actually looks like our encrypted build
  SRC=$(ls -t "$HOME"/Downloads/*.html 2>/dev/null | while IFS= read -r f; do
          if grep -q '"ct"' "$f" 2>/dev/null && ! grep -q 'window.SX' "$f" 2>/dev/null; then
            echo "$f"; fi
        done | head -1)
  [ -n "$SRC" ] && echo "→ using newest encrypted file: $SRC"
fi

if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
  echo "❌ No encrypted build found."
  echo "   Open protect-surgical-os.html, set your passphrase, and it downloads one."
  echo "   Then re-run this, or pass the path:  ./deploy.sh \"\$HOME/Downloads/index (2).html\""
  exit 1
fi

# must be encrypted, must not leak plaintext
if ! grep -q '"ct"' "$SRC" || grep -q 'window.SX' "$SRC"; then
  echo "❌ REFUSING: $SRC is not the encrypted build."
  exit 1
fi

# must match the app currently on disk
if [ -f "$APP" ]; then
  EXPECT=$(python3 - "$APP" <<'PY'
import os,sys,time
st=os.stat(sys.argv[1])
print(time.strftime("%Y%m%d-%H%M",time.localtime(st.st_mtime))+"-%.2fMB"%(st.st_size/1048576))
PY
)
  ACTUAL=$(grep -o 'name="sx-build" content="[^"]*"' "$SRC" | head -1 | sed 's/.*content="//;s/"//')
  if [ "$ACTUAL" != "$EXPECT" ]; then
    echo "⚠️  STALE BUILD"
    echo "     encrypted file : ${ACTUAL:-<no build stamp — made by an old protect page>}"
    echo "     app on disk    : $EXPECT"
    echo "   That file does NOT contain your current app."
    echo "   Re-run protect-surgical-os.html (regenerate it first if the app changed), then deploy."
    [ "$FORCE" -eq 1 ] || exit 1
    echo "   --force given, deploying the stale file anyway."
  else
    echo "✓ build stamp matches app on disk ($EXPECT)"
  fi
fi

cd "$(dirname "$0")"
cp "$SRC" index.html
SIZE=$(du -h index.html | cut -f1)
git add index.html
git commit -m "Deploy Surgical OS ($SIZE, encrypted)" --quiet || { echo "no changes to deploy"; exit 0; }
git push || { echo "❌ PUSH FAILED — commit is local only. Fix the error above and re-run."; exit 1; }
echo "✅ Deployed ($SIZE). Live in ~1 min at:"
echo "   https://jqoborsi-tech.github.io/surgical-os/"
