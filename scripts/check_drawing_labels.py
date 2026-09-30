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

from text_positions import shown_strings  # noqa: E402
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
            for shown in shown_strings(block):
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


FACES_SNAPSHOT = ROOT / "tests" / "flow_figures" / "label_faces_10.pdf"
REGIONS = ("Hobart", "Launceston", "Moonah", "Fremantle")


def label_fonts(pdf: bytes) -> tuple[dict[str, str], dict[str, str]]:
    """Per font /BaseFont (subset tag removed), the concatenated decoded
    text of its page-artifact strings and of its tagged strings."""
    document = Document(pdf)
    pages: list[int] = []
    page_order(document, int(document.get(document.root)["Pages"]), pages)
    artifacts: dict[str, list[str]] = {}
    tagged: dict[str, list[str]] = {}
    for page in pages:
        page_marked_text(document, page, artifacts, artifacts=True)
        page_marked_text(document, page, tagged)
    return ({font: "".join(texts) for font, texts in artifacts.items()}, {font: "".join(texts) for font, texts in tagged.items()})


def validate_drawing_label_faces_pdf(pdf: bytes) -> None:
    """The label-faces fixture: region names and a small repeat of the
    title in the body face, the title in a second face, and the tick values
    in a third; the two role faces are output fonts that no tagged text
    uses, so they entered the document through the labels alone."""
    artifacts, tagged = label_fonts(pdf)
    body = [font for font, text in artifacts.items() if all(name in text for name in REGIONS)]
    require(len(body) == 1, f"region names are not all in one font: {sorted(artifacts)}")
    titled = [font for font, text in artifacts.items() if "Café" in text]
    require(len(titled) == 2 and body[0] in titled, "the title is not shown in the body face and in one other face")
    title = next(font for font in titled if font != body[0])
    ticks = [font for font, text in artifacts.items() if font not in (body[0], title) and "50" in text and "100" in text]
    require(len(ticks) == 1, "tick values are not shown in a third face")
    for role_font in (title, ticks[0]):
        require(role_font not in tagged, f"label face {role_font} also sets tagged text")
    require(body[0] in tagged, "the body face sets no tagged text")


def self_test() -> None:
    validate_drawing_labels_pdf(SNAPSHOT.read_bytes())
    validate_drawing_label_faces_pdf(FACES_SNAPSHOT.read_bytes())
    # Single-face labels are all in the body face.
    try:
        validate_drawing_label_faces_pdf(SNAPSHOT.read_bytes())
    except ValidationError:
        pass
    else:
        raise SystemExit("drawing-label checker accepted body-face labels as label faces")
    # The unlabelled sections fixture paints the same charts without labels.
    try:
        validate_drawing_labels_pdf((ROOT / "tests" / "flow_figures" / "sections_10.pdf").read_bytes())
    except ValidationError:
        pass
    else:
        raise SystemExit("drawing-label checker accepted charts without labels")
    print("PASS drawing label checker self-test (labels and label faces)")


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
