#!/usr/bin/env python3
"""Independent structural checks for production-visual Form-backed alpha soft-mask
fixtures.

The checker parses the emitted bytes directly (no rewriting tool in front)
and proves the soft-mask facts of the slice without trusting the Roc
planner's summaries:

- every canonical mask state is exactly
  ``<< /SMask << /G m 0 R /S /Alpha /Type /Mask >> /Type /ExtGState >>``,
  one object per canonical mask form, and its ``/G`` resolves directly to a
  Form XObject carrying the exact isolated transparency group over the
  canonical blending space — never through a resource dictionary name;
- mask forms appear in no stream's ``/Resources`` dictionary (unless also
  placed as content), while the ``gs`` operands that select mask states
  resolve through their own stream's exact direct ``/ExtGState`` dictionary
  and open balanced ``q``-then-``gs`` groups;
- luminosity masks, backdrop colors, transfer functions, knockout state,
  and non-Normal blend modes appear nowhere;
- repeated mask groups across page and form streams share one physical mask
  state and one physical mask form, while distinct mask forms never merge;
- placement-site MCID/ParentTree ownership stays exactly the page-stream
  facts of the form slice.
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

from check_forms import check_ownership, replace_once
from check_transparency import (
    FORM_GROUP,
    TransparencyFacts,
    alpha_decimal,
)
from check_pdf_structure import ValidationError, require, validate_pdf

ROOT = Path(__file__).resolve().parents[1]
SHOWCASE_SNAPSHOT = ROOT / "tests" / "soft_masks" / "soft_masks.pdf"
REUSE_100_SNAPSHOT = ROOT / "tests" / "soft_masks" / "soft_masks_reuse_100.pdf"
REUSE_1000_SNAPSHOT = ROOT / "tests" / "soft_masks" / "soft_masks_reuse_1000.pdf"
MASKS_8_SNAPSHOT = ROOT / "tests" / "soft_masks" / "soft_masks_masks_8.pdf"
MASKS_64_SNAPSHOT = ROOT / "tests" / "soft_masks" / "soft_masks_masks_64.pdf"
CHAIN_2_SNAPSHOT = ROOT / "tests" / "soft_masks" / "soft_masks_chain_2.pdf"
CHAIN_4_SNAPSHOT = ROOT / "tests" / "soft_masks" / "soft_masks_chain_4.pdf"
NEGATIVE_SNAPSHOT = ROOT / "tests" / "soft_masks" / "soft_masks_negative.pdf"


def named_form_targets(facts: TransparencyFacts) -> set[int]:
    """Every form object reachable through a stream's /XObject dictionary."""
    named: set[int] = set()
    for page in facts.pages:
        for name, target in facts.form_facts.page_resources[page].items():
            if name.startswith("XO"):
                named.add(target)
    for form in facts.form_facts.forms:
        for name, target in facts.form_facts.form_resources[form].items():
            if name.startswith("XO"):
                named.add(target)
    return named


def check_mask_wiring(facts: TransparencyFacts, expected_masks: int) -> set[int]:
    """The canonical mask states, their isolated mask forms, and the rule
    that mask-only forms never enter a resource dictionary."""
    require(
        len(facts.mask_states) == expected_masks,
        f"expected {expected_masks} canonical mask states, found {len(facts.mask_states)}",
    )
    mask_forms = set(facts.mask_states.values())
    named = named_form_targets(facts)
    group_space = facts.page_group_space(facts.pages[0])
    require(group_space is not None, "masked page lost its transparency /Group dictionary")
    facts.check_blending_space(group_space)
    for state, target in facts.mask_states.items():
        group = FORM_GROUP.search(facts.form_facts.forms[target])
        require(group is not None, f"mask state {state}: mask form {target} lost its isolated group")
        require(
            int(group.group(1)) == group_space,
            f"mask state {state}: mask group blending space diverges from the page group",
        )
    for target in mask_forms - named:
        ## A mask-only form is referenced exclusively through /SMask /G.
        for page in facts.pages:
            require(
                target not in facts.form_facts.page_resources[page].values(),
                f"mask form {target} leaked into a page resource dictionary",
            )
    return mask_forms


def validate_soft_mask_showcase(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = TransparencyFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.form_facts.page_contents[page], True)

    mask_forms = check_mask_wiring(facts, dimensions["canonical_mask_states"])
    require(
        len(facts.states) + len(facts.mask_states) == dimensions["canonical_ext_g_states"],
        "canonical ExtGState object count mismatch",
    )
    require(
        len(facts.form_facts.forms) == dimensions["canonical_forms"],
        "physical form count is not the canonical count",
    )

    ## The authored twin mask deduplicated: one mask state, one mask form,
    ## and six gs operands resolving to it across page and form streams.
    mask_state = next(iter(facts.mask_states))
    mask_uses = sum(targets.count(mask_state) for targets in facts.stream_gs.values())
    require(mask_uses == dimensions["soft_mask_commands"], f"expected {dimensions['soft_mask_commands']} mask groups, found {mask_uses}")
    form_mask_uses = sum(
        targets.count(mask_state) for owner, targets in facts.stream_gs.items() if owner.startswith("form")
    )
    require(form_mask_uses == 1, "the isolated content form must apply the shared mask once")

    ## The shared half-opacity band inside the mask forms is the one alpha
    ## state, shared with nothing else.
    require(set(facts.states.values()) == {alpha_decimal(32768)}, "the alpha state is not the shared half constant")

    ## The mask form stays out of every resource dictionary; the two placed
    ## content forms are the only named form targets.
    named = named_form_targets(facts)
    require(len(named) == 2, "exactly the two placed content forms carry names")
    require(not (mask_forms & named), "the mask form leaked into a resource dictionary")

    ## Placement-site ownership stays page-stream facts: four meaningful
    ## placements, logical order leading with the second painted paragraph.
    check_ownership(facts.form_facts, page, 4)


