"""Verify the generated handbook's linked contents against its authored targets."""

from __future__ import annotations

from pathlib import Path
import re

from check_destination_references import page_label
from check_gallery_features import tagged, only
from check_navigation import check_name_tree, walk_name_tree
from check_pdf_structure import ValidationError, dictionary_ref, require
from check_rich_flow import ARTIFACT, read
from check_structure_semantics import element_children
from pdf_layout import twin

TARGETS = (
    b"scope", b"topology", b"severity", b"response", b"triage",
    b"rollback", b"failover", b"escalation", b"review", b"recovery-checklists",
    *(f"recovery-check-{index}".encode() for index in range(1, 33)),
    b"commands", b"drills",
)


def named_structures(document) -> dict[bytes, int]:
    root = dictionary_ref(document.bodies[document.root], b"Names << /Dests")
    result = {}
    for key, value in walk_name_tree(document.bodies, root):
        matched = re.search(rb"/SD \[([0-9]+) 0 R ", value)
        require(matched is not None, "named heading lost its structure destination")
        result[key] = int(matched[1])
    return result


def validate_handbook(pdf: bytes, authored: bytes) -> None:
    document, pages, root = tagged(pdf)
    old_document, old_pages, _ = tagged(authored)
    toc = only(root.descendants(), "TOC", "Recovery checklists")
    require(toc.pages == set(pages[:2]), "the generated contents should span the first two pages")
    require(len(toc.children) == len(TARGETS), "heading selection changed")
    named = check_name_tree(document.bodies, document.root, pages)
    old = check_name_tree(old_document.bodies, old_document.root, old_pages)
    require(old_pages.index(old[b"scope"][0]) == 1 and pages.index(named[b"scope"][0]) == 2,
            "the generated front matter did not move the first chapter from page 2 to page 3")
    structures = named_structures(document)
    require(set(named) == set(structures) == set(TARGETS), "heading identities differ from the authored targets")
    checks = [node for node in root.descendants() if node.role == "H2" and node.text == "Recovery checks"]
    require(len(checks) == 2, "the source must have two identical recovery headings")
    require(checks[0].value == document.get(structures[b"recovery-check-1"])
            and checks[1].value == document.get(structures[b"recovery-check-2"]),
            "the recovery heading destinations were swapped")
    for item, key in zip(toc.children, TARGETS, strict=True):
        require(item.role == "TOCI" and item.value.get("Ref") == [structures[key]],
                f"TOCI selected the wrong authored heading {key!r}")
        links = [node for node in item.descendants() if node.role == "Link"]
        require(len(links) == 2, "the title or page number lost its link")
        target_page, x, y = named[key]
        label = page_label(document, pages.index(target_page))
        require(links[1].text == label, f"{key!r} printed the wrong page label")
        for link in links:
            refs = [child for child in element_children(document, link.value)
                    if isinstance(child, dict) and child.get("Type") == "OBJR"]
            require(len(refs) == len(link.pages), "the link needs an annotation on each painted page")
            for ref in refs:
                action = document.get(int(ref["Obj"]))["A"]
                require(action["D"][0] == target_page and action["SD"][0] == structures[key],
                        "a linked entry disagrees with its paired destinations")
        if key == b"recovery-check-1":
            require(links[0].text == "Recovery checks", "the first title was changed")
        if key == b"recovery-check-2":
            require(links[0].text == "Recovery checks after settlement resumes", "the selected title override was lost")
        if key == b"commands":
            require(label == "A-1", "the appendix must use its restarted page labels")
    for page in toc.pages:
        stream = document.stream(int(document.get(page)["Contents"]))
        leaders = [block for kind, block in ARTIFACT.findall(stream)
                   if b"/Type /Layout" in kind and re.search(rb" 0\.6 0\.6 re", block)]
        require(leaders and all(b" Tf" not in block for block in leaders), "leaders must be nontext artifacts")


