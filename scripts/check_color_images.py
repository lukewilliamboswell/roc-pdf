#!/usr/bin/env python3
"""Independent structural checks for production-visual color and image leaf fixtures.

The checker parses the emitted bytes directly (no rewriting tool in front) and
proves the canonical leaf facts of the color-image slice:

- exactly one ICC profile stream exists per canonical profile and its payload
  is byte-identical to the vendored ``sRGB2014.icc`` asset (equality, not a
  digest comparison);
- exactly one color-space object exists per canonical space: the calibrated
  gray array carries the exact declared white point, and the ``/ICCBased``
  array references the canonical profile stream;
- exactly one image XObject exists per canonical image, its ``/ColorSpace``
  reference resolves to the canonical space object, its Flate payload decodes
  to the exact row-compacted pixels, the alpha plane emits as a ``/DeviceGray``
  soft mask, and the DCT payload is byte-identical to the sanitized JPEG;
- deduplicated authored twins resolve to one shared object from page and form
  dictionaries alike, while every stream's direct dictionary stays exact
  (reusing the production-visual form checker's used-equals-declared rule).
"""
from __future__ import annotations

import argparse
import hashlib
import re
import zlib
from pathlib import Path

from check_forms import FormFacts, check_ownership, replace_once
from check_pdf_structure import (
    ValidationError,
    dictionary_ref,
    indirect_length,
    object_slices,
    require,
    stream_parts,
    validate_pdf,
)

ROOT = Path(__file__).resolve().parents[1]
SHOWCASE_SNAPSHOT = ROOT / "tests" / "color_images" / "color_images.pdf"
DEDUP_8_SNAPSHOT = ROOT / "tests" / "color_images" / "color_images_dedup_8.pdf"
DEDUP_64_SNAPSHOT = ROOT / "tests" / "color_images" / "color_images_dedup_64.pdf"
DISTINCT_8_SNAPSHOT = ROOT / "tests" / "color_images" / "color_images_distinct_8.pdf"
DISTINCT_64_SNAPSHOT = ROOT / "tests" / "color_images" / "color_images_distinct_64.pdf"
NEGATIVE_SNAPSHOT = ROOT / "tests" / "color_images" / "color_images_negative.pdf"
SRGB_PROFILE = ROOT / "vendor" / "icc" / "sRGB2014.icc"
SRGB_SHA256 = "384b832de3412066743b52a75ee906b6fb9fb8d9e09e936fc2c43223815c6e0a"

RGB_PIXELS = bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255])
GRAY_PIXELS = bytes([0, 64, 128, 255])
ALPHA_PIXELS = bytes([255, 255, 0, 0])
CAL_GRAY_OBJECT = b"[/CalGray << /BlackPoint [0 0 0] /WhitePoint [0.95 1 1.089] >>]"


def showcase_jpeg() -> bytes:
    """The exact sanitized 1x1 three-component baseline JPEG the fixture embeds."""
    out = bytearray(b"\xff\xd8")
    out += b"\xff\xdb\x00\x43\x00" + bytes(64 * [1])
    out += bytes([0xFF, 0xC0, 0x00, 0x11, 8, 0, 1, 0, 1, 3, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0])
    counts = bytes([1] + 15 * [0])
    out += b"\xff\xc4\x00\x26" + bytes([0x00]) + counts + bytes([0]) + bytes([0x10]) + counts + bytes([0])
    out += bytes([0xFF, 0xDA, 0x00, 0x0C, 3, 1, 0x00, 2, 0x00, 3, 0x00, 0, 0x3F, 0])
    out += bytes([0x00])
    out += b"\xff\xd9"
    return bytes(out)


def raw_stream(bodies: dict[int, bytes], number: int) -> tuple[bytes, bytes]:
    body = bodies[number]
    marker = body.find(b"stream\n")
    require(marker >= 0, f"object {number} is not a stream")
    dictionary = body[:marker]
    length = indirect_length(bodies, dictionary_ref(dictionary, b"Length"))
    _, encoded = stream_parts(body, length)
    return dictionary, encoded


def flate_payload(bodies: dict[int, bytes], number: int) -> bytes:
    dictionary, encoded = raw_stream(bodies, number)
    require(b"/Filter /FlateDecode" in dictionary, f"object {number} is not FlateDecode")
    try:
        return zlib.decompress(encoded)
    except zlib.error as error:
        raise ValidationError(f"object {number} has invalid zlib DEFLATE: {error}") from error


