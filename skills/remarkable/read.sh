#!/usr/bin/env bash
# Read a document off the reMarkable cloud: every page with ink becomes a PNG.
# Usage: read.sh <name|/path|uuid> [--out DIR] [--all]
#        read.sh --list [folder]          # names, ids and types, e.g. --list /Claude
# <name> matches the visible name exactly (case-insensitive), then as a
# substring. Names with "/" in them work: lookup goes by document id.
# PDFs come back with the ink drawn on the page (rmapi geta); notebooks come
# back as the strokes alone. --all renders every page, not just marked ones.
# Exit: 2 not paired, 3 no match or ambiguous, 4 render failed
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RMAPI="$HERE/bin/rmapi"

# --- args ---------------------------------------------------------------
Q=""; OUT=""; ALL=0; LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out)  OUT="${2:-}"; shift 2 ;;
    --all)  ALL=1; shift ;;
    --list) LIST=1; shift ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "read: unknown flag $1" >&2; exit 3 ;;
    *)  [ -z "$Q" ] && Q="$1" || { echo "read: one document at a time" >&2; exit 3; }; shift ;;
  esac
done
[ "$LIST" = 1 ] || [ -n "$Q" ] || { echo "usage: read.sh <name|/path|uuid> [--out DIR] [--all]" >&2; exit 3; }

# send.sh owns the download of rmapi and the pairing; this only reads.
[ -x "$RMAPI" ] && "$RMAPI" -ni ls / >/dev/null 2>&1 || {
  echo "read: not paired. Get a code at https://my.remarkable.com/device/browser/connect" >&2
  echo "      then run: $HERE/send.sh --auth <code>" >&2; exit 2; }

# The local tree goes stale (see SKILL.md), so refresh before trusting it.
"$RMAPI" -ni refresh >/dev/null 2>&1 || true
CACHE=""
for c in "$HOME/Library/Caches/rmapi/tree.cache" "${XDG_CACHE_HOME:-$HOME/.cache}/rmapi/tree.cache"; do
  [ -f "$c" ] && { CACHE="$c"; break; }
done
[ -n "$CACHE" ] || { echo "read: no rmapi tree cache found" >&2; exit 3; }

# --- resolve: prints "id<TAB>type<TAB>path<TAB>name", or a candidate list and exit 3 --
resolve() {
  python3 - "$CACHE" "$1" "$2" <<'PY'
import json, re, sys
cache, q, mode = sys.argv[1], sys.argv[2], sys.argv[3]
docs = json.load(open(cache))["Docs"]
by_id = {d["DocumentID"]: d for d in docs}

def path(d):
    parts = []
    while d:
        parts.append(d["Metadata"]["visibleName"])
        d = by_id.get(d["Metadata"]["parent"])
    return "/" + "/".join(reversed(parts))

def alive(d):
    seen = d
    while seen:
        if seen["Metadata"]["parent"] == "trash" or seen["Metadata"].get("deleted"):
            return False
        seen = by_id.get(seen["Metadata"]["parent"])
    return True

files = [d for d in docs if d["Metadata"]["type"] == "DocumentType" and alive(d)]
kind = lambda d: (d.get("Content") or {}).get("fileType") or "?"
show = lambda d: f'{d["DocumentID"]}\t{kind(d)}\t{path(d)}'
row = lambda d: f'{show(d)}\t{d["Metadata"]["visibleName"]}'

if mode == "list":
    pre = q.rstrip("/")
    for d in sorted(files, key=path):
        if not pre or path(d).startswith(pre + "/"):
            print(show(d))
    sys.exit(0)

if re.fullmatch(r"[0-9a-f-]{36}", q) and q in by_id:
    print(row(by_id[q])); sys.exit(0)
ql = q.lower()
for test in (lambda d: path(d).lower() == ql,
             lambda d: d["Metadata"]["visibleName"].lower() == ql,
             lambda d: ql in path(d).lower()):
    hits = [d for d in files if test(d)]
    if len(hits) == 1:
        print(row(hits[0])); sys.exit(0)
    if hits:
        print(f"read: {len(hits)} documents match '{q}' — pass the id:", file=sys.stderr)
        for d in hits[:20]:
            print("  " + show(d), file=sys.stderr)
        sys.exit(3)
print(f"read: nothing matches '{q}'", file=sys.stderr)
sys.exit(3)
PY
}

