#!/usr/bin/env python3
"""Independent structural checks for the production-visual shading and tiling-pattern
fixtures.

The checker parses the emitted bytes directly (no rewriting tool in front)
and proves the paint facts of the slice without trusting the Roc planner's
summaries:

- every shading dictionary is exactly the supported axial/radial shape:
  ``/ShadingType 2|3``, exact ``/Coords``, an explicit ``/Domain [0 1]``, an
  explicit two-boolean ``/Extend``, a resolvable ``/ColorSpace``, and a
  ``/Function`` resolving to a supported function object;
- every function object is either an exponential segment
  (``/FunctionType 2``, explicit ``/C0``/``/C1``, ``/Domain [0 1]``,
  ``/N 1``) or a stitching function (``/FunctionType 3``, strictly
  increasing interior ``/Bounds``, ``[0 1]`` ``/Encode`` pairs, segment
  children), and the stop model is re-derived from bounds plus segment
  endpoint continuity;
- every tiling pattern stream is exactly the colored constant-spacing shape
  (``/PatternType 1 /PaintType 1 /TilingType 1``) with positive steps, an
  explicit matrix, and exactly its direct nested resource dictionary;
- every ``sh`` operand resolves through its own stream's direct ``/Shading``
  dictionary, and every pattern ``scn`` operand through its own stream's
  direct ``/Pattern`` dictionary after a ``/Pattern cs`` selection;
- function objects appear in no resource dictionary (they are reachable
  only through ``/Function``/``/Functions`` references), pattern streams
  carry no marked content or ``/StructParents``, equal canonical recipes
  share one physical object, and distinct recipes never merge;
- no unsupported shading type, function type, paint type, or tiling type
  appears anywhere in the file.
"""
from __future__ import annotations

import argparse
import re
import zlib
from pathlib import Path

from check_forms import check_balance, check_ownership, decoded_stream, replace_once
from check_transparency import alpha_decimal
from check_pdf_structure import ValidationError, dictionary_ref, require, validate_pdf

ROOT = Path(__file__).resolve().parents[1]
SHOWCASE_SNAPSHOT = ROOT / "tests" / "shading_patterns" / "shadings.pdf"
SHARE_100_SNAPSHOT = ROOT / "tests" / "shading_patterns" / "shadings_share_100.pdf"
SHARE_1000_SNAPSHOT = ROOT / "tests" / "shading_patterns" / "shadings_share_1000.pdf"
DISTINCT_8_SNAPSHOT = ROOT / "tests" / "shading_patterns" / "shadings_distinct_8.pdf"
DISTINCT_64_SNAPSHOT = ROOT / "tests" / "shading_patterns" / "shadings_distinct_64.pdf"
STOPS_16_SNAPSHOT = ROOT / "tests" / "shading_patterns" / "shadings_stops_16.pdf"
STOPS_64_SNAPSHOT = ROOT / "tests" / "shading_patterns" / "shadings_stops_64.pdf"
PSHARE_100_SNAPSHOT = ROOT / "tests" / "shading_patterns" / "patterns_share_100.pdf"
PSHARE_1000_SNAPSHOT = ROOT / "tests" / "shading_patterns" / "patterns_share_1000.pdf"
PDISTINCT_8_SNAPSHOT = ROOT / "tests" / "shading_patterns" / "patterns_distinct_8.pdf"
PDISTINCT_64_SNAPSHOT = ROOT / "tests" / "shading_patterns" / "patterns_distinct_64.pdf"
PCELLS_16_SNAPSHOT = ROOT / "tests" / "shading_patterns" / "patterns_cells_16.pdf"
PCELLS_64_SNAPSHOT = ROOT / "tests" / "shading_patterns" / "patterns_cells_64.pdf"
NEGATIVE_SNAPSHOT = ROOT / "tests" / "shading_patterns" / "shadings_negative.pdf"

from check_pdf_structure import object_slices

PAINT_BUCKETS = rb"/(ColorSpace|ExtGState|Font|Pattern|Shading|XObject) << ([^>]*) >>"
NAME_OPERAND = re.compile(rb"/([A-Za-z0-9_]+) (Do|cs|CS|gs|sh|scn|SCN)(?:\s|$)")
MCID_SEQUENCE = re.compile(rb"/P <</MCID ([0-9]+)>> BDC\n")
NUMBER = rb"-?[0-9]+(?:\.[0-9]+)?"