class LeafFacts:
    """Canonical leaf objects of one fixture: profiles, spaces, and images."""

    def __init__(self, pdf: bytes) -> None:
        _, self.bodies = object_slices(pdf)

        self.profiles: dict[int, bytes] = {}
        for number, body in self.bodies.items():
            marker = body.find(b"stream\n")
            if marker < 0:
                continue
            dictionary = body[:marker]
            if b"/N 3" in dictionary and b"/Subtype" not in dictionary and b"/Filter" not in dictionary:
                _, encoded = raw_stream(self.bodies, number)
                self.profiles[number] = encoded

        self.cal_gray_spaces = {
            number for number, body in self.bodies.items() if body.strip().startswith(b"[/CalGray")
        }
        self.icc_spaces: dict[int, int] = {}
        for number, body in self.bodies.items():
            match = re.match(rb"\[/ICCBased ([1-9][0-9]*) 0 R\]", body.strip())
            if match is not None:
                self.icc_spaces[number] = int(match.group(1))

        self.images: dict[int, bytes] = {}
        self.soft_masks: dict[int, bytes] = {}
        for number, body in self.bodies.items():
            marker = body.find(b"stream\n")
            if marker < 0:
                continue
            dictionary = body[:marker]
            if b"/Subtype /Image" not in dictionary:
                continue
            require(
                b"/BitsPerComponent 8" in dictionary,
                f"image {number}: bit depth is not the declared 8 bits per component",
            )
            if b"/ColorSpace /DeviceGray" in dictionary:
                self.soft_masks[number] = dictionary
            else:
                self.images[number] = dictionary

    def check_profiles(self, expected: int) -> None:
        require(
            len(self.profiles) == expected,
            f"expected {expected} canonical ICC profile streams, found {len(self.profiles)}",
        )
        vendored = SRGB_PROFILE.read_bytes()
        require(
            hashlib.sha256(vendored).hexdigest() == SRGB_SHA256,
            "vendored sRGB2014.icc does not match its pinned digest",
        )
        for number, payload in self.profiles.items():
            require(
                payload == vendored,
                f"profile stream {number} is not byte-identical to the vendored sRGB2014.icc",
            )

    def check_image_color_targets(self) -> None:
        canonical_spaces = self.cal_gray_spaces | set(self.icc_spaces)
        for number, dictionary in self.images.items():
            target = dictionary_ref(dictionary, b"ColorSpace")
            require(
                target in canonical_spaces,
                f"image {number}: /ColorSpace does not reference a canonical color-space object",
            )
        for number, target in self.icc_spaces.items():
            require(
                target in self.profiles,
                f"color space {number}: /ICCBased does not reference the canonical profile stream",
            )


