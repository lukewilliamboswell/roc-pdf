#!/usr/bin/env python3
"""production-visual navigation and link-annotation structural checker.

Independently of the Roc implementation, this proves from the emitted bytes
that:

- every page's `/Annots` array references distinct link-annotation objects,
  every emitted link annotation is referenced by exactly one page, and the
  array order (keyboard order) is exactly the fixture's declared order;
- every annotation dictionary carries the sorted required entries: a closed
  `/A` action, the zero-width `/BS` border style, `/F` restricted to 0 or 4,
  `/QuadPoints` with eight numbers per quadrilateral in the pinned
  bottom-left/bottom-right/top-right/top-left order, every quadrilateral
  axis-aligned and inside the normalized `/Rect`, a unique `/StructParent`
  key, `/Subtype /Link`, and `/Type /Annot`;
- every internal GoTo action carries BOTH `/SD` and `/D`: `/D` is
  `[page /XYZ x y null]` referencing a real page object, `/SD` is
  `[structelem /XYZ x y null]` referencing a real structure element, and the
  two carry identical coordinates and resolve to the same page when /SD
  follows the element’s /K reading order (ISO 32000-2 12.3.2.3, pdf-issues #140);
- every URI action is `/S /URI` with a byte-string URI and no other action
  type appears anywhere;
- the annotation `/StructParent` keys continue the ParentTree numbering
  after the per-page content-stream keys, each key maps to one direct
  structure-element reference, the owning Link structure element carries an
  OBJR kid whose `/Obj` references exactly that annotation with the correct
  `/Pg`, and `/ParentTreeNextKey` is one past the highest key;
- the catalog `/Names /Dests` name tree holds strictly ascending byte-string
  keys with correct non-root `/Limits`, and every named-destination value
  dictionary carries the same paired `/D` and `/SD` facts (pdf-issues #162);
- the catalog `/Outlines` tree has consistent `/First`, `/Last`, `/Prev`,
  `/Next`, and `/Parent` links, item counts agree with the state expressed by
  their signs, the root count is present only when at least one item is open,
  and every `/Dest` resolves through the name tree;
- the catalog `/PageLabels` number tree holds strictly ascending integer
  keys starting at 0 with only the closed `/S`, `/P`, `/St` vocabulary;
- every `/AP` normal appearance references a Form XObject whose `/BBox` is
  exactly `[0 0 w h]` with the annotation rectangle's extents and whose
  `/Matrix` is the identity.
"""

from __future__ import annotations

import argparse
import re
import sys
from functools import cache
from pathlib import Path

from check_pdf_structure import (
    is_structure_element,
    text_string,
    string_bytes,
    canonical_text,
    STRING,
    ValidationError,
    dictionary_int,
    dictionary_ref,
    object_slices,
    require,
    validate_page_tree,
    validate_stream_lengths,
    validate_xref,
)
from check_forms import replace_once
from check_structure_semantics import Ref, parse_object
from pdf_layout import twin as layout_twin

ROOT = Path(__file__).resolve().parents[1]

SNAPSHOTS = {
    "showcase": ROOT / "tests" / "navigation" / "navigation.pdf",
    "annots_8": ROOT / "tests" / "navigation" / "navigation_annots_8.pdf",
    "annots_64": ROOT / "tests" / "navigation" / "navigation_annots_64.pdf",
    "quads_32": ROOT / "tests" / "navigation" / "navigation_quads_32.pdf",
    "share_32": ROOT / "tests" / "navigation" / "navigation_share_32.pdf",
    "appearance_16": ROOT / "tests" / "navigation" / "navigation_appearance_16.pdf",
    "outline_deep_16": ROOT / "tests" / "navigation" / "navigation_outline_deep_16.pdf",
    "outline_wide_64": ROOT / "tests" / "navigation" / "navigation_outline_wide_64.pdf",
    "names_8": ROOT / "tests" / "navigation" / "navigation_names_8.pdf",
    "names_40": ROOT / "tests" / "navigation" / "navigation_names_40.pdf",
    "labels_8": ROOT / "tests" / "navigation" / "navigation_labels_8.pdf",
    "unique": ROOT / "tests" / "navigation" / "navigation_unique.pdf",
    "retained": ROOT / "tests" / "navigation" / "navigation_retained.pdf",
    "negative": ROOT / "tests" / "navigation" / "navigation_negative.pdf",
    "facade": ROOT / "tests" / "navigation_facade" / "navigation_facade.pdf",
    "facade_negative": ROOT / "tests" / "navigation_facade" / "navigation_facade_negative.pdf",
}

