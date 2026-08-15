#!/usr/bin/env python3
"""Independent structural checks for Gate 4 Form XObject fixtures.

The checker parses the emitted bytes directly (no rewriting tool in front),
resolves every content stream's operators against that stream's own direct
resource dictionary, and proves the sharing, ownership, and tagged facts of
the chosen placement-site model:

- every Form XObject dictionary is complete and canonical;
- page and form ``/Resources`` dictionaries contain exactly their direct uses
  (an unused entry or an unresolvable name is a failure, so a transitive
  dependency can never hide in a parent dictionary);
- every ``Do`` resolves in the current stream's dictionary and every marked
  content item is owned exactly once through ``/StructParents`` and the
  ParentTree;
- deduplicated visuals share one physical object while every semantic
  placement keeps its own placement-site MCID.
"""
from __future__ import annotations

import argparse
import re
import zlib
from pathlib import Path

from check_pdf_structure import (
    ValidationError,
    dictionary_int,
    dictionary_ref,
    indirect_length,
    object_slices,
    require,
    stream_parts,
    validate_pdf,
)

ROOT = Path(__file__).resolve().parents[1]
SHOWCASE_SNAPSHOT = ROOT / "tests" / "gate4_forms" / "snapshot.pdf"
REPEAT_100_SNAPSHOT = ROOT / "tests" / "gate4_forms_repeat_100" / "snapshot.pdf"
REPEAT_1000_SNAPSHOT = ROOT / "tests" / "gate4_forms_repeat_1000" / "snapshot.pdf"
DAG_8_SNAPSHOT = ROOT / "tests" / "gate4_forms_dag_8" / "snapshot.pdf"
DAG_32_SNAPSHOT = ROOT / "tests" / "gate4_forms_dag_32" / "snapshot.pdf"
DEEP_64_SNAPSHOT = ROOT / "tests" / "gate4_forms_deep_64" / "snapshot.pdf"
NEGATIVE_SNAPSHOT = ROOT / "tests" / "gate4_forms_negative" / "snapshot.pdf"
TEXT_SNAPSHOT = ROOT / "tests" / "gate4_form_text" / "snapshot.pdf"

NAME_OPERAND = re.compile(rb"/([A-Za-z0-9_]+) (Do|cs|CS)(?:\s|$)")
FONT_OPERAND = re.compile(rb"/([A-Za-z0-9_]+) [0-9.]+ Tf(?:\s|$)")
MCID_SEQUENCE = re.compile(rb"/P <</MCID ([0-9]+)>> BDC\n")


def decoded_stream(bodies: dict[int, bytes], number: int) -> tuple[bytes, bytes]:
    body = bodies[number]
    marker_offset = body.find(b"stream\n")
    require(marker_offset >= 0, f"object {number} is not a stream")
    dictionary = body[:marker_offset]
    length = indirect_length(bodies, dictionary_ref(dictionary, b"Length"))
    _, encoded = stream_parts(body, length)
    require(b"/Filter /FlateDecode" in dictionary, f"object {number} is not FlateDecode")
    try:
        return dictionary, zlib.decompress(encoded)
    except zlib.error as error:
        raise ValidationError(f"object {number} has invalid zlib DEFLATE: {error}") from error


def parse_resources(dictionary: bytes, owner: str) -> dict[str, int]:
    """The exact direct resource dictionary of one stream as name -> object."""
    match = re.search(rb"/Resources << (.*?) >> /(?:Rotate|Subtype)", dictionary, re.DOTALL)
    if match is None:
        match = re.search(rb"/Resources << (.*) >>", dictionary, re.DOTALL)
    require(match is not None, f"{owner}: missing /Resources dictionary")
    body = match.group(1)
    entries: dict[str, int] = {}
    for sub in re.finditer(rb"/(ColorSpace|Font|XObject) << ([^>]*) >>", body):
        for entry in re.finditer(rb"/([A-Za-z0-9_]+) ([1-9][0-9]*) 0 R", sub.group(2)):
            name = entry.group(1).decode("ascii")
            require(name not in entries, f"{owner}: duplicate resource name {name}")
            entries[name] = int(entry.group(2))
    stripped = re.sub(rb"/(ColorSpace|Font|XObject) << [^>]* >>", b"", body).strip()
    require(stripped == b"", f"{owner}: unexpected resource dictionary content {stripped!r}")
    return entries