def validate_soft_mask_grid(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = TransparencyFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.form_facts.page_contents[page], True)

    groups = dimensions["mask_groups"]
    canonical = dimensions["canonical_mask_states"]
    check_mask_wiring(facts, canonical)
    page_gs = facts.stream_gs[f"page {page}"]
    mask_targets = [target for target in page_gs if target in facts.mask_states]
    require(len(mask_targets) == groups, f"expected {groups} mask groups, found {len(mask_targets)}")
    require(
        len(set(mask_targets)) == canonical,
        "mask groups do not resolve to exactly the canonical mask states",
    )
    require(len(facts.states) == 1, "the mask forms' shared band must stay one alpha state")
    require(not named_form_targets(facts), "grid fixtures place no content forms")


def validate_soft_mask_chain(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = TransparencyFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.form_facts.page_contents[page], True)

    depth = dimensions["mask_chain"]
    check_mask_wiring(facts, depth)

    ## The chain links: the page's one mask group selects the head state,
    ## and each mask form up to the tail selects the next mask state in its
    ## own stream.
    page_gs = facts.stream_gs[f"page {page}"]
    require(len(page_gs) == 1 and page_gs[0] in facts.mask_states, "the page must apply exactly the head mask")
    visited = []
    current = facts.mask_states[page_gs[0]]
    while True:
        require(current not in visited, "mask chain revisits a form")
        visited.append(current)
        nested = [
            facts.mask_states[target]
            for target in facts.stream_gs[f"form {current}"]
            if target in facts.mask_states
        ]
        require(len(nested) <= 1, f"mask form {current} applies more than one mask")
        if not nested:
            break
        current = nested[0]
    require(len(visited) == depth, f"mask chain depth {len(visited)} does not match {depth}")


def validate_soft_masks_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    if dimensions.get("soft_mask_showcase"):
        validate_soft_mask_showcase(pdf, dimensions)
    elif dimensions.get("soft_mask_reuse") or dimensions.get("soft_mask_distinct"):
        validate_soft_mask_grid(pdf, dimensions)
    elif dimensions.get("soft_mask_chain"):
        validate_soft_mask_chain(pdf, dimensions)
    else:
        raise ValidationError("unknown production-visual soft-mask fixture dimensions")


SHOWCASE_DIMENSIONS = {
    "pages": 1,
    "soft_mask_showcase": 1,
    "soft_mask_commands": 6,
    "mask_states": 2,
    "canonical_mask_states": 1,
    "canonical_ext_g_states": 2,
    "canonical_forms": 3,
    "isolated_forms": 2,
}


def self_test() -> None:
    showcase = SHOWCASE_SNAPSHOT.read_bytes()
    validate_soft_mask_showcase(showcase, SHOWCASE_DIMENSIONS)
    validate_soft_mask_grid(
        REUSE_100_SNAPSHOT.read_bytes(),
        {"pages": 1, "soft_mask_reuse": 1, "mask_groups": 100, "canonical_mask_states": 1},
    )
    validate_soft_mask_grid(
        REUSE_1000_SNAPSHOT.read_bytes(),
        {"pages": 1, "soft_mask_reuse": 1, "mask_groups": 1000, "canonical_mask_states": 1},
    )
    validate_soft_mask_grid(
        MASKS_8_SNAPSHOT.read_bytes(),
        {"pages": 1, "soft_mask_distinct": 1, "mask_groups": 8, "canonical_mask_states": 8},
    )
    validate_soft_mask_grid(
        MASKS_64_SNAPSHOT.read_bytes(),
        {"pages": 1, "soft_mask_distinct": 1, "mask_groups": 64, "canonical_mask_states": 64},
    )
    validate_soft_mask_chain(
        CHAIN_2_SNAPSHOT.read_bytes(),
        {"pages": 1, "soft_mask_chain": 1, "mask_chain": 2},
    )
    validate_soft_mask_chain(
        CHAIN_4_SNAPSHOT.read_bytes(),
        {"pages": 1, "soft_mask_chain": 1, "mask_chain": 4},
    )
    validate_soft_mask_grid(
        NEGATIVE_SNAPSHOT.read_bytes(),
        {"pages": 1, "soft_mask_reuse": 1, "mask_groups": 1, "canonical_mask_states": 1},
    )

    ## Length-preserving mutation twins: each must be rejected.
    mutations = (
        ("mask subtype", replace_once(showcase, b"/S /Alpha /Type /Mask", b"/S /Alphb /Type /Mask")),
        ("mask kind", replace_once(showcase, b"/Type /Mask", b"/Type /Masq")),
        ("mask group isolation", replace_once(showcase, b"/I true /S /Transparency", b"/I trux /S /Transparency")),
        ("blend mode", replace_once(showcase, b"/BM /Normal", b"/BM /Nermal")),
    )
    for label, mutation in mutations:
        try:
            validate_soft_mask_showcase(mutation, SHOWCASE_DIMENSIONS)
        except ValidationError:
            continue
        raise SystemExit(f"production-visual soft-mask checker accepted mutated {label}")
    print("PASS production-visual soft-mask structural checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path, default=SHOWCASE_SNAPSHOT)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    validate_soft_mask_showcase(args.pdf.read_bytes(), SHOWCASE_DIMENSIONS)
    print(f"PASS production-visual soft-mask structural check: {args.pdf}")


if __name__ == "__main__":
    main()
