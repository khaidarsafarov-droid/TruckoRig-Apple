#!/usr/bin/env python3
"""Write the PDF and image fixtures the share-import tests read from the bundle."""

from __future__ import annotations

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "TruckoRigTests", "Fixtures")


def pdf_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def page_stream(text: str | list[str]) -> str:
    if isinstance(text, str):
        return f"BT /F1 12 Tf 72 720 Td ({pdf_escape(text)}) Tj ET"
    # Many short lines in a small font, so every character sits inside the MediaBox.
    # PDFKit only returns text that is drawn on the page.
    shown = " T* ".join(f"({pdf_escape(line)}) Tj" for line in text)
    return f"BT /F1 4 Tf 5 TL 20 780 Td {shown} ET"


def make_pdf(page_texts: list[str | list[str]]) -> bytes:
    n_pages = len(page_texts)
    font_id = 3 + n_pages * 2
    objects: dict[int, object] = {}
    kids: list[str] = []
    for index, text in enumerate(page_texts):
        page_id = 3 + index * 2
        content_id = page_id + 1
        kids.append(f"{page_id} 0 R")
        stream = page_stream(text)
        objects[page_id] = (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            f"/Contents {content_id} 0 R /Resources << /Font << /F1 {font_id} 0 R >> >> >>"
        )
        objects[content_id] = stream
    objects[1] = "<< /Type /Catalog /Pages 2 0 R >>"
    objects[2] = f"<< /Type /Pages /Count {n_pages} /Kids [{' '.join(kids)}] >>"
    objects[font_id] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"

    header = b"%PDF-1.4\n"
    body = bytearray()
    offsets = [0]
    pos = len(header)
    for obj_id in range(1, font_id + 1):
        offsets.append(pos)
        raw = objects[obj_id]
        if isinstance(raw, str) and obj_id % 2 == 0 and obj_id != 2 and obj_id != font_id:
            stream = raw.encode("latin1")
            piece = (
                f"{obj_id} 0 obj\n<< /Length {len(stream)} >>\nstream\n".encode("latin1")
                + stream
                + b"\nendstream\nendobj\n"
            )
        else:
            piece = f"{obj_id} 0 obj\n{raw}\nendobj\n".encode("latin1")
        body.extend(piece)
        pos += len(piece)
    xref = [f"xref\n0 {font_id + 1}\n", "0000000000 65535 f \n"]
    xref.extend(f"{offsets[obj_id]:010d} 00000 n \n" for obj_id in range(1, font_id + 1))
    trailer = (
        f"trailer\n<< /Size {font_id + 1} /Root 1 0 R >>\nstartxref\n{pos}\n%%EOF\n"
    )
    return header + bytes(body) + "".join(xref).encode("latin1") + trailer.encode("latin1")


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    text_layer = (
        "SWF2, Garner, NC to TOL3 Perrysburg OH. Total Rate 2500. Rate confirmation."
    )
    pages = []
    for number in range(1, 32):
        if number == 31:
            pages.append("PAGE31ONLY should not be extracted once the page cap is applied")
        else:
            pages.append(
                f"PAGE{number:02d} SWF2 Garner NC rate confirmation stays on this page"
            )
    # 100,050 characters as 200-character lines, 150 lines per page (4 pages),
    # then ENDMARKER on its own line past the 100,000-character limit.
    long_lines = ["A" * 200] * 500 + ["A" * 50, "ENDMARKER"]
    long_pages = [long_lines[start:start + 150] for start in range(0, len(long_lines), 150)]
    files = {
        "text-layer.pdf": make_pdf([text_layer]),
        "thirty-one-pages.pdf": make_pdf(pages),
        "long-text.pdf": make_pdf(long_pages),
        "pixel.jpg": bytes([0xFF, 0xD8, 0xFF, 0xD9]),
        "rejected.jpg": b"GIF89a this is not a jpeg",
    }
    for name, data in files.items():
        path = os.path.join(OUT, name)
        with open(path, "wb") as handle:
            handle.write(data)
        print(f"wrote {path} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