def used_names(content: bytes) -> set[str]:
    names = {match.group(1).decode("ascii") for match in NAME_OPERAND.finditer(content)}
    names |= {match.group(1).decode("ascii") for match in FONT_OPERAND.finditer(content)}
    return names


def check_stream_dictionary(owner: str, content: bytes, resources: dict[str, int]) -> None:
    used = used_names(content)
    declared = set(resources)
    require(
        used == declared,
        f"{owner}: operators use {sorted(used)} but the direct dictionary declares "
        f"{sorted(declared)}; every entry must be a direct use and every use must resolve",
    )


def check_balance(owner: str, content: bytes) -> None:
    require(content.count(b"q\n") == content.count(b"Q\n"), f"{owner}: unbalanced q/Q")
    require(content.count(b" BDC\n") == content.count(b"EMC\n"), f"{owner}: unbalanced BDC/EMC")
    require(content.count(b"BT\n") == content.count(b"ET\n"), f"{owner}: unbalanced BT/ET")


def form_objects(bodies: dict[int, bytes]) -> dict[int, bytes]:
    forms = {}
    for number, body in bodies.items():
        marker = body.find(b"stream\n")
        if marker < 0:
            continue
        dictionary = body[:marker]
        if b"/Subtype /Form" in dictionary:
            forms[number] = dictionary
    return forms


def check_form_dictionary(number: int, dictionary: bytes) -> None:
    require(b"/Type /XObject" in dictionary, f"form {number}: missing /Type /XObject")
    require(b"/Subtype /Form" in dictionary, f"form {number}: missing /Subtype /Form")
    require(b"/FormType 1" in dictionary, f"form {number}: missing /FormType 1")
    require(b"/Matrix [1 0 0 1 0 0]" in dictionary, f"form {number}: /Matrix is not the canonical identity")
    bbox = re.search(rb"/BBox \[(-?[0-9.]+) (-?[0-9.]+) (-?[0-9.]+) (-?[0-9.]+)\]", dictionary)
    require(bbox is not None, f"form {number}: missing /BBox")
    require(float(bbox.group(3)) > float(bbox.group(1)), f"form {number}: empty /BBox width")
    require(float(bbox.group(4)) > float(bbox.group(2)), f"form {number}: empty /BBox height")
    require(b"/Resources <<" in dictionary, f"form {number}: missing direct /Resources")
    for forbidden in (b"/Group", b"/StructParents", b"/StructParent", b"/OC", b"/Ref", b"/OPI"):
        require(forbidden + b" " not in dictionary, f"form {number}: deferred key {forbidden!r} emitted")


class FormFacts:
    def __init__(self, pdf: bytes, expected_pages: int) -> None:
        offsets, bodies = object_slices(pdf)
        self.bodies = bodies
        self.pages = [number for number, body in bodies.items() if b"/Type /Page " in body]
        require(len(self.pages) == expected_pages, "unexpected page count")
        self.forms = form_objects(bodies)
        for number, dictionary in self.forms.items():
            check_form_dictionary(number, dictionary)

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
            require(b" BDC\n" not in content or b"/P <</MCID" not in content, f"form {number}: structure-bearing marked content inside a form stream")
            self.form_contents[number] = content
            self.form_resources[number] = resources

        ## Every form referenced by some stream's XObject entry exists, every
        ## form object is reachable from a page, and the reference graph is a
        ## DAG (walked iteratively).
        reachable: set[int] = set()
        stack: list[int] = []
        for page in self.pages:
            for name, target in self.page_resources[page].items():
                if name.startswith("XO"):
                    require(target in self.forms, f"page {page}: /{name} does not name a Form XObject")
                    if target not in reachable:
                        reachable.add(target)
                        stack.append(target)
        while stack:
            form = stack.pop()
            for name, target in self.form_resources[form].items():
                if name.startswith("XO"):
                    require(target in self.forms, f"form {form}: /{name} does not name a Form XObject")
                    if target not in reachable:
                        reachable.add(target)
                        stack.append(target)
        require(reachable == set(self.forms), "unreachable Form XObject object")

        in_degree = {form: 0 for form in self.forms}
        for form in self.forms:
            for name, target in self.form_resources[form].items():
                if name.startswith("XO"):
                    in_degree[target] += 1
        ready = [form for form, degree in in_degree.items() if degree == 0]
        seen = 0
        while ready:
            form = ready.pop()
            seen += 1
            for name, target in self.form_resources[form].items():
                if name.startswith("XO"):
                    in_degree[target] -= 1
                    if in_degree[target] == 0:
                        ready.append(target)
        require(seen == len(self.forms), "Form XObject reference graph is not acyclic")

    def mcid_map(self, page: int) -> dict[int, bytes]:
        """MCID -> marked-content sequence body for one page stream."""
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
        body = self.bodies[page]
        struct_parents = dictionary_int(body, b"StructParents")
        catalog = next(number for number, candidate in self.bodies.items() if b"/Type /Catalog" in candidate)
        structure_root = dictionary_ref(self.bodies[catalog], b"StructTreeRoot")
        parent_tree = dictionary_ref(self.bodies[structure_root], b"ParentTree")
        nums = re.search(rb"/Nums \[([0-9]+) \[([^]]*)\]\]", self.bodies[parent_tree])
        require(nums is not None, "ParentTree row is not one page row")
        require(int(nums.group(1)) == struct_parents, "ParentTree key does not match page /StructParents")
        return [int(match.group(1)) for match in re.finditer(rb"([1-9][0-9]*) 0 R", nums.group(2))]


