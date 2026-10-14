#!/usr/bin/env bash
# Send a document to the reMarkable cloud: here -> tablet. read.sh goes the other way.
# Usage: send.sh <file> [--name "Title"] [--tag <name>] [--folder /Claude] [--no-date]
#                        [--replace] [--preview]
# --preview renders every page at the tablet's 226 DPI and prints the PNGs; no upload.
# --replace deletes earlier versions (same title, with or without date) first.
#        send.sh --auth <one-time-code>     # one-time pairing
# Names get a "YYYY-MM-DD " prefix so sorting by name on the tablet reads
# chronologically. Pass --no-date to skip it. --tag sets real reMarkable
# document tags; ~/.config/remarkable/tags can map a name to several.
# Exit: 2 not authenticated, 3 bad input, 4 render failed, 5 upload rejected
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RMAPI="$HERE/bin/rmapi"
RMAPI_VERSION="v0.0.35"
# sha256 per asset, as listed on the GitHub release. A new version: change all four.
rmapi_sha256() {
  case "$1" in
    rmapi-macos-arm64.zip)    echo fb55b6c782b83dc0ccbb236359d738727c4c600378feae920fcab505862f624a ;;
    rmapi-macos-intel.zip)    echo 1afc2c4d73ddde60e22e0ff8d2bc737450dfcaeaa723eb6a3b863ac96cb2102c ;;
    rmapi-linux-amd64.tar.gz) echo 117616151d11937446ead6972b0934f97155443087f8406141db38fd1ac8fb25 ;;
    rmapi-linux-arm64.tar.gz) echo 645c170d8119b4dcb652cf79612e362fcb032dc0e5869ff520eec1324da39637 ;;
  esac
}

ensure_rmapi() {
  # bin/rmapi.version records what was downloaded, so raising RMAPI_VERSION is
  # enough: the next run fetches the new build.
  [ -x "$RMAPI" ] && [ "$(cat "$RMAPI.version" 2>/dev/null)" = "$RMAPI_VERSION" ] && return 0
  mkdir -p "$HERE/bin"
  # The binary is gitignored, so it self-downloads per machine — this repo is
  # shared between a mac and a linux box.
  local asset dl tmp
  case "$(uname -s)/$(uname -m)" in
    Darwin/arm64)         asset="rmapi-macos-arm64.zip" ;;
    Darwin/x86_64)        asset="rmapi-macos-intel.zip" ;;
    Linux/x86_64)         asset="rmapi-linux-amd64.tar.gz" ;;
    Linux/aarch64|Linux/arm64) asset="rmapi-linux-arm64.tar.gz" ;;
    *) echo "send: no rmapi build for $(uname -s)/$(uname -m)" >&2; return 1 ;;
  esac
  tmp="$(mktemp -d)"; dl="$tmp/$asset"
  echo "send: fetching rmapi $RMAPI_VERSION for $(uname -s)..." >&2
  curl -fsSL --max-time 120 \
    "https://github.com/ddvk/rmapi/releases/download/$RMAPI_VERSION/$asset" -o "$dl" \
    || { echo "send: could not download rmapi" >&2; return 1; }
  local sum; sum="$( (sha256sum "$dl" 2>/dev/null || shasum -a 256 "$dl") | cut -d' ' -f1)"
  [ "$sum" = "$(rmapi_sha256 "$asset")" ] \
    || { echo "send: checksum mismatch for $asset — not installing it" >&2; rm -rf "$tmp"; return 1; }
  case "$asset" in
    *.zip)    unzip -o -q -d "$HERE/bin" "$dl" ;;
    *.tar.gz) tar -xzf "$dl" -C "$HERE/bin" ;;
  esac || { echo "send: could not unpack rmapi" >&2; return 1; }
  chmod +x "$RMAPI"
  echo "$RMAPI_VERSION" > "$RMAPI.version"
  rm -rf "$tmp"
}

