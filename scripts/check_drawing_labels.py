#!/usr/bin/env python3
"""Independently check intrinsic Figure label text and panel artifact text."""

from __future__ import annotations

import argparse
from pathlib import Path

from text_positions import shown_strings  # noqa: E402
from check_pdf_structure import ValidationError, require
import re

from check_rich_inline import page_marked_text, to_unicode
from check_structure_semantics import Document, element_children, page_order, text_string, validate_structure_semantics_pdf
from pdf_layout import planned_bodies, serialize_object_streams, trailer_facts


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests" / "flow_figures" / "labels_10.pdf"
REGIONS = ("Hobart", "Launceston", "Moonah", "Fremantle")
CHART_LABELS = (*REGIONS, "0", "50", "100", "AUD thousands")
PLAN_LABELS = tuple(f"Bay {number}" for number in range(1, 13))
PANEL_LABEL = "KEY FIGURES"


LAYOUT_TEXT = re.compile(rb"/Artifact <</Type /Layout>> BDC\n(.*?)\nEMC\n", re.S)
FONT = re.compile(rb"/(\S+) [0-9.]+ Tf")


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


def figures_with_text(pdf: bytes) -> list[tuple[str, tuple[str, ...], list[set[str]]]]:
    """Resolve each Figure's own ordered label sequences through /K and /ToUnicode."""
    validate_structure_semantics_pdf(pdf, {})
    document = Document(pdf)
    per_page: dict[int, tuple[dict[int, str], dict[int, set[str]]]] = {}
    figures = []
    for number in document.bodies:
        element = document.get(number)
        if not isinstance(element, dict) or element.get("S") != "Figure":
            continue
        contents = element_children(document, element)
        labels = []
        fonts = []
        for content in contents[1:]:
            page = int(content["Pg"])
            if page not in per_page:
                shown_fonts: dict[int, set[str]] = {}
                shown = dict(page_marked_text(document, page, by_mcid_fonts=shown_fonts))
                per_page[page] = shown, shown_fonts
            shown, shown_fonts = per_page[page]
            mcid = int(content["MCID"])
            labels.append(shown[mcid])
            fonts.append(shown_fonts[mcid])
        figures.append((text_string(element["Alt"]), tuple(labels), fonts))
    return figures


def validate_drawing_labels_pdf(pdf: bytes, count: int | None = None) -> None:
    figures = figures_with_text(pdf)
    charts = [labels for alt, labels, _ in figures if alt.startswith("Bar chart ")]
    plans = [labels for alt, labels, _ in figures if alt.startswith("Plan of the Moonah yard:")]
    require(charts and all(labels == CHART_LABELS for labels in charts), "each chart must own its exact labels in drawing order")
    if count is not None:
        require(len(charts) == count, f"expected {count} labelled charts, found {len(charts)}")
    require(plans == [PLAN_LABELS] and len(figures) == len(charts) + 1, "the scaled site plan must own twelve exact bay labels in drawing order")
    artifacts, tagged = artifact_and_tagged_text(pdf)
    require(artifacts == [PANEL_LABEL] and PANEL_LABEL not in tagged, "the custom panel label must stay a layout artifact")


FACES_SNAPSHOT = ROOT / "tests" / "flow_figures" / "label_faces_10.pdf"


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


def validate_drawing_label_faces_pdf(pdf: bytes, count: int | None = None) -> None:
    """Each chart owns its labels, with the Unicode title shown in two faces."""
    figures = figures_with_text(pdf)
    require(figures, "no labelled figures")
    if count is not None:
        require(len(figures) == count, f"expected {count} styled labelled figures, found {len(figures)}")
    for _, labels, fonts in figures:
        require(labels == (*REGIONS, "0", "50", "100", "Café", "Café"), "styled labels must keep their exact Unicode and reading order")
        body, ticks, title = fonts[0], fonts[4], fonts[7]
        require(all(len(face) == 1 for face in fonts), "a label uses multiple fonts")
        require(len(body | ticks | title) == 3, "the regions, ticks and title must use three selected faces")
        require(fonts[:4] == [body] * 4 and fonts[4:7] == [ticks] * 3 and fonts[8] == body, "drawing label faces do not match their authored roles")
    artifacts, _ = artifact_and_tagged_text(pdf)
    require(not artifacts, "intrinsic labels escaped as page artifacts")