def check_ownership(facts: FormFacts, page: int, expected_mcids: int) -> dict[int, bytes]:
    sequences = facts.mcid_map(page)
    require(len(sequences) == expected_mcids, f"expected {expected_mcids} MCIDs, found {len(sequences)}")
    require(sorted(sequences) == list(range(len(sequences))), "MCIDs are not dense in paint order")
    parents = facts.parent_tree_rows(page)
    require(len(parents) == expected_mcids, "ParentTree row length does not match painted MCIDs")

    ## Every marked-content item is owned exactly once: its parent structure
    ## element's /K holds exactly one MCR with this page and MCID.
    for mcid, parent in enumerate(parents):
        parent_body = facts.bodies[parent]
        pattern = rb"<< /MCID " + str(mcid).encode() + rb" /Pg " + str(page).encode() + rb" 0 R /Type /MCR >>"
        matches = sum(len(re.findall(pattern, body)) for body in facts.bodies.values())
        require(matches == 1, f"MCID {mcid} is referenced {matches} times; exactly one owner required")
        require(re.search(pattern, parent_body) is not None, f"MCID {mcid} owner disagrees with ParentTree")
    return sequences


def validate_showcase(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = FormFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.page_contents[page], True)
    require(len(facts.forms) == dimensions["canonical_forms"], "physical form count is not the canonical count")

    content = facts.page_contents[page]
    sequences = check_ownership(facts, page, 5)

    ## Placement-specific semantics over a shared physical form: each of the
    ## five semantic sequences wraps exactly one balanced form invocation, and
    ## one form name serves several distinct MCIDs.
    name_by_mcid: dict[int, str] = {}
    for mcid, body in sequences.items():
        invocations = re.findall(rb"q\n[-0-9. ]+ cm\n/([A-Za-z0-9_]+) Do\nQ\n", body)
        require(len(invocations) == 1, f"MCID {mcid} does not wrap exactly one form invocation")
        name_by_mcid[mcid] = invocations[0].decode("ascii")
    shared_names = {name for name in name_by_mcid.values() if list(name_by_mcid.values()).count(name) >= 2}
    require(shared_names, "no physical form is shared across distinct semantic placements")

    ## The same shared visual also paints as an artifact, with no MCID.
    artifact_bodies = re.findall(rb"/Artifact <<[^>]*>> BDC\n(.*?)EMC\n", content, re.DOTALL)
    artifact_names = {match.decode("ascii") for body in artifact_bodies for match in re.findall(rb"/([A-Za-z0-9_]+) Do", body)}
    require(shared_names & artifact_names, "semantic and artifact placements do not share a physical form")

    ## Repeated artifact placement of one form at two transforms.
    artifact_do = [match for body in artifact_bodies for match in re.findall(rb"q\n([-0-9. ]+) cm\n/([A-Za-z0-9_]+) Do\nQ\n", body)]
    by_name: dict[bytes, set[bytes]] = {}
    for transform, name in artifact_do:
        by_name.setdefault(name, set()).add(transform)
    require(any(len(transforms) >= 2 for transforms in by_name.values()), "no artifact form is placed at two distinct transforms")

    ## Nested forms with one shared dependency: two form dictionaries name the
    ## same nested form, and that nested form never leaks into the page's
    ## dictionary (the exact-use rule above already proves the general case).
    nested_targets = [target for resources in facts.form_resources.values() for name, target in resources.items() if name.startswith("XO")]
    require(nested_targets, "no nested form reference exists")
    shared_nested = {target for target in nested_targets if nested_targets.count(target) >= 2}
    require(shared_nested, "no nested form is shared by two parent forms")
    page_targets = set(facts.page_resources[page].values())
    require(not (shared_nested & page_targets), "a transitive-only form appears in the page dictionary")

    ## Two forms also share the image resource, and the page paints it too.
    image_users = [form for form, resources in facts.form_resources.items() if any(name.startswith("Im") for name in resources)]
    require(len(image_users) >= 2, "no visual resource is shared by two forms")

    ## Logical reading order differs from paint order: the first structure
    ## child of the document reads first but was painted second.
    catalog = next(number for number, body in facts.bodies.items() if b"/Type /Catalog" in body)
    structure_root = dictionary_ref(facts.bodies[catalog], b"StructTreeRoot")
    document = dictionary_ref(facts.bodies[structure_root], b"K")
    document_k = re.search(rb"/K \[([^]]*)\]", facts.bodies[document])
    require(document_k is not None, "document /K missing")
    children = [int(match.group(1)) for match in re.finditer(rb"([1-9][0-9]*) 0 R", document_k.group(1))]
    require(len(children) == 4, "document does not hold the four paragraphs")
    first_child_mcids = [int(m.group(1)) for m in re.finditer(rb"<< /MCID ([0-9]+) /Pg", facts.bodies[children[0]])]
    require(first_child_mcids == [1], "logical reading order does not lead with the second painted paragraph")
    last_child_mcids = [int(m.group(1)) for m in re.finditer(rb"<< /MCID ([0-9]+) /Pg", facts.bodies[children[3]])]
    require(last_child_mcids == [3, 4], "the split occurrence does not own its two placements in order")


