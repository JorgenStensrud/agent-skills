---
name: remarkable
description: >-
  Use when the user wants to send something to their reMarkable tablet —
  "send this to my reMarkable", "put this on the rM", "I want to read this
  on my tablet", "print this for the reMarkable". One way only: here to
  tablet, over the reMarkable cloud. Does not read from the tablet.
allowed-tools: Bash, Read, Write
---

# remarkable

Send a document to a reMarkable 2 over the reMarkable cloud. The tablet syncs
it over its own wifi — no cable, no shared network, no Connect subscription.

HTML and Markdown are re-rendered with e-ink typography sized to the rM2 screen
(158×210 mm, 12 pt serif, pure black on white) so pages fill the display and
need no pinch-zooming. PDFs upload untouched.

## Usage

```bash
skills/remarkable/send.sh <file.pdf|file.html|file.md|URL> \
    [--name "Title"] [--tag jobb|personlig|seeyou] [--folder /Claude] [--no-date]
skills/remarkable/send.sh --auth <one-time-code>    # first run only
```

`--name` sets the title shown on the tablet; it defaults to the filename.

To send something you wrote in this conversation, write it to a `.md` or
`.html` file first, then send that file.

## Naming

Every document gets a `YYYY-MM-DD ` prefix, so sorting the tablet's list by
name reads chronologically and the newest work sits at the bottom. `send.sh`
adds it — don't put a date in `--name` yourself. A name that already starts
with `YYYY-MM-DD ` is left alone; `--no-date` skips the prefix entirely.

## Tags

`--tag` sets real reMarkable document tags — the ones the tablet's own tag
filter sees. Three are allowed; anything else is rejected, so the vocabulary
stays a vocabulary:

| `--tag` | Tags set |
|---------|----------|
| `jobb` | `jobb` |
| `personlig` | `personlig` |
| `seeyou` | `seeyou` **and** `jobb` |

**`seeyou` implies `jobb`** — SeeYou work is work. Pass `--tag seeyou` alone;
never pass both.

Ask which tag applies when it isn't obvious from context. Tags and `--folder`
are independent — tags classify, folders file.

## Rules

1. **One direction.** This sends only. There is no read-back, no OCR, no
   pulling notes off the tablet. Don't offer it.
2. **`rmapi`'s local tree goes stale — run `rmapi refresh` before trusting it.**
   `stat` will report `Tags: []` on a document that is correctly tagged, and
   `ls` will show documents that are already deleted (or hide ones that exist).
   To check tags, `rmapi get` the document and read its `.content`; anything
   else is guesswork. Deletes work, but issue them against a refreshed tree and
   refresh again to confirm.
3. **Pairing is one-time.** If `send.sh` exits 2, get a code from
   https://my.remarkable.com/device/browser/connect and run `--auth <code>`.
   Codes are single-use and expire in minutes — ask the user for a fresh one
   rather than reusing an old one.
4. **PDFs pass through unrendered.** An A4 PDF stays A4 and will look small on
   a 10.3" screen. That is expected; re-paginating would wreck the original
   layout. Only HTML/Markdown gets e-ink treatment.
5. **Confirm before sending personal or sensitive content** — uploads go to
   reMarkable's servers.

## Keep `rmapi` current

The cloud's sync schema moves, and an old `rmapi` writes an old one. When that
happens `ls` still works — auth and listing are fine — but every upload dies with
`400 {"message":"invalid root schema"}` while writing `root.docSchema`. Nothing in
the error names the version, so it reads like a bad file: it is not, and a smaller
PDF fails the same way.

Cure: raise `RMAPI_VERSION` in `send.sh`, delete `bin/rmapi`, and run again — it
self-downloads. Seen 20 September 2026 on v0.0.34, fixed by v0.0.35.

## Exit codes

| Code | Meaning |
|------|---------|
| 2 | Not paired — run `--auth <code>` |
| 3 | Bad input (unsupported type, missing file) |
| 4 | Render failed (no Chrome, bad markdown, unreachable URL) |
| 5 | Upload rejected by the cloud |

## Common mistakes

- Expecting the document on the tablet instantly — it appears after the tablet
  syncs. Wake it, check wifi, pull down on the document list.
- Sending raw `.txt` or `.docx`. Convert to `.md` or `.html` first; xochitl only
  reads PDF and EPUB, and the renderer only accepts HTML, Markdown, and URLs.
- Reusing a spent pairing code after an exit 2.

## How it works

```
.pdf   ────────────────────────────────┐
.md    → markdown_py → HTML ┐          │            ┌─ no tag → put the PDF
.html  ─────────────────────┼→ inject  ├→ PDF ──────┤
URL    → curl → HTML ───────┘  eink.css│            └─ tagged → mkrmdoc.py → put
                               → chrome                          the .rmdoc
                                 --print-to-pdf
                                                    → cloud → tablet
```

`bin/rmapi` ([ddvk/rmapi](https://github.com/ddvk/rmapi)) handles cloud auth and
upload; it self-downloads on first use if missing. Markdown conversion shells out
to `uvx --from markdown markdown_py`. Rendering uses Google Chrome if installed,
otherwise Playwright's bundled `chrome-headless-shell`.

`mkrmdoc.py` exists because `rmapi put` regenerates `.content` for a bare PDF
and throws away any tags, but uploads `.rmdoc` archives byte-for-byte. So a
tagged document is wrapped into a `.rmdoc` — `.content` (with the tags),
`.metadata`, `.pagedata`, and the PDF — before upload. Page count comes from a
regex over the PDF; it was checked against `pypdf` on 1-, 2-, and 3-page files
and agreed on all of them. The document name comes from the *filename* in both
paths, not from `.metadata`.

`eink.css` holds the typography. Edit it there — both the sizing and the
black-on-white contrast are deliberate: e-ink has no greys to spare.
