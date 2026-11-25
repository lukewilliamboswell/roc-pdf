#!/usr/bin/env python3
"""Verify declared accessibility claims on the original emitted PDF bytes.

The harness first regenerates its registered snapshots and checks byte
identity. This lane runs the pinned validator separately with explicit
4, ua2 and wt1a profiles on those same paths. Atomic negative twins generated
under .roc-pdf-tmp check the validator response to isolated object changes.
"""
from __future__ import annotations

import argparse
import json
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

from check_pdf_structure import STRING, ValidationError, decode_stream, dictionary_ref, require as require_structure
from check_pdfa4 import (
    DEFAULT_VERAPDF, ROOT, SPEC, VERSION, OracleError, check_compliant, classify,
    require, run_verapdf, synthetic,
)
from check_pdfa4_structure import check_metadata, dictionary_part, skeleton
from extract_verapdf_rules import ACCESSIBILITY_PROFILES
from pdf_layout import LayoutError, is_stream_body, mutate, planned_bodies, trailer_facts

RDF = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
UAID = "http://www.aiim.org/pdfua/ns/id/"
DECLARATIONS = "http://pdfa.org/declarations/"
ACCESSIBILITY = DECLARATIONS + "wtpdf#accessibility1.0"
REFERENCES = ROOT / "tests" / "reference_documents"
REPORT_ROOT = ROOT / ".roc-pdf-tmp" / "accessible-archive-oracles"


def validate_claims(data: bytes, *, wtpdf: bool = False) -> None:
    _offsets, bodies, root, _xref = skeleton(data, 0)
    packet = check_metadata(bodies, dictionary_part(bodies[root]))
    try:
        xml = ET.fromstring(packet.split(b"?>", 1)[1].rsplit(b"<?xpacket", 1)[0])
    except ET.ParseError as error:
        raise ValidationError(f"XMP packet is invalid XML: {error}") from error
    description = f".//{{{RDF}}}Description"
    for field, expected in (("part", "2"), ("rev", "2024")):
        key = f"{{{UAID}}}{field}"
        values = [item.text for item in xml.findall(f"{description}/{key}")]
        all_values = xml.findall(f".//{key}")
        require_structure(values == [expected] and len(all_values) == 1, f"XMP must declare exactly pdfuaid:{field} {expected}")
        require_structure(re.search(rb"<pdfuaid:" + field.encode() + rb">", packet) is not None, f"XMP pdfuaid:{field} prefix changed")
    declaration_path = f"{description}/{{{DECLARATIONS}}}declarations/{{{RDF}}}Bag/{{{RDF}}}li"
    resources = xml.findall(declaration_path)
    declarations = xml.findall(f".//{{{DECLARATIONS}}}declarations")
    all_targets = xml.findall(f".//{{{DECLARATIONS}}}conformsTo")
    if wtpdf:
        require_structure(len(declarations) == len(resources) == len(all_targets) == 1, "XMP must carry one WTPDF declaration resource")
        resource = resources[0]
        require_structure(resource.get(f"{{{RDF}}}parseType") == "Resource", "WTPDF declaration must be an RDF resource")
        targets = resource.findall(f"{{{DECLARATIONS}}}conformsTo")
        require_structure([item.text for item in targets] == [ACCESSIBILITY], "XMP must declare WTPDF 1.0 Accessibility")
    else:
        require_structure(not declarations and not all_targets, "unexpected WTPDF declaration")


def case_paths() -> tuple[list[Path], list[Path]]:
    cases = json.loads(SPEC.read_text(encoding="utf-8"))["cases"]
    flags: dict[Path, tuple[bool, bool]] = {}
    for case in cases:
        path = ROOT / case["snapshot"]
        validators = case["validators"]
        ua = "pdfua2" in validators
        wt = "wtpdf_accessibility" in validators
        require(not ua or "pdfa4" in validators, f"{path}: PDF/UA-2 requires the PDF/A-4 checker")
        require(not wt or ua, f"{path}: WTPDF accessibility requires the PDF/UA-2 checker")
        require(flags.setdefault(path, (ua, wt)) == (ua, wt), f"{path}: cases sharing a snapshot disagree on declared profiles")
    combined = sorted(path for path, (ua, _) in flags.items() if ua)
    wtpdf = sorted(path for path, (_, wt) in flags.items() if wt)
    return combined, wtpdf


@dataclass(frozen=True)
class Control:
    name: str
    source: str | Path
    scope: str
    old: bytes | re.Pattern[bytes]
    new: bytes
    expected: frozenset[str]
    flavour: str = "ua2"


def ua_control(name: str, source: str | Path, scope: str, old: bytes | re.Pattern[bytes], new: bytes, *rules: str) -> Control:
    return Control(name, source, scope, old, new, frozenset(rules))