def parse_paint_resources(dictionary: bytes, owner: str) -> dict[str, int]:
    """The exact direct resource dictionary of one stream, including the
    /Pattern and /Shading buckets this slice introduces."""
    match = re.search(rb"/Resources << (.*?) >> /(?:Rotate|Subtype|TilingType|Type)", dictionary, re.DOTALL)
    if match is None:
        match = re.search(rb"/Resources << (.*) >>", dictionary, re.DOTALL)
    require(match is not None, f"{owner}: missing /Resources dictionary")
    body = match.group(1)
    entries: dict[str, int] = {}
    for sub in re.finditer(PAINT_BUCKETS, body):
        for entry in re.finditer(rb"/([A-Za-z0-9_]+) ([1-9][0-9]*) 0 R", sub.group(2)):
            name = entry.group(1).decode("ascii")
            require(name not in entries, f"{owner}: duplicate resource name {name}")
            entries[name] = int(entry.group(2))
    stripped = re.sub(PAINT_BUCKETS, b"", body).strip()
    require(stripped == b"", f"{owner}: unexpected resource dictionary content {stripped!r}")
    return entries


def used_paint_names(content: bytes) -> set[str]:
    """Every resource name a stream's operators use. The literal ``/Pattern
    cs`` selection names the Pattern color-space family, not a resource."""
    names = set()
    for match in NAME_OPERAND.finditer(content):
        name = match.group(1).decode("ascii")
        if name == "Pattern" and match.group(2) == b"cs":
            continue
        names.add(name)
    return names


def check_stream_dictionary(owner: str, content: bytes, resources: dict[str, int]) -> None:
    used = used_paint_names(content)
    declared = set(resources)
    require(
        used == declared,
        f"{owner}: operators use {sorted(used)} but the direct dictionary declares "
        f"{sorted(declared)}; every entry must be a direct use and every use must resolve",
    )


def check_pattern_selection(owner: str, content: bytes) -> None:
    """Every pattern paint is the exact two-operator selection: the Pattern
    color-space family, then the canonical ``Pt`` name as ``scn``."""
    for match in re.finditer(rb"/(Pt[0-9A-Za-z_]*) (scn|SCN)", content):
        require(match.group(2) == b"scn", f"{owner}: pattern selected as a stroking paint")
    scn_names = re.findall(rb"/([A-Za-z0-9_]+) scn\n", content)
    pattern_names = [name for name in scn_names if name.startswith(b"Pt")]
    selections = re.findall(rb"/Pattern cs\n/(Pt[A-Za-z0-9_]*) scn\n", content)
    require(
        len(selections) == len(pattern_names),
        f"{owner}: every pattern paint must be the exact '/Pattern cs' + '/Pt.. scn' selection",
    )


def check_stream_neutrality(owner: str, content: bytes) -> None:
    """Reusable paint streams carry no marked content and no text."""
    require(b"BDC" not in content, f"{owner}: marked content inside an ownership-neutral stream")
    require(b"/MCID" not in content, f"{owner}: MCID inside an ownership-neutral stream")
    require(b"BT\n" not in content, f"{owner}: text inside an ownership-neutral stream")


