#!/usr/bin/env bash
# Render HTML/Markdown/URL to a reMarkable-sized PDF with e-ink typography.
# Usage: render.sh <input.html|input.md|URL> <output.pdf>
# Exit: 3 unsupported input, 4 render failed
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$HERE/eink.css"

[ $# -eq 2 ] || { echo "usage: render.sh <input.html|input.md|URL> <output.pdf>" >&2; exit 3; }
SRC="$1"; OUT="$2"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

find_chrome() {
  local c
  for c in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
  do [ -x "$c" ] && { echo "$c"; return 0; }; done
  for c in google-chrome google-chrome-stable chromium chromium-browser brave-browser; do
    command -v "$c" >/dev/null && { command -v "$c"; return 0; }
  done
  # Playwright's headless shell, newest first. Cache lives under ~/Library on
  # macOS and ~/.cache on linux; the inner dir is named per platform.
  c="$(ls -d "$HOME"/Library/Caches/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell \
              "$HOME"/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux/headless_shell \
              "$HOME"/.cache/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell \
       2>/dev/null | sort -V | tail -1)"
  [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  return 1
}

# 1. Get the source as HTML in $TMP/in.html
case "$SRC" in
  http://*|https://*)
    curl -fsSL --max-time 30 "$SRC" -o "$TMP/in.html" 2>"$TMP/curl.log" \
      || { echo "render: could not fetch $SRC — $(tail -1 "$TMP/curl.log")" >&2; exit 4; }
    ;;
  *.md|*.markdown)
    [ -f "$SRC" ] || { echo "render: no such file: $SRC" >&2; exit 3; }
    command -v uvx >/dev/null \
      || { echo "render: markdown input needs uv (brew install uv), or pass HTML" >&2; exit 4; }
    uvx --quiet --from markdown==3.11 markdown_py \
        -x extra -x sane_lists -x smarty "$SRC" > "$TMP/body.html" 2>"$TMP/md.log" \
      || { echo "render: markdown conversion failed — $(tail -1 "$TMP/md.log")" >&2; exit 4; }
    TITLE="$(basename "${SRC%.*}")"
    { printf '<!doctype html><html lang="nb"><head><meta charset="utf-8"><title>%s</title></head><body>\n' "$TITLE"
      cat "$TMP/body.html"
      printf '\n</body></html>\n'; } > "$TMP/in.html"
    ;;
  *.html|*.htm)
    [ -f "$SRC" ] || { echo "render: no such file: $SRC" >&2; exit 3; }
    cp "$SRC" "$TMP/in.html"
    ;;
  *)
    echo "render: unsupported input '$SRC' (want .html, .md, or a URL)" >&2; exit 3 ;;
esac

# 2. Inject the e-ink stylesheet last so it overrides the document's own CSS.
CSS_PATH="$CSS" python3 - "$TMP/in.html" "$TMP/styled.html" <<'PY'
import os, re, sys
src, dst = sys.argv[1], sys.argv[2]
html = open(src, encoding="utf-8", errors="replace").read()
style = "<style>\n" + open(os.environ["CSS_PATH"], encoding="utf-8").read() + "\n</style>"
if not re.search(r"<meta[^>]+charset", html, re.I):
    style = '<meta charset="utf-8">' + style
# Last stylesheet in <head> wins on equal specificity; fall back to prepending.
if re.search(r"</head\s*>", html, re.I):
    html = re.sub(r"</head\s*>", style + "</head>", html, count=1, flags=re.I)
else:
    html = style + html
open(dst, "w", encoding="utf-8").write(html)
PY

# 3. Print to PDF.
CHROME="$(find_chrome)" || {
  echo "render: no Chrome/Chromium found. Install Google Chrome, or run: npx playwright install chromium" >&2
  exit 4
}
# A fresh profile and HOME per run: a service user may have no writable home, and
# two renders sharing the default profile crash each other.
HOME="$TMP" "$CHROME" --headless --disable-gpu --no-sandbox --no-pdf-header-footer \
          --user-data-dir="$TMP/chrome" --virtual-time-budget=10000 \
          --print-to-pdf="$OUT" "file://$TMP/styled.html" >"$TMP/chrome.log" 2>&1 \
  || { echo "render: chrome failed — $(tail -1 "$TMP/chrome.log")" >&2; exit 4; }

[ -s "$OUT" ] || { echo "render: produced an empty PDF" >&2; exit 4; }
