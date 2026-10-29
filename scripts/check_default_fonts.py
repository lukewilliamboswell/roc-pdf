#!/usr/bin/env python3
"""Verify public default-family selection against the exact static font programs.

This independent oracle reads original emitted bytes, resolves each shown CID
through its own font and ToUnicode mapping, validates every embedded subset,
and compares selected glyph outlines and style facts with the pinned source.
It neither asks the Roc resolver which face it chose nor trusts font names as
proof of a genuine bold or italic program.
"""
from __future__ import annotations

import argparse
import hashlib
from fractions import Fraction
from pathlib import Path
import re
import struct

from check_fonts import FontFacts
from check_pdf_structure import ValidationError, object_slices, require
from check_rich_inline import page_marked_text
from check_structure_semantics import Document, page_order
from pdf_layout import flatten, mutate

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/default_fonts"
STYLES = {"Regular": (400, False), "Bold": (700, False),
          "Italic": (400, True), "BoldItalic": (700, True)}


def tables(data: bytes) -> dict[bytes, bytes]:
    require(data[:4] == b"\0\1\0\0", "source is not a static TrueType sfnt")
    count = struct.unpack_from(">H", data, 4)[0]
    result = {}
    for index in range(count):
        tag, _checksum, start, length = struct.unpack_from(">4sIII", data, 12 + index * 16)
        require(start + length <= len(data), "source table escapes font")
        result[tag] = data[start:start + length]
    require(not ({b"fvar", b"gvar", b"HVAR", b"MVAR", b"CFF ", b"CFF2"} & result.keys()),
            "selected source is not a supported static TrueType instance")
    return result


def source_glyph(font: dict[bytes, bytes], scalar: int) -> int:
    cmap = font[b"cmap"]
    candidates = []
    for index in range(struct.unpack_from(">H", cmap, 2)[0]):
        platform, encoding, offset = struct.unpack_from(">HHI", cmap, 4 + index * 8)
        fmt = struct.unpack_from(">H", cmap, offset)[0]
        if platform in (0, 3) and fmt in (4, 12):
            candidates.append((fmt, offset))
    for fmt, offset in sorted(candidates, reverse=True):
        if fmt == 12:
            for index in range(struct.unpack_from(">I", cmap, offset + 12)[0]):
                first, last, glyph = struct.unpack_from(">III", cmap, offset + 16 + index * 12)
                if first <= scalar <= last:
                    return glyph + scalar - first
        elif scalar <= 0xFFFF:
            count = struct.unpack_from(">H", cmap, offset + 6)[0] // 2
            ends = offset + 14
            starts = ends + count * 2 + 2
            deltas = starts + count * 2
            ranges = deltas + count * 2
            for index in range(count):
                first = struct.unpack_from(">H", cmap, starts + index * 2)[0]
                last = struct.unpack_from(">H", cmap, ends + index * 2)[0]
                if first <= scalar <= last:
                    delta = struct.unpack_from(">h", cmap, deltas + index * 2)[0]
                    distance = struct.unpack_from(">H", cmap, ranges + index * 2)[0]
                    if not distance:
                        return (scalar + delta) & 0xFFFF
                    address = ranges + index * 2 + distance + (scalar - first) * 2
                    value = struct.unpack_from(">H", cmap, address)[0]
                    return (value + delta) & 0xFFFF if value else 0
    raise ValidationError(f"selected source does not cover U+{scalar:04X}")