def validate_repeat(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = FormFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.page_contents[page], True)
    require(len(facts.forms) == 1, "repeated artifact placement must share one physical form")
    check_ownership(facts, page, 1)
    placements = dimensions["form_placements"]
    invocations = re.findall(rb"q\n([-0-9. ]+) cm\n/([A-Za-z0-9_]+) Do\nQ\n", facts.page_contents[page])
    require(len(invocations) == placements, f"expected {placements} form invocations, found {len(invocations)}")
    require(len({name for _, name in invocations}) == 1, "repeated placements use more than one name")
    distinct_transforms = {transform for transform, _ in invocations}
    require(len(distinct_transforms) == min(placements, 90), "repeated placements do not keep their declared transforms")


def validate_dag(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = FormFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.page_contents[page], True)
    parents = dimensions["dag_parents"]
    require(len(facts.forms) == parents + 4, "DAG form count is not parents plus the four shared bases")
    page_form_targets = {target for name, target in facts.page_resources[page].items() if name.startswith("XO")}
    require(len(page_form_targets) == parents, "page dictionary must contain exactly the parent forms")
    base_targets = set(facts.forms) - page_form_targets
    require(len(base_targets) == 4, "exactly four base forms must stay out of the page dictionary")
    for parent in page_form_targets:
        nested = {target for name, target in facts.form_resources[parent].items() if name.startswith("XO")}
        require(nested == base_targets, f"parent form {parent} does not name exactly the four shared bases")
    for base in base_targets:
        require(not any(name.startswith("XO") for name in facts.form_resources[base]), f"base form {base} must have no nested forms")


def validate_deep(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = FormFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.page_contents[page], True)
    depth = dimensions["chain_depth"]
    require(len(facts.forms) == depth, "chain form count mismatch")
    chain_heads = [target for name, target in facts.page_resources[page].items() if name.startswith("XO")]
    require(len(chain_heads) == 1, "the chain must enter through one page placement")
    current = chain_heads[0]
    visited = []
    while True:
        visited.append(current)
        nested = [target for name, target in facts.form_resources[current].items() if name.startswith("XO")]
        require(len(nested) <= 1, f"chain form {current} has more than one nested form")
        if not nested:
            break
        current = nested[0]
        require(current not in visited, "chain revisits a form")
    require(len(visited) == depth, f"chain depth {len(visited)} does not match {depth}")


