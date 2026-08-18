#!/usr/bin/env python3
"""Independent structural checks for Gate 4 transparency fixtures.

The checker parses the emitted bytes directly (no rewriting tool in front)
and proves the constant-opacity facts of the transparency slice without
trusting the Roc planner's summaries:

- every canonical ``ExtGState`` object is exactly
  ``<< /BM /Normal /CA a /Type /ExtGState /ca a >>`` with equal stroking and
  non-stroking alphas, one object per distinct alpha, and no ``/SMask``,
  knockout, or non-Normal blend state anywhere;
- every ``gs`` operand resolves through its own stream's exact direct
  ``/ExtGState`` dictionary (the used-equals-declared rule extends to
  graphics states), and each opacity group is the balanced
  ``q\\n/GSn gs`` .. ``Q`` shape;
- transparency pages carry ``/Group << /CS n 0 R /S /Transparency >>`` whose
  ``/CS`` resolves through the canonical ICCBased array to a profile stream
  byte-identical to the vendored ``sRGB2014.icc``;
- isolated forms carry ``/Group << /CS n 0 R /I true /S /Transparency >>``
  over the same blending space; non-isolated forms carry no ``/Group``;
- shared constants collapse to one physical state object across page and
  form dictionaries alike, while distinct constants never merge;
- placement-site MCID/ParentTree ownership stays exactly the page-stream
  facts of the form slice.
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

from check_gate4_forms import FormFacts, check_ownership, replace_once
from check_pdf_structure import (
    ValidationError,
    dictionary_ref,
    object_slices,
    require,
    validate_pdf,
)

ROOT = Path(__file__).resolve().parents[1]
SHOWCASE_SNAPSHOT = ROOT / "tests" / "gate4_transparency" / "snapshot.pdf"
SHARE_100_SNAPSHOT = ROOT / "tests" / "gate4_transparency_share_100" / "snapshot.pdf"
SHARE_1000_SNAPSHOT = ROOT / "tests" / "gate4_transparency_share_1000" / "snapshot.pdf"
STATES_100_SNAPSHOT = ROOT / "tests" / "gate4_transparency_states_100" / "snapshot.pdf"
STATES_1000_SNAPSHOT = ROOT / "tests" / "gate4_transparency_states_1000" / "snapshot.pdf"
NEST_16_SNAPSHOT = ROOT / "tests" / "gate4_transparency_nest_16" / "snapshot.pdf"
NEST_64_SNAPSHOT = ROOT / "tests" / "gate4_transparency_nest_64" / "snapshot.pdf"
FORMS_8_SNAPSHOT = ROOT / "tests" / "gate4_transparency_forms_8" / "snapshot.pdf"
FORMS_32_SNAPSHOT = ROOT / "tests" / "gate4_transparency_forms_32" / "snapshot.pdf"
NEGATIVE_SNAPSHOT = ROOT / "tests" / "gate4_transparency_negative" / "snapshot.pdf"
SRGB_PROFILE = ROOT / "vendor" / "icc" / "sRGB2014.icc"

STATE_OBJECT = re.compile(
    rb"^<< /BM /Normal /CA ([0-9.]+) /Type /ExtGState /ca ([0-9.]+) >>\s*endobj$"
)
MASK_STATE_OBJECT = re.compile(
    rb"^<< /SMask << /G ([1-9][0-9]*) 0 R /S /Alpha /Type /Mask >> /Type /ExtGState >>\s*endobj$"
)
GS_OPEN = re.compile(rb"q\n/([A-Za-z0-9_]+) gs\n")
PAGE_GROUP = re.compile(rb"/Group << /CS ([1-9][0-9]*) 0 R /S /Transparency >>")
FORM_GROUP = re.compile(rb"/Group << /CS ([1-9][0-9]*) 0 R /I true /S /Transparency >>")


def alpha_decimal(value: int) -> bytes:
    """The canonical U16-to-PDF-number mapping shared with color channels."""
    numerator = value * 10**9
    quotient, remainder = divmod(numerator, 65535)
    if remainder * 2 > 65535 or (remainder * 2 == 65535 and quotient % 2 == 1):
        quotient += 1
    if quotient == 0:
        return b"0"
    text = f"{quotient // 10**9}.{quotient % 10**9:09d}".rstrip("0").rstrip(".")
    return text.encode("ascii")


class TransparencyFacts:
    """Graphics-state and transparency-group objects of one fixture."""

    def __init__(self, pdf: bytes, expected_pages: int) -> None:
        self.form_facts = FormFacts(pdf, expected_pages)
        self.bodies = self.form_facts.bodies
        self.pages = self.form_facts.pages

        self.states: dict[int, bytes] = {}
        self.mask_states: dict[int, int] = {}
        for number, body in self.bodies.items():
            stripped = body.strip()
            if b"/ExtGState" not in stripped or stripped.startswith(b"<< /") is False:
                continue
            if b"/Type /ExtGState" not in stripped:
                continue
            mask_match = MASK_STATE_OBJECT.match(stripped)
            if mask_match is not None:
                self.mask_states[number] = int(mask_match.group(1))
                continue
            match = STATE_OBJECT.match(stripped)
            require(match is not None, f"state {number}: not a canonical constant-alpha or Alpha-mask shape")
            require(
                match.group(1) == match.group(2),
                f"state {number}: /CA {match.group(1)!r} disagrees with /ca {match.group(2)!r}",
            )
            self.states[number] = match.group(1)

        values = list(self.states.values())
        require(
            len(set(values)) == len(values),
            "two canonical ExtGState objects share one alpha; deduplication failed",
        )
        mask_targets = list(self.mask_states.values())
        require(
            len(set(mask_targets)) == len(mask_targets),
            "two canonical mask states share one mask form; deduplication failed",
        )

        ## Every mask state's /G resolves to an isolated-group form that
        ## never appears in any resource dictionary under a name (soft masks
        ## are referenced directly, never through /Resources).
        for number, target in self.mask_states.items():
            require(target in self.form_facts.forms, f"mask state {number}: /G does not reference a Form XObject")
            require(
                FORM_GROUP.search(self.form_facts.forms[target]) is not None,
                f"mask state {number}: mask form {target} is not an isolated transparency group",
            )

        ## Only the canonical Alpha mask shape may carry /SMask; luminosity
        ## masks, backdrop colors, knockout state, transfer functions, and
        ## non-Normal blend modes may appear nowhere.
        for number in self.states:
            require(b"/SMask" not in self.bodies[number], f"state {number}: soft mask emitted on an alpha state")
        for number, body in self.bodies.items():
            if b"/Type /ExtGState" in body and b"/SMask" in body:
                require(number in self.mask_states, f"object {number}: unclassified soft-mask state")
            for blend in re.finditer(rb"/BM /([A-Za-z]+)", body):
                require(blend.group(1) == b"Normal", f"object {number}: forbidden blend mode {blend.group(1)!r}")
            require(b"/Luminosity" not in body, f"object {number}: luminosity mask emitted")
            require(b"/BC " not in body, f"object {number}: mask backdrop color emitted")
            require(b"/TR " not in body and b"/TR2 " not in body, f"object {number}: transfer function emitted")

        ## Every gs operand resolves through its stream's direct dictionary
        ## to a canonical state object, and opens a balanced group.
        self.stream_gs: dict[str, list[int]] = {}
        for page in self.pages:
            self._check_stream(f"page {page}", self.form_facts.page_contents[page], self.form_facts.page_resources[page])
        for form in self.form_facts.forms:
            self._check_stream(f"form {form}", self.form_facts.form_contents[form], self.form_facts.form_resources[form])

    def _check_stream(self, owner: str, content: bytes, resources: dict[str, int]) -> None:
        targets: list[int] = []
        for match in re.finditer(rb"/([A-Za-z0-9_]+) gs", content):
            name = match.group(1).decode("ascii")
            require(name in resources, f"{owner}: gs operand /{name} does not resolve in the direct dictionary")
            target = resources[name]
            require(
                target in self.states or target in self.mask_states,
                f"{owner}: /{name} does not reference a canonical ExtGState object",
            )
            targets.append(target)
        opened = [m.group(1).decode("ascii") for m in GS_OPEN.finditer(content)]
        require(
            len(opened) == len(targets),
            f"{owner}: a gs operand is not the balanced q-then-gs group opening",
        )
        self.stream_gs[owner] = targets

    def page_group_space(self, page: int) -> int | None:
        match = PAGE_GROUP.search(self.bodies[page])
        return None if match is None else int(match.group(1))

    def check_blending_space(self, space: int) -> None:
        body = self.bodies.get(space)
        require(body is not None, "blending space object missing")
        icc = re.match(rb"\[/ICCBased ([1-9][0-9]*) 0 R\]", body.strip())
        require(icc is not None, "page /Group /CS is not the canonical ICCBased array")
        profile = int(icc.group(1))
        profile_body = self.bodies[profile]
        marker = profile_body.find(b"stream\n")
        require(marker >= 0, "blending profile is not a stream")
        payload = profile_body[marker + len(b"stream\n") : profile_body.rfind(b"\nendstream")]
        require(payload == SRGB_PROFILE.read_bytes(), "blending profile is not byte-identical to the vendored sRGB2014.icc")

    def isolated_forms(self) -> dict[int, int]:
        isolated = {}
        for form, dictionary in self.form_facts.forms.items():
            match = FORM_GROUP.search(dictionary)
            if match is not None:
                isolated[form] = int(match.group(1))
        return isolated


def validate_transparency_showcase(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = TransparencyFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.form_facts.page_contents[page], True)

    require(
        len(facts.states) == dimensions["canonical_ext_g_states"],
        f"expected {dimensions['canonical_ext_g_states']} canonical states, found {len(facts.states)}",
    )
    require(
        len(facts.form_facts.forms) == dimensions["canonical_forms"],
        "physical form count is not the canonical count",
    )

    ## The exact canonical alphas: 0.5, 0.75, 0.25, and zero — including the
    ## nested 0.75 x 2/3 product that must collapse onto the directly
    ## authored 0.5 rather than minting a fifth state.
    expected_values = {alpha_decimal(32768), alpha_decimal(49152), alpha_decimal(16384), alpha_decimal(0)}
    require(
        set(facts.states.values()) == expected_values,
        f"canonical alphas {sorted(facts.states.values())} differ from the authored constants",
    )

    ## The page transparency group resolves to the vendored sRGB profile.
    group_space = facts.page_group_space(page)
    require(group_space is not None, "transparency page lost its /Group dictionary")
    facts.check_blending_space(group_space)

    ## Exactly one isolated form group over the same blending space; the
    ## other forms carry no /Group at all.
    isolated = facts.isolated_forms()
    require(len(isolated) == dimensions["isolated_forms"], "isolated form-group count mismatch")
    for form, space in isolated.items():
        require(space == group_space, f"form {form}: group blending space diverges from the page group")

    ## Cross-stream canonical sharing: the page's 0.25 state object and the
    ## in-form 0.25 state object are one physical object, and the isolated
    ## form's internal 0.5 shares the page's 0.5 object.
    by_value = {value: number for number, value in facts.states.items()}
    quarter = by_value[alpha_decimal(16384)]
    half = by_value[alpha_decimal(32768)]
    form_targets = {target for owner, targets in facts.stream_gs.items() if owner.startswith("form") for target in targets}
    require(quarter in form_targets, "the in-form 0.25 group does not share the canonical page state")
    require(half in form_targets, "the isolated form's 0.5 group does not share the canonical page state")

    ## The opaque identity emitted no state: total gs operands across every
    ## stream equal the nine non-opaque groups.
    total_gs = sum(len(targets) for targets in facts.stream_gs.values())
    require(total_gs == dimensions["opacity_groups"], f"expected {dimensions['opacity_groups']} gs operands, found {total_gs}")

    ## Placement-site ownership stays page-stream facts: four meaningful
    ## placements, logical order leading with the second painted paragraph.
    check_ownership(facts.form_facts, page, 4)
    catalog = next(number for number, body in facts.bodies.items() if b"/Type /Catalog" in body)
    structure_root = dictionary_ref(facts.bodies[catalog], b"StructTreeRoot")
    document = dictionary_ref(facts.bodies[structure_root], b"K")
    document_k = re.search(rb"/K \[([^]]*)\]", facts.bodies[document])
    require(document_k is not None, "document /K missing")
    children = [int(match.group(1)) for match in re.finditer(rb"([1-9][0-9]*) 0 R", document_k.group(1))]
    require(len(children) == 4, "document does not hold the four paragraphs")
    first_child_mcids = [int(m.group(1)) for m in re.finditer(rb"<< /MCID ([0-9]+) /Pg", facts.bodies[children[0]])]
    require(first_child_mcids == [1], "logical reading order does not lead with the second painted paragraph")

    ## The alpha image keeps its raster soft mask (image /SMask is the
    ## existing color-image capability, distinct from ExtGState masks).
    image_masks = [
        number
        for number, body in facts.bodies.items()
        if b"/Subtype /Image" in body and b"/SMask" in body
    ]
    require(len(image_masks) == 1, "the alpha image lost its raster soft mask")


def validate_transparency_grid(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = TransparencyFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.form_facts.page_contents[page], True)

    groups = dimensions["opacity_groups"]
    canonical = dimensions["canonical_ext_g_states"]
    require(len(facts.states) == canonical, f"expected {canonical} canonical states, found {len(facts.states)}")
    page_gs = facts.stream_gs[f"page {page}"]
    require(len(page_gs) == groups, f"expected {groups} gs operands, found {len(page_gs)}")
    require(len(set(page_gs)) == canonical, "gs operands do not resolve to exactly the canonical state objects")
    group_space = facts.page_group_space(page)
    require(group_space is not None, "transparency page lost its /Group dictionary")
    facts.check_blending_space(group_space)
    require(not facts.isolated_forms(), "grid fixtures carry no isolated form groups")


def validate_transparency_nest(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = TransparencyFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.form_facts.page_contents[page], True)

    depth = dimensions["nest_depth"]
    require(len(facts.states) == depth, f"expected {depth} distinct nested states, found {len(facts.states)}")
    content = facts.form_facts.page_contents[page]
    page_gs = facts.stream_gs[f"page {page}"]
    require(len(page_gs) == depth, "nested chain does not open one state per level")
    require(len(set(page_gs)) == depth, "nested chain levels do not stay distinct")

    ## The chain nests: each `q /GS.. gs` is followed by another opening or
    ## the innermost path, and the run of closes is contiguous.
    opens = [m.start() for m in GS_OPEN.finditer(content)]
    closes = content.count(b"Q\n")
    require(closes >= depth, "nested chain lost its balanced closes")
    for first, second in zip(opens, opens[1:]):
        between = content[first:second]
        require(b"Q" not in between, "nested chain closed a group before its child opened")

    group_space = facts.page_group_space(page)
    require(group_space is not None, "transparency page lost its /Group dictionary")
    facts.check_blending_space(group_space)


def validate_transparency_forms(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = TransparencyFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.form_facts.page_contents[page], True)

    forms = dimensions["opacity_forms"]
    require(len(facts.form_facts.forms) == forms, f"expected {forms} distinct forms, found {len(facts.form_facts.forms)}")
    require(len(facts.states) == 1, "the shared constant must collapse to one canonical state")
    shared_state = next(iter(facts.states))
    for form in facts.form_facts.forms:
        targets = facts.stream_gs[f"form {form}"]
        require(targets == [shared_state], f"form {form}: does not open exactly the one shared state")
        entries = {name: target for name, target in facts.form_facts.form_resources[form].items() if name.startswith("GS")}
        require(list(entries.values()) == [shared_state], f"form {form}: /ExtGState dictionary is not exactly the shared state")
    require(facts.stream_gs[f"page {page}"] == [], "the page stream itself paints no opacity group")
    group_space = facts.page_group_space(page)
    require(group_space is not None, "transparency page lost its /Group dictionary")
    facts.check_blending_space(group_space)
    require(not facts.isolated_forms(), "per-form opacity fixtures carry no isolated groups")


def validate_gate4_transparency_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    if dimensions.get("gate4_transparency_showcase"):
        validate_transparency_showcase(pdf, dimensions)
    elif dimensions.get("gate4_transparency_share") or dimensions.get("gate4_transparency_states"):
        validate_transparency_grid(pdf, dimensions)
    elif dimensions.get("gate4_transparency_nest"):
        validate_transparency_nest(pdf, dimensions)
    elif dimensions.get("gate4_transparency_forms"):
        validate_transparency_forms(pdf, dimensions)
    else:
        raise ValidationError("unknown Gate 4 transparency fixture dimensions")


SHOWCASE_DIMENSIONS = {
    "pages": 1,
    "gate4_transparency_showcase": 1,
    "opacity_commands": 10,
    "opacity_groups": 9,
    "canonical_ext_g_states": 4,
    "canonical_forms": 3,
    "isolated_forms": 1,
}


def self_test() -> None:
    showcase = SHOWCASE_SNAPSHOT.read_bytes()
    validate_transparency_showcase(showcase, SHOWCASE_DIMENSIONS)
    validate_transparency_grid(
        SHARE_100_SNAPSHOT.read_bytes(),
        {"pages": 1, "gate4_transparency_share": 1, "opacity_groups": 100, "canonical_ext_g_states": 1},
    )
    validate_transparency_grid(
        SHARE_1000_SNAPSHOT.read_bytes(),
        {"pages": 1, "gate4_transparency_share": 1, "opacity_groups": 1000, "canonical_ext_g_states": 1},
    )
    validate_transparency_grid(
        STATES_100_SNAPSHOT.read_bytes(),
        {"pages": 1, "gate4_transparency_states": 1, "opacity_groups": 100, "canonical_ext_g_states": 100},
    )
    validate_transparency_grid(
        STATES_1000_SNAPSHOT.read_bytes(),
        {"pages": 1, "gate4_transparency_states": 1, "opacity_groups": 1000, "canonical_ext_g_states": 1000},
    )
    validate_transparency_nest(
        NEST_16_SNAPSHOT.read_bytes(),
        {"pages": 1, "gate4_transparency_nest": 1, "nest_depth": 16},
    )
    validate_transparency_nest(
        NEST_64_SNAPSHOT.read_bytes(),
        {"pages": 1, "gate4_transparency_nest": 1, "nest_depth": 64},
    )
    validate_transparency_forms(
        FORMS_8_SNAPSHOT.read_bytes(),
        {"pages": 1, "gate4_transparency_forms": 1, "opacity_forms": 8},
    )
    validate_transparency_forms(
        FORMS_32_SNAPSHOT.read_bytes(),
        {"pages": 1, "gate4_transparency_forms": 1, "opacity_forms": 32},
    )
    validate_transparency_grid(
        NEGATIVE_SNAPSHOT.read_bytes(),
        {"pages": 1, "gate4_transparency_share": 1, "opacity_groups": 1, "canonical_ext_g_states": 1},
    )

    ## Length-preserving mutation twins: each must be rejected.
    mutations = (
        ("blend mode", replace_once(showcase, b"/BM /Normal", b"/BM /Nermal")),
        ("stroking alpha agreement", replace_once(showcase, b"/CA 0.50000763", b"/CA 0.50000765")),
        ("page group kind", replace_once(showcase, b"/S /Transparency", b"/S /Transparencx")),
        ("isolated flag", replace_once(showcase, b"/I true", b"/I truk")),
    )
    for label, mutation in mutations:
        try:
            validate_transparency_showcase(mutation, SHOWCASE_DIMENSIONS)
        except ValidationError:
            continue
        raise SystemExit(f"Gate 4 transparency checker accepted mutated {label}")
    print("PASS Gate 4 transparency structural checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path, default=SHOWCASE_SNAPSHOT)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    validate_transparency_showcase(args.pdf.read_bytes(), SHOWCASE_DIMENSIONS)
    print(f"PASS Gate 4 transparency structural check: {args.pdf}")


if __name__ == "__main__":
    main()