def validate_flow_fixture(pdf: bytes, dimensions: dict[str, int]) -> None:
    document, pages, root, _ = read(pdf)
    is_long = dimensions["flow_long"]
    page_index = is_long
    require(len(pages) == dimensions["pages"] == page_index + 1,
            "measured label must move the heading only for the long shape")
    paragraph, heading, body = root.children
    expected = "RECOVERY-CHECKS-2" if is_long else "A-1"
    require((paragraph.role, heading.role, body.role) == ("P", "H1", "P")
            and heading.text == "Recovery checks", "flow reference changed the logical body order")
    require({mark.page for mark in heading.marks} == {page_index},
            "heading paint is on the wrong committed page")
    link = only(paragraph.descendants(), "Link", expected)
    prefix = [mark for mark in paragraph.marks if mark not in link.marks]
    values = {glyph[2] for mark in link.marks for glyph in mark.glyphs}
    previous = {glyph[2] for mark in prefix for glyph in mark.glyphs}
    require(len(values) == 1 and values.isdisjoint(previous) == bool(is_long),
            "the resolved label must wrap as one unbreakable atom")
    destinations = check_name_tree(document.bodies, document.root, pages)
    require(set(destinations) == {b"recovery"}, "flow reference changed the authored target")
    page, _, _ = destinations[b"recovery"]
    require(page == pages[page_index] and page_label(document, page_index) == expected,
            "resolved label disagrees with the committed named destination")
    require(named_structures(document)[b"recovery"] == heading.number,
            "flow reference has the wrong structure destination")
    refs = [item for item in element_children(document, link.value)
            if isinstance(item, dict) and item.get("Type") == "OBJR"]
    require(len(refs) == 1, "flow reference link lost its annotation")
    action = document.get(int(refs[0]["Obj"]))["A"]
    require(action["D"][0] == page and action["SD"][0] == heading.number,
            "flow reference annotation disagrees with the final target")


def check(example: Path) -> None:
    for length, meaning in (("short", 0), ("long", 1)):
        payload = (example / f"operations-handbook-flow-{length}.pdf").read_bytes()
        validate_flow_fixture(payload, {"flow_long": meaning, "pages": meaning + 1})
    pdf = (example / "operations-handbook-generated.pdf").read_bytes()
    authored = (example / "operations-handbook.pdf").read_bytes()
    validate_handbook(pdf, authored)
    document, _, _ = tagged(pdf)
    structures = named_structures(document)
    one, two = (structures[key] for key in (b"recovery-check-1", b"recovery-check-2"))
    bad = twin(pdf, f"/Ref [{one} 0 R]".encode(), f"/Ref [{two} 0 R]".encode())
    try:
        validate_handbook(bad, authored)
    except ValidationError as error:
        require("wrong authored heading" in str(error), "wrong-target control failed for a different reason")
    else:
        raise ValidationError("the generated-contents oracle accepted a different valid heading")


def validate_generated_fixture(pdf: bytes, dimensions: dict[str, int]) -> None:
    document, pages, root = tagged(pdf)
    require(len(pages) == dimensions["pages"], "generated contents page count changed")
    count = dimensions["entries"]
    selected = tuple(f"recovery-{index}".encode() for index in range(1, count + 1))
    contents = only(root.descendants(), "TOC", "Recovery checks")
    require(len(contents.children) == count, "generated scope included or omitted a heading")
    structures = named_structures(document)
    named = check_name_tree(document.bodies, document.root, pages)
    require(set(structures) == set(selected) | {b"procedures", b"appendix"}, "unexpected authored headings")
    require(named[b"recovery-1"][0] != named[b"recovery-2"][0], "duplicate heading control needs different pages")
    for index, (item, target) in enumerate(zip(contents.children, selected, strict=True), 1):
        require(item.role == "TOCI" and item.value.get("Ref") == [structures[target]],
                "generated contents reference selected a wrong heading")
        target_page = named[target][0]
        label = page_label(document, pages.index(target_page))
        text = {1: "Recovery checks", 2: "Follow-up recovery checks"}.get(index, f"Regional check {index}")
        links = [node for node in item.descendants() if node.role == "Link"]
        require([link.text for link in links] == [text, label], "generated text disagrees with source or page label")
        for link in links:
            refs = [kid for kid in element_children(document, link.value)
                    if isinstance(kid, dict) and kid.get("Type") == "OBJR"]
            require(len(refs) == len(link.pages), "generated link lost annotation ownership")
            for ref in refs:
                action = document.get(int(ref["Obj"]))["A"]
                require(action["D"][0] == target_page and action["SD"][0] == structures[target],
                        "paired link destinations disagree with the authored heading")
    if count > 2:
        require(len(contents.pages) > 1, "scale fixture must continue its contents across pages")


if __name__ == "__main__":
    import argparse
    import json

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", required=True)
    parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    check(root / "examples/operations-handbook")
    spec = json.loads((root / "tests/spec.json").read_text())
    for case in spec["cases"]:
        if "generated_contents" in case["validators"]:
            validate_generated_fixture((root / case["snapshot"]).read_bytes(), case["dimensions"])
    print("PASS generated contents targets, page labels and mutation control")
