#!/usr/bin/env python3
"""Wrap a PDF into a .rmdoc archive so it can carry reMarkable document tags.

rmapi's `put` rebuilds .content for a bare PDF and drops any tags, but it
uploads .rmdoc archives verbatim — so tags survive only via this route.

Usage: mkrmdoc.py <input.pdf> <output.rmdoc> <visible-name> [tag ...]
"""
import json
import re
import sys
import time
import uuid
import zipfile


def page_count(pdf_bytes: bytes) -> int:
    """Page count without a PDF library.

    Prefers the page tree's /Count, falls back to counting page objects.
    """
    counts = [int(m) for m in re.findall(rb"/Type\s*/Pages\b[^>]*?/Count\s+(\d+)", pdf_bytes, re.S)]
    if not counts:
        counts = [int(m) for m in re.findall(rb"/Count\s+(\d+)[^>]*?/Type\s*/Pages\b", pdf_bytes, re.S)]
    if counts:
        return max(counts)
    n = len(re.findall(rb"/Type\s*/Page[^s]", pdf_bytes))
    return max(n, 1)


def page_idx(i: int) -> str:
    """reMarkable's fractional page-order key: ba, bb, ... bz, bza, bzb, ..."""
    if i < 26:
        return "b" + chr(ord("a") + i)
    return "bz" + chr(ord("a") + (i - 26) % 26) * (1 + (i - 26) // 26)


def build(pdf_path: str, out_path: str, name: str, tags: list[str]) -> None:
    pdf = open(pdf_path, "rb").read()
    pages = page_count(pdf)
    now = int(time.time() * 1000)
    doc_id = str(uuid.uuid4())

    content = {
        "coverPageNumber": -1,
        "customZoomCenterX": 0,
        "customZoomCenterY": 936,
        "customZoomOrientation": "portrait",
        "customZoomPageHeight": 1872,
        "customZoomPageWidth": 1404,
        "customZoomScale": 1,
        "documentMetadata": {"title": name},
        "dummyDocument": False,
        "extraMetadata": {},
        "fileType": "pdf",
        "fontName": "",
        "formatVersion": 2,
        "lastOpenedPage": 0,
        "lineHeight": -1,
        "margins": 180,
        "orientation": "portrait",
        "pageCount": pages,
        "pageTags": [],
        "sizeInBytes": str(len(pdf)),
        "tags": [{"name": t, "timestamp": now} for t in tags],
        "textAlignment": "justify",
        "textScale": 1,
        "zoomMode": "bestFit",
        "cPages": {
            "lastOpened": {"timestamp": "1:1", "value": ""},
            "original": {"timestamp": "1:1", "value": -1},
            "pages": [
                {
                    "id": str(uuid.uuid4()),
                    "idx": {"timestamp": "1:2", "value": page_idx(i)},
                    # Which page of the PDF this entry shows. Hard-coding 0 makes
                    # every page render the cover — a 62-page book looked like the
                    # front page 62 times on the tablet.
                    "redir": {"timestamp": "1:2", "value": i},
                }
                for i in range(pages)
            ],
            "uuids": [{"first": str(uuid.uuid4()), "second": 1}],
        },
    }

    metadata = {
        "createdTime": str(now),
        "deleted": False,
        "lastModified": str(now),
        "lastOpened": "0",
        "lastOpenedPage": 0,
        "metadatamodified": False,
        "modified": False,
        "new": False,
        "parent": "",
        "pinned": False,
        "source": "",
        "synced": False,
        "type": "DocumentType",
        "version": 1,
        "visibleName": name,
    }

    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(f"{doc_id}.content", json.dumps(content))
        z.writestr(f"{doc_id}.metadata", json.dumps(metadata))
        z.writestr(f"{doc_id}.pagedata", "Blank\n" * pages)
        z.writestr(f"{doc_id}.pdf", pdf)

    print(f"{doc_id} {pages} pages, tags={tags}")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    build(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:])