# --- auth ---------------------------------------------------------------
if [ "${1:-}" = "--auth" ]; then
  [ -n "${2:-}" ] || {
    echo "Get a one-time code at https://my.remarkable.com/device/browser/connect" >&2
    echo "then run: send.sh --auth <code>" >&2; exit 2; }
  ensure_rmapi || exit 2
  echo "$2" | "$RMAPI" ls / >/dev/null 2>&1 \
    || { echo "send: pairing failed — code may be expired or already used" >&2; exit 2; }
  case "$(uname -s)" in
    Darwin) conf="$HOME/Library/Application Support/rmapi/rmapi.conf" ;;
    *)      conf="${XDG_CONFIG_HOME:-$HOME/.config}/rmapi/rmapi.conf" ;;
  esac
  echo "paired. token stored in ${RMAPI_CONFIG:-$conf}"
  exit 0
fi

# --- args ---------------------------------------------------------------
SRC=""; NAME=""; FOLDER="/Claude"; DATED=1; TAG=""; REPLACE=0; PREVIEW=0
while [ $# -gt 0 ]; do
  case "$1" in
    --name)    NAME="${2:-}"; shift 2 ;;
    --folder)  FOLDER="${2:-}"; shift 2 ;;
    --tag)     TAG="${2:-}"; shift 2 ;;
    --no-date) DATED=0; shift ;;
    --replace) REPLACE=1; shift ;;
    --preview) PREVIEW=1; shift ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "send: unknown flag $1" >&2; exit 3 ;;
    *)  [ -z "$SRC" ] && SRC="$1" || { echo "send: one input at a time" >&2; exit 3; }; shift ;;
  esac
done
[ -n "$SRC" ] || { echo "usage: send.sh <file.pdf|file.html|file.md|URL> [--name \"Title\"] [--tag <name>]" >&2; exit 3; }
case "$FOLDER" in /*) ;; *) FOLDER="/$FOLDER" ;; esac

# Real reMarkable document tags. The vocabulary is personal, so it lives outside
# the repo: one line per name, "<name> <tag>...", the name and the tags it sets
# ("kunde kunde jobb" makes --tag kunde set both). With the file, only listed
# names are accepted. Without it, --tag sets the name as a single tag.
TAGS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/remarkable/tags"
# An array, so a tag with a space stays one tag and "*" is never globbed.
TAGS=()
if [ -n "$TAG" ] && [ -f "$TAGS_FILE" ]; then
  vocab() { sed 's/#.*//' "$TAGS_FILE"; }   # comments may follow a line or fill it
  read -ra TAGS <<< "$(vocab | awk -v t="$TAG" 'tolower($1) == tolower(t) {
    n = $1; $1 = ""; sub(/^ +/, ""); print ($0 == "" ? n : $0); exit }')"
  [ "${#TAGS[@]}" -gt 0 ] || {
    echo "send: unknown tag '$TAG' (want one of: $(vocab | awk 'NF { print $1 }' | paste -sd, -))" >&2
    exit 3; }
elif [ -n "$TAG" ]; then
  TAGS=("$TAG")
fi

ensure_rmapi || exit 2

# --- auth check ---------------------------------------------------------
"$RMAPI" -ni ls / >/dev/null 2>&1 || {
  echo "send: not paired. Get a code at https://my.remarkable.com/device/browser/connect" >&2
  echo "      then run: $0 --auth <code>" >&2; exit 2; }

# --- produce a PDF ------------------------------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# reMarkable takes the document name from the filename, so name the file.
if [ -z "$NAME" ]; then
  case "$SRC" in
    http://*|https://*) NAME="$(basename "${SRC%%\?*}")"; NAME="${NAME%.*}"; [ -n "$NAME" ] || NAME="web" ;;
    *) NAME="$(basename "${SRC%.*}")" ;;
  esac
fi
NAME="$(printf '%s' "$NAME" | tr '/' '-')"

# "YYYY-MM-DD Title" — sorting by name on the tablet then reads chronologically.
if [ "$DATED" = 1 ]; then
  case "$NAME" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ *) ;;   # caller already dated it
    *) NAME="$(date +%F) $NAME" ;;
  esac
fi

PDF="$TMP/$NAME.pdf"

case "$SRC" in
  *.pdf)
    [ -f "$SRC" ] || { echo "send: no such file: $SRC" >&2; exit 3; }
    cp "$SRC" "$PDF" ;;                      # already native — upload as-is
  *)
    "$HERE/render.sh" "$SRC" "$PDF" || exit $? ;;
