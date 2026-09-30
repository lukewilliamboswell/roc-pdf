#!/usr/bin/env python3
"""Independent evidence for text labels inside drawings.

Every label of the flow-figures `labels` fixture must be shown as page
artifact text whose CIDs decode through the font's ToUnicode CMap to the
label's exact string, and no label may appear as the whole text of a
tagged (MCID-owned) marked-content sequence: labels belong to no structure
element, and a figure's alternative text carries their meaning.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from check_pdf_structure import ValidationError, require
import re

from check_rich_inline import page_marked_text, to_unicode
from check_structure_semantics import Document, page_order


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests" / "flow_figures" / "labels_10.pdf"
LABELS = {"Hobart", "Launceston", "Moonah", "Fremantle", "AUD thousands", "KEY FIGURES", "0", "50", "100", *(f"Bay {n}" for n in range(1, 13))}


LAYOUT_TEXT = re.compile(rb"/Artifact <</Type /Layout>> BDC\n(.*?)\nEMC\n", re.S)
FONT = re.compile(rb"/(\S+) [0-9.]+ Tf")
SHOWN = re.compile(rb"<([0-9A-F]+)> Tj")


def artifact_and_tagged_text(pdf: bytes) -> tuple[list[str], list[str]]:
    """The decoded text of each Layout artifact sequence, and each MCID's text."""
    document = Document(pdf)
    pages: list[int] = []
    page_order(document, int(document.get(document.root)["Pages"]), pages)
    artifacts: list[str] = []
    tagged: list[str] = []
    for page in pages:
        page_value = document.get(page)
        fonts = page_value.get("Resources", {}).get("Font", {})
        content = document.stream(int(page_value["Contents"]))
        for block in LAYOUT_TEXT.findall(content):
            font = FONT.search(block)
            if font is None:
                continue
            name = font.group(1).decode("latin-1")
            require(name in fonts, f"artifact text selects an undeclared font /{name}")
            mapping = to_unicode(document, int(fonts[name]))
            text = []
            for shown in SHOWN.findall(block):
                raw = bytes.fromhex(shown.decode())
                for index in range(0, len(raw), 2):
                    cid = int.from_bytes(raw[index:index + 2], "big")
                    require(cid in mapping, f"artifact CID {cid} has no ToUnicode mapping")
                    text.append(mapping[cid])
            artifacts.append("".join(text))
        tagged.extend(text for _, text in page_marked_text(document, page))
    return artifacts, tagged


def validate_drawing_labels_pdf(pdf: bytes) -> None:
    artifacts, tagged = artifact_and_tagged_text(pdf)
    shown = set(artifacts)
    missing = sorted(LABELS - shown)
    require(not missing, f"drawing labels are not shown as artifact text: {missing}")
    leaked = sorted(LABELS.intersection(tagged))
    require(not leaked, f"drawing labels are tagged content: {leaked}")


def self_test() -> None:
    validate_drawing_labels_pdf(SNAPSHOT.read_bytes())
    # The unlabelled sections fixture paints the same charts without labels.
    try:
        validate_drawing_labels_pdf((ROOT / "tests" / "flow_figures" / "sections_10.pdf").read_bytes())
    except ValidationError:
        pass
    else:
        raise SystemExit("drawing-label checker accepted charts without labels")
    print("PASS drawing label checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path, default=SNAPSHOT)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    validate_drawing_labels_pdf(args.pdf.read_bytes())
    print(f"PASS drawing labels: {args.pdf}")


if __name__ == "__main__":
    main()
