#!/usr/bin/env bash
# Repeatable web bundle builder (bos114). web/ -> dist/ (minified, core bundle + lazy screens, ?v=<hash>, service-worker precache list), optional sync into the public GitHub Pages repo.
#   tools/build_web.sh                      build into ./dist
#   tools/build_web.sh --out DIR            build into DIR
#   tools/build_web.sh --minify-only        same files/tags as web/, only minified (equivalence check for the minifier)
#   tools/build_web.sh --to PUBLIC_REPO     build, then copy dist/ into the public repo checkout (a pages/* branch, never main). Same protections as make_bundle.sh:
#                                           config.js is NEVER overwritten (and must equal web/config.js), setup-*.html / audit-a.html / PUBLISH_NOTES.md / DEPLOY_CHECKLIST.md / CNAME / .nojekyll / .git stay,
#                                           files that vanished from web/ are removed, node-style files, conflict markers, secrets and missing references abort. Never pushes.
# Needs: node, and terser + esbuild (found in /opt/node-tools/node_modules, tools/node_modules or ~/.cache/bos-build; installed there with npm on first use).
# Same input => same output bytes; ?v= is the hash of each file's own content, so a deploy changes only the URLs of files that changed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(dirname "$HERE")"
OUT="$REPO/dist"; TO=""; EXTRA=()
while [ $# -gt 0 ]; do case "$1" in --out) OUT="$(readlink -f "$2")"; shift 2;; --to) TO="$2"; shift 2;; --minify-only) EXTRA+=(--minify-only); shift;; --no-stamp) EXTRA+=(--no-stamp); shift;; --no-minify) EXTRA+=(--no-minify); shift;; *) echo "unknown option $1"; exit 64;; esac; done
have_nm() { [ -d "$1/terser" ] && [ -d "$1/esbuild" ]; }
NM=""; for d in "${WEB_BUILD_NM:-}" /opt/node-tools/node_modules "$HERE/node_modules" "$HOME/.cache/bos-build/node_modules"; do [ -n "$d" ] && have_nm "$d" && NM="$d" && break; done
if [ -z "$NM" ]; then echo "installing terser + esbuild into ~/.cache/bos-build (once)"; npm install --silent --no-audit --no-fund --prefix "$HOME/.cache/bos-build" terser esbuild acorn >/dev/null; NM="$HOME/.cache/bos-build/node_modules"; fi
export WEB_BUILD_NM="$NM"
if [ -n "$TO" ]; then
  BR="$(git -C "$TO" rev-parse --abbrev-ref HEAD)"; [ "$BR" != "main" ] && [ "$BR" != "master" ] || { echo "ABORT: $TO is on $BR; checkout a pages/* branch first"; exit 2; }
  [ -z "$(git -C "$REPO" status --porcelain -- web)" ] || { echo "ABORT: web/ has uncommitted changes"; exit 2; }
  cmp -s "$REPO/web/config.js" "$TO/config.js" || { echo "ABORT: config.js differs between web/ and the public repo. Not copying. Review by hand."; diff "$REPO/web/config.js" "$TO/config.js" | sed 's/eyJ[A-Za-z0-9._-]*/eyJ…/g' | head -20; exit 3; }
fi
node "$HERE/web_build.js" --src "${WEB_SRC_OVERRIDE:-$REPO/web}" --out "$OUT" "${EXTRA[@]}"
[ -z "$TO" ] && { echo "dist ready: $OUT"; exit 0; }

# ---------------- sync into the public repo (same rules as make_bundle.sh) ----------------
DEST="$TO"; BUILD="$(cat "$OUT/.build-id")"
PROTECT_RE='^(setup-[^/]*\.html|audit-a\.html|PUBLISH_NOTES\.md|DEPLOY_CHECKLIST\.md|CNAME|\.nojekyll|\.git(/.*)?|config\.js)$'
LIST="$(mktemp)"; trap 'rm -f "$LIST" "$LIST.dest"' EXIT
( cd "$OUT" && find . -type f | sed 's|^\./||' | LC_ALL=C sort ) | grep -vE '^\.build-id$' > "$LIST"
ADD=0; CHG=0; DEL=0; SAME=0
while IFS= read -r f; do
  [ "$f" = "config.js" ] && continue
  mkdir -p "$DEST/$(dirname "$f")"
  if [ ! -e "$DEST/$f" ]; then ADD=$((ADD+1)); cp -p "$OUT/$f" "$DEST/$f"
  elif cmp -s "$OUT/$f" "$DEST/$f"; then SAME=$((SAME+1))
  else CHG=$((CHG+1)); cp -p "$OUT/$f" "$DEST/$f"; fi
done < "$LIST"
( cd "$DEST" && find . -type f -not -path './.git/*' | sed 's|^\./||' | LC_ALL=C sort ) > "$LIST.dest"
while IFS= read -r f; do
  echo "$f" | grep -qE "$PROTECT_RE" && continue
  grep -qxF "$f" "$LIST" && continue
  rm -f "$DEST/$f"; DEL=$((DEL+1)); echo "removed (gone from web/): $f"
done < "$LIST.dest"
FAIL=0; bad(){ echo "FAIL: $*"; FAIL=1; }
cd "$DEST"
for f in $(git ls-files -co --exclude-standard | grep -E '\.js$'); do node --check "$f" 2>/dev/null || bad "node --check $f"; done
if grep -rnE '^(<<<<<<< |=======$|>>>>>>> )' --exclude-dir=.git . | grep -v 'vendor/'; then bad "conflict markers (above)"; fi
grep -rnIoE 'service_role|sb_secret' --exclude-dir=.git --exclude='setup-*.html' --exclude=audit-a.html --exclude=PUBLISH_NOTES.md --exclude=DEPLOY_CHECKLIST.md . | sort | uniq -c | sed 's/^/INFO keyword mention: /' || true
if grep -rnIE 'sb_secret_[A-Za-z0-9_-]{16,}|sk-ant-[A-Za-z0-9_-]{16,}|sk_live_[A-Za-z0-9]{10,}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY|bot[0-9]{6,}:[A-Za-z0-9_-]{30,}' --exclude-dir=.git . | cut -c1-120; then bad "secret value (above)"; fi
if grep -rnIlE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' --exclude-dir=.git . | grep -vE '^\./(setup-|audit-a)'; then bad "JWT-like token (files above)"; fi
cmp -s config.js "$REPO/web/config.js" || bad "config.js differs from web/"
if [ -f PUBLISH_NOTES.md ] && ! grep -q '^## Web bundle (pages/web-bundle)' PUBLISH_NOTES.md; then
python3 - <<'PY'
s=open('PUBLISH_NOTES.md',encoding='utf-8').read()
sec="""
## Web bundle (pages/web-bundle)

The web app files at the repo root (core.js, lazy screen scripts, app.css, index.html, sw.js) were built from My-tools `web/` by `tools/build_web.sh`, which never touches `config.js`, `setup-*.html`, `audit-a.html` or this file. Every file is loaded with `?v=<its content hash>` and `sw.js` has a matching VERSION, so phones never mix old and new files. Screens other than Home and POS are fetched when first opened.
"""
a,b=s.split('\n',1)
open('PUBLISH_NOTES.md','w',encoding='utf-8').write(a+'\n'+sec+b)
PY
fi
echo "web: $(git -C "$REPO" rev-parse --abbrev-ref HEAD) @ $(git -C "$REPO" rev-parse --short HEAD)   build: $BUILD"
echo "added=$ADD changed=$CHG unchanged=$SAME removed=$DEL   (config.js untouched, protected files kept)"
[ "$FAIL" = 0 ] && echo "STATIC CHECKS: PASS" || { echo "STATIC CHECKS: FAIL"; exit 5; }