NUMBER = rb"-?\d+(?:\.\d+)?"
DEST_ARRAY = re.compile(
    rb"\[(\d+) 0 R /XYZ (" + NUMBER + rb") (" + NUMBER + rb") null\]"
)


def parse_number(raw: bytes) -> float:
    return float(raw)


def parse_ref_array(body: bytes, name: bytes) -> list[int]:
    match = re.search(rb"/" + name + rb" \[((?:\d+ 0 R ?)*)\]", body)
    require(match is not None, f"missing /{name.decode()} array")
    return [int(m) for m in re.findall(rb"(\d+) 0 R", match.group(1))]


def parse_numbers_array(body: bytes, name: bytes) -> list[float]:
    match = re.search(rb"/" + name + rb" \[((?:" + NUMBER + rb" ?)*)\]", body)
    require(match is not None, f"missing /{name.decode()} number array")
    return [parse_number(m) for m in re.findall(NUMBER, match.group(1))]


def top_level_keys(dictionary: bytes) -> list[bytes]:
    """Keys of the outermost dictionary, ignoring nested containers."""
    body = dictionary[dictionary.index(b"<<") + 2 :]
    depth = 0
    keys: list[bytes] = []
    index = 0
    while index < len(body):
        two = body[index : index + 2]
        if two == b"<<":
            depth += 1
            index += 2
            continue
        if two == b">>":
            if depth == 0:
                break
            depth -= 1
            index += 2
            continue
        if depth == 0 and body[index : index + 1] == b"/":
            match = re.match(rb"/([A-Za-z0-9_]+)", body[index:])
            if match is not None:
                keys.append(match.group(1))
                index += match.end()
                # Skip a name VALUE immediately following a key so it is not
                # miscounted as a key.
                rest = body[index:]
                value = re.match(rb" /([A-Za-z0-9_]+)", rest)
                if value is not None:
                    index += value.end()
                continue
        index += 1
    return keys


def parse_structure(pdf: bytes):
    require(pdf.startswith(b"%PDF-2.0\n"), "missing PDF 2.0 header")
    require(pdf.endswith(b"%%EOF\n"), "missing trailing EOF")
    start_match = re.search(rb"startxref\n(\d+)\n%%EOF\n$", pdf)
    require(start_match is not None, "missing startxref")
    xref_offset = int(start_match.group(1))
    offsets, bodies = object_slices(pdf)
    xref_object = next(
        number for number, offset in offsets.items() if offset == xref_offset
    )
    root, _identifier = validate_xref(pdf, offsets, bodies, xref_object, xref_offset)
    page_count = sum(1 for body in bodies.values() if b"/Type /Page " in body)
    pages = validate_page_tree(bodies, dictionary_ref(bodies[root], b"Pages"), page_count)
    validate_stream_lengths(bodies, xref_object, set(), b"")
    return offsets, bodies, root, pages


def collect_annotations(bodies, pages):
    """Return (annotation object -> page object) in per-page /Annots order."""
    annotation_pages: dict[int, int] = {}
    ordered: list[int] = []
    for page in sorted(pages):
        body = bodies[page]
        if b"/Annots" not in body:
            continue
        refs = parse_ref_array(body, b"Annots")
        require(len(set(refs)) == len(refs), "duplicate annotation in /Annots")
        for ref in refs:
            require(ref in bodies, "dangling /Annots reference")
            require(
                ref not in annotation_pages,
                "annotation referenced by more than one page",
            )
            annotation_pages[ref] = page
            ordered.append(ref)
    for number, body in bodies.items():
        if b"/Subtype /Link" in body and b"/Type /Annot" in body:
            require(
                number in annotation_pages,
                f"link annotation {number} not referenced by any page",
            )
    return annotation_pages, ordered