def validate_color_image_showcase(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = FormFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.page_contents[page], True)
    leaves = LeafFacts(pdf)

    ## Canonical counts: authored twins may never emit twin objects.
    leaves.check_profiles(dimensions["canonical_profiles"])
    require(
        len(leaves.cal_gray_spaces) + len(leaves.icc_spaces) == dimensions["canonical_color_spaces"],
        "canonical color-space object count mismatch",
    )
    require(len(leaves.cal_gray_spaces) == 1, "the duplicated calibrated-gray declarations must share one object")
    require(len(leaves.icc_spaces) == 1, "Srgb and the equivalent IccBased declaration must share one object")
    require(
        len(leaves.images) == dimensions["canonical_images"],
        f"expected {dimensions['canonical_images']} canonical images, found {len(leaves.images)}",
    )
    require(len(leaves.soft_masks) == 1, "the gray-plus-alpha image must emit exactly one soft mask")
    leaves.check_image_color_targets()

    cal_gray = next(iter(leaves.cal_gray_spaces))
    require(
        leaves.bodies[cal_gray].strip().startswith(CAL_GRAY_OBJECT),
        "calibrated-gray object does not carry the exact declared white point",
    )

    ## The alpha imagery makes this a transparency page, so it must carry the
    ## transparency group naming the canonical ICCBased sRGB blending space.
    group = re.search(rb"/Group << /CS ([1-9][0-9]*) 0 R /S /Transparency >>", facts.bodies[page])
    require(group is not None, "transparency page lost its /Group dictionary")
    require(int(group.group(1)) in leaves.icc_spaces, "page /Group /CS is not the canonical ICCBased space")

    ## Classify the three canonical images by their exact payloads.
    icc_space = next(iter(leaves.icc_spaces))
    rgb_image = gray_image = dct_image = None
    for number, dictionary in leaves.images.items():
        if b"/Filter /DCTDecode" in dictionary:
            _, encoded = raw_stream(leaves.bodies, number)
            require(encoded == showcase_jpeg(), f"image {number}: DCT payload is not the sanitized JPEG")
            require(dictionary_ref(dictionary, b"ColorSpace") == icc_space, "JPEG image lost its ICCBased space")
            dct_image = number
        elif b"/SMask" in dictionary:
            require(flate_payload(leaves.bodies, number) == GRAY_PIXELS, f"image {number}: gray plane mismatch")
            mask = dictionary_ref(dictionary, b"SMask")
            require(mask in leaves.soft_masks, f"image {number}: /SMask does not reference the soft mask")
            require(flate_payload(leaves.bodies, mask) == ALPHA_PIXELS, "soft mask alpha plane mismatch")
            gray_image = number
        else:
            require(flate_payload(leaves.bodies, number) == RGB_PIXELS, f"image {number}: RGB plane mismatch")
            require(dictionary_ref(dictionary, b"ColorSpace") == icc_space, "RGB image lost its ICCBased space")
            rgb_image = number
    require(None not in (rgb_image, gray_image, dct_image), "showcase image classification incomplete")

    ## The padded authored twin resolved to the compact twin's object: the
    ## form's image entry and the page's RGB image entry share one target.
    form = next(iter(facts.forms))
    form_images = {target for name, target in facts.form_resources[form].items() if name.startswith("Im")}
    require(form_images == {rgb_image}, "the form must reference exactly the deduplicated RGB image")
    page_images = {target for name, target in facts.page_resources[page].items() if name.startswith("Im")}
    require(page_images == {rgb_image, gray_image, dct_image}, "page dictionary must carry exactly the canonical images")

    ## The duplicated gray-plus-alpha twin paints twice through one name.
    content = facts.page_contents[page]
    gray_name = next(
        name for name, target in facts.page_resources[page].items() if target == gray_image
    )
    gray_uses = len(re.findall(rb"/" + gray_name.encode("ascii") + rb" Do", content))
    require(gray_uses == 2, "the duplicated gray image must paint twice through one canonical name")

    ## The form fills in the ICCBased space the page also uses through the
    ## deduplicated twin declaration.
    form_spaces = {target for name, target in facts.form_resources[form].items() if name.startswith("CS")}
    require(form_spaces == {icc_space}, "the form must name exactly the ICCBased space")

    ## Placement-site ownership: three meaningful placements, logical order
    ## differing from paint order.
    check_ownership(facts, page, 3)
    catalog = next(number for number, body in facts.bodies.items() if b"/Type /Catalog" in body)
    structure_root = dictionary_ref(facts.bodies[catalog], b"StructTreeRoot")
    document = dictionary_ref(facts.bodies[structure_root], b"K")
    document_k = re.search(rb"/K \[([^]]*)\]", facts.bodies[document])
    require(document_k is not None, "document /K missing")
    children = [int(match.group(1)) for match in re.finditer(rb"([1-9][0-9]*) 0 R", document_k.group(1))]
    require(len(children) == 3, "document does not hold the three paragraphs")
    first_child_mcids = [int(m.group(1)) for m in re.finditer(rb"<< /MCID ([0-9]+) /Pg", facts.bodies[children[0]])]
    require(first_child_mcids == [1], "logical reading order does not lead with the second painted paragraph")


