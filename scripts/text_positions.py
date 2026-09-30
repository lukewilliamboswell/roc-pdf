#!/usr/bin/env python3
"""Independent model of the package's glyph-run text encoding.

The package writes each baseline segment of a prepared glyph run as one
`Td` (relative to the previous segment start, omitted when zero) followed by
one `TJ` array. Inside the array every glyph after the first carries the
adjustment that returns the pen to the glyph's exact layout position, rounded
to the nearest 1/ADJUSTMENT_SCALE of a thousandth of text space, with the
rounding error carried forward so it never accumulates.

This module re-derives that encoding from explicit glyph positions, so
checkers keep their authored per-glyph positions as the expectation, and it
interprets `Td`/`Tm`/`Tj`/`TJ` text objects back into glyph positions. Both
use exact rational arithmetic in thousandths of a point ("raw" layout units),
never floating point.
"""
from __future__ import annotations

import re
from fractions import Fraction

# TJ adjustment steps per thousandth of text space: 10 ** the package's
# `KernelPdfText.adjustment_digits`.
ADJUSTMENT_SCALE = 10

LEGACY_GLYPH = re.compile(rb"1 0 0 1 (-?[0-9.]+) (-?[0-9.]+) Tm\n<([0-9A-F]{4})> Tj\n")
FONT_SELECTION = re.compile(rb"/([A-Za-z0-9_]+) ([0-9.]+) Tf\n")


def raw(text: bytes | str) -> int:
    """Thousandths of a point from a canonical decimal."""
    value = Fraction(text.decode() if isinstance(text, bytes) else text)
    scaled = value * 1000
    if scaled.denominator != 1:
        raise ValueError(f"{text!r} is not a whole number of thousandths")
    return int(scaled)


def decimal(value: Fraction | int) -> bytes:
    """Canonical PDF decimal: no exponent, no trailing zeros, no -0."""
    value = Fraction(value)
    if value == 0:
        return b"0"
    sign = "-" if value < 0 else ""
    value = abs(value)
    whole = value.numerator // value.denominator
    fraction = value - whole
    digits = ""
    while fraction and len(digits) < 12:
        fraction *= 10
        digit = fraction.numerator // fraction.denominator
        digits += str(digit)
        fraction -= digit
    if fraction:
        raise ValueError(f"{value} has no short decimal form")
    text = f"{sign}{whole}" + (f".{digits}" if digits else "")
    return text.encode()


def round_half_up(numerator: int, denominator: int) -> int:
    """floor(numerator / denominator + 1/2) for a positive denominator."""
    return (2 * numerator + denominator) // (2 * denominator)


def encode_segment_glyphs(glyphs: list[tuple[int, int, int]], widths: dict[int, int], size: int) -> bytes:
    """Encode glyphs [(x_raw, y_raw, cid)] of one run, positions relative to the
    run origin, as `Td` + `TJ` segments. ``size`` is the font size in raw units
    and ``widths`` the emitted /W value (thousandths of an em) per CID."""
    out = bytearray()
    segment_x = segment_y = 0
    pen = 0
    previous_cid: int | None = None
    open_array = False
    for x, y, cid in glyphs:
        if not open_array or y != segment_y:
            if open_array:
                out += b">] TJ\n"
            dx, dy = x - segment_x, y - segment_y
            if dx or dy:
                out += decimal(Fraction(dx, 1000)) + b" " + decimal(Fraction(dy, 1000)) + b" Td\n"
            segment_x, segment_y = x, y
            out += b"[<"
            open_array = True
            pen = 0
        else:
            nominal = pen + widths[previous_cid] * ADJUSTMENT_SCALE * size
            target = (x - segment_x) * 1000 * ADJUSTMENT_SCALE
            steps = round_half_up(nominal - target, size)
            pen = nominal - steps * size
            if steps:
                out += b"> " + decimal(Fraction(steps, ADJUSTMENT_SCALE)) + b" <"
        out += f"{cid:04X}".encode()
        previous_cid = cid
    if open_array:
        out += b">] TJ\n"
    return bytes(out)