CONTROLS = (
    ua_control("ua-identification", "letter", "payloads", re.compile(rb"<pdfuaid:part>2</pdfuaid:part>\s*<pdfuaid:rev>2024</pdfuaid:rev>"), b"", "5-1"),
    ua_control("ua-identification-part", "letter", "payloads", b"<pdfuaid:part>2</pdfuaid:part>", b"<pdfuaid:part>1</pdfuaid:part>", "5-2"),
    ua_control("ua-identification-part-prefix", "letter", "payloads", b"<pdfuaid:part>2</pdfuaid:part>", b'<uaid:part xmlns:uaid="' + UAID.encode() + b'">2</uaid:part>', "5-3"),
    ua_control("ua-identification-rev-prefix", "letter", "payloads", b"<pdfuaid:rev>2024</pdfuaid:rev>", b'<uaid:rev xmlns:uaid="' + UAID.encode() + b'">2024</uaid:rev>', "5-4"),
    ua_control("ua-identification-revision", "letter", "payloads", b"<pdfuaid:rev>2024</pdfuaid:rev>", b"<pdfuaid:rev>2020</pdfuaid:rev>", "5-5"),
    ua_control("mark-info", "letter", "objects", b"/Marked true", b"/Marked false", "6.2-1"),
    ua_control("document-title", "letter", "payloads", re.compile(rb"<dc:title>.*?</dc:title>", re.S), b"", "8.11.1-1"),
    ua_control("metadata-subtype", "letter", "objects", b"/Subtype /XML /Type /Metadata", b"/Subtype /Text /Type /Metadata", "8.11.1-2"),
    ua_control("display-document-title", "letter", "objects", b"/DisplayDocTitle true", b"/DisplayDocTitle false", "8.11.2-1"),
    ua_control("structure-root", "letter", "objects", re.compile(rb" /StructTreeRoot [0-9]+ 0 R(?= /Type /Catalog)"), b"", "8.2.1-1", "8.2.2-1"),
    ua_control("structure-containment", "letter", "objects", b"/S /LBody ", b"/S /LI ", "Table 5. LI-LI-1", "Table 5. LI-P-1"),
    ua_control("nonstandard-structure-role", "letter", "objects", b"/S /LBody ", b"/S /Unknown ", "8.2.4-1"),
    ua_control("unnumbered-heading", "letter", "objects", b"/S /H1 ", b"/S /H ", "8.2.5.12-1"),
    ua_control("single-document-root", "letter", "objects", re.compile(rb"/K ([0-9]+ 0 R)(?=[^\n]+ /Type /StructTreeRoot)"), rb"/K [\g<1> \g<1>]", "8.2.5.2-1", "Table 5. StructTreeRoot-Document-1"),
    ua_control("link-structure-role", "invoice", "objects", b"/S /Link ", b"/S /Span ", "8.2.5.20-1"),
    ua_control("document-namespace", "letter", "objects", re.compile(rb" /NS [0-9]+ 0 R(?= /P [0-9]+ 0 R /S /Document >>)"), b"", "8.2.5.2-2"),
    ua_control("list-numbering", "letter", "objects", b"/ListNumbering /Decimal", b"/ListNumbering /None", "8.2.5.25-1"),
    ua_control("table-column-span", "letter", "objects", b"/O /Table /Scope /Column", b"/ColSpan 2 /O /Table /Scope /Column", "8.2.5.26-4"),
    ua_control("figure-alternative", "report", "objects", re.compile(rb" /Alt " + STRING + rb"(?= [^\n]+ /S /Figure >>)"), b"", "8.2.5.28.2-1"),
    ua_control("alternate-text-pua", "report", "objects", re.compile(rb" /Alt " + STRING + rb"(?= [^\n]+ /S /Figure >>)"), b" /Alt <FEFFE000>", "8.4.3-3"),
    ua_control("document-language", "letter", "objects", b"/Lang (en-AU) /MarkInfo", b"/MarkInfo", "8.4.4-1"),
    ua_control("invalid-language", "letter", "objects", b"/Lang (en-AU) /MarkInfo", b"/Lang (12_) /MarkInfo", "8.4.4-2"),
    ua_control("cid-to-gid-map", "letter", "objects", b" /CIDToGIDMap /Identity", b"", "8.4.5.3.2-1"),
    ua_control("embedded-font-program", "letter", "objects", re.compile(rb" /FontFile2 [0-9]+ 0 R"), b"", "8.4.5.5.1-1"),
    ua_control("to-unicode", "letter", "objects", re.compile(rb" /ToUnicode [0-9]+ 0 R"), b"", "8.4.5.8-1"),
    ua_control("internal-structure-destination", "report", "objects", re.compile(rb"(?<=/S /GoTo) /SD \[[^\]]+\]"), b"", "8.8-2"),
    ua_control("invisible-link", "invoice", "objects", b" /F 4 /QuadPoints", b" /F 5 /QuadPoints", "8.9.2.2-1"),
    ua_control("link-tab-order", "invoice", "objects", re.compile(rb"(/Annots \[[^\]]+\][^\n]+?) /Tabs /S(?= /Type /Page)"), rb"\g<1>", "8.9.3.3-1"),
    ua_control("unclassified-artifact", "letter", "streams", re.compile(rb"/Artifact <</Type /Pagination /Subtype /Header>> BDC\n(.*?)EMC\n", re.S), rb"\g<1>", "8.2.2-1"),
    ua_control("table-row-span", "letter", "objects", b"/O /Table /Scope /Column", b"/O /Table /RowSpan 2 /Scope /Column", "8.2.5.26-2"),
    ua_control("table-caption-position", "letter", "objects", re.compile(rb"(/K \[)([0-9]+ 0 R) ([0-9]+ 0 R) ([0-9]+ 0 R)(\] /NS [0-9]+ 0 R /P [0-9]+ 0 R /S /Table >>)"), rb"\g<1>\g<3> \g<2> \g<4>\g<5>", "8.2.5.27-1"),
    ua_control("glyph-width", "letter", "objects", re.compile(rb"(/W \[0 \[[0-9]+) [0-9]+"), rb"\g<1> 7000", "8.4.5.6-1"),
    ua_control("unicode-mapping-bom", "report", "streams", re.compile(rb"(?<=beginbfchar\n)<0001> <0020>"), b"<0001> <FEFF>", "8.4.5.8-2"),
    ua_control("real-text-pua", "report", "streams", re.compile(rb"(?<=beginbfchar\n)<0001> <0020>"), b"<0001> <E000>", "8.4.3-1"),
    ua_control("notdef-glyph", "letter", "streams", re.compile(rb"(\n\[<)[0-9A-F]{4}(?=[0-9A-F]+>)"), rb"\g<1>0000", "8.4.5.8-1", "8.4.5.9-1"),
    ua_control("outline-title-pua", "report", "objects", re.compile(rb" /Title " + STRING + rb"(?= >>)"), b" /Title <FEFFE000>", "8.6-1"),
    ua_control("no-view-link", "invoice", "objects", b" /F 4 /QuadPoints", b" /F 36 /QuadPoints", "8.9.2.2-2"),
    Control(
        "wtpdf-declaration-missing", "", "payloads",
        re.compile(rb"<pdfd:declarations>.*?</pdfd:declarations>", re.S),
        b"", frozenset({"6.1.3-1"}), "wt1a",
    ),
    Control("wtpdf-identifier", "", "payloads", ACCESSIBILITY.encode(), b"http://pdfa.org/declarations/example", frozenset({"6.1.3-1"}), "wt1a"),
)