class PaintFacts:
    """Every shading, function, and pattern object plus per-stream resolved
    resource dictionaries, parsed directly from the emitted bytes."""

    def __init__(self, pdf: bytes, expected_pages: int) -> None:
        _, bodies = object_slices(pdf)
        self.bodies = bodies
        self.pages = [number for number, body in bodies.items() if b"/Type /Page " in body]
        require(len(self.pages) == expected_pages, "unexpected page count")

        ## No unsupported paint construct anywhere in the file.
        for number, body in bodies.items():
            for forbidden in (b"/ShadingType 1", b"/ShadingType 4", b"/ShadingType 5", b"/ShadingType 6", b"/ShadingType 7"):
                require(forbidden not in body, f"object {number}: unsupported shading type")
            for forbidden in (b"/FunctionType 0", b"/FunctionType 4"):
                require(forbidden not in body, f"object {number}: unsupported function type")
            for forbidden in (b"/PatternType 2", b"/PaintType 2", b"/TilingType 2", b"/TilingType 3"):
                require(forbidden not in body, f"object {number}: unsupported pattern shape")

        self.shadings: dict[int, dict] = {}
        self.functions: dict[int, dict] = {}
        self.patterns: dict[int, bytes] = {}
        for number, body in bodies.items():
            if b"/ShadingType" in body:
                self.shadings[number] = self.parse_shading(number, body)
            elif b"/FunctionType" in body:
                self.functions[number] = self.parse_function(number, body)
            elif b"/PatternType 1" in body:
                self.patterns[number] = body

        for number, fact in self.shadings.items():
            require(fact["function"] in self.functions, f"shading {number}: /Function does not resolve to a function object")
        for number, fact in self.functions.items():
            if fact["type"] == 3:
                for child in fact["children"]:
                    require(child in self.functions, f"function {number}: /Functions child does not resolve")
                    require(self.functions[child]["type"] == 2, f"function {number}: stitching child is not an exponential segment")
                self.check_stitch(number, fact)

        ## Streams: page contents, form streams, pattern streams, each with
        ## its exact direct dictionary and paint-operand resolution.
        self.page_contents: dict[int, bytes] = {}
        self.page_resources: dict[int, dict[str, int]] = {}
        for page in self.pages:
            body = bodies[page]
            content_object = dictionary_ref(body, b"Contents")
            _, content = decoded_stream(bodies, content_object)
            resources = parse_paint_resources(body, f"page {page}")
            check_stream_dictionary(f"page {page}", content, resources)
            check_balance(f"page {page}", content)
            check_pattern_selection(f"page {page}", content)
            self.page_contents[page] = content
            self.page_resources[page] = resources

        self.form_streams: dict[int, bytes] = {}
        self.form_resources: dict[int, dict[str, int]] = {}
        for number, body in bodies.items():
            marker = body.find(b"stream\n")
            if marker < 0 or b"/Subtype /Form" not in body[:marker]:
                continue
            _, content = decoded_stream(bodies, number)
            resources = parse_paint_resources(body[:marker], f"form {number}")
            check_stream_dictionary(f"form {number}", content, resources)
            check_balance(f"form {number}", content)
            check_pattern_selection(f"form {number}", content)
            self.form_streams[number] = content
            self.form_resources[number] = resources

        self.pattern_streams: dict[int, bytes] = {}
        self.pattern_resources: dict[int, dict[str, int]] = {}
        for number, body in self.patterns.items():
            self.check_pattern_dictionary(number, body)
            _, content = decoded_stream(bodies, number)
            resources = parse_paint_resources(body[: body.find(b"stream\n")], f"pattern {number}")
            check_stream_dictionary(f"pattern {number}", content, resources)
            check_balance(f"pattern {number}", content)
            check_pattern_selection(f"pattern {number}", content)
            check_stream_neutrality(f"pattern {number}", content)
            require(b" gs\n" not in content, f"pattern {number}: graphics state inside an opaque pattern stream")
            self.pattern_streams[number] = content
            self.pattern_resources[number] = resources

        self.check_resolution_and_reachability()

    def parse_shading(self, number: int, body: bytes) -> dict:
        shading_type = re.search(rb"/ShadingType ([0-9]+)", body)
        require(shading_type is not None and shading_type.group(1) in (b"2", b"3"), f"shading {number}: unsupported /ShadingType")
        kind = int(shading_type.group(1))
        coords = re.search(rb"/Coords \[((?:" + NUMBER + rb" )*" + NUMBER + rb")\]", body)
        require(coords is not None, f"shading {number}: missing /Coords")
        values = [float(value) for value in coords.group(1).split()]
        require(len(values) == (4 if kind == 2 else 6), f"shading {number}: /Coords arity does not match the shading type")
        if kind == 3:
            require(values[2] >= 0 and values[5] >= 0, f"shading {number}: negative radius")
            require(values[2] > 0 or values[5] > 0, f"shading {number}: both radii are zero")
            require(values[:3] != values[3:], f"shading {number}: coincident radial circles")
        else:
            require(values[:2] != values[2:], f"shading {number}: degenerate axis")
        require(b"/Domain [0 1]" in body, f"shading {number}: missing explicit /Domain [0 1]")
        extend = re.search(rb"/Extend \[(true|false) (true|false)\]", body)
        require(extend is not None, f"shading {number}: missing explicit /Extend")
        space = re.search(rb"/ColorSpace ([1-9][0-9]*) 0 R", body)
        require(space is not None, f"shading {number}: missing indirect /ColorSpace")
        function = re.search(rb"/Function ([1-9][0-9]*) 0 R", body)
        require(function is not None, f"shading {number}: missing indirect /Function")
        space_body = self.bodies.get(int(space.group(1)))
        require(space_body is not None, f"shading {number}: /ColorSpace does not resolve")
        require(
            b"/ICCBased" in space_body or b"/CalGray" in space_body,
            f"shading {number}: color space is not a supported device-independent form",
        )
        return {
            "coords": values,
            "extend": (extend.group(1) == b"true", extend.group(2) == b"true"),
            "function": int(function.group(1)),
            "space": int(space.group(1)),
            "type": kind,
        }

    def parse_function(self, number: int, body: bytes) -> dict:
        function_type = re.search(rb"/FunctionType ([0-9]+)", body)
        require(function_type is not None and function_type.group(1) in (b"2", b"3"), f"function {number}: unsupported /FunctionType")
        require(b"/Domain [0 1]" in body, f"function {number}: missing explicit /Domain [0 1]")
        if function_type.group(1) == b"2":
            require(b"/N 1" in body, f"function {number}: exponent is not the linear 1")
            c0 = re.search(rb"/C0 \[([^]]*)\]", body)
            c1 = re.search(rb"/C1 \[([^]]*)\]", body)
            require(c0 is not None and c1 is not None, f"function {number}: missing /C0 or /C1")
            c0_values = c0.group(1).split()
            c1_values = c1.group(1).split()
            require(len(c0_values) == len(c1_values), f"function {number}: /C0 and /C1 arity differ")
            require(len(c0_values) in (1, 3), f"function {number}: unsupported component arity")
            for value in c0_values + c1_values:
                require(0.0 <= float(value) <= 1.0, f"function {number}: component outside [0, 1]")
            return {"c0": c0_values, "c1": c1_values, "children": [], "type": 2}
        bounds = re.search(rb"/Bounds \[([^]]*)\]", body)
        encode = re.search(rb"/Encode \[([^]]*)\]", body)
        functions = re.search(rb"/Functions \[([^]]*)\]", body)
        require(bounds is not None and encode is not None and functions is not None, f"function {number}: stitching keys missing")
        children = [int(match.group(1)) for match in re.finditer(rb"([1-9][0-9]*) 0 R", functions.group(1))]
        return {
            "bounds": [float(value) for value in bounds.group(1).split()],
            "children": children,
            "encode": encode.group(1).split(),
            "type": 3,
        }

    def check_stitch(self, number: int, fact: dict) -> None:
        bounds = fact["bounds"]
        children = fact["children"]
        require(len(children) >= 2, f"function {number}: stitching over fewer than two segments")
        require(len(bounds) == len(children) - 1, f"function {number}: bounds arity does not match segment count")
        previous = 0.0
        for bound in bounds:
            require(previous < bound < 1.0, f"function {number}: bounds are not strictly increasing interior stops")
            previous = bound
        require(fact["encode"] == [b"0", b"1"] * len(children), f"function {number}: encode is not the canonical [0 1] per segment")

        ## The stop model is continuous by construction: segment k ends on
        ## the stop segment k+1 starts from.
        for left, right in zip(children, children[1:]):
            require(
                self.functions[left]["c1"] == self.functions[right]["c0"],
                f"function {number}: adjacent segments disagree on their shared stop color",
            )

    def check_pattern_dictionary(self, number: int, body: bytes) -> None:
        dictionary = body[: body.find(b"stream\n")]
        require(b"/Type /Pattern" in dictionary, f"pattern {number}: missing /Type /Pattern")
        require(b"/PatternType 1" in dictionary, f"pattern {number}: not a tiling pattern")
        require(b"/PaintType 1" in dictionary, f"pattern {number}: not a colored pattern")
        require(b"/TilingType 1" in dictionary, f"pattern {number}: not constant spacing")
        require(b"/StructParents" not in dictionary, f"pattern {number}: semantic ownership on a pattern stream")
        bbox = re.search(rb"/BBox \[(" + NUMBER + rb") (" + NUMBER + rb") (" + NUMBER + rb") (" + NUMBER + rb")\]", dictionary)
        require(bbox is not None, f"pattern {number}: missing /BBox")
        require(float(bbox.group(3)) > float(bbox.group(1)), f"pattern {number}: empty /BBox width")
        require(float(bbox.group(4)) > float(bbox.group(2)), f"pattern {number}: empty /BBox height")
        x_step = re.search(rb"/XStep (" + NUMBER + rb")", dictionary)
        y_step = re.search(rb"/YStep (" + NUMBER + rb")", dictionary)
        require(x_step is not None and float(x_step.group(1)) > 0, f"pattern {number}: non-positive /XStep")
        require(y_step is not None and float(y_step.group(1)) > 0, f"pattern {number}: non-positive /YStep")
        matrix = re.search(rb"/Matrix \[(" + NUMBER + rb"(?: " + NUMBER + rb"){5})\]", dictionary)
        require(matrix is not None, f"pattern {number}: missing explicit /Matrix")
        values = [float(value) for value in matrix.group(1).split()]
        require(values[0] * values[3] - values[1] * values[2] != 0, f"pattern {number}: singular /Matrix")
        require(b"/Resources <<" in dictionary, f"pattern {number}: missing direct /Resources")

    def check_resolution_and_reachability(self) -> None:
        """Every paint operand resolves through its own stream's direct
        dictionary; every shading, function, and pattern object is reachable
        through exactly the supported reference shapes."""
        used_shadings: set[int] = set()
        used_patterns: set[int] = set()
        streams = (
            [(f"page {page}", self.page_contents[page], self.page_resources[page]) for page in self.pages]
            + [(f"form {number}", content, self.form_resources[number]) for number, content in self.form_streams.items()]
            + [(f"pattern {number}", content, self.pattern_resources[number]) for number, content in self.pattern_streams.items()]
        )
        for owner, content, resources in streams:
            for match in re.finditer(rb"/([A-Za-z0-9_]+) sh\n", content):
                name = match.group(1).decode("ascii")
                require(name in resources, f"{owner}: sh operand /{name} does not resolve")
                target = resources[name]
                require(target in self.shadings, f"{owner}: /{name} does not name a shading object")
                used_shadings.add(target)
            for match in re.finditer(rb"/(Pt[A-Za-z0-9_]*) scn\n", content):
                name = match.group(1).decode("ascii")
                require(name in resources, f"{owner}: scn operand /{name} does not resolve")
                target = resources[name]
                require(target in self.patterns, f"{owner}: /{name} does not name a tiling pattern stream")
                used_patterns.add(target)
            for name, target in resources.items():
                if name.startswith("Sh"):
                    require(target in self.shadings, f"{owner}: /{name} entry is not a shading object")
                if name.startswith("Pt"):
                    require(target in self.patterns, f"{owner}: /{name} entry is not a pattern stream")
                require(target not in self.functions, f"{owner}: function object leaked into a resource dictionary")

        require(used_shadings == set(self.shadings), "unreachable shading object")
        require(used_patterns == set(self.patterns), "unreachable pattern stream")

        used_functions: set[int] = set()
        for fact in self.shadings.values():
            used_functions.add(fact["function"])
        for fact in self.functions.values():
            used_functions.update(fact["children"])
        require(used_functions == set(self.functions), "unreachable function object")

    def stream_shading_uses(self, owner_prefix: str) -> list[int]:
        uses = []
        streams = [(f"page {page}", self.page_contents[page], self.page_resources[page]) for page in self.pages]
        streams += [(f"form {number}", content, self.form_resources[number]) for number, content in self.form_streams.items()]
        streams += [(f"pattern {number}", content, self.pattern_resources[number]) for number, content in self.pattern_streams.items()]
        for owner, content, resources in streams:
            if not owner.startswith(owner_prefix):
                continue
            for match in re.finditer(rb"/([A-Za-z0-9_]+) sh\n", content):
                uses.append(resources[match.group(1).decode("ascii")])
        return uses