if [ "$LIST" = 1 ]; then resolve "${Q:-}" list; exit 0; fi

HIT="$(resolve "$Q" find)" || exit 3
IFS=$'\t' read -r ID KIND DOCPATH NAME <<<"$HIT"
OUT="${OUT:-${TMPDIR:-/tmp}/remarkable-read/$ID}"
mkdir -p "$OUT"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# get --id saves under the visible name, so a "/" in it means a subdirectory.
[[ "$NAME" != */* ]] || mkdir -p "$WORK/${NAME%/*}"
(cd "$WORK" && "$RMAPI" -ni get --id "$ID" >/dev/null 2>&1) \
  || { echo "read: download failed for $ID" >&2; exit 4; }
RMDOC="$(find "$WORK" -name '*.rmdoc' | head -1)"
mkdir -p "$WORK/doc"; unzip -o -q "$RMDOC" -d "$WORK/doc"

# Page list in reading order: "<page number><TAB><.rm path or empty>".
# A layer under ~500 bytes is a page that was opened, not written on.
python3 - "$WORK/doc" "$ID" "$ALL" >"$WORK/pages" <<'PY'
import json, os, sys
root, doc_id, show_all = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
c = json.load(open(os.path.join(root, doc_id + ".content")))
pages = [p["id"] for p in c.get("cPages", {}).get("pages", []) if "deleted" not in p] or c.get("pages", [])
for n, pid in enumerate(pages, 1):
    rm = os.path.join(root, doc_id, pid + ".rm")
    inked = os.path.exists(rm) and os.path.getsize(rm) > 500
    if inked or show_all:
        print(f"{n}\t{rm if os.path.exists(rm) else ''}")
PY
[ -s "$WORK/pages" ] || { echo "read: '$DOCPATH' has no pages with ink (--all to render every page)"; exit 0; }

echo "$DOCPATH  ($KIND, $ID)"

# PDFs and EPUBs: geta draws the ink in the right place on the page, which
# hand-rolled overlay maths does not (SKILL.md). It only takes a path, so a
# name with "/" in it cannot go through geta — fall back to strokes alone.
if [ "$KIND" != notebook ] && [[ "$NAME" != */* ]]; then
  (cd "$WORK" && "$RMAPI" -ni geta "$DOCPATH" >/dev/null 2>&1) \
    || { echo "read: geta failed for $DOCPATH" >&2; exit 4; }
  PDF="$(find "$WORK" -maxdepth 1 -name '*-annotations.pdf' | head -1)"
  while IFS=$'\t' read -r n _; do
    pdftoppm -r 110 -png -singlefile -f "$n" -l "$n" "$PDF" "$OUT/page-$(printf %03d "$n")" \
      || { echo "read: could not render page $n" >&2; exit 4; }
    echo "page $n: $OUT/page-$(printf %03d "$n").png"
  done <"$WORK/pages"
  exit 0
fi

[ "$KIND" = notebook ] || echo "note: '/' in the name blocks geta — strokes only, without the page under them" >&2
while IFS=$'\t' read -r n rm; do
  png="$OUT/page-$(printf %03d "$n").png"
  [ -n "$rm" ] || { echo "page $n: (blank)"; continue; }
  # rmc follows the tablet's file format, so pin it; a new firmware may need a newer one.
  uvx -q --from rmc==0.3.0 rmc -t svg "$rm" -o "$WORK/p.svg" 2>/dev/null \
    || { echo "read: could not decode page $n" >&2; exit 4; }
  rsvg-convert -z 3 -b white "$WORK/p.svg" -o "$png" \
    || { echo "read: could not render page $n" >&2; exit 4; }
  # 1568 px on the long side is what a vision model reads; more only costs tokens.
  magick "$png" -trim +repage -bordercolor white -border 30 -resize '1568x1568>' "$png" 2>/dev/null || true
  echo "page $n: $png"
done <"$WORK/pages"
