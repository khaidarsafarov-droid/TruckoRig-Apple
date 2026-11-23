#!/usr/bin/env python3
"""Write the PDF and image fixtures the share-import tests read from the bundle."""

from __future__ import annotations

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "TruckoRigTests", "Fixtures")


def pdf_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def make_pdf(page_texts: list[str]) -> bytes:
    n_pages = len(page_texts)
    font_id = 3 + n_pages * 2
    objects: dict[int, object] = {}
    kids: list[str] = []
    for index, text in enumerate(page_texts):
        page_id = 3 + index * 2
        content_id = page_id + 1
        kids.append(f"{page_id} 0 R")
        stream = f"BT /F1 12 Tf 72 720 Td ({pdf_escape(text)}) Tj ET"
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
    long_text = ("A" * 100_050) + "ENDMARKER"
    files = {
        "text-layer.pdf": make_pdf([text_layer]),
        "thirty-one-pages.pdf": make_pdf(pages),
        "long-text.pdf": make_pdf([long_text]),
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