def validate_shading_showcase(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = PaintFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.page_contents[page], True)

    require(len(facts.shadings) == dimensions["canonical_shadings"], "physical shading count is not the canonical count")
    require(len(facts.functions) == dimensions["canonical_functions"], "physical function count is not the canonical count")
    require(len(facts.patterns) == dimensions["canonical_patterns"], "physical pattern count is not the canonical count")

    ## The exact authored geometry, reconstructed independently: the shared
    ## horizontal two-stop axis, the multi-stop axis, the radial cone, the
    ## calibrated-gray axis, the swapped twin, and the in-cell ramp.
    axes = sorted(tuple(fact["coords"]) for fact in facts.shadings.values() if fact["type"] == 2)
    require(axes.count((10.0, 0.0, 90.0, 0.0)) == 3, "the three horizontal page-band axes are not the exact authored axis")
    require((10.0, 70.0, 90.0, 80.0) in axes, "the multi-stop gradient lost its exact diagonal axis")
    require((5.0, 0.0, 10.0, 0.0) in axes, "the pattern cell ramp lost its exact axis")
    radial = [fact for fact in facts.shadings.values() if fact["type"] == 3]
    require(len(radial) == 1, "exactly one radial shading exists")
    require(radial[0]["coords"] == [30.0, 59.0, 2.0, 60.0, 59.0, 12.0], "radial geometry is not the exact authored geometry")
    require(radial[0]["extend"] == (True, True), "radial extend flags are not the authored extension")

    ## The two-stop red-to-blue gradient and its swapped-color twin resolve
    ## to distinct segment functions with the exact canonical endpoint
    ## components; the authored duplicate deduplicated into one object.
    one = alpha_decimal(65535).decode("ascii")
    zero = alpha_decimal(0).decode("ascii")
    red_blue = [
        number
        for number, fact in facts.functions.items()
        if fact["type"] == 2 and fact["c0"] == [one.encode(), zero.encode(), zero.encode()] and fact["c1"] == [zero.encode(), zero.encode(), one.encode()]
    ]
    blue_red = [
        number
        for number, fact in facts.functions.items()
        if fact["type"] == 2 and fact["c0"] == [zero.encode(), zero.encode(), one.encode()] and fact["c1"] == [one.encode(), zero.encode(), zero.encode()]
    ]
    require(len(red_blue) == 1, "the deduplicated red-to-blue segment is not one physical function")
    require(len(blue_red) == 1, "the swapped-color twin did not stay distinct")

    ## The multi-stop stitch carries the exact asymmetric interior bounds,
    ## and its middle segment is the same physical function the pattern
    ## cell's ramp shading references directly (cross-shading sharing).
    stitches = [(number, fact) for number, fact in facts.functions.items() if fact["type"] == 3]
    require(len(stitches) == 1, "exactly one stitching function exists")
    stitch_number, stitch = stitches[0]
    require(len(stitch["children"]) == 3, "the multi-stop gradient does not stitch three segments")
    require(stitch["bounds"] == [float(alpha_decimal(16384)), float(alpha_decimal(49152))], "stitch bounds are not the exact authored offsets")
    direct_functions = {fact["function"] for fact in facts.shadings.values()}
    shared = set(stitch["children"]) & direct_functions
    require(shared, "no segment function is shared between the stitch and a direct shading")

    ## The shared two-stop shading paints through two distinct owners (a
    ## fragment MCID and an artifact wrapper) plus the placed form's stream.
    page_content = facts.page_contents[page]
    page_uses = facts.stream_shading_uses("page")
    counts = {target: page_uses.count(target) for target in set(page_uses)}
    require(max(counts.values()) >= 2, "no shading is painted twice on the page (the authored twin did not share)")
    form_uses = facts.stream_shading_uses("form")
    require(len(form_uses) == 1, "the placed form does not paint exactly one shading")
    require(form_uses[0] in counts, "the form does not share the page's canonical shading")
    pattern_uses = facts.stream_shading_uses("pattern")
    require(len(set(pattern_uses)) == 1 and len(pattern_uses) == 2, "both pattern twins' cells must paint the one cell ramp")

    ## The calibrated-gray shading names the CalGray space; the sRGB ones
    ## name the ICCBased array.
    gray = [fact for fact in facts.shadings.values() if b"/CalGray" in facts.bodies[fact["space"]]]
    require(len(gray) == 1, "exactly one calibrated-gray shading exists")

    ## Patterns: the identity-matrix cell and its doubled twin stay
    ## distinct, with exact bounds and steps.
    matrices = set()
    for number, body in facts.patterns.items():
        dictionary = body[: body.find(b"stream\n")]
        require(b"/BBox [0 0 10 10]" in dictionary, f"pattern {number}: bounds are not the exact authored cell")
        require(b"/XStep 10" in dictionary and b"/YStep 10" in dictionary, f"pattern {number}: steps are not the exact authored steps")
        matrix = re.search(rb"/Matrix \[([^]]*)\]", dictionary)
        matrices.add(matrix.group(1))
    require(matrices == {b"1 0 0 1 0 0", b"2 0 0 2 0 0"}, "the two canonical patterns are not the identity and doubled matrices")

    ## Placement-site ownership stays page-stream facts: six meaningful
    ## placements with logical order differing from paint order.
    check_ownership(facts_form_view(facts), page, 6)

    ## The opacity group wraps a shading paint (transparency interaction).
    require(re.search(rb"q\n/GS[A-Za-z0-9_]+ gs\nq\n[^s]*? re\nW n\n/Sh[A-Za-z0-9_]+ sh\nQ\nQ\n", page_content) is not None, "the opacity group does not wrap a clipped shading paint")


