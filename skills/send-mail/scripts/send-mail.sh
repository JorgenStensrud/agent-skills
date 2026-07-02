#!/usr/bin/env bash
# send-mail.sh — send a transactional email via Resend's REST API.
#
# Default recipient is jorgen.stensrud@proton.me; override with --to.
# Body comes from --body "<text>", --file <path>, or stdin (pipe).
#
# Env:
#   RESEND_API_KEY  required — the `re_*` key from https://resend.com/api-keys
#   RESEND_FROM     optional — verified From address (e.g. hello@prisl.app).
#                   Falls back to `onboarding@resend.dev` (Resend's own test
#                   sender; only delivers to your Resend account owner email).
#
# Usage:
#   send-mail --subject "hei" --body "kort melding"
#   echo "some longer text" | send-mail --subject "log dump"
#   send-mail --subject "report" --file /tmp/report.md --html
#   send-mail --to alice@example.com --subject "notice" --body "..."
set -euo pipefail

usage() {
  cat <<'USAGE'
send-mail [--to <addr>] [--from <addr>] --subject <s> {--body <text> | --file <path> | (stdin)} [--html]

Defaults:
  --to     jorgen.stensrud@proton.me
  --from   $RESEND_FROM (or onboarding@resend.dev if unset)

Env:
  RESEND_API_KEY  required
  RESEND_FROM     optional default From address (verified domain)
USAGE
}

die() { printf 'send-mail: %s\n' "$*" >&2; exit 1; }

TO="jorgen.stensrud@proton.me"
FROM="${RESEND_FROM:-onboarding@resend.dev}"
SUBJECT=""
BODY=""
FILE=""
HTML=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)      TO="$2"; shift 2;;
    --from)    FROM="$2"; shift 2;;
    --subject|-s) SUBJECT="$2"; shift 2;;
    --body|-b)    BODY="$2"; shift 2;;
    --file|-f)    FILE="$2"; shift 2;;
    --html)    HTML=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown arg: $1";;
  esac
done

[[ -n "$SUBJECT" ]] || die "--subject is required"
[[ -n "${RESEND_API_KEY:-}" ]] || die "RESEND_API_KEY not set (get one at https://resend.com/api-keys)"

# Read body: --body wins, then --file, then stdin
if [[ -z "$BODY" ]]; then
  if [[ -n "$FILE" ]]; then
    [[ -r "$FILE" ]] || die "cannot read --file $FILE"
    BODY="$(cat -- "$FILE")"
  elif [[ ! -t 0 ]]; then
    BODY="$(cat)"
  else
    die "no body: use --body, --file, or pipe on stdin"
  fi
fi

FIELD="text"
[[ "$HTML" -eq 1 ]] && FIELD="html"

# Build the JSON payload with python (safe escaping, stdlib only)
PAYLOAD="$(python3 - "$FROM" "$TO" "$SUBJECT" "$FIELD" "$BODY" <<'PY'
import json, sys
frm, to, subject, field, body = sys.argv[1:6]
# to accepts a comma-separated list
to_list = [x.strip() for x in to.split(",") if x.strip()]
print(json.dumps({
    "from": frm,
    "to": to_list,
    "subject": subject,
    field: body,
}))
PY
)"

# Send. Fail on non-2xx.
HTTP_CODE="$(curl -sS -o /tmp/send-mail.$$.body -w '%{http_code}' \
  -X POST 'https://api.resend.com/emails' \
  -H "Authorization: Bearer $RESEND_API_KEY" \
  -H 'Content-Type: application/json' \
  --data-binary "$PAYLOAD")"

BODY_RESP="$(cat /tmp/send-mail.$$.body)"
rm -f /tmp/send-mail.$$.body

if [[ "$HTTP_CODE" =~ ^2 ]]; then
  # extract the id if present
  ID="$(printf '%s' "$BODY_RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id",""))' 2>/dev/null || true)"
  printf '{"status":"sent","http":%s,"id":"%s","to":"%s","subject":"%s"}\n' "$HTTP_CODE" "$ID" "$TO" "$SUBJECT"
else
  printf 'send-mail: http %s\n%s\n' "$HTTP_CODE" "$BODY_RESP" >&2
  exit 1
fi