def validate_color_image_grid(pdf: bytes, dimensions: dict[str, int]) -> None:
    facts = FormFacts(pdf, dimensions.get("pages", 1))
    page = facts.pages[0]
    validate_pdf(pdf, dimensions.get("pages", 1), facts.page_contents[page], True)
    leaves = LeafFacts(pdf)
    placements = dimensions["image_placements"]
    canonical = dimensions["canonical_images"]

    require(len(leaves.profiles) == 0, "grid fixtures embed no ICC profile")
    require(len(leaves.images) == canonical, f"expected {canonical} canonical images, found {len(leaves.images)}")
    require(not leaves.soft_masks, "grid fixtures carry no soft mask")
    leaves.check_image_color_targets()

    content = facts.page_contents[page]
    invocations = re.findall(rb"/([A-Za-z0-9_]+) Do", content)
    require(
        len(invocations) == placements,
        f"expected {placements} image placements, found {len(invocations)}",
    )
    used_targets = {facts.page_resources[page][name.decode("ascii")] for name in set(invocations)}
    require(
        used_targets == set(leaves.images),
        "painted image names do not resolve to exactly the canonical image objects",
    )
    payloads = {number: flate_payload(leaves.bodies, number) for number in leaves.images}
    require(
        len(set(payloads.values())) == canonical,
        "canonical images are not byte-distinct; a duplicate escaped deduplication",
    )
    for number, payload in payloads.items():
        require(len(payload) == 4 and payload[1:] == GRAY_PIXELS[1:], f"image {number}: unexpected plane bytes")


def validate_color_images_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    if dimensions.get("color_image_showcase"):
        validate_color_image_showcase(pdf, dimensions)
    elif dimensions.get("color_image_distinct") or dimensions.get("color_image_dedup"):
        validate_color_image_grid(pdf, dimensions)
    else:
        raise ValidationError("unknown production-visual color-image fixture dimensions")


SHOWCASE_DIMENSIONS = {
    "pages": 1,
    "color_image_showcase": 1,
    "authored_profiles": 2,
    "canonical_profiles": 1,
    "authored_color_spaces": 4,
    "canonical_color_spaces": 2,
    "authored_images": 5,
    "canonical_images": 3,
}


def self_test() -> None:
    showcase = SHOWCASE_SNAPSHOT.read_bytes()
    validate_color_image_showcase(showcase, SHOWCASE_DIMENSIONS)
    validate_color_image_grid(
        DEDUP_8_SNAPSHOT.read_bytes(),
        {"pages": 1, "color_image_dedup": 1, "image_placements": 8, "canonical_images": 1},
    )
    validate_color_image_grid(
        DEDUP_64_SNAPSHOT.read_bytes(),
        {"pages": 1, "color_image_dedup": 1, "image_placements": 64, "canonical_images": 1},
    )
    validate_color_image_grid(
        DISTINCT_8_SNAPSHOT.read_bytes(),
        {"pages": 1, "color_image_distinct": 1, "image_placements": 8, "canonical_images": 8},
    )
    validate_color_image_grid(
        DISTINCT_64_SNAPSHOT.read_bytes(),
        {"pages": 1, "color_image_distinct": 1, "image_placements": 64, "canonical_images": 64},
    )
    validate_color_image_grid(
        NEGATIVE_SNAPSHOT.read_bytes(),
        {"pages": 1, "color_image_dedup": 1, "image_placements": 1, "canonical_images": 1},
    )

    ## Length-preserving mutation twins: each must be rejected.
    vendored = SRGB_PROFILE.read_bytes()
    profile_prefix = vendored[:64]
    offset = showcase.find(profile_prefix)
    require(offset >= 0, "self-test fixture does not embed the vendored profile bytes")
    flipped_profile = (
        showcase[: offset + 40] + bytes([showcase[offset + 40] ^ 0x01]) + showcase[offset + 41 :]
    )
    require(len(flipped_profile) == len(showcase), "profile mutation changed the byte length")

    mutations = (
        ("profile payload", flipped_profile),
        ("profile component count", replace_once(showcase, b"/N 3", b"/N 4")),
        ("calibrated white point", replace_once(showcase, b"/WhitePoint [0.95 1 1.089]", b"/WhitePoint [0.94 1 1.089]")),
        ("image bit depth", replace_once(showcase, b"/BitsPerComponent 8", b"/BitsPerComponent 9")),
    )
    for label, mutation in mutations:
        try:
            validate_color_image_showcase(mutation, SHOWCASE_DIMENSIONS)
        except ValidationError:
            continue
        raise SystemExit(f"production-visual color-image checker accepted mutated {label}")
    print("PASS production-visual color-image structural checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path, default=SHOWCASE_SNAPSHOT)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    validate_color_image_showcase(args.pdf.read_bytes(), SHOWCASE_DIMENSIONS)
    print(f"PASS production-visual color-image structural check: {args.pdf}")


if __name__ == "__main__":
    main()