class _FormFactsView:
    """The minimal duck-typed view check_ownership needs."""

    def __init__(self, facts: PaintFacts) -> None:
        self.bodies = facts.bodies
        self.page_contents = facts.page_contents

    def mcid_map(self, page: int) -> dict[int, bytes]:
        content = self.page_contents[page]
        sequences: dict[int, bytes] = {}
        position = 0
        while True:
            match = MCID_SEQUENCE.search(content, position)
            if match is None:
                break
            end = content.find(b"EMC\n", match.end())
            require(end >= 0, f"page {page}: unterminated marked-content sequence")
            mcid = int(match.group(1))
            require(mcid not in sequences, f"page {page}: MCID {mcid} painted twice")
            sequences[mcid] = content[match.end() : end]
            position = match.end()
        return sequences

    def parent_tree_rows(self, page: int) -> list[int]:
        from check_forms import FormFacts

        return FormFacts.parent_tree_rows(self, page)  # type: ignore[arg-type]

    def dictionary_int(self, *args):  # pragma: no cover - unused
        raise NotImplementedError


def facts_form_view(facts: PaintFacts) -> _FormFactsView:
    return _FormFactsView(facts)


def validate_shading_grid(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = PaintFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.page_contents[page], True)
    canonical = dimensions["canonical_shadings"]
    require(len(facts.shadings) == canonical, f"expected {canonical} canonical shadings, found {len(facts.shadings)}")
    if "shading_paints" in dimensions:
        uses = facts.stream_shading_uses("page")
        require(len(uses) == dimensions["shading_paints"], "page shading paints do not match the authored count")
        require(len(set(uses)) == canonical, "shading paints do not resolve to exactly the canonical shadings")


