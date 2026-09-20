---
name: garmin
description: >-
  Use when the user wants their own Garmin data on this machine — "how did I
  sleep", "pull my runs from Garmin", "what's my HRV been doing", "export my
  activities", "chart my resting heart rate". Reads Garmin Connect for the
  account that logs in here: activities, sleep, HRV, stress, body battery,
  weight, training readiness. Read only; it never writes to Garmin.
---

# Garmin Connect

Garmin has **no personal API**. Their developer program takes companies,
universities and hospitals, and turns individuals away. So every route to your own
data is a workaround, and the one that works is the same mobile endpoints the phone
app uses, driven by [`garminconnect`](https://github.com/cyberjunky/python-garminconnect).

That has a cost worth stating up front: the endpoints are undocumented and change
without notice. In March 2026 Garmin altered its auth flow and broke `garth`, the
library the whole Python ecosystem was built on; it was deprecated and new logins
stopped working overnight. `garminconnect` carries its own auth now and is
maintained, but the same thing can happen again. **Assume this will break someday,
and don't build anything time-critical on it.**

## Usage

```bash
skills/garmin/garmin.sh auth                      # once per machine
skills/garmin/garmin.sh day [--til 2026-09-19]    # everything for one day
skills/garmin/garmin.sh activities --fra 2026-09-01 --til 2026-09-19
skills/garmin/garmin.sh sleep --til i-gar --table
skills/garmin/garmin.sh raw get_activity_details 1234567890
skills/garmin/garmin.sh methods                   # all 109 endpoints
```

JSON on stdout by default, so it pipes into `jq` or straight into your own code.
`--table` prints the first six columns instead, for reading.

Dates are `YYYY-MM-DD`, or `i-dag` / `i-gar`. `--fra` defaults to a week back,
`--til` to today.

## Commands

| Command | What it returns |
|---------|-----------------|
| `day` | One day, assembled: stats, sleep, HRV, training readiness, activities. A missing measurement becomes an error field rather than failing the whole call. |
| `activities` | Every activity in the range, with distance, duration, pace, heart rate |
| `sleep` | Sleep stages, duration, score for one night |
| `steps` | Daily step counts across the range |
| `hr` / `hrv` / `stress` | Heart rate through the day, HRV overnight, stress |
| `body-battery` | Body battery curve across the range |
| `weight` | Weigh-ins in the range |
| `readiness` | Morning training readiness |
| `stats` | Daily totals plus body composition |
| `raw <method> [args]` | Any of the 109 `get_*` methods directly |
| `methods` | List them |

Start with `day` when the question is about one date, and `raw` when it is about
something specific — the wrapper deliberately covers only what gets asked for often.

## Auth

One time per machine:

```bash
skills/garmin/garmin.sh auth
```

It asks for email, then password (not echoed), then the Garmin one-time code if MFA
is on. Refresh tokens land in `~/.garminconnect` at mode 700; the password is never
written anywhere. `GARMIN_EMAIL` and `GARMIN_PASSWORD` work for unattended runs.

**Never pass credentials as arguments.** `argv` is readable by every process on the
machine, so the script has no `--password` flag on purpose. Don't add one.

**When the user is on their phone,** don't ask them to type the password into the
chat — it stays in the transcript forever, and a password there cannot be taken
back. Serve them a form instead:

```bash
python3 innlogging.py --port 8477 &
tailscale serve --bg --https 8477 http://127.0.0.1:8477
# they open https://<host>.ts.net:8477, fill it in, page shuts itself down
```

It is one page, two steps (password, then the one-time code if the account asks
for it), and it exits 0 once the tokens are saved. Bind to localhost and put
`tailscale serve` in front — over plain HTTP the password crosses the network in
clear text. The fields carry `autocomplete="current-password"` and
`one-time-code`, so iOS offers the keychain entry and autofills the code.

### Two things that cost an hour here

- **`login()` returns `(None, None)` on a clean login.** Only `("needs_mfa", state)`
  means a code is needed. Treating a `None` status as failure rejects a login that
  actually worked — the tokens were valid and got thrown away.
- **Save with `client.dump(path)`.** `garth.dump()` is from the old library and
  raises `AttributeError` here. It fires *after* a successful login, so it looks
  like the login failed when it did not.

**How often you log in again: roughly once a year.** Two tokens are involved. The
short one expires in hours and the library refreshes it from the long one before
each call, without touching the login endpoint — which also dodges the Cloudflare
block that sometimes sits in front of it. The long one lasts about a year from the
day it was issued, and only that expiry sends you back to a password and an MFA
code.

Four things end a session early: Garmin changing the auth flow, a password change,
signing out everywhere from account settings, and deleting `~/.garminconnect`.
Exit 2 means re-run `auth`, whatever the reason.

## Rules

1. **Read only.** The library can upload workouts and log weight; this skill does
   not, and should not start. Writing to someone's health record is a different
   kind of action than reading it.
2. **This is health data.** Sleep, heart rate, weight, menstrual logs. Keep it on
   the machine. Don't paste it into anything external, don't put it in a commit,
   and summarise rather than dump when the user just asked a question.
3. **Say when the number is the device's guess.** Sleep stages, stress, body
   battery and training readiness are Garmin's models, not measurements. Steps,
   heart rate and distance are closer to real. The difference matters when someone
   is about to act on it.
4. **One account.** Whoever ran `auth` is whose data comes out. There is no
   account switch; check with the user before re-authenticating as someone else.

## When auth breaks

It will, eventually. Exit 5 on `auth` with a fresh password means Garmin changed
something. In order:

1. `uv cache clean` and retry — you may be on a stale build of the library.
2. Check [the issue tracker](https://github.com/cyberjunky/python-garminconnect/issues);
   a break affects everyone at once and gets a fix fast.
3. While waiting, the **account data export** still works and needs no library:
   Garmin Connect → Account → Export Your Data. It is a GDPR export, so it is
   complete but arrives as a ZIP some hours later, by email. Good for a one-off
   backfill, useless for a daily question.
4. **FIT files** straight off the watch over USB are the rawest form, and need no
   account at all. Worth knowing about when the cloud is the problem.

Don't paper over a broken login by asking the user for their password again — that
is not what exit 5 means, and it teaches them a bad habit.

## Exit codes

| Code | Meaning |
|------|---------|
| 2 | Not authenticated — run `auth` |
| 3 | Bad input (unknown command, malformed date, missing method name) |
| 4 | Missing runtime (`uvx` not installed) |
| 5 | Garmin rejected the call |

## Common mistakes

- Asking for today's sleep before the watch has synced. Sleep lands when the watch
  next talks to the phone; `--til i-gar` is usually what you want.
- Treating `day` as cheap. It is five API calls. For a range, use the range
  commands, which are one call each.
- Expecting activity GPS from `activities`. That summary has no track — use
  `raw get_activity_details <id>`.
- Rate limits. Garmin throttles silently rather than erroring cleanly; a loop over
  a year of dates will start returning empty. Space it out, and cache what you pull.
- Reading a `429` on login as a wrong password. It is the IP being throttled, and
  retrying makes it worse. The library retries by itself, so a 429 in the log
  next to a login that worked is normal — check the outcome, not the log.

## How it works

```
garmin.sh → uvx --from garminconnect → garmin.py
                                          │
                     ~/.garminconnect ────┤ refresh tokens (0700)
                                          │
                         sso.garmin.com ──┴── connectapi.garmin.com
```

`uvx` fetches the library per machine, so nothing is installed globally and the
version floats with upstream — which is what you want for something that breaks when
Garmin moves. `garmin.py` is a thin wrapper: it owns the auth handling, the date
parsing, the output shape and the exit codes, and forwards everything else to the
library. New endpoints need no code change; `raw` reaches them the day they ship.