def glyph_fingerprint(font: dict[bytes, bytes], glyph: int,
                      memo: dict[int, bytes] | None = None,
                      active: frozenset[int] = frozenset()) -> bytes:
    """Ignore only subset glyph-number relocation and trailing sfnt padding."""
    memo = {} if memo is None else memo
    if glyph in memo:
        return memo[glyph]
    require(glyph not in active and len(active) < 64, "composite cycle or excessive depth")
    count = struct.unpack_from(">H", font[b"maxp"], 4)[0]
    require(glyph < count, "glyph escapes font")
    long_loca = struct.unpack_from(">h", font[b"head"], 50)[0]
    fmt, width, multiplier = (">I", 4, 1) if long_loca else (">H", 2, 2)
    start = struct.unpack_from(fmt, font[b"loca"], glyph * width)[0] * multiplier
    end = struct.unpack_from(fmt, font[b"loca"], (glyph + 1) * width)[0] * multiplier
    require(start <= end <= len(font[b"glyf"]), "glyph span escapes glyf")
    data = bytearray(font[b"glyf"][start:end])
    children = []
    if data and struct.unpack_from(">h", data)[0] < 0:
        cursor = 10
        while True:
            flags, child = struct.unpack_from(">HH", data, cursor)
            data[cursor + 2:cursor + 4] = b"\0\0"
            children.append(glyph_fingerprint(font, child, memo, active | {glyph}))
            cursor += 4 + (4 if flags & 1 else 2)
            cursor += 2 if flags & 8 else 4 if flags & 64 else 8 if flags & 128 else 0
            require(cursor <= len(data), "composite transform escapes glyph")
            if not flags & 32:
                break
    result = hashlib.sha256(bytes(data).rstrip(b"\0") + b"".join(children)).digest()
    memo[glyph] = result
    return result


def expected(kind: str) -> dict[str, list[str]]:
    if kind == "gallery":
        return {"Inter-Regular": ["Inter body text supports the Command shortcut ⌘K."],
                "Inter-Bold": ["Built-in font families", "Genuine bold."],
                "Inter-Italic": ["Genuine italic."],
                "Inter-BoldItalic": ["Genuine bold italic."],
                "Merriweather-Regular": ["Merriweather regular."],
                "Merriweather-Bold": ["Serif bold."],
                "Merriweather-Italic": ["Serif italic."],
                "Merriweather-BoldItalic": ["Serif bold italic."],
                "FiraCode-Regular": ["Fira Code ⌘K", "shortcut = \"⌘K\"", "answer = 42"],
                "FiraCode-Bold": ["genuine mono bold"]}
    if kind in ("sans", "serif"):
        label, family = ("Sans", "Inter") if kind == "sans" else ("Serif", "Merriweather")
        return {f"{family}-Regular": [f"{label} regular"],
                f"{family}-Bold": [f"{label} family", f"{label} heading", f"{label} bold"],
                f"{family}-Italic": [f"{label} italic"],
                f"{family}-BoldItalic": [f"{label} strong emphasis", f"{label} emphasis strong"],
                "FiraCode-Regular": ["Fira regular", "source = 42"],
                "FiraCode-Bold": ["Fira bold"]}
    if kind == "mono":
        return {"FiraCode-Regular": ["Mono regular", "Fira regular", "source = 42"],
                "FiraCode-Bold": ["Mono family", "Mono heading", "Mono bold", "Fira bold"]}
    if kind == "override":
        return {"FiraCode-Regular": ["Mono regular"],
                "Inter-Italic": ["Exact italic override"],
                "Inter-BoldItalic": ["Exact combined override", "Exact combined reverse"]}
    require(kind in ("scale_10", "scale_100"), f"unknown default-font fixture {kind}")
    return {"Inter-Regular": ["Scale regular "], "Inter-Bold": ["bold "],
            "Inter-Italic": ["italic "], "Inter-BoldItalic": ["combined "],
            "FiraCode-Regular": ["code", "source = 42"]}