def structure_page_lookup(bodies):
    """The first content item found by the §12.3.2.3 /K traversal.

    A writer-produced destination has a painted anchor, so its subtree must
    supply a page before the specification's empty-target fallback.
    """
    active: set[int] = set()

    @cache
    def parsed(number):
        return parse_object(bodies[number])

    @cache
    def first_content_page(number):
        require(number not in active, "cycle in structured destination /K")
        active.add(number)
        try:
            element = parsed(number)
            children = element.get("K", [])
            for child in children if isinstance(children, list) else [children]:
                if isinstance(child, Ref):
                    value = parsed(int(child))
                    if "S" in value:
                        found = first_content_page(int(child))
                        if found is not None:
                            return found
                        continue
                    child = value
                if type(child) is int:
                    page = element.get("Pg")
                else:
                    require(isinstance(child, dict) and child.get("Type") in ("MCR", "OBJR"), "unexpected structured destination /K item")
                    page = child.get("Pg", element.get("Pg"))
                require(isinstance(page, Ref), "structured destination content item needs a /Pg reference")
                return int(page)
            return None
        finally:
            active.remove(number)

    return first_content_page


def check_annotation(structure_page, bodies, pages, structure_elements, number: int, page: int):
    body = bodies[number]
    require(b"/Subtype /Link" in body, "annotation is not a link")
    require(b"/Type /Annot" in body, "annotation missing /Type /Annot")
    require(b"/BS << /W 0 >>" in body, "annotation missing zero-width border style")
    flags = dictionary_int(body, b"F")
    require(flags in (0, 4), f"unsupported annotation flags {flags}")
    rect = parse_numbers_array(body, b"Rect")
    require(len(rect) == 4, "rect must have four numbers")
    require(rect[0] < rect[2] and rect[1] < rect[3], "rect is not normalized")
    quads = parse_numbers_array(body, b"QuadPoints")
    require(len(quads) >= 8 and len(quads) % 8 == 0, "quadpoints not a multiple of 8")
    for index in range(0, len(quads), 8):
        x1, y1, x2, y2, x3, y3, x4, y4 = quads[index : index + 8]
        require(x1 == x4 and x2 == x3, "quad is not axis-aligned horizontally")
        require(y1 == y2 and y3 == y4, "quad is not axis-aligned vertically")
        require(x1 < x2 and y1 < y3, "quad order is not BL BR TR TL")
        require(
            rect[0] <= x1 and x2 <= rect[2] and rect[1] <= y1 and y3 <= rect[3],
            "quad escapes the annotation rect",
        )
    action_match = re.search(rb"/A << (.*?) >> /(?:AP|BS)", body, re.S)
    require(action_match is not None, "annotation missing /A action")
    action = action_match.group(1)
    if b"/S /URI" in action:
        require(b"/Type /Action" in action, "URI action missing /Type")
        require(
            re.search(rb"/URI " + STRING, action) is not None,
            "URI action missing byte-string URI",
        )
        destination = None
    else:
        require(b"/S /GoTo" in action, "unknown action type")
        d_match = re.search(rb"/D " + DEST_ARRAY.pattern, action)
        sd_match = re.search(rb"/SD " + DEST_ARRAY.pattern, action)
        require(d_match is not None, "GoTo action missing /D")
        require(sd_match is not None, "GoTo action missing /SD")
        d_target, d_x, d_y = int(d_match.group(1)), d_match.group(2), d_match.group(3)
        sd_target, sd_x, sd_y = (
            int(sd_match.group(1)),
            sd_match.group(2),
            sd_match.group(3),
        )
        require(d_target in pages, "/D does not reference a page object")
        require(
            is_structure_element(bodies.get(sd_target, b"")),
            "/SD does not reference a structure element",
        )
        require(
            d_x == sd_x and d_y == sd_y,
            "paired /D and /SD carry different coordinates",
        )
        require(structure_page(sd_target) == d_target, "GoTo /SD and /D resolve to different pages")
        destination = (d_target, parse_number(d_x), parse_number(d_y))
    if b"/AP" in body:
        appearance = dictionary_ref(body, b"AP << /N")
        form = bodies[appearance]
        require(b"/Subtype /Form" in form, "appearance is not a Form XObject")
        require(b"/Matrix [1 0 0 1 0 0]" in form, "appearance matrix is not identity")
        bbox = parse_numbers_array(form, b"BBox")
        require(bbox[0] == 0 and bbox[1] == 0, "appearance bbox origin is not zero")
        require(
            bbox[2] == rect[2] - rect[0] and bbox[3] == rect[3] - rect[1],
            "appearance bbox extents disagree with the annotation rect",
        )
        require(b"/Resources" in form, "appearance missing direct resources")
    struct_parent = dictionary_int(body, b"StructParent")
    return struct_parent, destination


