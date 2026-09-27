#!/usr/bin/env bash
# Send a document to the reMarkable cloud: here -> tablet. read.sh goes the other way.
# Usage: send.sh <file> [--name "Title"] [--tag jobb|personlig|seeyou] [--folder /Claude] [--no-date]
#        send.sh --auth <one-time-code>     # one-time pairing
# Names get a "YYYY-MM-DD " prefix so sorting by name on the tablet reads
# chronologically. Pass --no-date to skip it. --tag sets real reMarkable
# document tags; seeyou implies jobb.
# Exit: 2 not authenticated, 3 bad input, 4 render failed, 5 upload rejected
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RMAPI="$HERE/bin/rmapi"
RMAPI_VERSION="v0.0.35"

ensure_rmapi() {
  [ -x "$RMAPI" ] && return 0
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
  case "$asset" in
    *.zip)    unzip -o -q -d "$HERE/bin" "$dl" ;;
    *.tar.gz) tar -xzf "$dl" -C "$HERE/bin" ;;
  esac || { echo "send: could not unpack rmapi" >&2; return 1; }
  chmod +x "$RMAPI"
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
  echo "paired. token stored in ~/Library/Application Support/rmapi"
  exit 0
fi

# --- args ---------------------------------------------------------------
SRC=""; NAME=""; FOLDER="/Claude"; DATED=1; TAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name)    NAME="${2:-}"; shift 2 ;;
    --folder)  FOLDER="${2:-}"; shift 2 ;;
    --tag)     TAG="${2:-}"; shift 2 ;;
    --no-date) DATED=0; shift ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "send: unknown flag $1" >&2; exit 3 ;;
    *)  [ -z "$SRC" ] && SRC="$1" || { echo "send: one input at a time" >&2; exit 3; }; shift ;;
  esac
done
[ -n "$SRC" ] || { echo "usage: send.sh <file.pdf|file.html|file.md|URL> [--name \"Title\"] [--tag jobb|personlig|seeyou]" >&2; exit 3; }
case "$FOLDER" in /*) ;; *) FOLDER="/$FOLDER" ;; esac

# Real reMarkable document tags. seeyou always implies jobb — SeeYou work is work.
TAGS=""
case "$(printf '%s' "$TAG" | tr 'A-Z' 'a-z')" in
  "")        ;;
  jobb)      TAGS="jobb" ;;
  personlig) TAGS="personlig" ;;
  seeyou)    TAGS="seeyou jobb" ;;
  *) echo "send: unknown tag '$TAG' (want jobb, personlig, or seeyou)" >&2; exit 3 ;;
esac

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
UPLOAD="$PDF"
if [ -n "$TAGS" ]; then
  UPLOAD="$TMP/$NAME.rmdoc"
  python3 "$HERE/mkrmdoc.py" "$PDF" "$UPLOAD" "$NAME" $TAGS >/dev/null \
    || { echo "send: could not build .rmdoc wrapper" >&2; exit 4; }
fi

"$RMAPI" -ni put "$UPLOAD" "$FOLDER" >"$TMP/put.log" 2>&1 \
  || { echo "send: upload rejected — $(tail -1 "$TMP/put.log")" >&2; exit 5; }

if [ -n "$TAGS" ]; then
  echo "sent \"$NAME\" to $FOLDER tagged [${TAGS// /, }] — sync the tablet over wifi to see it"
else
  echo "sent \"$NAME\" to $FOLDER — sync the tablet over wifi to see it"
fi
