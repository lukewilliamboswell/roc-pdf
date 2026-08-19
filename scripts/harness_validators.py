from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

from check_actual_text import EXPECTED_CONTENT as ACTUAL_TEXT_CONTENT
from check_actual_text import validate_actual_text_pdf
from check_caller_facade import validate_caller_facade_pdf
from check_caller_text import validate_caller_text_pdf
from check_case_text import validate_case_pdf
from check_cjk_text import EXPECTED_CONTENT as CJK_TEXT_CONTENT
from check_cjk_text import validate_cjk_text_pdf
from check_color_images import validate_color_images_pdf
from check_combining import validate_combining_pdf
from check_external_discretionary_hyphen import (
    EXPECTED_CONTENT as EXTERNAL_DISCRETIONARY_HYPHEN_CONTENT,
)
from check_external_discretionary_hyphen import validate_external_discretionary_hyphen_pdf
from check_facade_output import fixture_oracle, validate_facade_output_pdf
from check_fonts import validate_fonts_pdf
from check_forms import validate_forms_pdf
from check_generated_labels import validate_generated_labels_pdf
from check_ligature import EXPECTED_CONTENT as LIGATURE_CONTENT
from check_ligature import validate_ligature_pdf
from check_metadata import validate_metadata_pdf
from check_multiface_facade import validate_multiface_facade_pdf
from check_multiface_text import validate_multiface_text_pdf
from check_navigation import validate_navigation_pdf
from check_pdf_structure import validate_pdf
from check_rtl import validate_rtl_pdf
from check_shadings import validate_shadings_pdf
from check_soft_hyphen import EXPECTED_CONTENT as SOFT_HYPHEN_CONTENT
from check_soft_hyphen import validate_soft_hyphen_pdf
from check_soft_masks import validate_soft_masks_pdf
from check_supplementary_text import EXPECTED_CONTENT as SUPPLEMENTARY_TEXT_CONTENT
from check_supplementary_text import validate_supplementary_text_pdf
from check_tagged_visual import validate_tagged_visual_pdf
from check_text import EXPECTED_CONTENT as TEXT_CONTENT
from check_text import validate_text_pdf
from check_transparency import validate_transparency_pdf


Reporter = Callable[[str], None]
Validator = Callable[[bytes, dict[str, int], Reporter], None]


MINIMAL_CONTENT = (
    b"/P <</MCID 0>> BDC\n/CS1_0 cs\n0.50000763 scn\n0 0 1 1 re\nf\n"
    b"EMC\n/Artifact <</Type /Background>> BDC\nq\n1 0 0 1 2 3 cm\nq\n"
    b"2 0 0 1 4 5 cm\n/Im1_0 Do\nQ\nQ\nEMC\n"
)