def check(data: bytes, kind: str) -> None:
    _offsets, bodies = object_slices(data)
    pages = sum(b"/Type /Page " in body for body in bodies.values())
    facts = FontFacts(data, pages)
    require({font.postscript_name for font in facts.bundles} == set(expected(kind)),
            f"{kind}: unexpected selected family/style programs")
    for font in facts.bundles:
        name = font.postscript_name
        source = tables((ROOT / "package/fonts" / f"{name}.ttf").read_bytes())
        actual = font.subset.tables
        require(actual[b"OS/2"] == source[b"OS/2"], f"{name}: subset changed source style facts")
        weight, italic = STYLES[name.rsplit("-", 1)[1]]
        require(struct.unpack_from(">H", actual[b"OS/2"], 4)[0] == weight, f"{name}: wrong weight")
        require(bool(struct.unpack_from(">H", actual[b"head"], 44)[0] & 2) == italic,
                f"{name}: wrong genuine italic flag")
        source_angle = struct.unpack_from(">i", source[b"post"], 4)[0]
        source_fixed_value = struct.unpack_from(">I", source[b"post"], 12)[0]
        source_fixed = source_fixed_value != 0
        # These pinned rc4 programs leave IBM family classification unknown;
        # their PANOSE serif field is also unknown (including Inter's Latin
        # text family). A family name must not invent a Serif descriptor bit.
        family_class = struct.unpack_from(">H", source[b"OS/2"], 30)[0]
        panose_family, panose_serif = source[b"OS/2"][32:34]
        require(family_class == 0 and panose_family in (0, 2) and panose_serif == 0,
                f"{name}: pinned source classification changed; review descriptor expectations")
        require(struct.unpack_from(">i", actual[b"post"], 4)[0] == source_angle,
                f"{name}: sanitized post table lost the exact source italic angle")
        require(struct.unpack_from(">I", actual[b"post"], 12)[0] == source_fixed_value,
                f"{name}: sanitized post table lost source fixed-pitch evidence")
        descriptor = bodies[font.descriptor]
        flags = re.search(rb"/Flags ([0-9]+)(?:\s|>)", descriptor)
        angle = re.search(rb"/ItalicAngle ([+-]?[0-9]+(?:\.[0-9]+)?)(?:\s|>)", descriptor)
        require(flags is not None and angle is not None, f"{name}: missing descriptor style fields")
        flags_value = int(flags[1])
        require(bool(flags_value & 64) == italic, f"{name}: PDF Italic flag disagrees with the selected program")
        require(bool(flags_value & 1) == source_fixed,
                f"{name}: PDF FixedPitch flag disagrees with the selected program")
        require(not flags_value & 2, f"{name}: PDF Serif flag invents missing source classification")
        require(Fraction(angle[1].decode()) == Fraction(source_angle, 65536),
                f"{name}: PDF ItalicAngle is not the exact selected source angle")
        source_memo: dict[int, bytes] = {}
        subset_memo: dict[int, bytes] = {}
        for cid, text in font.mappings.items():
            require(len(text) == 1, f"{name}: unexpected mapping expansion in this fixture")
            original = source_glyph(source, ord(text))
            require(original > 0, f"{name}: source maps {text!r} to .notdef")
            require(glyph_fingerprint(actual, cid, subset_memo) == glyph_fingerprint(source, original, source_memo),
                    f"{name}: subset glyph for {text!r} differs from the selected static program")
    document = Document(data)
    order: list[int] = []
    page_order(document, int(document.get(document.root)["Pages"]), order)
    by_font: dict[str, list[str]] = {}
    for page in order:
        page_marked_text(document, page, by_font=by_font)
    for name, fragments in expected(kind).items():
        shown = "".join(by_font.get(name, []))
        for fragment in fragments:
            require(fragment in shown, f"{kind}: {fragment!r} is not shown in {name}")
        if kind.startswith("scale_"):
            count = int(kind.split("_")[1])
            for fragment in fragments:
                require(shown.count(fragment) == count,
                        f"{kind}: {name} does not own every authored {fragment!r}")
    print(f"PASS default fonts {kind}: {len(facts.bundles)} exact static programs, source glyphs and selectable text")


def validate_default_fonts_pdf(data: bytes, dimensions: dict[str, int]) -> None:
    kinds = [kind for kind in ("sans", "serif", "mono", "override")
             if dimensions.get(f"default_font_{kind}") == 1]
    if "font_resolution_sections" in dimensions:
        kinds.append(f"scale_{dimensions['font_resolution_sections']}")
    require(len(kinds) == 1, "default font oracle requires one explicit fixture kind")
    check(data, kinds[0])