def reworked_control(data: bytes, control: Control) -> bytes:
    """Edit one PDF fact, repairing only serialization offsets and lengths."""
    if isinstance(control.old, bytes):
        return mutate(data, control.old, control.new, occurrences=None, scope=control.scope, first_only=True)
    parsed, bodies = planned_bodies(data)
    if control.scope == "objects":
        for number in sorted(bodies):
            body = bodies[number]
            if not control.old.search(body):
                continue
            changed = control.old.sub(control.new, body, count=1)
            return mutate(data, body, changed, scope="objects")
    elif control.scope == "streams":
        for number in sorted(bodies):
            body = bodies[number]
            if not is_stream_body(body) or b"/Filter /DCTDecode" in dictionary_part(body):
                continue
            _, payload = decode_stream(bodies, number)
            match = control.old.search(payload)
            if match:
                return mutate(data, match.group(0), match.expand(control.new), scope="payloads", first_only=True, occurrences=None)
    else:
        root, _id = trailer_facts(parsed)
        _dict, packet = decode_stream(bodies, dictionary_ref(bodies[int(root)], b"Metadata"))
        match = control.old.search(packet)
        if match:
            return mutate(data, match.group(0), match.expand(control.new), scope="payloads")
    raise OracleError(f"{control.name}: mutation target {control.old.pattern!r} absent")


def expect_rejection(control: Control, result_path: str, compliant: bool, failed_rules: frozenset[str]) -> None:
    require(
        not compliant and failed_rules == control.expected,
        f"{result_path}: {control.name}: expected {sorted(control.expected)}, observed {sorted(failed_rules)}",
    )