def _pattern_content(dimensions: dict[str, int]) -> bytes:
    length = dimensions.get("content_stream_bytes", 0)
    period = dimensions.get("content_pattern_period")
    if length == 0 and period is None:
        return b""
    if period != 4:
        raise SystemExit("content_stream_bytes requires the versioned four-byte q/Q pattern")
    pattern = b"q Q\n"
    return (pattern * ((length + len(pattern) - 1) // len(pattern)))[:length]


def _simple(function: Callable[[bytes], None], message: str) -> Validator:
    def validate(data: bytes, _dimensions: dict[str, int], report: Reporter) -> None:
        function(data)
        report(message)

    return validate


def _dimensioned(function: Callable[[bytes, dict[str, int]], None], message: str) -> Validator:
    def validate(data: bytes, dimensions: dict[str, int], report: Reporter) -> None:
        function(data, dimensions)
        report(message)

    return validate


def _pdf_structure_with(content: bytes | None) -> Validator:
    def validate(data: bytes, dimensions: dict[str, int], report: Reporter) -> None:
        pages = dimensions.get("pages")
        if pages is None:
            raise SystemExit("PDF structure validators require dimensions.pages")
        expected = _pattern_content(dimensions) if content is None else content
        validate_pdf(
            data,
            pages,
            expected,
            dimensions.get("normalized_plan_identity", 0) == 1,
        )
        report("independent offsets, lengths, xref, and page facts")

    return validate


def _facade_output(data: bytes, _dimensions: dict[str, int], report: Reporter) -> None:
    expected_text, _ = fixture_oracle()
    validate_facade_output_pdf(data, expected_text)
    report("independent offsets, lengths, xref, page, authored facade paragraph, Type 0 font, CID, and Unicode mapping facts")


VALIDATORS: dict[str, Validator] = {
    "pdf_structure": _pdf_structure_with(None),
    "pdf_structure_text": _pdf_structure_with(TEXT_CONTENT),
    "pdf_structure_actual_text": _pdf_structure_with(ACTUAL_TEXT_CONTENT),
    "pdf_structure_cjk_text": _pdf_structure_with(CJK_TEXT_CONTENT),
    "pdf_structure_ligature_text": _pdf_structure_with(LIGATURE_CONTENT),
    "pdf_structure_supplementary_text": _pdf_structure_with(SUPPLEMENTARY_TEXT_CONTENT),
    "pdf_structure_soft_hyphen": _pdf_structure_with(SOFT_HYPHEN_CONTENT),
    "pdf_structure_external_discretionary_hyphen": _pdf_structure_with(EXTERNAL_DISCRETIONARY_HYPHEN_CONTENT),
    "pdf_structure_minimal_content": _pdf_structure_with(MINIMAL_CONTENT),
    "facade_output": _facade_output,
    "multiface_text": _simple(validate_multiface_text_pdf, "exact selected Latin/CJK Type 0 resources, CID maps, and Unicode mappings"),
    "generated_label": _simple(validate_generated_labels_pdf, "independent offsets, lengths, xref, typed list ownership, labels, Type 0 font, CID, and Unicode mapping facts"),
    "combining_text": _simple(validate_combining_pdf, "exact decomposed combining CID and two-scalar ToUnicode facts"),
    "case_text": _simple(validate_case_pdf, "resolved case presentation, logical ActualText, CID, and Unicode mapping facts"),
    "rtl_text": _simple(validate_rtl_pdf, "resolved visual order, mirrored presentation, logical ActualText, CID, and Unicode mapping facts"),
    "multiface_facade": _simple(validate_multiface_facade_pdf, "independent offsets, lengths, xref, dense two-font resources, visual-order paint segments, CID, and per-font Unicode mapping facts"),
    "caller_facade": _simple(validate_caller_facade_pdf, "independent offsets, lengths, xref, public caller source identity, three placements, Type 0 font, CID, and Unicode mapping facts"),
    "fonts": _dimensioned(validate_fonts_pdf, "canonical Type 0 bundles, verified embedded subsets, identity CID maps, ToUnicode facts, exact per-stream /Font dictionaries, and placement-site ownership"),
    "forms": _dimensioned(validate_forms_pdf, "exact Form XObject dictionaries, per-stream direct resources, Do resolution, sharing, and placement-site MCID/ParentTree ownership facts"),
    "color_images": _dimensioned(validate_color_images_pdf, "canonical ICC/color-space/image objects, exact leaf payload equality, soft-mask wiring, and deduplicated direct dictionaries"),
    "transparency": _dimensioned(validate_transparency_pdf, "canonical ExtGState objects, exact per-stream /ExtGState dictionaries, balanced opacity groups, transparency-group and blending-space wiring, and placement-site ownership facts"),
    "soft_masks": _dimensioned(validate_soft_masks_pdf, "canonical Alpha mask states, direct /SMask /G wiring to isolated mask forms outside every resource dictionary, balanced mask groups, and placement-site ownership facts"),
    "shadings": _dimensioned(validate_shadings_pdf, "canonical shading/function/pattern objects, exact per-stream /Shading and /Pattern dictionaries, re-derived stop models, ownership-neutral pattern streams, and sh/scn operand resolution"),
    "navigation": _dimensioned(validate_navigation_pdf, "paired /SD + /D actions, keyboard-ordered /Annots, OBJR/ParentTree linkage, named destinations, outline preorder, page labels, and appearance geometry verified structurally"),
    "metadata": _dimensioned(validate_metadata_pdf, "catalog /Lang, canonical XMP metadata stream, GTS_PDFA1 output intent, and the single shared sRGB2014 profile stream verified structurally"),
    "tagged_visual": _simple(validate_tagged_visual_pdf, "exact normalized tagged structure and resources"),
    "visible_text": _simple(validate_text_pdf, "exact font, CID, Unicode mapping, and visible text facts"),
    "caller_text": _simple(validate_caller_text_pdf, "exact caller font identity, CID, Unicode mapping, and visible text facts"),
    "actual_text": _simple(validate_actual_text_pdf, "exact visual reordering and logical ActualText facts"),
    "supplementary_text": _simple(validate_supplementary_text_pdf, "exact supplementary-plane UTF-16BE, CID, Unicode mapping, and sanitized subset facts"),
    "cjk_text": _simple(validate_cjk_text_pdf, "exact CJK CID widths, Unicode mapping, and sanitized subset facts"),
    "ligature_text": _simple(validate_ligature_pdf, "parsed GSUB fact, ligature CID, ActualText, Unicode mapping, and sanitized subset facts"),
    "soft_hyphen": _simple(validate_soft_hyphen_pdf, "explicit U+00AD source, selected presentation, ActualText, CID, and subset facts"),
    "external_discretionary_hyphen": _simple(validate_external_discretionary_hyphen_pdf, "external zero-width source boundary, selected visible hyphen, ActualText, CID, and subset facts"),
}


@dataclass(frozen=True)
class PreflightCheck:
    script: str
    skip_on_snapshot_update: bool = False


PREFLIGHT_CHECKS: dict[str, PreflightCheck] = {
    name.removeprefix("check_").removesuffix(".py"): PreflightCheck(name)
    for name in (
        "check_arlington.py", "check_pdfbox.py", "check_tagged_visual.py", "check_visual_renderers.py",
        "check_text.py", "check_caller_text.py", "check_caller_facade.py", "check_facade_output.py",
        "check_generated_labels.py", "check_actual_text.py", "check_supplementary_text.py", "check_cjk_text.py",
        "check_ligature.py", "check_multiface_facade.py", "check_case_text.py", "check_combining.py",
        "check_rtl.py", "check_multiface_text.py", "check_soft_hyphen.py", "check_external_discretionary_hyphen.py",
        "check_text_renderers.py", "check_forms.py", "check_form_renderers.py", "check_color_images.py",
        "check_color_image_renderers.py", "check_transparency.py", "check_transparency_renderers.py",
        "check_soft_masks.py", "check_soft_mask_renderers.py", "check_shadings.py", "check_shading_renderers.py",
        "check_fonts.py", "check_font_renderers.py", "check_metadata.py", "check_metadata_renderers.py",
        "check_navigation.py", "check_navigation_renderers.py",
    )
}
PREFLIGHT_CHECKS["contracts"] = PreflightCheck("check_contracts.py", True)
PREFLIGHT_CHECKS["pdf_structure"] = PreflightCheck("check_pdf_structure.py", True)


def validate_registry_ids(validators: tuple[str, ...], field: str) -> None:
    if len(validators) != len(set(validators)):
        raise SystemExit(f"{field}: validators must be unique")
    unknown = set(validators) - VALIDATORS.keys()
    if unknown:
        raise SystemExit(f"{field}: unknown validator(s): {', '.join(sorted(unknown))}")


def validate_preflight_ids(checks: tuple[str, ...], field: str) -> None:
    if not checks or len(checks) != len(set(checks)):
        raise SystemExit(f"{field}: preflight checks must be non-empty and unique")
    unknown = set(checks) - PREFLIGHT_CHECKS.keys()
    if unknown:
        raise SystemExit(f"{field}: unknown preflight check(s): {', '.join(sorted(unknown))}")


def run_validators(
    validator_ids: tuple[str, ...], data: bytes, dimensions: dict[str, int], report: Reporter
) -> None:
    for validator_id in validator_ids:
        VALIDATORS[validator_id](data, dimensions, report)