def legacy_to_tj(content: bytes, widths_by_font: dict[bytes, dict[int, int]]) -> bytes:
    """Rewrite every legacy `1 0 0 1 x y Tm` / `<cid> Tj` glyph sequence that
    follows a `Tf` into the segment encoding. ``widths_by_font`` maps a font
    resource name to its CID widths."""
    out = bytearray()
    position = 0
    for selection in FONT_SELECTION.finditer(content):
        start = selection.end()
        glyphs = []
        cursor = start
        while True:
            match = LEGACY_GLYPH.match(content, cursor)
            if match is None:
                break
            glyphs.append((raw(match.group(1)), raw(match.group(2)), int(match.group(3), 16)))
            cursor = match.end()
        if not glyphs:
            continue
        out += content[position:start]
        out += encode_segment_glyphs(glyphs, widths_by_font[selection.group(1)], raw(selection.group(2)))
        position = cursor
    out += content[position:]
    return bytes(out)


TOKEN = re.compile(rb"\[|\]|<[0-9A-Fa-f]*>|/[^\s/<>\[\]()]+|-?[0-9]*\.?[0-9]+|[A-Za-z'\"*]+")


def glyph_positions(content: bytes, widths_by_font: dict[bytes, dict[int, int]]) -> list[tuple[bytes, int, Fraction, Fraction]]:
    """Text-space glyph origins [(font, cid, x_raw, y_raw)] of every shown
    glyph, from `Tf`, `Td`, `Tm`, `Tj`, and `TJ` inside `BT`/`ET` (the text
    matrix is assumed to be a pure translation, as the package writes it)."""
    positions: list[tuple[bytes, int, Fraction, Fraction]] = []
    operands: list[object] = []
    array: list[object] | None = None
    font = b""
    size = Fraction(0)
    line = [Fraction(0), Fraction(0)]
    pen = [Fraction(0), Fraction(0)]

    def show(string: bytes) -> None:
        data = bytes.fromhex(string.decode())
        for index in range(0, len(data), 2):
            cid = int.from_bytes(data[index : index + 2], "big")
            positions.append((font, cid, pen[0], pen[1]))
            pen[0] += Fraction(widths_by_font[font][cid] * size, 1000)

    for token in TOKEN.findall(content):
        if token == b"[":
            array = []
        elif token == b"]":
            operands.append(array)
            array = None
        elif token.startswith(b"<"):
            (array if array is not None else operands).append(token[1:-1])
        elif token.startswith(b"/"):
            operands.append(token[1:])
        elif re.fullmatch(rb"-?[0-9]*\.?[0-9]+", token):
            (array if array is not None else operands).append(Fraction(token.decode()) * 1000)
        else:
            if token == b"BT":
                line = [Fraction(0), Fraction(0)]
                pen = [Fraction(0), Fraction(0)]
            elif token == b"Tf":
                font, size = operands[-2], operands[-1]
            elif token == b"Td":
                line = [line[0] + operands[-2], line[1] + operands[-1]]
                pen = list(line)
            elif token == b"Tm":
                line = [operands[-2], operands[-1]]
                pen = list(line)
            elif token == b"Tj":
                show(operands[-1])
            elif token == b"TJ":
                for item in operands[-1]:
                    if isinstance(item, bytes):
                        show(item)
                    else:
                        # item is n * 1000 (a raw-unit scaled number)
                        pen[0] -= item / 1000 * size / 1000
            operands = []
    return positions


SHOW_STRING = re.compile(rb"<([0-9A-Fa-f]*)>(?= Tj\n)|\[((?:<[0-9A-Fa-f]*>|-?[0-9.]+| )*)\] TJ\n")


def shown_strings(content: bytes) -> list[bytes]:
    """Every hex string shown by a `Tj` or inside a `TJ` array, in order."""
    strings: list[bytes] = []
    for match in SHOW_STRING.finditer(content):
        if match.group(1) is not None:
            strings.append(match.group(1))
        else:
            strings.extend(re.findall(rb"<([0-9A-Fa-f]*)>", match.group(2)))
    return strings


def shown_cids(content: bytes) -> list[int]:
    """Every two-byte CID shown by `Tj` or `TJ`, in content order."""
    cids: list[int] = []
    for string in shown_strings(content):
        if len(string) % 4:
            raise ValueError(f"shown string {string!r} is not whole two-byte CIDs")
        cids.extend(int(string[index : index + 4], 16) for index in range(0, len(string), 4))
    return cids