def self_test_glyphs() -> None:
    # A composite's relocated component ID must not change its outline proof;
    # a changed child program must change the proof.
    simple = struct.pack(">hhhhh", 1, 0, 0, 10, 10) + b"\x01\x02"
    compound = struct.pack(">hhhhhHHhh", -1, 0, 0, 10, 10, 3, 0, 0, 0)
    def model(glyphs: list[bytes]) -> dict[bytes, bytes]:
        head = bytearray(54)
        struct.pack_into(">h", head, 50, 1)
        ends = [0]
        for glyph in glyphs:
            ends.append(ends[-1] + len(glyph))
        return {b"head": bytes(head), b"maxp": b"\0\1\0\0" + struct.pack(">H", len(glyphs)),
                b"loca": b"".join(struct.pack(">I", end) for end in ends), b"glyf": b"".join(glyphs)}
    relocated = bytearray(compound)
    struct.pack_into(">H", relocated, 12, 1)
    original = model([simple, compound])
    moved = model([bytes(relocated), simple])
    changed = model([bytes(relocated), simple[:-1] + b"\x03"])
    require(glyph_fingerprint(original, 1) == glyph_fingerprint(moved, 0), "component relocation changed proof")
    require(glyph_fingerprint(original, 1) != glyph_fingerprint(changed, 0), "changed child program escaped proof")


def self_test() -> None:
    self_test_glyphs()
    for kind in ("sans", "serif", "mono", "override", "scale_10", "scale_100"):
        check((FIXTURES / f"{kind}.pdf").read_bytes(), kind)
    sans = (FIXTURES / "sans.pdf").read_bytes()
    bad = mutate(sans, b"+Inter-BoldItalic", b"+Inter-FakeItalic", occurrences=None)
    try:
        check(bad, "sans")
    except ValidationError:
        pass
    else:
        raise ValidationError("renamed combined-style mutation was accepted")
    try:
        check(sans, "serif")
    except ValidationError:
        pass
    else:
        raise ValidationError("wrong-family mutation was accepted")
    descriptor = re.search(rb"/ItalicAngle (-[0-9]+(?:\.[0-9]+)?)", flatten(sans))
    require(descriptor is not None, "italic fixture lacks a nonzero angle to mutate")
    bad_angle = mutate(sans, descriptor[0], b"/ItalicAngle 0", occurrences=None, scope="objects", first_only=True)
    try:
        check(bad_angle, "sans")
    except ValidationError:
        pass
    else:
        raise ValidationError("zeroed italic descriptor mutation was accepted")
    mono = (FIXTURES / "mono.pdf").read_bytes()
    mono_facts = FontFacts(mono, 1)
    descriptor_body = mono_facts.bodies[mono_facts.bundles[0].descriptor]
    flags = re.search(rb"/Flags ([0-9]+)", descriptor_body)
    require(flags is not None and int(flags[1]) & 1, "mono fixture lacks a FixedPitch flag to mutate")
    bad_fixed = mutate(mono, flags[0], f"/Flags {int(flags[1]) & ~1}".encode(),
                       occurrences=None, scope="objects", first_only=True)
    try:
        check(bad_fixed, "mono")
    except ValidationError:
        pass
    else:
        raise ValidationError("cleared fixed-pitch descriptor mutation was accepted")
    bad_serif = mutate(mono, flags[0], f"/Flags {int(flags[1]) | 2}".encode(),
                       occurrences=None, scope="objects", first_only=True)
    try:
        check(bad_serif, "mono")
    except ValidationError:
        pass
    else:
        raise ValidationError("invented Serif descriptor classification was accepted")
    print("PASS default font oracle mutation checks")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--pdf", type=Path)
    parser.add_argument("--kind", choices=("sans", "serif", "mono", "override", "scale_10", "scale_100", "gallery"))
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.pdf:
        check(args.pdf.read_bytes(), args.kind or args.pdf.stem)
    else:
        parser.error("--self-test or --pdf is required")


if __name__ == "__main__":
    main()
