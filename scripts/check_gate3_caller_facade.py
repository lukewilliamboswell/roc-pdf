#!/usr/bin/env python3
"""Structural and reader evidence for the public caller-font facade fixture."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from check_gate3_caller_text import EXPECTED_NAMES, subset_names
from check_gate3_facade_output import (
    check_fixture_renderers,
    check_pdfbox_extraction,
    only_page_font,
    validate_facade_output_pdf,
)
from check_gate3_renderers import InkMetrics
from check_gate3_text import decoded_stream, only_object, replace_once
from check_pdf_structure import ValidationError, dictionary_ref, dictionary_ref_array, object_slices, require


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests" / "gate3_caller_facade" / "snapshot.pdf"
ORACLE = ROOT / "tests" / "gate3_caller_facade" / "oracles.json"


def fixture_oracle() -> tuple[str, str, tuple[InkMetrics, InkMetrics]]:
    raw = json.loads(ORACLE.read_text(encoding="utf-8"))
    required = {"direct_text", "pdfbox_text", "pdfbox_72dpi", "pdfium_72dpi"}
    if set(raw) != required or any(not isinstance(raw[name], str) for name in ("direct_text", "pdfbox_text")):
        raise SystemExit(f"invalid caller-facade oracle: {ORACLE}")
    fields = ("x0", "y0", "x1", "y1", "changed", "dark", "ink")
    metrics: list[InkMetrics] = []
    for renderer in ("pdfbox_72dpi", "pdfium_72dpi"):
        entry = raw[renderer]
        if not isinstance(entry, dict) or set(entry) != set(fields) or any(type(entry[name]) is not int for name in fields):
            raise SystemExit(f"invalid {renderer} metrics in caller-facade oracle: {ORACLE}")
        metrics.append(InkMetrics(
            bounds=(entry["x0"], entry["y0"], entry["x1"], entry["y1"]),
            changed_pixels=entry["changed"],
            dark_pixels=entry["dark"],
            ink=entry["ink"],
        ))
    return raw["direct_text"], raw["pdfbox_text"], (metrics[0], metrics[1])


def validate_gate3_caller_facade_pdf(pdf: bytes) -> None:
    direct_text, _, _ = fixture_oracle()
    validate_facade_output_pdf(pdf, direct_text)
    _, bodies = object_slices(pdf)
    page = only_object(bodies, b"/Type /Page ", "page")
    _, content = decoded_stream(bodies, dictionary_ref(bodies[page], b"Contents"))
    require(content.count(b" BDC\n") == 3, "caller facade must retain three fragment-owned placements")
    require(content.count(b"BT\n") == 3, "caller facade must retain three text placements")

    _, type0 = only_page_font(bodies[page])
    type0_body = bodies[type0]
    descendants = dictionary_ref_array(type0_body, b"DescendantFonts")
    require(len(descendants) == 1, "caller facade Type 0 font has the wrong descendant count")
    descriptor = dictionary_ref(bodies[descendants[0]], b"FontDescriptor")
    descriptor_body = bodies[descriptor]
    require(b"/CapHeight 728" in descriptor_body, "caller facade did not retain validated OS/2 CapHeight")
    names = re.findall(rb"/(?:BaseFont|FontName) /([A-Z]{6}\+CallerFixtureSans-Regular)", type0_body + bodies[descendants[0]] + descriptor_body)
    require(len(names) == 3 and len(set(names)) == 1, "caller facade substituted the packaged face or changed its subset identity")
    _, font_bytes = decoded_stream(bodies, dictionary_ref(descriptor_body, b"FontFile2"))
    require(subset_names(font_bytes) == EXPECTED_NAMES, "caller facade subset did not preserve caller source names")


def self_test() -> None:
    pdf = SNAPSHOT.read_bytes()
    validate_gate3_caller_facade_pdf(pdf)
    for index, mutation in enumerate((
        replace_once(pdf, b"/CapHeight 728", b"/CapHeight 729"),
        replace_once(pdf, b"/FontName /GJLQPJ+CallerFixtureSans-Regular", b"/FontName /GJLQPJ+CallerFixtureSans-Regulbr"),
    )):
        try:
            validate_gate3_caller_facade_pdf(mutation)
        except ValidationError:
            continue
        raise SystemExit(f"Gate 3 caller-facade checker accepted atomic negative twin {index}")
    print("PASS Gate 3 caller-font facade structural checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path, default=SNAPSHOT)
    parser.add_argument("--pdfbox-extraction", action="store_true")
    parser.add_argument("--pdfium-renderer", type=Path)
    parser.add_argument("--pdfium-working-directory", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    direct_text, pdfbox_text, metrics = fixture_oracle()
    pdf = args.pdf.resolve()
    validate_gate3_caller_facade_pdf(pdf.read_bytes())
    print(f"PASS Gate 3 caller-font facade structure, source identity, CID, and three-placement facts: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf, pdfbox_text)
    if args.pdfium_renderer is not None:
        check_fixture_renderers(args.pdfium_renderer.resolve(), args.pdfium_working_directory, pdf, metrics)


if __name__ == "__main__":
    main()