def check_parent_tree(bodies, root, annotation_pages, struct_parents):
    catalog = bodies[root]
    tree_root = dictionary_ref(catalog, b"StructTreeRoot")
    structure_root = bodies[tree_root]
    parent_tree = dictionary_ref(structure_root, b"ParentTree")
    next_key = dictionary_int(structure_root, b"ParentTreeNextKey")
    nums_body = bodies[parent_tree]
    entries = re.findall(rb"(\d+) (\[[^]]*\]|\d+ 0 R)", nums_body)
    keys = [int(k) for k, _ in entries]
    require(keys == sorted(keys), "ParentTree keys are not ascending")
    require(next_key == (max(keys) + 1 if keys else 0), "ParentTreeNextKey mismatch")
    scalar = {
        int(k): int(re.match(rb"(\d+) 0 R", v).group(1))
        for k, v in entries
        if not v.startswith(b"[")
    }
    for annotation, key in struct_parents.items():
        require(key in scalar, f"annotation StructParent {key} missing from ParentTree")
        element = scalar[key]
        element_body = bodies[element]
        require(is_structure_element(element_body), "ParentTree row is not a StructElem")
        objr = re.findall(
            rb"<< /Obj (\d+) 0 R /Pg (\d+) 0 R /Type /OBJR >>", element_body
        )
        matches = [
            (obj, pg) for obj, pg in objr if int(obj) == annotation
        ]
        require(len(matches) == 1, "owning element OBJR does not reference annotation")
        require(
            int(matches[0][1]) == annotation_pages[annotation],
            "OBJR /Pg disagrees with the page association",
        )


def walk_name_tree(bodies, node, depth=0):
    require(depth < 8, "name tree too deep")
    body = bodies[node]
    entries: list[tuple[bytes, bytes]] = []
    if b"/Kids" in body:
        for kid in parse_ref_array(body, b"Kids"):
            entries.extend(walk_name_tree(bodies, kid, depth + 1))
    else:
        names_match = re.search(rb"/Names \[(.*)\] >>", body, re.S)
        require(names_match is not None, "leaf node missing /Names")
        pairs = re.findall(rb"(" + STRING + rb") (<<.*?>>)", names_match.group(1))
        entries.extend((string_bytes(k), v) for k, v in pairs)
    if depth > 0:
        limits = re.findall(rb"/Limits \[(" + STRING + rb") (" + STRING + rb")\]", body)
        require(len(limits) == 1, "non-root node missing /Limits")
        first, last = string_bytes(limits[0][0]), string_bytes(limits[0][1])
        require(
            entries and entries[0][0] == first and entries[-1][0] == last,
            "node /Limits disagree with its descendant span",
        )
    return entries


def check_name_tree(bodies, root, pages, structure_page=None):
    catalog = bodies[root]
    if b"/Names" not in catalog:
        return {}
    dests_root = dictionary_ref(catalog, b"Names << /Dests")
    entries = walk_name_tree(bodies, dests_root)
    keys = [key for key, _ in entries]
    require(keys == sorted(keys) and len(set(keys)) == len(keys), "name keys not strictly ascending")
    destinations = {}
    if structure_page is None:
        structure_page = structure_page_lookup(bodies)
    for key, value in entries:
        d_match = re.search(rb"/D " + DEST_ARRAY.pattern, value)
        sd_match = re.search(rb"/SD " + DEST_ARRAY.pattern, value)
        require(d_match is not None, "named destination missing /D")
        require(sd_match is not None, "named destination missing /SD")
        require(int(d_match.group(1)) in pages, "named /D does not reference a page")
        require(
            is_structure_element(bodies.get(int(sd_match.group(1)), b"")),
            "named /SD does not reference a structure element",
        )
        require(
            d_match.group(2) == sd_match.group(2)
            and d_match.group(3) == sd_match.group(3),
            "named destination /D and /SD coordinates disagree",
        )
        require(structure_page(int(sd_match.group(1))) == int(d_match.group(1)), "named /SD and /D resolve to different pages")
        destinations[key] = (int(d_match.group(1)), d_match.group(2), d_match.group(3))
    return destinations


