#!/usr/bin/env python3
"""Independent structural checks for production-visual canonical font-leaf fixtures.

The checker parses the emitted bytes directly (no rewriting tool in front)
and proves the canonical font-bundle facts:

- exactly one nine-object Type 0 bundle per canonical font: the Type 0
  parent, CIDFontType2 descendant, font descriptor, unfiltered ``FontFile2``
  subset stream, identity ``CIDToGIDMap`` stream, and ``ToUnicode`` CMap,
  wired by reference;
- the embedded subset program is a well-formed sfnt whose table set stays
  inside the sanitizer's allowlist, whose per-table checksums and whole-font
  ``checkSumAdjustment`` verify, and whose ``hmtx`` advances scaled by
  ``unitsPerEm`` reproduce the emitted ``/W`` array exactly;
- the ``CIDToGIDMap`` stream is exactly the dense identity map over the
  subset's glyph count, and every ``ToUnicode`` ``bfchar`` entry names an
  in-range CID in ascending order;
- ``BaseFont`` is a six-uppercase-letter subset tag joined to the validated
  PostScript name, and a shared tag never merges distinct bundles;
- every ``Tf`` operand resolves through its own stream's exact direct
  ``/Font`` dictionary (used-equals-declared covers fonts), deduplicated
  authored fonts resolve to one physical bundle, distinct canonical fonts
  never share an object, and no external or non-Type 0 font shape appears;
- placement-site MCID/ParentTree ownership holds on every page.
"""
from __future__ import annotations

import argparse
import re
import struct
import zlib
from pathlib import Path

from check_forms import (
    check_balance,
    check_stream_dictionary,
    decoded_stream,
    form_objects,
    parse_resources,
)
from check_pdf_structure import (
    ValidationError,
    dictionary_int,
    dictionary_ref,
    indirect_length,
    object_slices,
    require,
    stream_parts,
)

ROOT = Path(__file__).resolve().parents[1]
SHOWCASE_SNAPSHOT = ROOT / "tests" / "font_leaves" / "font_leaves.pdf"
FACTS_SNAPSHOT = ROOT / "tests" / "font_leaves" / "font_leaf_facts.pdf"
SHARE_100_SNAPSHOT = ROOT / "tests" / "font_leaves" / "font_leaves_share_100.pdf"
DEDUPE_8_SNAPSHOT = ROOT / "tests" / "font_leaves" / "font_leaves_dedupe_8.pdf"
DISTINCT_8_SNAPSHOT = ROOT / "tests" / "font_leaves" / "font_leaves_distinct_8.pdf"

REQUIRED_TABLES = {b"OS/2", b"cmap", b"glyf", b"head", b"hhea", b"hmtx", b"loca", b"maxp", b"name", b"post"}
ALLOWED_TABLES = REQUIRED_TABLES | {b"cvt ", b"fpgm", b"gasp", b"prep"}
BASE_FONT = re.compile(rb"/BaseFont /([A-Z]{6})\+([A-Za-z0-9-]+)")
BFCHAR = re.compile(rb"<([0-9A-F]{4})> <((?:[0-9A-F]{4})+)>")


def raw_stream(bodies: dict[int, bytes], number: int) -> tuple[bytes, bytes]:
    """Dictionary and exact bytes of one unfiltered stream object."""
    body = bodies[number]
    marker = body.find(b"stream\n")
    require(marker >= 0, f"object {number} is not a stream")
    dictionary = body[:marker]
    require(b"/Filter" not in dictionary, f"object {number} must be unfiltered")
    length = indirect_length(bodies, dictionary_ref(dictionary, b"Length"))
    _, payload = stream_parts(body, length)
    return dictionary, payload


def checksum(data: bytes) -> int:
    padded = data + b"\0" * (-len(data) % 4)
    total = 0
    for (word,) in struct.iter_unpack(">I", padded):
        total = (total + word) & 0xFFFFFFFF
    return total


