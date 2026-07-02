#!/usr/bin/env bash
# load-env-from-ingrid.sh — export RESEND_API_KEY + RESEND_FROM into the
# current shell by reading ingrid_jobb's existing secrets.env.
#
# ingrid_jobb sends mail via SMTP (smtp.resend.com), so the Resend API key
# lives under SMTP_PASSWORD there. The same key works for the REST API our
# send-mail skill uses. SENDER_EMAIL is Ingrid's verified From address.
#
# Usage — MUST be sourced (not executed) so exports land in your shell:
#
#   source ~/dev/personal/agent-skills/skills/send-mail/scripts/load-env-from-ingrid.sh
#
# Or add to ~/.zshrc so it loads on every new terminal:
#
#   [ -f ~/dev/personal/agent-skills/skills/send-mail/scripts/load-env-from-ingrid.sh ] \
#     && source ~/dev/personal/agent-skills/skills/send-mail/scripts/load-env-from-ingrid.sh >/dev/null
#
# Override the source file:
#   INGRID_ENV=/path/to/secrets.env source load-env-from-ingrid.sh

INGRID_ENV="${INGRID_ENV:-$HOME/dev/personal/ingrid_jobb/config/secrets.env}"

_die() { printf 'load-env-from-ingrid: %s\n' "$*" >&2; return 1 2>/dev/null || exit 1; }

[ -r "$INGRID_ENV" ] || _die "cannot read $INGRID_ENV"

# Ingrid_jobb SMTP config points at smtp.resend.com — sanity-check that we're
# actually pulling a Resend key and not (say) a Gmail app-password.
_host="$(grep -E '^SMTP_HOST=' "$INGRID_ENV" | head -1 | cut -d= -f2-)"
if [ -n "$_host" ] && [ "$_host" != "smtp.resend.com" ]; then
  printf 'load-env-from-ingrid: warning — SMTP_HOST is "%s", not "smtp.resend.com".\n' "$_host" >&2
  printf '  The password may not be a Resend API key. Continue at your own risk.\n' >&2
fi

_pw="$(grep -E '^SMTP_PASSWORD=' "$INGRID_ENV" | head -1 | cut -d= -f2-)"
_from="$(grep -E '^SENDER_EMAIL=' "$INGRID_ENV" | head -1 | cut -d= -f2-)"

[ -n "$_pw" ]   || _die "SMTP_PASSWORD missing in $INGRID_ENV"
[ -n "$_from" ] || _die "SENDER_EMAIL missing in $INGRID_ENV"

# Strip surrounding quotes if present
_pw="${_pw%\"}"; _pw="${_pw#\"}"; _pw="${_pw%\'}"; _pw="${_pw#\'}"
_from="${_from%\"}"; _from="${_from#\"}"; _from="${_from%\'}"; _from="${_from#\'}"

export RESEND_API_KEY="$_pw"
export RESEND_FROM="$_from"

unset _pw _from _host

printf 'load-env-from-ingrid: RESEND_FROM=%s exported. RESEND_API_KEY set (%d chars).\n' \
  "$RESEND_FROM" "${#RESEND_API_KEY}"
