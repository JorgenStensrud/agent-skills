---
name: send-mail
description: >-
  Send a transactional email via Resend's REST API to jorgen.stensrud@proton.me
  (or --to override). ONLY invoke when the user explicitly says to send mail —
  "send me an email", "mail me", "email this to my inbox". Do NOT auto-invoke
  as a side effect of another task. Body from stdin, --body, or --file; --html
  for HTML content.
---

# send-mail

Simple wrapper around the Resend REST API. One bash script, no dependencies
beyond `curl` + `python3` (both stdlib-only usage).

## Invocation rule — explicit only

**Do not trigger this skill as a side effect.** Only invoke when the user
explicitly asks to send mail:

- ✅ "send me an email with the status"
- ✅ "mail me the report"
- ✅ "email this to Proton"
- ❌ Do NOT auto-email at the end of a long task unless the user asked for it
- ❌ Do NOT chain with other skills (e.g. `handoff | send-mail`) unless the
  user explicitly wired that pipe themselves

Silent notifications are a footgun: they send real mail to a real inbox and
cost Resend quota. Ask if the user actually wants it.

## When this fits

- User asks to send an email — see rule above.
- User pipes into it themselves: `some-cmd | send-mail --subject "log tail"`.

Not for: transactional email from an application (use the Resend SDK
directly), bulk sends, or anything where deliverability tracking matters
beyond the immediate response.

## Prereqs

```bash
export RESEND_API_KEY=re_xxxxxxxxxx        # from https://resend.com/api-keys
export RESEND_FROM='hello@your-domain'     # optional; must be verified in Resend
```

Without `RESEND_FROM`, the script falls back to `onboarding@resend.dev` —
Resend's own test sender that only delivers to the API-key owner's email
(fine for testing, not for cross-recipient sending).

Sten's setup: `prisl.app` is verified at Resend (DKIM + SPF). Use e.g.
`RESEND_FROM='hello@prisl.app'` to send to any recipient.

## Usage

```bash
# Short message via --body
send-mail --subject "morning status" --body "3 handoffs done, 1 stuck on cursor"

# Long body via stdin
handoff status 20260702-fix-auth --safe | send-mail --subject "handoff snapshot"

# From a file, as HTML
send-mail --subject "report" --file /tmp/report.html --html

# Different recipient
send-mail --to alice@example.com --subject "note" --body "the fix is in main"
```

On success it prints one JSON line:

```json
{"status":"sent","http":200,"id":"a1b2c3...","to":"jorgen.stensrud@proton.me","subject":"..."}
```

Non-2xx exits 1 and prints the Resend error body to stderr.

## Safety

- The script reads `RESEND_API_KEY` from the environment; never bake it in.
- `--to` accepts a comma-separated list, but the skill does not spread beyond
  what the caller passes. No address-book lookups, no bcc/cc mysteries.
- Bodies are sent verbatim — if you have secrets in the text, pre-redact
  (e.g. pipe through `state.py redact` from the `handoff` skill).
