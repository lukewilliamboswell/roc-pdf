#!/usr/bin/env python3
"""Compare visible text, editable repertoire, and widget ownership with form authorship."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import struct
import subprocess
import tempfile

from check_pdf_structure import ValidationError, require
from check_profile_declarations import validate_claims
from check_rich_inline import page_marked_text
from check_structure_semantics import Document, Parser, Ref, element_children, page_order, text_string, validate_structure_semantics_pdf
from pdf_layout import mutate

ROOT = Path(__file__).resolve().parents[1]
DA = b"0 0 0 rg /Ftx 10 Tf"


@dataclass(frozen=True)
class Field:
    id: str
    label: str
    value: str | bool
    page: int
    x: int
    y: int
    width: int

    @property
    def rect(self) -> list[int]:
        return [self.x, self.y, self.x + self.width, self.y + 22]


def expected_fields(dimensions: dict[str, int]) -> list[Field]:
    if dimensions.get("mixed_intake"):
        return [
            Field("contact_name", "Contact name", "", 0, 56, 614, 300),
            Field("inspection_report", "Include an inspection report", True, 0, 56, 570, 22),
            Field("service_reference", "Service reference", "HF-2041", 0, 56, 500, 180),
            Field("site_visit", "Request a site visit", False, 0, 56, 456, 22),
        ]
    if dimensions.get("checkbox_defaults"):
        return [Field("visit", "Request a site visit", False, 0, 56, 650, 22)]
    if dimensions.get("mixed_scale"):
        return [
            Field(f"mixed_{index}", f"Option {index}", f"Ref {index}" if index % 2 else index % 4 == 0,
                  index // 6, 56, 680 - index % 6 * 64, 200 if index % 2 else 22)
            for index in range(dimensions["fields"])
        ]
    if dimensions.get("intake"):
        return [
            Field("contact_name", "Contact name", "", 0, 56, 614, 300),
            Field("service_reference", "Service reference", "HF-2041", 0, 56, 550, 180),
        ]
    if dimensions.get("defaults"):
        return [Field("name", "Name", "", 0, 56, 650, 200)]
    return [
        Field(f"field_{index}", f"Intake label {index}", f"Ref {index}" if index % 2 else "",
              index // 6, 56, 680 - index % 6 * 64, 200)
        for index in range(dimensions["fields"])
    ]


def validate_fillable_pdf(data: bytes, dimensions: dict[str, int]) -> None:
    validate(data, expected_fields(dimensions), bool(dimensions.get("wtpdf")))


def validate(data: bytes, expected: list[Field], wtpdf: bool) -> None:
    validate_claims(data, wtpdf=wtpdf)
    validate_structure_semantics_pdf(data, {"pages": 1 + max(field.page for field in expected)})
    document = Document(data)
    catalog = document.get(document.root)
    form = catalog["AcroForm"]
    font_ref = None
    if any(isinstance(field.value, str) for field in expected):
        require(set(form) == {"DA", "DR", "Fields"} and form["DA"] == DA, "AcroForm default appearance or resource contract changed")
        font_ref = form["DR"]["Font"]["Ftx"]
        require(isinstance(font_ref, Ref), "the editable font must be an indirect object")
        verify_editable_font(document, font_ref)
    else:
        require(set(form) == {"Fields"}, "checkbox-only form must contain only a Fields registry")
    widgets = form["Fields"]
    require(len(widgets) == len(expected) and len(set(widgets)) == len(widgets), "AcroForm field count or identity changed")
    pages: list[int] = []
    page_order(document, int(catalog["Pages"]), pages)
    require(len(pages) == 1 + max(field.page for field in expected), "physical page count differs")
    tree = document.get(int(catalog["StructTreeRoot"]))
    document_role = document.get(int(tree["K"]))
    form_owners = [
        child for child in element_children(document, document_role)
        if isinstance(child, Ref) and document.get(int(child))["S"] == "Form"
    ]
    require(len(form_owners) == len(widgets), "logical structure lost or duplicated a Form")
    by_page: list[list[Ref]] = [[] for _ in pages]
    labels = [dict(page_marked_text(document, page)) for page in pages]
    shared_checkbox_appearances = None
    for authored, widget_ref, owner_ref in zip(expected, widgets, form_owners, strict=True):
        require(isinstance(widget_ref, Ref), "field must be one indirect terminal widget")
        page = pages[authored.page]
        by_page[authored.page].append(widget_ref)
        widget = document.get(int(widget_ref))
        require(widget["Type"] == "Annot" and widget["Subtype"] == "Widget", "field has no terminal widget")
        require(widget["T"] == authored.id.encode("ascii"), "field identity differs from authored order")
        require(text_string(widget["TU"]) == authored.label, "field context label differs")
        require(widget["F"] == 4 and widget["Ff"] == 0, "field is not printable, visible and editable")
        require(widget["P"] == Ref(page) and widget["Rect"] == authored.rect, "widget page or rectangle differs")
        require(not any(key in widget for key in ("RV", "AA", "A", "Kids")), "unsupported widget contents")
        require(set(widget["AP"]) == {"N"}, "widget must supply only normal appearances")
        normal = widget["AP"]["N"]
        if isinstance(authored.value, str):
            require(widget["FT"] == "Tx", "wrong text field type")
            require(widget["V"] == authored.value.encode("ascii"), "field initial value differs")
            require(widget["DA"] == DA and widget["MaxLen"] == 64, "text field default appearance or editable flags changed")
            require(isinstance(normal, Ref) and font_ref is not None, "text widget needs a single normal appearance stream and editable font")
            verify_appearance(document, int(normal), authored, font_ref)
        else:
            require(widget["FT"] == "Btn", "wrong checkbox field type")
            require(set(widget) == {"Type", "Subtype", "AP", "AS", "F", "FT", "Ff", "P", "Rect", "StructParent", "T", "TU", "V"}, "checkbox requires a vector-only terminal field dictionary")
            state = "Yes" if authored.value else "Off"
            require(widget["V"] == state and widget["AS"] == state, "checkbox initial field value or selected appearance differs")
            require(isinstance(normal, dict) and set(normal) == {"Yes", "Off"}, "checkbox must provide both named normal appearances")
            require(len(set(normal.values())) == 2 and all(isinstance(ref, Ref) for ref in normal.values()), "checkbox appearances must be two distinct streams")
            if shared_checkbox_appearances is None:
                verify_checkbox_appearances(document, normal)
                shared_checkbox_appearances = normal
            else:
                require(normal == shared_checkbox_appearances, "checkboxes must share their normal appearance objects")

        owner = document.get(int(owner_ref))
        children = element_children(document, owner)
        require(len(children) == 2 and isinstance(children[0], Ref) and isinstance(children[1], dict), "Form needs one Lbl followed by one OBJR")
        label = document.get(int(children[0]))
        require(label["S"] == "Lbl" and label["P"] == owner_ref, "visible label is not a direct child of its Form")
        require(children[1] == {"Obj": widget_ref, "Pg": Ref(page), "Type": "OBJR"}, "Form does not point to its intended widget")
        label_parts = element_children(document, label)
        require(all(part["Type"] == "MCR" and part["Pg"] == Ref(page) for part in label_parts), "visible label does not belong to the widget's page")
        shown_label = "".join(labels[authored.page][part["MCID"]] for part in label_parts)
        require(shown_label == authored.label, "visible label text differs from its authored widget assignment")
    for page, refs in zip(pages, by_page, strict=True):
        page_value = document.get(page)
        require(page_value.get("Tabs") == "S" and page_value.get("Annots", []) == refs, "page tab order differs from authored field order")


def verify_appearance(document: Document, appearance: int, authored: Field, font_ref: Ref) -> None:
    dictionary = document.get(appearance)
    require(dictionary["Subtype"] == "Form" and dictionary["Type"] == "XObject", "normal appearance is not a Form XObject")
    require(dictionary["BBox"] == [0, 0, authored.width, 22] and dictionary["Resources"] == {"Font": {"Ftx": font_ref}}, "appearance dimensions or editable face disagree")
    operations = document.stream(appearance)
    require(operations.count(DA) == 1 and b"/Tx BMC\n" in operations, "normal appearance lacks default variable text")
    prefix = b"\n4 7 Td\n"
    start = operations.index(prefix) + len(prefix)
    parser = Parser(operations[start:], canonical=False)
    shown = parser.value()
    require(shown == authored.value.encode("ascii"), "appearance text differs from authored initial value")
    require(operations[start + parser.at:] == b" Tj\nET\nQ\nEMC\n", "extra content follows initial value")


def verify_checkbox_appearances(document: Document, normal: dict[str, Ref]) -> None:
    for state, ref in normal.items():
        dictionary = document.get(int(ref))
        require(dictionary["Subtype"] == "Form" and dictionary["Type"] == "XObject", "checkbox appearance is not a Form XObject")
        require(dictionary["BBox"] == [0, 0, 22, 22] and dictionary["Resources"] == {}, "checkbox appearance needs a vector-only 22-point box")
        operators = document.stream(int(ref)).split()
        require(operators[:15] == b"q 1 1 1 rg 0 0 0 RG 1 w 0.5 0.5 21 21".split(), "checkbox box geometry differs")
        require(operators[15:17] == [b"re", b"B"] and operators[-1] == b"Q", "checkbox border is not a white-filled black outline")
        mark = operators[17:-1]
        if state == "Off":
            require(not mark, "Off checkbox appearance unexpectedly paints a check mark")
        else:
            require(mark == b"2 w 1 J 1 j 5 11 m 9 7 l 17 15 l S".split(), "Yes checkbox appearance has no check mark")


def verify_editable_font(document: Document, ref: Ref) -> None:
    dictionary = document.get(int(ref))
    require(dictionary["Subtype"] == "TrueType" and dictionary["Encoding"] == "WinAnsiEncoding", "unsupported editable font declaration")
    require(dictionary["FirstChar"] == 32 and dictionary["LastChar"] == 126, "editable font repertoire changed")
    descriptor = document.get(int(dictionary["FontDescriptor"]))
    program = document.stream(int(descriptor["FontFile2"]))
    require(program == (ROOT / "package/RocPdfSans-Regular.ttf").read_bytes(), "the editable face must embed the complete packaged program")
    cmap = document.stream(int(dictionary["ToUnicode"]))
    require(re.findall(rb"\d+ beginbfrange\n([^\n]+)\nendbfrange", cmap) == [b"<20> <7E> <0020>"], "the editable font's one-byte ToUnicode repertoire changed")
    require(dictionary["Widths"] == font_ascii_widths(program), "editable-to-visible font widths disagree")


def font_ascii_widths(program: bytes) -> list[int]:
    u16 = lambda offset: struct.unpack_from(">H", program, offset)[0]
    tables = {}
    for index in range(u16(4)):
        tag, _, offset, _ = struct.unpack_from(">4sIII", program, 12 + 16 * index)
        tables[tag] = offset
    cmap = tables[b"cmap"]
    windows = []
    for index in range(u16(cmap + 2)):
        platform, encoding, relative = struct.unpack_from(">HHI", program, cmap + 4 + 8 * index)
        if platform == 3 and encoding == 1:
            windows.append(cmap + relative)
    require(len(windows) == 1 and u16(windows[0]) == 4, "the editable face has no Windows Unicode cmap")
    table = windows[0]
    count = u16(table + 6) // 2
    endcodes = table + 14
    startcodes = endcodes + count * 2 + 2
    deltas = startcodes + count * 2
    ranges = deltas + count * 2
    widths = []
    units = u16(tables[b"head"] + 18)
    metrics = u16(tables[b"hhea"] + 34)
    glyph_count = u16(tables[b"maxp"] + 4)
    for character in range(32, 127):
        segment = next((i for i in range(count) if u16(startcodes + 2 * i) <= character <= u16(endcodes + 2 * i)), None)
        require(segment is not None, f"editable character {character} is missing from the embedded font")
        start = u16(startcodes + 2 * segment)
        delta = u16(deltas + 2 * segment)
        slot = ranges + 2 * segment
        radial = u16(slot)
        glyph = u16(slot + radial + 2 * (character - start)) if radial else character
        glyph = (glyph + delta) % 65536 if glyph else glyph
        require(0 < glyph < glyph_count, f"editable character {character} resolves to a missing glyph")
        width = u16(tables[b"hmtx"] + 4 * min(glyph, metrics - 1))
        widths.append((width * 1000 + units // 2) // units)
    return widths


def self_test(renderer: Path | None) -> None:
    data = (ROOT / "tests/interactive_fields/intake.pdf").read_bytes()
    expected = expected_fields({"intake": 1})
    validate(data, expected, False)
    wrong = mutate(data, b"(HF-2041) Tj", b"(HF-2042) Tj", scope="payloads")
    controls = [
        (wrong, "appearance text differs"),
        (mutate(data, b"/Ff 0 /MK", b"/Ff 1 /MK", occurrences=None, scope="objects", first_only=True), "not printable, visible and editable"),
        (mutate(data, b"/TU (Contact name)", b"/TU (Different name)", scope="objects"), "field context label differs"),
    ]
    for original, diagnostic in controls:
        try:
            validate(original, expected, False)
        except ValidationError as error:
            require(diagnostic in str(error), f"unexpected mutation diagnostic: {error}")
        else:
            raise ValidationError(f"mutation passed: {diagnostic}")
    mixed = (ROOT / "tests/interactive_fields/mixed_intake.pdf").read_bytes()
    expected_mixed = expected_fields({"mixed_intake": 1})
    validate(mixed, expected_mixed, False)
    wrong_state = mutate(mutate(mixed, b"/AS /Yes", b"/AS /Off", scope="objects"), b"/V /Yes", b"/V /Off", scope="objects")
    document = Document(mixed)
    checked = document.get(int(document.get(document.root)["AcroForm"]["Fields"][1]))
    refs = checked["AP"]["N"]
    original = f'/Off {int(refs["Off"])} 0 R /Yes {int(refs["Yes"])} 0 R'.encode("ascii")
    swapped = f'/Off {int(refs["Yes"])} 0 R /Yes {int(refs["Off"])} 0 R'.encode("ascii")
    wrong_appearance = mutate(mixed, original, swapped, occurrences=2, scope="objects")
    for pdf, diagnostic in [
        (wrong_state, "checkbox initial field value or selected appearance differs"),
        (wrong_appearance, "Off checkbox appearance unexpectedly paints a check mark"),
    ]:
        try:
            validate(pdf, expected_mixed, False)
        except ValidationError as error:
            require(diagnostic in str(error), f"unexpected checkbox mutation diagnostic: {error}")
        else:
            raise ValidationError(f"checkbox mutation passed: {diagnostic}")
    if renderer is not None:
        blank, filled = rendered_field_interiors(renderer, data, [(60, 618, 180, 632), (60, 554, 180, 568)])
        require(blank == 0 and filled > 0, "rendered text field interiors disagree with the initial values")
        boxes = [(59, 574, 75, 588), (59, 460, 75, 474)]
        checked, unchecked = rendered_field_interiors(renderer, mixed, boxes)
        require(checked > 0 and unchecked == 0, "rendered checkbox interiors disagree with the initial states")
        require(rendered_field_interiors(renderer, wrong_state, boxes) == [0, 0], "wrong state should render both boxes unchecked")
        swapped_checked, swapped_unchecked = rendered_field_interiors(renderer, wrong_appearance, boxes)
        require(swapped_checked == 0 and swapped_unchecked > 0, "swapped appearance should reverse both visible marks")
    print("PASS decoded form field values, editable repertoire, tagged label ownership, and text/checkbox mutation controls")


def rendered_field_interiors(renderer: Path, data: bytes, regions: list[tuple[int, int, int, int]]) -> list[int]:
    scratch = ROOT / ".roc-pdf-tmp"
    scratch.mkdir(exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".pdf", dir=scratch) as source:
        source.write(data)
        source.flush()
        rendered = subprocess.check_output([str(renderer), "-f", "1", "-singlefile", "-r", "96", source.name])
    signature, dimensions, maximum, pixels = rendered.split(b"\n", 3)
    require(signature == b"P6" and maximum == b"255", "Poppler must emit an 8-bit RGB pixmap")
    width, height = map(int, dimensions.split())
    require((width, height) == (794, 1123) and len(pixels) == width * height * 3, "unexpected preview geometry")
    counts = []
    for x0, y0, x1, y1 in regions:
        # The source fixture is A4, with its origin in the lower left.
        left, top, right, bottom = [round(points * 96 / 72) for points in (x0, 842 - y1, x1, 842 - y0)]
        counts.append(sum(
            pixels[index:index + 3] != b"\xff\xff\xff"
            for y in range(top, bottom)
            for x in range(left, right)
            for index in (3 * (y * width + x),)
        ))
    return counts


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", required=True, action="store_true")
    parser.add_argument("--renderer", type=Path, help="run optional rendered field checks with the pinned pdftoppm")
    self_test(parser.parse_args().renderer)