def run_controls(verapdf: Path, combined: list[Path], wtpdf: list[Path], report_dir: Path) -> None:
    bases = set(combined)
    output = report_dir / "control-pdfs"
    output.mkdir(parents=True, exist_ok=True)
    for flavour in sorted({control.flavour for control in CONTROLS}):
        controls = [control for control in CONTROLS if control.flavour == flavour]
        paths = []
        for control in controls:
            if control.source:
                source = control.source if isinstance(control.source, Path) else REFERENCES / f"{control.source}.pdf"
                require(source in bases, f"{control.name}: source is not a registered combined positive")
            else:
                require(bool(wtpdf), f"{control.name}: no registered WTPDF positive")
                source = wtpdf[0]
            path = output / f"{control.name}.pdf"
            data = source.read_bytes()
            changed = reworked_control(data, control)
            require(changed != data, f"{control.name}: mutation changed no bytes")
            path.write_bytes(changed)
            paths.append(path)
        results = run_verapdf(verapdf, paths, flavour=flavour, report_dir=report_dir / "negative")
        for control, result in zip(controls, results, strict=True):
            expect_rejection(control, result.path, result.compliant, result.failed_rules)
        print(f"PASS veraPDF {VERSION} {flavour}: {len(results)} atomic negative controls failed their exact rules")


def validate_cases(verapdf: Path, combined: list[Path], wtpdf: list[Path], report_dir: Path) -> None:
    require(combined, "no registered PDF/UA-2 fixtures")
    wt_set = set(wtpdf)
    for path in combined:
        try:
            validate_claims(path.read_bytes(), wtpdf=path in wt_set)
        except ValidationError as error:
            raise OracleError(f"{path}: {error}") from error
    for flavour, paths in (("4", combined), ("ua2", combined), ("wt1a", wtpdf)):
        if not paths:
            continue
        results = run_verapdf(verapdf, paths, flavour=flavour, report_dir=report_dir / "positive")
        check_compliant(results, flavour)
        print(f"PASS veraPDF {VERSION} {flavour}: {len(results)} original PDFs compliant with zero failed checks")


def self_test() -> None:
    combined, wt = case_paths()
    require(set(wt) <= set(combined), "WTPDF cases are missing from combined cases")
    ids = {
        name: {rule["id"] for rule in json.loads(profile.catalog.read_text(encoding="utf-8"))["rules"]}
        for name, profile in ACCESSIBILITY_PROFILES.items()
    }
    require(len({item.name for item in CONTROLS}) == len(CONTROLS), "duplicate negative control name")
    for control in CONTROLS:
        require(control.expected and control.expected <= ids[control.flavour], f"{control.name}: rule is absent from pinned profile")
        expect_rejection(control, "synthetic.pdf", False, control.expected)
        for verdict, rules in ((True, frozenset()), (False, control.expected | {"unrelated"})):
            try:
                expect_rejection(control, "synthetic.pdf", verdict, rules)
            except OracleError:
                continue
            raise OracleError(f"{control.name}: accepted a false verdict or extra rule failure")
    for name, profile in ACCESSIBILITY_PROFILES.items():
        check_compliant(classify(synthetic(True, [], profile=profile.name), flavour=name), name)
        try:
            classify(synthetic(True, []), flavour=name)
        except OracleError:
            continue
        raise OracleError(f"{name}: accepted a report from the PDF/A-4 profile")
    print(f"PASS accessibility oracle self-test: {len(CONTROLS)} exact negative verdicts and profile inventory")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verapdf", type=Path, default=DEFAULT_VERAPDF)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--cases", action="store_true")
    mode.add_argument("--self-test", action="store_true")
    parser.add_argument("--wtpdf", action="store_true", help="require WTPDF Accessibility on supplied paths")
    parser.add_argument("pdfs", nargs="*", type=Path)
    args = parser.parse_args()

    try:
        if args.self_test:
            require(not args.pdfs and not args.wtpdf, "--self-test takes no PDF paths or --wtpdf")
            self_test()
        elif args.cases:
            require(not args.pdfs and not args.wtpdf, "--cases takes no PDF paths or --wtpdf")
            combined, wtpdf = case_paths()
            require(wtpdf, "no registered WTPDF accessibility fixtures")
            validate_cases(args.verapdf, combined, wtpdf, REPORT_ROOT)
            run_controls(args.verapdf, combined, wtpdf, REPORT_ROOT)
        else:
            require(args.pdfs, "supply PDF paths or choose --cases or --self-test")
            validate_cases(args.verapdf, args.pdfs, args.pdfs if args.wtpdf else [], REPORT_ROOT)
    except (LayoutError, OracleError, ValidationError) as error:
        raise SystemExit(f"FAIL {error}") from error


if __name__ == "__main__":
    main()
