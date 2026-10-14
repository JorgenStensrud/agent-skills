---
name: remarkable
description: >-
  Use when the user wants to send something to their reMarkable tablet —
  "send this to my reMarkable", "put this on the rM", "I want to read this
  on my tablet", "print this for the reMarkable" — or read something back
  off it: "read my notes", "what did I write on the rM", "read my markup on
  the draft", a notebook or document by name. Over the reMarkable cloud.
allowed-tools: Bash, Read, Write
---

# remarkable

Send a document to a reMarkable 2 over the reMarkable cloud, and read notebooks
and marked-up documents back. The tablet syncs over its own wifi — no cable, no
shared network, no Connect subscription.

HTML and Markdown are re-rendered with e-ink typography sized to the rM2 screen
(158×210 mm, 12 pt serif, pure black on white) so pages fill the display and
need no pinch-zooming. PDFs upload untouched.

## Usage

```bash
skills/remarkable/send.sh <file.pdf|file.html|file.md|URL> \
    [--name "Title"] [--tag <name>] [--folder /Claude] [--no-date]
skills/remarkable/send.sh --auth <one-time-code>    # first run only
skills/remarkable/send.sh <file> --preview          # PNGs at 226 DPI, no upload
skills/remarkable/send.sh <file> --name "Budsjett" --no-date --replace  # update in place

skills/remarkable/read.sh <name|/path|uuid> [--out DIR] [--all]
skills/remarkable/read.sh --list [/Claude]          # id, type, path
```

`read.sh` prints one `page N: <png>` line per page with ink on it; look at the
PNGs with Read. PDFs come back with the ink drawn on the page; notebooks as the
strokes alone. There is no OCR — you read the handwriting from the image. A name
with `/` in it ("Sunday-27/09") works: lookup goes by document id, never by path.

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
filter sees. The vocabulary is the user's own and lives outside the repo, in
`~/.config/remarkable/tags`: one line per name, the name first and then the
tags it sets.

```
# ~/.config/remarkable/tags
jobb      jobb
personlig personlig
kunde     kunde jobb     # a narrower tag implies the broader one
```

With the file, only listed names are accepted, so the vocabulary stays a
vocabulary; pass the most specific name alone, never a parent alongside it.
Without the file, `--tag <name>` sets that one tag. Read the file before
choosing a tag; comments in it say what each name is for.

Ask which tag applies when it isn't obvious from context. Tags and `--folder`
are independent — tags classify, folders file.

## Rules

1. **Read only what was asked for.** `read.sh` pulls personal handwriting
   off the cloud; fetch the document the user named, not the library.
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
   layout. Only HTML/Markdown gets e-ink treatment. A landscape PDF is declared
   `"orientation": "landscape"` in `.content`, which both fills the screen when
   the tablet is turned and keeps pen strokes aligned with the page under them.
5. **Confirm before sending personal or sensitive content** — uploads go to
   reMarkable's servers.
6. **Look at every page before you upload.** `send.sh <file> --preview` renders
   each page at the tablet's 226 DPI without uploading. Read every PNG. Nothing
   may be cut off: text clipped in a cell, a word broken mid-word, a missing
   right-hand border, a lone row spilling onto an extra page. Fix and preview
   again until it fits, then send. Saying "sent" without having looked is not
   done.
7. **One living copy, not a pile of versions.** For a document that gets
   updated (a budget, a plan), give it a stable name with `--no-date` and send
   with `--replace`, which deletes earlier versions of the same title — dated or
   not — in that folder first. A version with a different title must be removed
   by hand (`rmapi rm "/Claude/<name>"`).

## Spreadsheet pages to write on

For numbers the user wants to edit by hand, render an Excel-style grid: a
`<table>` with a blank corner, column letters A–E in a grey header row
(`thead`, so it repeats on every page), row numbers in a grey first column, and
cells about 7.5 mm tall so handwriting fits. Section titles span all columns
(`colspan`); leave the last columns and a block of rows empty for notes. Use
`width: calc(100% - 2px)` or the right border is cut off, let text wrap
(`white-space` normal, `word-break: normal`) and keep numbers `nowrap`, and keep
column headers short so they don't break mid-word. Then preview (rule 6).

## Markup review: send a draft, read the notes, fix, resend

The tablet is a good place to review a long document, and the notes come back with
it. This round-trip is the most useful thing the skill does: when the user says they
wrote something on it, this is the loop.

**1. Send the draft.** Ordinary `send.sh`. Landscape PDFs are declared landscape, so
the page fills the screen and the ink lands where it looks like it lands.

**2. Read the marked-up pages.** `read.sh "<name>"`, then look at each PNG it lists.
It renders only pages with ink, numbered as on the tablet, via `rmapi geta` — **use
`geta`, not your own compositing.** The ink is stored in the tablet's coordinate
system, not the PDF's, and the two do not line up by translation; an arrow rendered
on its own tells you nothing about what it points at. `geta` only takes a path, so
a PDF whose name contains `/` falls back to strokes without the page under them —
`read.sh` says so. Rename it on the tablet if the context matters.

A layer under ~500 bytes is an empty page the user merely opened, not a note;
`read.sh` skips those (`--all` renders every page anyway).

**3. Resend after fixing.** Delete first, or you get two documents with one name.
Say plainly that the handwriting does not survive a rebuild; save it as PNG first if
it is worth keeping.

**Deleting from the cloud does not delete from the tablet — and the tablet syncs
its copy back.** Replace a document under the same name and you get a merge, not a
replacement: the cloud ends up with both page sets interleaved. A 62-page book came
back as 124 pages where, from page 28 on, it alternated between two places in the
book. It reads exactly like the pages are in the wrong order, because they are.

So when resending a document the user already has open:

```bash
rmapi ls /Claude                       # how many copies are actually there?
rmapi get "/Claude/<name>" && …        # count cPages.pages — 2x means it merged
```

**Upload under a new name** rather than reusing the old one, and tell the user to
delete the old document *on the tablet*. Deleting it in the cloud alone lets it
come back at the next sync.

**Two documents with the same name break every path-based command.** `get`, `geta`
and `stat` each pick one arbitrarily — and `rm` deletes *both*. Check with
`rmapi ls <dir>` before any of them, use `get --id <uuid>` when in doubt, and keep a
local copy before deleting anything that has ink on it.

**A note that reads like a layout complaint usually is one.** «text is on top of the
figure» was true: measured in a browser with the real font, the label sat 0.2 units
under the drawing. Reproduce with the actual fonts before believing a render that
looks fine — a fallback font with shorter letters hides the collision.

## Every page showed the cover

`.content`'s `cPages.pages[i].redir.value` is **which page of the PDF that entry
renders**. It must be `i`. Hard-coded to 0, a 62-page book syncs, opens, scrolls,
and reports 62 pages — every one of them the front page. Nothing errors; the
upload succeeds. Fixed 20 September 2026.

Verify a tagged upload by fetching it back rather than trusting the local tree:

```bash
rmapi get "/Claude/<name>" && python3 -c "
import zipfile,json,glob
z=zipfile.ZipFile(glob.glob('*.rmdoc')[0])
c=json.loads(z.read([n for n in z.namelist() if n.endswith('.content')][0]))
p=c['cPages']['pages']; print(len(p), [x['redir']['value'] for x in p[:5]])"
```

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
| 3 | Bad input (unsupported type, missing file); `read.sh`: no match, or several — it lists them |
| 4 | Render failed (no Chrome, bad markdown, unreachable URL; `read.sh`: download or page render) |
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