def validate_shading_stops(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = PaintFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.page_contents[page], True)
    stops = dimensions["stops"]
    require(len(facts.shadings) == 1, "the stop ramp is one canonical shading")
    require(len(facts.functions) == dimensions["canonical_functions"], "canonical function count mismatch")
    stitch = [fact for fact in facts.functions.values() if fact["type"] == 3]
    require(len(stitch) == 1, "the stop ramp is one stitching function")
    require(len(stitch[0]["children"]) == stops - 1, "segment count is not stops minus one")
    require(len(stitch[0]["bounds"]) == stops - 2, "bounds count is not the interior stop count")


def validate_pattern_grid(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = PaintFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.page_contents[page], True)
    canonical = dimensions["canonical_patterns"]
    require(len(facts.patterns) == canonical, f"expected {canonical} canonical patterns, found {len(facts.patterns)}")
    if "pattern_fills" in dimensions:
        fills = re.findall(rb"/Pattern cs\n/(Pt[A-Za-z0-9_]*) scn\n", facts.page_contents[page])
        require(len(fills) == dimensions["pattern_fills"], "page pattern fills do not match the authored count")
        targets = {facts.page_resources[page][name.decode("ascii")] for name in fills}
        require(len(targets) == canonical, "pattern fills do not resolve to exactly the canonical patterns")
    if "cell_commands" in dimensions:
        stream = next(iter(facts.pattern_streams.values()))
        fills = re.findall(rb" re\nf\n", stream)
        require(len(fills) == dimensions["cell_commands"], "cell stream does not paint exactly the authored commands")