def validate_furniture_typography_pdf(pdf: bytes) -> None:
    """Independent furniture-only face, 8 pt artifact text and 11 pt body."""
    artifacts, tagged = label_fonts(pdf)
    require(len(artifacts) == 1, "furniture does not use exactly one face")
    furniture_font = next(iter(artifacts))
    require("NotoMonoCodeFixture" in furniture_font, "furniture did not select the registered mono face")
    require(furniture_font not in tagged, "furniture entered tagged reading order")
    require(len(tagged) == 1 and "Body remains eleven points." in next(iter(tagged.values())), "body typography or content changed")
    document = Document(pdf)
    pages: list[int] = []
    page_order(document, int(document.get(document.root)["Pages"]), pages)
    for ordinal, page in enumerate(pages, 1):
        value = document.get(page)
        content = document.stream(int(value["Contents"]))
        # Artifact ownership and ToUnicode are read independently above;
        # verify selected sizes directly from each marked text sequence.
        artifact_blocks = re.findall(rb"/Artifact.*?BDC\n(.*?)EMC", content, re.S)
        text_artifacts = [block for block in artifact_blocks if b" Tf" in block]
        require(len(text_artifacts) == 2, "header/footer artifact pair missing")
        for block in text_artifacts:
            require(re.findall(rb"/\S+ ([0-9.]+) Tf", block) == [b"8"], "furniture size is not 8 pt")
            require(b"0.31372549 0.31372549 0.31372549 scn" in block, "furniture gray was not painted")
        tagged_blocks = re.findall(rb"/P <</MCID [0-9]+>> BDC\n(.*?)EMC", content, re.S)
        require(len(tagged_blocks) == 1 and re.findall(rb"/\S+ ([0-9.]+) Tf", tagged_blocks[0]) == [b"11"], "body size changed")
        # Exact page fields are decoded per page, never inferred from glyph IDs.
        fonts: dict[str, list[str]] = {}
        page_marked_text(document, page, fonts, artifacts=True)
        text = "".join(part for parts in fonts.values() for part in parts)
        require("Quiet running header" in text and f"Page {ordinal} of {len(pages)}" in text, "selected furniture face lost fields or literals")


def swap_label_and_caption_owners(pdf: bytes) -> bytes:
    """Swap two same-page MCID owners while preserving paint and both indexes."""
    document = Document(pdf)
    tree = document.get(int(document.get(document.root)["StructTreeRoot"]))
    figure = next(number for number in sorted(document.bodies) if b"/S /Figure >>" in document.bodies[number])
    element = document.get(figure)
    page = int(element["Pg"])
    section = document.get(int(element["P"]))
    caption = document.get(int(section["K"][1]))
    paragraph = int(caption["K"][0])
    paragraph_element = document.get(paragraph)
    require(int(paragraph_element["Pg"]) == page, "ownership mutation needs a same-page caption")
    label_mcid = element["K"][1]
    caption_mcid = paragraph_element["K"][0]

    parsed, bodies = planned_bodies(pdf)
    figure_kids = element["K"].copy()
    figure_kids[1] = caption_mcid
    encode_kids = lambda kids: b"/K [" + b" ".join(str(kid).encode() for kid in kids) + b"]"
    bodies[figure] = bodies[figure].replace(encode_kids(element["K"]), encode_kids(figure_kids), 1)
    bodies[paragraph] = bodies[paragraph].replace(encode_kids([caption_mcid]), encode_kids([label_mcid]), 1)

    parent_tree = int(tree["ParentTree"])
    nums = document.get(parent_tree)["Nums"]
    key = document.get(page)["StructParents"]
    row_index = next(index for index in range(0, len(nums), 2) if nums[index] == key) + 1
    old_row = nums[row_index]
    new_row = old_row.copy()
    new_row[label_mcid], new_row[caption_mcid] = new_row[caption_mcid], new_row[label_mcid]
    encode_row = lambda row: b"[" + b" ".join(f"{int(reference)} 0 R".encode() for reference in row) + b"]"
    bodies[parent_tree] = bodies[parent_tree].replace(encode_row(old_row), encode_row(new_row), 1)
    root, identifier = trailer_facts(parsed)
    return serialize_object_streams(bodies, parsed.header, root, identifier)


def self_test() -> None:
    labelled = SNAPSHOT.read_bytes()
    validate_drawing_labels_pdf(labelled, 10)
    validate_drawing_label_faces_pdf(FACES_SNAPSHOT.read_bytes(), 10)
    wrong_owner = swap_label_and_caption_owners(labelled)
    validate_structure_semantics_pdf(wrong_owner, {})
    require(artifact_and_tagged_text(labelled) == artifact_and_tagged_text(wrong_owner), "ownership twin changed the painted text")
    try:
        validate_drawing_labels_pdf(wrong_owner, 10)
    except ValidationError as error:
        require("each chart must own its exact labels" in str(error), f"unexpected ownership twin failure: {error}")
    else:
        raise SystemExit("drawing-label checker accepted a label owned by the caption")
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
    validate_furniture_typography_pdf((ROOT / "tests" / "page_templates" / "typography_3.pdf").read_bytes())
    try:
        validate_furniture_typography_pdf((ROOT / "tests" / "page_templates" / "slot_inset.pdf").read_bytes())
    except ValidationError:
        pass
    else:
        raise SystemExit("furniture typography checker accepted inherited body typography")
    print("PASS drawing label and furniture typography checker self-test")


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