esac

# --- preview: look at every page as the tablet will show it --------------
if [ "$PREVIEW" = 1 ]; then
  OUT="${TMPDIR:-/tmp}/remarkable-preview/$NAME"; rm -rf "$OUT"; mkdir -p "$OUT"
  pdftoppm -r 226 -png "$PDF" "$OUT/page" || { echo "send: preview render failed" >&2; exit 4; }
  echo "preview of \"$NAME\" ($(ls "$OUT" | wc -l | tr -d ' ') pages at 226 DPI, not uploaded):"
  ls "$OUT"/*.png
  exit 0
fi

# --- upload -------------------------------------------------------------
# Create each level in turn — mkdir does not make parents. Already-exists: fine.
ACC=""
IFS='/' read -ra PARTS <<< "${FOLDER#/}"
for p in "${PARTS[@]}"; do
  [ -n "$p" ] || continue
  ACC="$ACC/$p"
  "$RMAPI" -ni mkdir "$ACC" >/dev/null 2>&1 || true
done

# rmapi rebuilds .content for a bare PDF and drops tags, but uploads .rmdoc
# archives verbatim — so a tagged document has to be wrapped first. It takes the
# document name from the filename either way.
# --replace: remove earlier versions — same title with or without a date
# prefix, in this folder only. Found by id in the refreshed tree, removed by path.
if [ "$REPLACE" = 1 ]; then
  "$RMAPI" -ni refresh >/dev/null 2>&1 || true
  CACHE=""
  for c in "$HOME/Library/Caches/rmapi/tree.cache" "${XDG_CACHE_HOME:-$HOME/.cache}/rmapi/tree.cache"; do
    [ -f "$c" ] && { CACHE="$c"; break; }
  done
  [ -n "$CACHE" ] && python3 - "$CACHE" "$FOLDER" "$NAME" <<'PY' | sort -u | while IFS= read -r old; do
import json, re, sys
cache, folder, name = sys.argv[1:]
undated = lambda n: re.sub(r"^\d{4}-\d{2}-\d{2} ", "", n)
docs = json.load(open(cache))["Docs"]
by_id = {d["DocumentID"]: d for d in docs}
def path(d):
    parts = []
    while d:
        parts.append(d["Metadata"]["visibleName"]); d = by_id.get(d["Metadata"]["parent"])
    return "/" + "/".join(reversed(parts))
def alive(d):  # as in read.sh: a folder in the trash takes its documents with it
    while d:
        if d["Metadata"]["parent"] == "trash" or d["Metadata"].get("deleted"):
            return False
        d = by_id.get(d["Metadata"]["parent"])
    return True
for d in docs:
    m = d["Metadata"]
    if m["type"] == "DocumentType" and alive(d) \
       and path(d).rsplit("/", 1)[0] == folder.rstrip("/") and undated(m["visibleName"]) == undated(name):
        print(m["visibleName"])
PY
    "$RMAPI" -ni rm "$FOLDER/$old" >/dev/null 2>&1 \
      && echo "replaced: removed \"$old\"" || echo "send: could not remove \"$old\"" >&2
  done
fi

UPLOAD="$PDF"
if [ "${#TAGS[@]}" -gt 0 ]; then
  UPLOAD="$TMP/$NAME.rmdoc"
  python3 "$HERE/mkrmdoc.py" "$PDF" "$UPLOAD" "$NAME" "${TAGS[@]}" >/dev/null \
    || { echo "send: could not build .rmdoc wrapper" >&2; exit 4; }
fi

"$RMAPI" -ni put "$UPLOAD" "$FOLDER" >"$TMP/put.log" 2>&1 \
  || { echo "send: upload rejected — $(tail -1 "$TMP/put.log")" >&2; exit 5; }

if [ "${#TAGS[@]}" -gt 0 ]; then
  LIST="$(printf '%s, ' "${TAGS[@]}")"
  echo "sent \"$NAME\" to $FOLDER tagged [${LIST%, }] — sync the tablet over wifi to see it"
else
  echo "sent \"$NAME\" to $FOLDER — sync the tablet over wifi to see it"
fi