def check_outline(bodies, root, named):
    catalog = bodies[root]
    if b"/Outlines" not in catalog:
        return 0
    outline_root = dictionary_ref(catalog, b"Outlines")
    root_body = bodies[outline_root]
    require(b"/Type /Outlines" in root_body, "outline root missing /Type")

    def signed_count(body):
        dictionary = parse_object(body)
        if "Count" not in dictionary:
            return None
        value = dictionary["Count"]
        require(type(value) is int, "outline /Count is not an integer")
        return value

    def children(parent_number):
        body = bodies[parent_number]
        if b"/First" not in body:
            require(b"/Last" not in body, "outline /Last has no corresponding /First")
            return []
        first = dictionary_ref(body, b"First")
        last = dictionary_ref(body, b"Last")
        items = []
        cursor = first
        previous = None
        while True:
            item = bodies[cursor]
            require(
                dictionary_ref(item, b"Parent") == parent_number,
                "outline /Parent link broken",
            )
            if previous is None:
                require(b"/Prev" not in item, "first child carries /Prev")
            else:
                require(dictionary_ref(item, b"Prev") == previous, "outline /Prev broken")
            items.append(cursor)
            if b"/Next" not in item:
                require(cursor == last, "outline /Last disagrees with sibling chain")
                break
            following = dictionary_ref(item, b"Next")
            previous = cursor
            cursor = following
        return items

    def subtree_visible(parent_number):
        total = 0
        has_open_item = False
        for item in children(parent_number):
            total += 1
            declared = signed_count(bodies[item])
            below, open_below = subtree_visible(item)
            if below == 0:
                require(declared in (None, 0), "outline leaf /Count is nonzero")
            elif declared is not None and declared > 0:
                require(declared == below, "open outline /Count mismatch")
                total += below
                has_open_item = True
            else:
                require(declared == -below, "closed outline /Count mismatch")
            has_open_item |= open_below
        return total, has_open_item

    total_items = 0

    def count_items(parent_number):
        nonlocal total_items
        for item in children(parent_number):
            total_items += 1
            body = bodies[item]
            dest = re.search(rb"/Dest (" + STRING + rb")", body)
            require(dest is not None, "outline item missing /Dest name")
            require(
                string_bytes(dest.group(1)) in named,
                "outline /Dest name not in the name tree",
            )
            title = re.search(rb"/Title (" + STRING + rb")", body)
            require(title is not None and title.group(1) == canonical_text(text_string(title.group(1))), "outline item missing canonical text-string title")
            count_items(item)

    declared_root = signed_count(root_body)
    visible, has_open_item = subtree_visible(outline_root)
    require(
        declared_root == (visible if has_open_item else None),
        "outline root /Count presence or visibility mismatch",
    )
    count_items(outline_root)
    return total_items


def check_page_labels(bodies, root):
    catalog = bodies[root]
    if b"/PageLabels" not in catalog:
        return 0
    labels_root = dictionary_ref(catalog, b"PageLabels")

    label_entry = re.compile(rb"([0-9]+) (<<(?:[^<>()]|" + STRING + rb")*?>>)(?: |$)")
    label_dictionary = re.compile(
        rb"<<(?: /P " + STRING + rb")?"
        rb"(?: /S /(?P<style>[DRrAa]))?(?: /St (?P<start>[+-]?[0-9]+))? >>"
    )

    def walk(node):
        body = bodies[node]
        entries = []
        if body.startswith(b"<< /Kids ["):
            for kid in parse_ref_array(body, b"Kids"):
                entries.extend(walk(kid))
        else:
            nums = re.search(rb"/Nums \[(.*)\] >>", body, re.S)
            require(nums is not None, "label node missing /Nums")
            values = nums.group(1)
            position = 0
            while position < len(values):
                entry = label_entry.match(values, position)
                require(entry is not None, "malformed page-label number tree entry")
                entries.append((int(entry.group(1)), entry.group(2)))
                position = entry.end()
        return entries

    entries = walk(labels_root)
    keys = [k for k, _ in entries]
    require(keys == sorted(keys) and len(set(keys)) == len(keys), "label keys not ascending")
    require(keys and keys[0] == 0, "page labels must start at page zero")
    for _, value in entries:
        label = label_dictionary.fullmatch(value)
        require(label is not None, "invalid page-label dictionary")
        start = label.group("start")
        if start is not None:
            require(label.group("style") is not None, "explicit /St requires /S")
            number = int(start)
            require(
                str(number).encode() == start and 2 <= number <= 2**63 - 1,
                "explicit /St must be a canonical integer from 2 through 9223372036854775807",
            )
    return len(entries)