def validate_shadings_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    if dimensions.get("shading_showcase"):
        validate_shading_showcase(pdf, dimensions)
    elif dimensions.get("shading_share") or dimensions.get("shading_distinct"):
        validate_shading_grid(pdf, dimensions)
    elif dimensions.get("shading_stops"):
        validate_shading_stops(pdf, dimensions)
    elif dimensions.get("pattern_share") or dimensions.get("pattern_distinct") or dimensions.get("pattern_cells"):
        validate_pattern_grid(pdf, dimensions)
    else:
        raise ValidationError("unknown production-visual shading-pattern fixture dimensions")


SHOWCASE_DIMENSIONS = {
    "pages": 1,
    "shading_showcase": 1,
    "authored_shadings": 7,
    "canonical_shadings": 6,
    "canonical_functions": 8,
    "authored_patterns": 3,
    "canonical_patterns": 2,
    "shading_objects": 6,
    "function_objects": 8,
    "pattern_objects": 2,
}


def self_test() -> None:
    showcase = SHOWCASE_SNAPSHOT.read_bytes()
    validate_shading_showcase(showcase, SHOWCASE_DIMENSIONS)
    validate_shading_grid(SHARE_100_SNAPSHOT.read_bytes(), {"pages": 1, "shading_share": 1, "shading_paints": 100, "canonical_shadings": 1})
    validate_shading_grid(SHARE_1000_SNAPSHOT.read_bytes(), {"pages": 1, "shading_share": 1, "shading_paints": 1000, "canonical_shadings": 1})
    validate_shading_grid(DISTINCT_8_SNAPSHOT.read_bytes(), {"pages": 1, "shading_distinct": 1, "canonical_shadings": 8})
    validate_shading_grid(DISTINCT_64_SNAPSHOT.read_bytes(), {"pages": 1, "shading_distinct": 1, "canonical_shadings": 64})
    validate_shading_stops(STOPS_16_SNAPSHOT.read_bytes(), {"pages": 1, "shading_stops": 1, "stops": 16, "canonical_functions": 16})
    validate_shading_stops(STOPS_64_SNAPSHOT.read_bytes(), {"pages": 1, "shading_stops": 1, "stops": 64, "canonical_functions": 64})
    validate_pattern_grid(PSHARE_100_SNAPSHOT.read_bytes(), {"pages": 1, "pattern_share": 1, "pattern_fills": 100, "canonical_patterns": 1})
    validate_pattern_grid(PSHARE_1000_SNAPSHOT.read_bytes(), {"pages": 1, "pattern_share": 1, "pattern_fills": 1000, "canonical_patterns": 1})
    validate_pattern_grid(PDISTINCT_8_SNAPSHOT.read_bytes(), {"pages": 1, "pattern_distinct": 1, "canonical_patterns": 8})
    validate_pattern_grid(PDISTINCT_64_SNAPSHOT.read_bytes(), {"pages": 1, "pattern_distinct": 1, "canonical_patterns": 64})
    validate_pattern_grid(PCELLS_16_SNAPSHOT.read_bytes(), {"pages": 1, "pattern_cells": 1, "cell_commands": 16, "canonical_patterns": 1})
    validate_pattern_grid(PCELLS_64_SNAPSHOT.read_bytes(), {"pages": 1, "pattern_cells": 1, "cell_commands": 64, "canonical_patterns": 1})
    validate_shading_grid(NEGATIVE_SNAPSHOT.read_bytes(), {"pages": 1, "shading_share": 1, "shading_paints": 1, "canonical_shadings": 1})

    ## Length-preserving mutation twins: each must be rejected.
    interior = alpha_decimal(16384) + b" " + alpha_decimal(49152)
    swapped_bounds = alpha_decimal(49152) + b" " + alpha_decimal(16384)
    require(len(interior) == len(swapped_bounds), "bounds mutation must preserve byte length")
    mutations = (
        ("shading type", replace_once(showcase, b"/ShadingType 3", b"/ShadingType 5")),
        ("coordinates", replace_once(showcase, b"/Coords [30 59 2 60 59 12]", b"/Coords [30 59 2 60 59 13]")),
        ("domain", replace_once(showcase, b"/Domain [0 1]", b"/Domain [0 2]")),
        ("extend array", replace_once(showcase, b"/Extend [true true]", b"/Extend [true trux]")),
        ("function type", replace_once(showcase, b"/FunctionType 3", b"/FunctionType 4")),
        ("stitch bounds order", replace_once(showcase, b"/Bounds [" + interior + b"]", b"/Bounds [" + swapped_bounds + b"]")),
        ("paint type", replace_once(showcase, b"/PaintType 1", b"/PaintType 2")),
        ("tiling type", replace_once(showcase, b"/TilingType 1", b"/TilingType 3")),
        ("pattern steps", replace_once(showcase, b"/XStep 10", b"/XStep 90")),
        ("pattern matrix", replace_once(showcase, b"/Matrix [2 0 0 2 0 0]", b"/Matrix [2 0 0 3 0 0]")),
        ("resource dictionary entry", replace_once(showcase, b"/Shading << /Sh", b"/Shading << /SX")),
    )
    for label, mutation in mutations:
        try:
            validate_shading_showcase(mutation, SHOWCASE_DIMENSIONS)
        except ValidationError:
            continue
        raise SystemExit(f"production-visual shading-pattern checker accepted mutated {label}")

    ## The neutrality and cycle guards are exercised directly: a pattern
    ## stream carrying marked content, semantic text, or a graphics state
    ## must be rejected, whatever produced it.
    for label, content in (
        ("marked content", b"/P <</MCID 0>> BDC\n0 0 1 1 re\nf\nEMC\n"),
        ("text", b"BT\n0 Tr\nET\n"),
    ):
        try:
            check_stream_neutrality("pattern twin", content)
        except ValidationError:
            continue
        raise SystemExit(f"production-visual shading-pattern checker accepted {label} in a pattern stream")
    print("PASS production-visual shading-pattern structural checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path, default=SHOWCASE_SNAPSHOT)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    validate_shading_showcase(args.pdf.read_bytes(), SHOWCASE_DIMENSIONS)
    print(f"PASS production-visual shading-pattern structural check: {args.pdf}")


if __name__ == "__main__":
    main()