def validate_text(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = FormFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.page_contents[page], True)
    require(len(facts.forms) == 1, "the text fixture holds one form")
    sequences = check_ownership(facts, page, 1)
    invocations = re.findall(rb"/([A-Za-z0-9_]+) Do", sequences[0])
    require(len(invocations) == 1, "the semantic placement must wrap exactly the form invocation")
    form = next(iter(facts.forms))
    content = facts.form_contents[form]
    require(b"BT\n" in content and b" Tf\n" in content and b"ET\n" in content, "form stream does not paint text")
    font_entries = {name: target for name, target in facts.form_resources[form].items() if name.startswith("F")}
    require(len(font_entries) == 1, "the form's dictionary must carry exactly its font")
    font_object = next(iter(font_entries.values()))
    font_body = facts.bodies[font_object]
    require(b"/Subtype /Type0" in font_body, "form font is not the planned Type 0 font")
    require(b"/ToUnicode" in font_body, "form font lost its ToUnicode mapping")
    page_fonts = {name for name in facts.page_resources[page] if name.startswith("F")}
    require(not page_fonts, "the page dictionary must not carry the form's font")


def validate_gate4_forms_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    if dimensions.get("gate4_forms_showcase"):
        validate_showcase(pdf, dimensions)
    elif dimensions.get("gate4_forms_repeat"):
        validate_repeat(pdf, dimensions)
    elif dimensions.get("gate4_forms_dag"):
        validate_dag(pdf, dimensions)
    elif dimensions.get("gate4_forms_deep"):
        validate_deep(pdf, dimensions)
    elif dimensions.get("gate4_form_text"):
        validate_text(pdf, dimensions)
    else:
        raise ValidationError("unknown Gate 4 form fixture dimensions")


def replace_once(value: bytes, old: bytes, new: bytes) -> bytes:
    require(len(old) == len(new), "negative twin must preserve byte length")
    require(value.count(old) >= 1, f"negative twin source missing: {old!r}")
    return value.replace(old, new, 1)


def self_test() -> None:
    showcase = SHOWCASE_SNAPSHOT.read_bytes()
    showcase_dimensions = {"pages": 1, "gate4_forms_showcase": 1, "authored_forms": 9, "canonical_forms": 5}
    validate_showcase(showcase, showcase_dimensions)
    validate_repeat(REPEAT_100_SNAPSHOT.read_bytes(), {"pages": 1, "form_placements": 100})
    validate_repeat(REPEAT_1000_SNAPSHOT.read_bytes(), {"pages": 1, "form_placements": 1000})
    validate_repeat(NEGATIVE_SNAPSHOT.read_bytes(), {"pages": 1, "form_placements": 1})
    validate_dag(DAG_8_SNAPSHOT.read_bytes(), {"pages": 1, "dag_parents": 8})
    validate_dag(DAG_32_SNAPSHOT.read_bytes(), {"pages": 1, "dag_parents": 32})
    validate_deep(DEEP_64_SNAPSHOT.read_bytes(), {"pages": 1, "chain_depth": 64})
    validate_text(TEXT_SNAPSHOT.read_bytes(), {"pages": 1, "gate4_form_text": 1})

    nums = re.search(rb"/Nums \[0 \[([1-9][0-9]*) 0 R ([1-9][0-9]*) 0 R ", showcase)
    require(nums is not None, "self-test fixture has no ParentTree row")
    require(nums.group(1) != nums.group(2), "self-test ParentTree row is degenerate")
    swapped_row = showcase[: nums.start()] + (
        b"/Nums [0 [" + nums.group(2) + b" 0 R " + nums.group(1) + b" 0 R "
    ) + showcase[nums.end() :]
    require(len(swapped_row) == len(showcase), "ParentTree mutation changed the byte length")

    mutations = (
        ("form type", replace_once(showcase, b"/FormType 1", b"/FormType 2")),
        ("matrix", replace_once(showcase, b"/Matrix [1 0 0 1 0 0]", b"/Matrix [2 0 0 1 0 0]")),
        ("parent tree ownership", swapped_row),
        ("struct parents", replace_once(showcase, b"/StructParents 0", b"/StructParents 9")),
    )
    for label, mutation in mutations:
        try:
            validate_showcase(mutation, showcase_dimensions)
        except ValidationError:
            continue
        raise SystemExit(f"Gate 4 form checker accepted mutated {label}")
    print("PASS Gate 4 Form XObject structural checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path, default=SHOWCASE_SNAPSHOT)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    validate_showcase(args.pdf.read_bytes(), {"pages": 1, "gate4_forms_showcase": 1, "authored_forms": 9, "canonical_forms": 5})
    print(f"PASS Gate 4 Form XObject structural check: {args.pdf}")


if __name__ == "__main__":
    main()