def check_navigation(pdf: bytes, expectations: dict[str, int]) -> None:
    offsets, bodies, root, pages = parse_structure(pdf)
    catalog = bodies[root]
    require(
        top_level_keys(catalog) == sorted(top_level_keys(catalog)),
        "catalog keys are not sorted",
    )

    annotation_pages, ordered = collect_annotations(bodies, pages)
    structure_elements = {
        number for number, body in bodies.items() if b"/Type /StructElem" in body
    }
    struct_parents = {}
    structure_page = structure_page_lookup(bodies)
    for number in ordered:
        key, _destination = check_annotation(
            structure_page, bodies, pages, structure_elements, number, annotation_pages[number]
        )
        require(key not in struct_parents.values(), "duplicate /StructParent key")
        struct_parents[number] = key
    if struct_parents:
        check_parent_tree(bodies, root, annotation_pages, struct_parents)
    named = check_name_tree(bodies, root, pages, structure_page)
    outline_items = check_outline(bodies, root, named)
    label_ranges = check_page_labels(bodies, root)

    if "annotations" in expectations:
        require(
            len(ordered) == expectations["annotations"],
            f"expected {expectations['annotations']} annotations, found {len(ordered)}",
        )
    if "destinations" in expectations:
        require(
            len(named) == expectations["destinations"],
            f"expected {expectations['destinations']} named destinations, found {len(named)}",
        )
    if "outline_entries" in expectations:
        require(
            outline_items == expectations["outline_entries"],
            f"expected {expectations['outline_entries']} outline items, found {outline_items}",
        )
    if "label_ranges" in expectations:
        require(
            label_ranges == expectations["label_ranges"],
            f"expected {expectations['label_ranges']} label ranges, found {label_ranges}",
        )


def validate_navigation_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    expectations = {
        key: dimensions[key]
        for key in ("annotations", "destinations", "outline_entries", "label_ranges")
        if key in dimensions
    }
    check_navigation(pdf, expectations)