class Subset:
    """A verified sanitized TrueType subset program."""

    def __init__(self, owner: str, data: bytes) -> None:
        require(len(data) >= 12, f"{owner}: sfnt too short")
        signature, table_count = struct.unpack(">IH", data[:6])
        require(signature == 0x00010000, f"{owner}: not a TrueType-flavoured sfnt")
        self.tables: dict[bytes, bytes] = {}
        adjustment = 0
        for index in range(table_count):
            tag, check, offset, length = struct.unpack(">4sIII", data[12 + index * 16 : 28 + index * 16])
            require(offset + length <= len(data), f"{owner}: table {tag!r} escapes the font")
            table = data[offset : offset + length]
            if tag == b"head":
                require(length >= 54, f"{owner}: short head table")
                adjustment = struct.unpack(">I", table[8:12])[0]
                table_sum = checksum(table[:8] + b"\0\0\0\0" + table[12:])
            else:
                table_sum = checksum(table)
            require(table_sum == check, f"{owner}: table {tag!r} checksum mismatch")
            require(tag not in self.tables, f"{owner}: duplicate table {tag!r}")
            self.tables[tag] = table
        tags = set(self.tables)
        require(REQUIRED_TABLES <= tags, f"{owner}: missing required tables {sorted(REQUIRED_TABLES - tags)}")
        require(tags <= ALLOWED_TABLES, f"{owner}: forbidden tables {sorted(tags - ALLOWED_TABLES)}")
        zeroed_total = (checksum(data) - adjustment) & 0xFFFFFFFF
        whole = (0xB1B0AFBA - zeroed_total) & 0xFFFFFFFF
        require(whole == adjustment, f"{owner}: checkSumAdjustment mismatch")
        self.units_per_em = struct.unpack(">H", self.tables[b"head"][18:20])[0]
        self.glyph_count = struct.unpack(">H", self.tables[b"maxp"][4:6])[0]
        require(self.glyph_count >= 1, f"{owner}: empty subset")
        metric_count = struct.unpack(">H", self.tables[b"hhea"][34:36])[0]
        require(metric_count == self.glyph_count, f"{owner}: hmtx is not one long metric per glyph")
        hmtx = self.tables[b"hmtx"]
        require(len(hmtx) == 4 * self.glyph_count, f"{owner}: hmtx length mismatch")
        self.advances = [struct.unpack(">H", hmtx[4 * glyph : 4 * glyph + 2])[0] for glyph in range(self.glyph_count)]

    def scaled_widths(self) -> list[int]:
        return [(advance * 1000 + self.units_per_em // 2) // self.units_per_em for advance in self.advances]


class Bundle:
    """One emitted Type 0 bundle, fully resolved and verified."""

    def __init__(self, bodies: dict[int, bytes], type0: int) -> None:
        owner = f"font {type0}"
        parent = bodies[type0]
        base = BASE_FONT.search(parent)
        require(base is not None, f"{owner}: BaseFont is not a tagged subset name")
        self.tag = base.group(1).decode()
        self.postscript_name = base.group(2).decode()
        require(b"/Encoding /Identity-H" in parent, f"{owner}: encoding is not Identity-H")
        descendants = re.search(rb"/DescendantFonts \[([1-9][0-9]*) 0 R\]", parent)
        require(descendants is not None, f"{owner}: missing one-descendant array")
        self.type0 = type0
        self.descendant = int(descendants.group(1))
        descendant = bodies[self.descendant]
        require(b"/Subtype /CIDFontType2" in descendant, f"{owner}: descendant is not CIDFontType2")
        require(base.group(0) in descendant, f"{owner}: descendant BaseFont disagrees")
        require(
            b"/CIDSystemInfo << /Ordering <FEFF004900640065006E0074006900740079> "
            b"/Registry <FEFF00410064006F00620065> /Supplement 0 >>" in descendant,
            f"{owner}: CIDSystemInfo is not the canonical UTF-16BE Adobe-Identity-0",
        )
        require(b"/DW 1000" in descendant, f"{owner}: /DW is not 1000")
        self.descriptor = dictionary_ref(descendant, b"FontDescriptor")
        descriptor = bodies[self.descriptor]
        require(b"/Type /FontDescriptor" in descriptor, f"{owner}: descriptor object shape")
        require(b"/FontName /" + base.group(1) + b"+" in descriptor, f"{owner}: descriptor FontName disagrees")
        self.stem_v = dictionary_int(descriptor, b"StemV")
        require(b"/FontFile " not in descriptor and b"/FontFile3" not in descriptor, f"{owner}: non-TrueType font program")
        self.font_file = dictionary_ref(descriptor, b"FontFile2")
        file_dictionary, self.subset_bytes = raw_stream(bodies, self.font_file)
        length1 = dictionary_int(file_dictionary, b"Length1")
        require(length1 == len(self.subset_bytes), f"{owner}: /Length1 disagrees with the subset bytes")
        self.subset = Subset(owner, self.subset_bytes)

        self.cid_map = dictionary_ref(descendant, b"CIDToGIDMap")
        _, cid_map = raw_stream(bodies, self.cid_map)
        expected = b"".join(struct.pack(">H", glyph) for glyph in range(self.subset.glyph_count))
        require(cid_map == expected, f"{owner}: CIDToGIDMap is not the dense identity map")

        widths = re.search(rb"/W \[0 \[((?:[0-9]+ ?)+)\]\]", descendant)
        require(widths is not None, f"{owner}: /W is not the canonical one-run array")
        self.widths = [int(value) for value in widths.group(1).split()]
        require(
            self.widths == self.subset.scaled_widths(),
            f"{owner}: /W disagrees with the subset's scaled hmtx advances",
        )

        self.to_unicode = dictionary_ref(parent, b"ToUnicode")
        _, cmap = raw_stream(bodies, self.to_unicode)
        require(b"begincmap" in cmap and b"endcmap" in cmap, f"{owner}: ToUnicode is not a CMap")
        require(b"/CMapName /Adobe-Identity-UCS def" in cmap, f"{owner}: ToUnicode CMap name")
        self.mappings: dict[int, str] = {}
        previous = -1
        blocks = re.findall(rb"beginbfchar\n(.*?)endbfchar", cmap, re.DOTALL)
        require(blocks, f"{owner}: ToUnicode has no bfchar block")
        for match in BFCHAR.finditer(b"".join(blocks)):
            cid = int(match.group(1), 16)
            require(cid > previous, f"{owner}: ToUnicode CIDs are not ascending")
            require(0 < cid < self.subset.glyph_count, f"{owner}: ToUnicode CID out of subset range")
            previous = cid
            units = bytes.fromhex(match.group(2).decode())
            self.mappings[cid] = units.decode("utf-16-be")
        require(self.mappings, f"{owner}: empty ToUnicode mapping")

    @property
    def objects(self) -> set[int]:
        return {self.type0, self.descendant, self.descriptor, self.font_file, self.cid_map, self.to_unicode}


class FontFacts:
    def __init__(self, pdf: bytes, expected_pages: int) -> None:
        _, bodies = object_slices(pdf)
        self.bodies = bodies
        self.pages = [number for number, body in bodies.items() if b"/Type /Page " in body]
        require(len(self.pages) == expected_pages, "unexpected page count")

        ## Every font object in the file is part of exactly one supported
        ## Type 0 bundle; no other font shape or technology may appear.
        type0s = []
        font_objects_seen = set()
        for number, body in bodies.items():
            if re.search(rb"/Type /Font[ >]", body) is None:
                continue
            font_objects_seen.add(number)
            if b"/Subtype /Type0" in body:
                type0s.append(number)
            else:
                require(b"/Subtype /CIDFontType2" in body, f"object {number}: forbidden font subtype")
        self.bundles = [Bundle(bodies, type0) for type0 in sorted(type0s)]
        require(
            font_objects_seen == {bundle.type0 for bundle in self.bundles} | {bundle.descendant for bundle in self.bundles},
            "font object outside every Type 0 bundle",
        )
        claimed: set[int] = set()
        for bundle in self.bundles:
            require(not (bundle.objects & claimed), "two bundles share a physical object")
            claimed |= bundle.objects
        programs = [bundle.subset_bytes for bundle in self.bundles]
        for index, program in enumerate(programs):
            for other in range(index + 1, len(programs)):
                identical = program == programs[other]
                same_bundle_facts = (
                    identical
                    and self.bundles[index].mappings == self.bundles[other].mappings
                    and self.bundles[index].stem_v == self.bundles[other].stem_v
                )
                require(
                    not same_bundle_facts,
                    "two emitted bundles are exact twins; canonical deduplication must have merged them",
                )

        self.forms = form_objects(bodies)
        self.page_contents: dict[int, bytes] = {}
        self.page_resources: dict[int, dict[str, int]] = {}
        for page in self.pages:
            body = bodies[page]
            content_object = dictionary_ref(body, b"Contents")
            _, content = decoded_stream(bodies, content_object)
            resources = parse_resources(body, f"page {page}")
            check_stream_dictionary(f"page {page}", content, resources)
            check_balance(f"page {page}", content)
            self.page_contents[page] = content
            self.page_resources[page] = resources
        self.form_contents: dict[int, bytes] = {}
        self.form_resources: dict[int, dict[str, int]] = {}
        for number, dictionary in self.forms.items():
            _, content = decoded_stream(bodies, number)
            resources = parse_resources(dictionary, f"form {number}")
            check_stream_dictionary(f"form {number}", content, resources)
            check_balance(f"form {number}", content)
            require(b"/P <</MCID" not in content, f"form {number}: structure-bearing marked content inside a form stream")
            self.form_contents[number] = content
            self.form_resources[number] = resources

        ## Font resource entries resolve to Type 0 parents only, and no
        ## bundle exists without a dictionary reference.
        referenced: set[int] = set()
        for owner, resources in list(self.page_resources.items()) + list(self.form_resources.items()):
            for name, target in resources.items():
                if name.startswith("F"):
                    require(
                        target in {bundle.type0 for bundle in self.bundles},
                        f"{owner}: /{name} does not resolve to a Type 0 bundle",
                    )
                    referenced.add(target)
        require(
            referenced == {bundle.type0 for bundle in self.bundles},
            "every canonical bundle must be referenced by at least one direct dictionary",
        )

    def bundle_of(self, target: int) -> Bundle:
        for bundle in self.bundles:
            if bundle.type0 == target:
                return bundle
        raise ValidationError(f"object {target} is not a Type 0 bundle")

    def check_ownership(self) -> None:
        """Placement-site MCIDs: dense per page, one ParentTree owner each."""
        catalog = next(number for number, body in self.bodies.items() if b"/Type /Catalog" in body)
        structure_root = dictionary_ref(self.bodies[catalog], b"StructTreeRoot")
        parent_tree = dictionary_ref(self.bodies[structure_root], b"ParentTree")
        nums = re.search(rb"/Nums \[(.*)\] >>", self.bodies[parent_tree], re.DOTALL)
        require(nums is not None, "missing ParentTree /Nums")
        rows = {
            int(match.group(1)): [int(ref.group(1)) for ref in re.finditer(rb"([1-9][0-9]*) 0 R", match.group(2))]
            for match in re.finditer(rb"([0-9]+) \[([^]]*)\]", nums.group(1))
        }
        for page in self.pages:
            content = self.page_contents[page]
            mcids = [int(match.group(1)) for match in re.finditer(rb"/P <</MCID ([0-9]+)>> BDC\n", content)]
            require(sorted(mcids) == list(range(len(mcids))), f"page {page}: MCIDs are not dense in paint order")
            key = dictionary_int(self.bodies[page], b"StructParents")
            require(key in rows, f"page {page}: /StructParents key missing from ParentTree")
            require(len(rows[key]) == len(mcids), f"page {page}: ParentTree row length disagrees with painted MCIDs")
            for mcid, parent in enumerate(rows[key]):
                pattern = rb"<< /MCID " + str(mcid).encode() + rb" /Pg " + str(page).encode() + rb" 0 R /Type /MCR >>"
                matches = sum(len(re.findall(pattern, body)) for body in self.bodies.values())
                require(matches == 1, f"page {page}: MCID {mcid} referenced {matches} times")
                require(re.search(pattern, self.bodies[parent]) is not None, f"page {page}: MCID {mcid} owner disagrees")


def font_entries(resources: dict[str, int]) -> dict[str, int]:
    return {name: target for name, target in resources.items() if name.startswith("F")}


def validate_showcase(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = FontFacts(pdf, dimensions.get("pages", 2))
    require(len(facts.bundles) == dimensions.get("canonical_fonts", 3), "unexpected bundle count")
    require(len(facts.forms) == 1, "showcase must place exactly one text-bearing form")
    facts.check_ownership()

    ## The shared canonical subset: referenced from both pages and from the
    ## form's own direct dictionary, as one physical bundle.
    form = next(iter(facts.forms))
    form_fonts = font_entries(facts.form_resources[form])
    require(len(form_fonts) == 1, "the form dictionary must carry exactly its font")
    shared = facts.bundle_of(next(iter(form_fonts.values())))
    page_font_targets = [set(font_entries(facts.page_resources[page]).values()) for page in facts.pages]
    require(
        shared.type0 in page_font_targets[0] and shared.type0 in page_font_targets[1],
        "the shared bundle must be a direct use of both pages",
    )
    require(shared.mappings and set(shared.mappings.values()) == {"A", "B"}, "shared bundle ToUnicode facts")

    ## The distinct-closure and different-face bundles stay distinct.
    others = [bundle for bundle in facts.bundles if bundle.type0 != shared.type0]
    require(len(others) == 2, "expected two non-shared bundles")
    names = {bundle.postscript_name for bundle in facts.bundles}
    require(len({bundle.postscript_name for bundle in others}) == 2, "distinct faces must keep distinct names")
    require(any("Caller" in name for name in names), "the caller face bundle is missing")
    for bundle in others:
        require(set(bundle.mappings.values()) == {"C"}, "distinct bundles map exactly their painted text")
        require(bundle.subset_bytes != shared.subset_bytes, "a distinct closure shares the shared subset program")


def validate_facts(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = FontFacts(pdf, dimensions.get("pages", 1))
    require(len(facts.bundles) == dimensions.get("canonical_fonts", 5), "unexpected bundle count")
    facts.check_ownership()

    ## Three bundles deliberately share one subset tag (same face, same
    ## glyph closure) while remaining three physical bundles, split by one
    ## emitted fact each: the ToUnicode mapping and the StemV policy.
    by_tag: dict[str, list[Bundle]] = {}
    for bundle in facts.bundles:
        by_tag.setdefault(bundle.tag, []).append(bundle)
    shared_tag = [group for group in by_tag.values() if len(group) == 3]
    require(len(shared_tag) == 1, "expected exactly one three-bundle shared subset tag")
    trio = shared_tag[0]
    require(len({bundle.subset_bytes for bundle in trio}) == 1, "the shared-tag trio must embed one exact subset program")
    texts = sorted("".join(bundle.mappings.values()) for bundle in trio)
    require(texts == ["A", "A", "Å"], "the mapping-distinct pair must extract A versus Å")
    stems = sorted(bundle.stem_v for bundle in trio)
    require(stems[0] == stems[1] and stems[2] != stems[0], "the policy-distinct bundle must differ in StemV alone")

    ## The base closure and the caller face are the other two bundles.
    other = [bundle for bundle in facts.bundles if bundle not in trio]
    require(len(other) == 2, "expected the base closure and the caller face")
    require(any("Caller" in bundle.postscript_name for bundle in other), "the caller face bundle is missing")


def validate_scaled(pdf: bytes, dimensions: dict[str, int], canonical: int, placements: int) -> None:
    facts = FontFacts(pdf, dimensions.get("pages", 1))
    require(len(facts.bundles) == canonical, "unexpected bundle count")
    facts.check_ownership()
    tf_count = sum(len(re.findall(rb" Tf\n", content)) for content in facts.page_contents.values())
    require(tf_count == placements, f"expected {placements} font selections, found {tf_count}")
    programs = {bundle.subset_bytes for bundle in facts.bundles}
    require(len(programs) == canonical, "distinct canonical bundles must embed distinct programs")


def validate_fonts_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    if dimensions.get("font_showcase"):
        validate_showcase(pdf, dimensions)
    elif dimensions.get("font_facts"):
        validate_facts(pdf, dimensions)
    elif dimensions.get("font_share"):
        validate_scaled(pdf, dimensions, 1, dimensions["font_share"])
    elif dimensions.get("font_dedupe"):
        validate_scaled(pdf, dimensions, 1, dimensions["font_dedupe"])
    elif dimensions.get("font_distinct"):
        validate_scaled(pdf, dimensions, dimensions["font_distinct"], dimensions["font_distinct"])
    else:
        ## The unique/retained ownership fixtures reuse the showcase
        ## document, and the collision/negative carriers reuse the one-run
        ## sharing document.
        if dimensions.get("font_unique") or dimensions.get("font_retained"):
            validate_showcase(pdf, dimensions)
        else:
            validate_scaled(pdf, dimensions, 1, 1)


def replace_once(value: bytes, old: bytes, new: bytes) -> bytes:
    require(value.count(old) >= 1, f"mutation target {old!r} not found")
    return value.replace(old, new, 1)


def self_test() -> None:
    showcase = SHOWCASE_SNAPSHOT.read_bytes()
    validate_showcase(showcase, {"pages": 2, "canonical_fonts": 3})
    validate_facts(FACTS_SNAPSHOT.read_bytes(), {"pages": 1, "canonical_fonts": 5})
    validate_scaled(SHARE_100_SNAPSHOT.read_bytes(), {"pages": 1}, 1, 100)
    validate_scaled(DEDUPE_8_SNAPSHOT.read_bytes(), {"pages": 1}, 1, 8)
    validate_scaled(DISTINCT_8_SNAPSHOT.read_bytes(), {"pages": 1}, 8, 8)

    ## Length-preserving mutations must each be rejected.
    mutations = [
        ("font subtype", replace_once(showcase, b"/Subtype /Type0", b"/Subtype /Typo0")),
        ("descendant subtype", replace_once(showcase, b"/Subtype /CIDFontType2", b"/Subtype /CIDFontType3")),
        ("identity encoding", replace_once(showcase, b"/Encoding /Identity-H", b"/Encoding /Identity-V")),
        ("default width", replace_once(showcase, b"/DW 1000", b"/DW 1001")),
        ("subset tag casing", None),
        ("cid map identity", None),
        ("subset signature", None),
    ]
    tag_match = BASE_FONT.search(showcase)
    lowered = tag_match.group(1).lower()
    mutations[4] = ("subset tag casing", showcase.replace(tag_match.group(1), lowered))
    identity_prefix = b"\x00\x00\x00\x01\x00\x02"
    require(identity_prefix in showcase, "identity CIDToGIDMap prefix not found")
    mutations[5] = ("cid map identity", replace_once(showcase, identity_prefix, b"\x00\x00\x00\x02\x00\x01"))
    signature = struct.pack(">I", 0x00010000)
    mutations[6] = ("subset signature", replace_once(showcase, signature + b"\x00\x0e", struct.pack(">I", 0x4F54544F) + b"\x00\x0e"))
    for label, mutated in mutations:
        try:
            validate_showcase(mutated, {"pages": 2, "canonical_fonts": 3})
        except ValidationError:
            continue
        raise SystemExit(f"self-test: {label} mutation was not rejected")
    print("PASS check_fonts self-test: canonical bundles, subset verification, and mutation rejections")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("pdf", nargs="?", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    require(arguments.pdf is not None, "a PDF path or --self-test is required")
    validate_showcase(arguments.pdf.read_bytes(), {"pages": 2, "canonical_fonts": 3})
    print(f"PASS {arguments.pdf}")


if __name__ == "__main__":
    main()