def self_test() -> None:
    for label, path in SNAPSHOTS.items():
        pdf = path.read_bytes()
        check_navigation(pdf, {})

    showcase = SNAPSHOTS["showcase"].read_bytes()
    wide = SNAPSHOTS["outline_wide_64"].read_bytes()
    _, wide_objects = object_slices(wide)
    wide_root = next(body.split(b"\n", 1)[0] for body in wide_objects.values() if b"/Type /Outlines" in body)

    mutations = [
        ("open outline missing root Count", layout_twin(showcase, b"/Count 3 /First", b"/First", exactly_once=True)),
        ("leaf-only outline with redundant root Count",
         layout_twin(wide, wide_root, wide_root.replace(b"<< ", b"<< /Count 64 ", 1), exactly_once=True)),
        ("forbidden action type", replace_once(showcase, b"/S /GoTo", b"/S /GoUo")),
        ("SD-only pairing break", replace_once(showcase, b"/SD [", b"/XD [")),
        ("quad escaping its rect", replace_once(showcase, b"/QuadPoints [10 56 70 56 70 66 10 66",
                                                 b"/QuadPoints [10 56 70 56 70 99 10 99")),
        ("wrong quad vertex order", replace_once(showcase, b"/QuadPoints [10 56 70 56 70 66 10 66",
                                                  b"/QuadPoints [10 66 70 66 10 56 70 56")),
        ("unsupported annotation flags", replace_once(showcase, b"/F 4", b"/F 9")),
        ("StructParent key drift", replace_once(showcase, b"/StructParent 2", b"/StructParent 9")),
        ("outline count drift", replace_once(showcase, b"/Count 3 /First", b"/Count 9 /First")),
        ("name ordering break", replace_once(showcase, b"(intro)", b"(zntro)")),
        ("page-label zero key loss", replace_once(showcase, b"/Nums [0 << /S /r >>", b"/Nums [7 << /S /r >>")),
        ("OBJR target drift", replace_once(showcase, b"/Obj 25 0 R", b"/Obj 15 0 R")),
        ("duplicate Annots entry", replace_once(showcase, b"/Annots [24 0 R 25 0 R]", b"/Annots [24 0 R 24 0 R]")),
    ]
    for label, mutated in mutations:
        try:
            check_navigation(mutated, {})
        except ValidationError:
            continue
        except Exception:
            continue
        raise SystemExit(f"navigation checker accepted {label}")
    page_mismatches = (
        (b"/D [18 0 R /XYZ 10 42 null] /S /GoTo", b"/D [15 0 R /XYZ 10 42 null] /S /GoTo", "GoTo /SD and /D resolve to different pages"),
        (b"/D [18 0 R /XYZ 10 42 null] /SD", b"/D [15 0 R /XYZ 10 42 null] /SD", "named /SD and /D resolve to different pages"),
    )
    for old, new, expected in page_mismatches:
        try:
            check_navigation(layout_twin(showcase, old, new, exactly_once=True), {})
        except ValidationError as error:
            require(str(error) == expected, f"destination page twin failed for the wrong reason: {error}")
        else:
            raise ValidationError(f"navigation checker missed {expected}")

    # Independently exercise /K order, scalars, and all emitted kid kinds.
    destination_kids = {
        1: b"<< /K [2 0 R 3 0 R 0] /Pg 10 0 R /S /P >> endobj",
        2: b"<< /S /Artifact >> endobj",
        3: b"<< /K << /Obj 20 0 R /Pg 11 0 R /Type /OBJR >> /S /Link >> endobj",
        4: b"<< /K 0 /Pg 10 0 R /S /P >> endobj",
        5: b"<< /K [<< /MCID 1 /Pg 11 0 R /Type /MCR >> 0] /Pg 10 0 R /S /P >> endobj",
    }
    lookup = structure_page_lookup(destination_kids)
    require([lookup(i) for i in destination_kids] == [11, None, 11, 10, 11], "structured /K traversal disagrees with the authored content order")

    # Test decoded number-tree objects, including a two-byte negative mutation.
    # The fixture dictionaries live in compressed object streams.
    catalog = b"<< /PageLabels 2 0 R >>"
    labels = b"<< /Nums [0 << /S /D /St 10 >>] >>"
    label_objects = {1: catalog, 2: labels}
    check_page_labels(label_objects, 1)
    check_page_labels({1: catalog, 2: b"<< /Nums [0 << >>] >>"}, 1)
    check_page_labels({1: catalog, 2: labels.replace(b"10", b"9223372036854775807")}, 1)
    check_page_labels({1: catalog, 2: b"<< /Nums [0 << /P (/Kids [/St 2]) >>] >>"}, 1)
    for token in (b"-1", b"+2", b"02", b"0", b"1", b"2.0", b"/D", b"9223372036854775808"):
        try:
            check_page_labels({1: catalog, 2: labels.replace(b"10", token)}, 1)
        except ValidationError:
            continue
        raise SystemExit(f"page-label checker accepted /St {token!r}")
    print(
        "PASS production-visual navigation structural checker self-test: paired /SD + /D "
        "actions, keyboard-ordered /Annots, OBJR/ParentTree linkage, the "
        "named-destination registry, outline preorder counts, page labels, "
        f"and appearance geometry verified on {len(SNAPSHOTS)} snapshots; "
        f"{len(mutations) + len(page_mismatches)} mutation twins rejected",
        flush=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    if arguments.pdf is None:
        raise SystemExit("provide a PDF path or --self-test")
    check_navigation(arguments.pdf.read_bytes(), {})
    print(f"PASS {arguments.pdf}", flush=True)


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    main()
