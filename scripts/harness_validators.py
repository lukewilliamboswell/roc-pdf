from __future__ import annotations

import re
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from check_fillable_forms import validate_fillable_pdf
from check_footnotes import validate_footnotes_pdf
from check_associated_files import validate_associated_files_pdf
from check_anchored_figure import validate_anchored_figure_pdf
from check_profile_declarations import validate_claims
from check_default_fonts import validate_default_fonts_pdf
from check_contents_entries import validate_contents_entries_pdf
from check_destination_references import validate_destination_references_pdf
from check_chapter_templates import validate_chapter_templates_pdf
from check_vector_diagrams import validate_vector_diagrams_pdf
from check_fixed_pages import validate_fixed_pages_pdf
from check_gallery_features import ARTIFACT, tagged
from check_designed_brief import validate_designed_brief_pdf
from check_generated_handbook import validate_flow_fixture, validate_generated_fixture, validate_index_fixture
from check_arabic_invoice import check as check_arabic_invoice
from check_hindi_statement import check as check_hindi_statement
from check_thai_notice import check as check_thai_notice, check_scale as check_thai_scale
from check_bibliography import check as check_bibliography
from check_bilingual_invoice import check as check_bilingual_invoice
from check_inter_latin import validate_inter_latin_pdf
from check_columns import validate_columns_pdf
from check_actual_text import EXPECTED_CONTENT as ACTUAL_TEXT_CONTENT
from check_actual_text import validate_actual_text_pdf
from check_caller_facade import validate_caller_facade_pdf, validate_unhinted_caller_pdf
from check_link_underlines import validate_link_underlines_pdf
from check_drawing_labels import validate_drawing_label_faces_pdf, validate_drawing_labels_pdf, validate_furniture_typography_pdf
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
from check_pdfa4_structure import validate_pdfa4_pdf, validate_standard_twin_pdf
from check_multiface_facade import validate_multiface_facade_pdf
from check_multiface_text import validate_multiface_text_pdf
from check_navigation import validate_navigation_pdf
from check_page_labels import validate_page_labels_pdf
from check_pdf_structure import canonical_text, dictionary_ref, indirect_length, is_structure_element, object_slices, require, stream_parts, structure_kids, validate_pdf
from check_rich_inline import validate_rich_inline_pdf
from check_rich_flow import MARKED, validate_rich_flow_pdf
from check_table_paint_frames import validate_table_paint_frames_pdf
from check_table_spans import validate_table_spans
from check_technical_manual import validate_technical_manual_pdf
from check_source_foregrounds import validate_source_foregrounds_pdf
from check_source_blocks import validate_source_blocks_pdf, validate_multiple_sources_pdf
from check_rtl import validate_rtl_pdf
from check_shadings import validate_shadings_pdf
from check_soft_hyphen import EXPECTED_CONTENT as SOFT_HYPHEN_CONTENT
from check_soft_hyphen import validate_soft_hyphen_pdf
from check_soft_masks import validate_soft_masks_pdf
from check_structure_semantics import Document, Ref, text_string, validate_structure_semantics_pdf
from check_supplementary_text import EXPECTED_CONTENT as SUPPLEMENTARY_TEXT_CONTENT
from check_supplementary_text import validate_supplementary_text_pdf
from check_tagged_visual import validate_tagged_visual_pdf
from check_text import EXPECTED_CONTENT as TEXT_CONTENT
from check_text import decoded_stream, only_object, validate_text_pdf
from check_transparency import validate_transparency_pdf


# Claim IDs select project-owned output checks and label local oracle inputs.
PROFILE_VALIDATORS = {"pdfua2": "pdfa4", "wtpdf_accessibility": "pdfua2"}


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


def _facade_image(data: bytes, dimensions: dict[str, int], report: Reporter) -> None:
    _, bodies = object_slices(data)
    page = only_object(bodies, b"/Type /Page ", "page")
    _, content = decoded_stream(bodies, dictionary_ref(bodies[page], b"Contents"))
    validate_pdf(data, dimensions["pages"], content, normalized_plan_identity=True)

    image = only_object(bodies, b"/Subtype /Image ", "image")
    image_dictionary, pixels = decoded_stream(bodies, image)
    require(b"/BitsPerComponent 8" in image_dictionary, "facade image is not eight-bit")
    require(b"/Width 8" in image_dictionary and b"/Height 4" in image_dictionary, "facade image dimensions changed")
    expected_pixels = bytes([
        20, 90, 140, 20, 90, 140, 240, 180, 40, 240, 180, 40, 40, 160, 90, 40, 160, 90, 245, 245, 240, 245, 245, 240,
        20, 90, 140, 20, 90, 140, 240, 180, 40, 240, 180, 40, 40, 160, 90, 40, 160, 90, 245, 245, 240, 245, 245, 240,
        245, 245, 240, 245, 245, 240, 40, 160, 90, 40, 160, 90, 240, 180, 40, 240, 180, 40, 20, 90, 140, 20, 90, 140,
        245, 245, 240, 245, 245, 240, 40, 160, 90, 40, 160, 90, 240, 180, 40, 240, 180, 40, 20, 90, 140, 20, 90, 140,
    ])
    require(pixels == expected_pixels, "facade image pixels do not equal the authored packed plane")
    require(content.count(b" Do\n") == 1, "facade image must be painted exactly once")

    figure = only_object(bodies, b"/S /Figure ", "Figure structure element")
    expected_alt = canonical_text("A four-color field palette arranged in mirrored bands")
    require(b"/Alt " + expected_alt + b" " in bodies[figure], "Figure alternative text is missing or changed")
    require(is_structure_element(bodies[figure]) and [kind for kind, _, _ in structure_kids(bodies[figure])] == ["mcr"], "Figure does not own its marked-content reference")
    report("exact packed image payload, one image placement, semantic Figure ownership, and authored /Alt")


def _image_objects(document: Document):
    return [(number, body) for number in sorted(document.bodies)
            if isinstance(body := document.get(number), dict) and body.get("Subtype") == "Image"]


def _page_xobjects(document: Document, page: dict):
    resources = page["Resources"]
    if isinstance(resources, Ref):
        resources = document.get(int(resources))
    xobjects = resources["XObject"]
    return document.get(int(xobjects)) if isinstance(xobjects, Ref) else xobjects


def _shared_image_figures(pdf: bytes, dimensions: dict[str, int]):
    validate_structure_semantics_pdf(pdf, dimensions)
    document, pages, root = tagged(pdf)
    require(len(pages) == dimensions["pages"], "shared image page count changed")
    figures = [node for node in root.descendants() if node.role == "Figure"]
    captions = [node for node in root.descendants() if node.role == "Caption"]
    require(len(figures) == len(captions) == 3 * len(pages), "image sharing merged a semantic figure or caption")
    return document, pages, figures, captions


def _facade_shared_rasters(pdf: bytes, dimensions: dict[str, int], report: Reporter) -> None:
    document, pages, figures, captions = _shared_image_figures(pdf, dimensions)
    images = _image_objects(document)
    colors = [(number, body) for number, body in images if "SMask" in body]
    require(len(images) == 4 and len(colors) == 2, "expected exactly two canonical RGB streams with their masks")
    require(all(document.stream(number) == bytes([30, 60, 90, 120, 150, 180]) for number, _ in colors), "RGB bytes changed")
    require([document.stream(int(body["SMask"])) for _, body in colors] == [bytes([0, 255]), bytes([255, 0])],
            "distinct alpha payloads changed or lost first-occurrence order")
    a, b = [number for number, _ in colors]

    _check_owned_image_paints(document, pages, figures, captions, [a, b, a])
    report("two canonical RGB and alpha streams, A/B/A per page, and independent figure ownership")


def _facade_shared_jpeg(pdf: bytes, dimensions: dict[str, int], report: Reporter) -> None:
    document, pages, figures, captions = _shared_image_figures(pdf, dimensions)
    images = _image_objects(document)
    require(len(images) == 1, "expected exactly one shared JPEG image stream")
    image, dictionary = images[0]
    require(dictionary.get("Filter") == "DCTDecode" and dictionary.get("Width") == dictionary.get("Height") == 8,
            "shared JPEG lost its filter or dimensions")
    length = indirect_length(document.bodies, int(dictionary["Length"]))
    _, encoded = stream_parts(document.bodies[image], length)
    expected = (Path(__file__).resolve().parents[1] / "tests/assets/jpeg-fuzz-corpus/rgb-8x8.jpg").read_bytes()
    require(encoded == expected, "shared JPEG payload changed")
    _check_owned_image_paints(document, pages, figures, captions, [image] * 3)
    report("one byte-exact DCT stream and one owned image paint per tagged figure")


def _check_owned_image_paints(document: Document, pages, figures, captions, expected: list[int]) -> None:
    for page_index, page in enumerate(pages):
        page_value = document.get(page)
        xobjects = _page_xobjects(document, page_value)
        require(sorted(map(int, xobjects.values())) == sorted(set(expected)), "page dictionary has duplicate, missing or foreign image references")
        marks = {int(mcid): body for mcid, body in MARKED.findall(document.stream(int(page_value["Contents"])))}
        painted = []
        for position in range(3):
            index = 3 * page_index + position
            figure, caption = figures[index], captions[index]
            require(text_string(figure.value["Alt"]) == f"Image description {index + 1}", "figure alternative changed")
            require(caption.text == f"Survey figure {index + 1}" and caption.pages == {page}, "figure caption changed")
            require(len(figure.marks) == 1 and figure.pages == {page}, "figure lost its own drawing mark")
            _, mcid = figure.marks[0]
            names = re.findall(rb"/([A-Za-z0-9_]+) Do\n", marks[mcid])
            require(len(names) == 1, "figure must paint exactly one image")
            painted.append(int(xobjects[names[0].decode("ascii")]))
        require(painted == expected, "figure paint references changed the authored image sequence")


def _furniture_shared_rasters(pdf: bytes, dimensions: dict[str, int], report: Reporter) -> None:
    document, pages, _ = tagged(pdf)
    images = _image_objects(document)
    require(len(images) == dimensions["canonical_images"], "physical furniture image count changed")
    mark = images[-1][0]
    logo = images[0][0]
    if logo != mark:
        require(document.stream(logo) == bytes([20, 90, 140] * 16 + [240, 180, 40] * 16), "header logo pixels changed")
    require(document.stream(mark) == bytes([0, 80, 160, 240, 240, 160, 80, 0]), "gray mark pixels changed")
    expected_refs = sorted({logo, mark})
    expected_paints = ([(b"<</Type /Pagination /Subtype /Header>>", logo)] * dimensions["header_image_placements"]
                       + [(b"<</Type /Pagination /Subtype /Footer>>", mark)])
    for page in pages:
        page_value = document.get(page)
        xobjects = _page_xobjects(document, page_value)
        require(sorted(map(int, xobjects.values())) == expected_refs, "page has repeated furniture resource entries")
        content = document.stream(int(page_value["Contents"]))
        paints = [(declaration, int(xobjects[name.decode("ascii")]))
                  for declaration, body in ARTIFACT.findall(content)
                  for name in re.findall(rb"/([A-Za-z0-9_]+) Do\n", body)]
        require(paints == expected_paints, "furniture raster placement or artifact classification changed")
    report("shared furniture images with exact pixels and separate header/footer artifacts on each page")


VALIDATORS: dict[str, Validator] = {
    "facade_shared_rasters": _facade_shared_rasters,
    "facade_shared_jpeg": _facade_shared_jpeg,
    "furniture_shared_rasters": _furniture_shared_rasters,
    "footnotes": _dimensioned(validate_footnotes_pdf, "first-citation placement, logical backlinks and structure destinations"),
    "fillable_forms": _dimensioned(validate_fillable_pdf, "editable widget repertoire, exact values and appearances, authored geometry and tab order, and Form-owned labels"),
    "anchored_figure": _dimensioned(validate_anchored_figure_pdf, "atomic anchor deferral with owned figure and caption, exact drawing geometry and authored order"),
    "associated_files": _dimensioned(validate_associated_files_pdf, "catalog AF, name-tree ordering and boundaries, exact file-specification metadata, distinct streams, and extracted payloads"),
    "default_fonts": _dimensioned(validate_default_fonts_pdf, "genuine static family/style programs, exact selected glyph outlines and searchable source text"),
    "authored_index": _dimensioned(validate_index_fixture, "index collation and linked authored locations"),
    "flow_page_reference": _dimensioned(validate_flow_fixture, "final reference wrapping, committed labels and paired destinations"),
    "generated_contents": _dimensioned(validate_generated_fixture, "authored generated contents targets, printed labels, and paired link destinations"),
    "contents_entries": _dimensioned(validate_contents_entries_pdf, "aligned contents columns, wrapped titles, linked exact page references and decorative leaders"),
    "destination_references": _dimensioned(validate_destination_references_pdf, "printed reference Unicode agrees with emitted destinations and page labels, fixed advances, semantic owners and explicit annotations"),
    "arabic_invoice": _dimensioned(lambda pdf, _: check_arabic_invoice(pdf), "Arabic invoice logical text, writing modes, paint positions and language scopes"),
    "hindi_statement": _dimensioned(lambda pdf, _: check_hindi_statement(pdf), "logical text, glyph positions and language scopes"),
    "thai_notice": _dimensioned(lambda pdf, _: check_thai_notice(pdf), "logical text, glyph positions and language scopes"),
    "thai_dictionary_scale": _dimensioned(check_thai_scale, "logical Thai dictionary word and ordered line positions at scale"),
    "bibliography": _dimensioned(check_bibliography, "authored bibliography order, namespaces, citation actions and reciprocal references"),
    "bilingual_invoice": _dimensioned(lambda pdf, _: check_bilingual_invoice(pdf), "bilingual invoice logical text, writing modes, paint positions and language scopes"),
    "inter_latin": _dimensioned(validate_inter_latin_pdf, "exact kerned positions, ligature and literal mapping, wrap ownership and scope color"),
    "columns": _dimensioned(validate_columns_pdf, "authored source and semantic ownership across unequal-width columns and pages"),
    "designed_brief": _dimensioned(validate_designed_brief_pdf, "fixed figure and text geometry, exact caption ownership, and independent semantic and paint permutations"),
    "fixed_pages": _dimensioned(validate_fixed_pages_pdf, "fixed frame geometry, independent structure and stream order, and exact background/overlay ownership"),
    "vector_diagrams": _dimensioned(validate_vector_diagrams_pdf, "exact prepared-vector Unicode labels, caption/Alt ownership and cubic/arrowhead paths"),
    "page_labels": _dimensioned(validate_page_labels_pdf, "visible labels match emitted PDF label ranges; repeated labels remain artifacts"),
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
    "facade_image": _facade_image,
    "multiface_text": _simple(validate_multiface_text_pdf, "exact selected Latin/CJK Type 0 resources, CID maps, and Unicode mappings"),
    "generated_label": _simple(validate_generated_labels_pdf, "independent offsets, lengths, xref, typed list ownership, labels, Type 0 font, CID, and Unicode mapping facts"),
    "combining_text": _simple(validate_combining_pdf, "exact decomposed combining CID and two-scalar ToUnicode facts"),
    "case_text": _simple(validate_case_pdf, "resolved case presentation, logical ActualText, CID, and Unicode mapping facts"),
    "rtl_text": _simple(validate_rtl_pdf, "resolved visual order, mirrored presentation, logical ActualText, CID, and Unicode mapping facts"),
    "multiface_facade": _simple(validate_multiface_facade_pdf, "independent offsets, lengths, xref, dense two-font resources, visual-order paint segments, CID, and per-font Unicode mapping facts"),
    "caller_facade": _simple(validate_caller_facade_pdf, "independent offsets, lengths, xref, public caller source identity, three placements, Type 0 font, CID, and Unicode mapping facts"),
    "drawing_labels": _dimensioned(lambda pdf, dimensions: validate_drawing_labels_pdf(pdf, dimensions.get("labelled_figures")), "exact Figure label Unicode and ownership in drawing order, and panel label as Layout artifact"),
    "drawing_label_faces": _dimensioned(lambda pdf, dimensions: validate_drawing_label_faces_pdf(pdf, dimensions.get("labelled_figures")), "exact Figure label Unicode, ownership and authored face selection"),
    "link_underlines": _simple(validate_link_underlines_pdf, "every link line quadrilateral has a Layout artifact underline inside its extent, and underlines exist"),
    "unhinted_caller_font": _simple(validate_unhinted_caller_pdf, "caller facade facts plus an embedded subset of exactly the ten required TrueType tables, no hinting table"),
    "fonts": _dimensioned(validate_fonts_pdf, "canonical Type 0 bundles, verified embedded subsets, identity CID maps, ToUnicode facts, exact per-stream /Font dictionaries, and placement-site ownership"),
    "forms": _dimensioned(validate_forms_pdf, "exact Form XObject dictionaries, per-stream direct resources, Do resolution, sharing, and placement-site MCID/ParentTree ownership facts"),
    "color_images": _dimensioned(validate_color_images_pdf, "canonical ICC/color-space/image objects, exact leaf payload equality, soft-mask wiring, and deduplicated direct dictionaries"),
    "transparency": _dimensioned(validate_transparency_pdf, "canonical ExtGState objects, exact per-stream /ExtGState dictionaries, balanced opacity groups, transparency-group and blending-space wiring, and placement-site ownership facts"),
    "soft_masks": _dimensioned(validate_soft_masks_pdf, "canonical Alpha mask states, direct /SMask /G wiring to isolated mask forms outside every resource dictionary, balanced mask groups, and placement-site ownership facts"),
    "shadings": _dimensioned(validate_shadings_pdf, "canonical shading/function/pattern objects, exact per-stream /Shading and /Pattern dictionaries, re-derived stop models, ownership-neutral pattern streams, and sh/scn operand resolution"),
    "navigation": _dimensioned(validate_navigation_pdf, "paired /SD + /D actions, keyboard-ordered /Annots, OBJR/ParentTree linkage, named destinations, outline preorder, page labels, and appearance geometry verified structurally"),
    "pdfa4": _dimensioned(validate_pdfa4_pdf, "PDF/A-4 identification packet, single GTS_PDFA1 sRGB2014 intent, printable links, FontFile2 Type 0 fonts, permitted filters and images, no /Info or excluded keys, verified structurally"),
    "pdfa4_standard_twin": _dimensioned(validate_standard_twin_pdf, "PDF 2.0 file skeleton of a Standard twin with no PDF/A identification"),
    "metadata": _dimensioned(validate_metadata_pdf, "catalog /Lang, canonical XMP metadata stream, GTS_PDFA1 output intent, and the single shared sRGB2014 profile stream verified structurally"),
    "chapter_templates": _dimensioned(validate_chapter_templates_pdf, "chapter scope opening/continuation boundaries, selected body frames, exact running-label artifacts, reset and global numbering verified independently"),
    "structure_semantics": _dimensioned(validate_structure_semantics_pdf, "object-number-independent structure tree, Table 5 containment, ParentTree/MCID/OBJR exactly-once, IDTree/ID, language inheritance, typed attributes, DisplayDocTitle, MarkInfo, Tabs, and MCID-free page furniture with exact page fields verified independently"),
    "source_blocks_multiple": _dimensioned(validate_multiple_sources_pdf, "three source Code owners, shared/distinct canonical source identities, exact text/reading order and font reuse"),
    "source_foregrounds": _dimensioned(validate_source_foregrounds_pdf, "original UTF8 colour mapping, searchable source text and canonical semantic ownership"),
    "source_blocks": _dimensioned(validate_source_blocks_pdf, "canonical source ActualText, exact measured text/blank rows, line continuation, local typography, padded artifact panels, and body spacing"),
    "furniture_typography": _simple(validate_furniture_typography_pdf, "independent furniture face, size, color, page fields, and artifact ownership"),
    "rich_inline": _dimensioned(validate_rich_inline_pdf, "ToUnicode-decoded logical text in structure order equal to paint order, text-bearing inline roles, /E on Span only, and one OBJR-owning link annotation per page painted"),
    "technical_manual": _dimensioned(validate_technical_manual_pdf, "combined printed destinations, scoped chapter furniture, rich source/vector/table ownership, nested padding and repeated-reference artifacts"),
    "table_paint_frames": _dimensioned(validate_table_paint_frames_pdf, "scoped table outer paint, exact row boundaries, semantic text and repeated-reference artifacts"),
    "table_spans": _dimensioned(validate_table_spans, "authored row rectangles, exact header edges, repeated artifacts and cell paint across pages"),
    "rich_flow": _dimensioned(validate_rich_flow_pdf, "exact rich LI/callout source/figure/table ownership, reading order, original source and foregrounds, parent frames, panel padding, and artifact table headers"),
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
        "check_tagged_visual.py", "check_visual_renderers.py",
        "check_text.py", "check_caller_text.py", "check_caller_facade.py", "check_facade_output.py",
        "check_generated_labels.py", "check_actual_text.py", "check_supplementary_text.py", "check_cjk_text.py",
        "check_ligature.py", "check_multiface_facade.py", "check_case_text.py", "check_combining.py",
        "check_rtl.py", "check_multiface_text.py", "check_soft_hyphen.py", "check_external_discretionary_hyphen.py",
        "check_forms.py", "check_color_images.py",
        "check_transparency.py", "check_transparency_renderers.py",
        "check_soft_masks.py", "check_shadings.py", "check_shading_renderers.py",
        "check_metadata.py", "check_metadata_renderers.py",
        "check_navigation.py", "check_link_underlines.py", "check_drawing_labels.py", "roc_diagnostics.py",
    )
}
PREFLIGHT_CHECKS["pdfa4_structure"] = PreflightCheck("check_pdfa4_structure.py", True)
PREFLIGHT_CHECKS["profile_declarations"] = PreflightCheck("check_profile_declarations.py", True)
PREFLIGHT_CHECKS["contracts"] = PreflightCheck("check_contracts.py", True)
PREFLIGHT_CHECKS["pdf_structure"] = PreflightCheck("check_pdf_structure.py", True)
# The font self-test validates the committed font-leaf snapshots' exact
# descendant dictionaries, which are also in flux during --update-snapshots.
PREFLIGHT_CHECKS["default_fonts"] = PreflightCheck("check_default_fonts.py", True)
PREFLIGHT_CHECKS["fonts"] = PreflightCheck("check_fonts.py", True)
# The structure-semantics self-test reads committed facade and container
# snapshots, which are in flux during --update-snapshots.
PREFLIGHT_CHECKS["structure_semantics"] = PreflightCheck("check_structure_semantics.py", True)
# The rich-inline self-test pins the rich-inline snapshots' logical text.
PREFLIGHT_CHECKS["rich_inline"] = PreflightCheck("check_rich_inline.py", True)
PREFLIGHT_CHECKS["table_paint_frames"] = PreflightCheck("check_table_paint_frames.py", True)
PREFLIGHT_CHECKS["rich_flow"] = PreflightCheck("check_rich_flow.py", True)
PREFLIGHT_CHECKS["technical_manual"] = PreflightCheck("check_technical_manual.py", True)
PREFLIGHT_CHECKS["generated_contents"] = PreflightCheck("check_generated_handbook.py", True)
PREFLIGHT_CHECKS["contents_entries"] = PreflightCheck("check_contents_entries.py", True)
PREFLIGHT_CHECKS["destination_references"] = PreflightCheck("check_destination_references.py", True)
PREFLIGHT_CHECKS["source_blocks"] = PreflightCheck("check_source_blocks.py", True)
PREFLIGHT_CHECKS["bibliography"] = PreflightCheck("check_bibliography.py", True)
PREFLIGHT_CHECKS["bilingual_invoice"] = PreflightCheck("check_bilingual_invoice.py", True)
PREFLIGHT_CHECKS["inter_latin"] = PreflightCheck("check_inter_latin.py", True)
PREFLIGHT_CHECKS["columns"] = PreflightCheck("check_columns.py", True)
PREFLIGHT_CHECKS["fixed_pages"] = PreflightCheck("check_fixed_pages.py", True)
PREFLIGHT_CHECKS["vector_diagrams"] = PreflightCheck("check_vector_diagrams.py", True)
PREFLIGHT_CHECKS["source_foregrounds"] = PreflightCheck("check_source_foregrounds.py", True)
# The reference-document self-test reads the reference and gallery
# snapshots, which are in flux during --update-snapshots.
PREFLIGHT_CHECKS["reference_documents"] = PreflightCheck("check_reference_documents.py", True)


def validate_registry_ids(validators: tuple[str, ...], field: str) -> None:
    if len(validators) != len(set(validators)):
        raise SystemExit(f"{field}: validators must be unique")
    unknown = set(validators) - VALIDATORS.keys() - PROFILE_VALIDATORS.keys()
    if unknown:
        raise SystemExit(f"{field}: unknown validator(s): {', '.join(sorted(unknown))}")
    for selected, required in PROFILE_VALIDATORS.items():
        if selected in validators and required not in validators:
            raise SystemExit(f"{field}: {selected} requires {required}")


def validate_preflight_ids(checks: tuple[str, ...], field: str) -> None:
    if not checks or len(checks) != len(set(checks)):
        raise SystemExit(f"{field}: preflight checks must be non-empty and unique")
    unknown = set(checks) - PREFLIGHT_CHECKS.keys()
    if unknown:
        raise SystemExit(f"{field}: unknown preflight check(s): {', '.join(sorted(unknown))}")


def run_validators(
    validator_ids: tuple[str, ...], data: bytes, dimensions: dict[str, int], report: Reporter
) -> None:
    if "pdfua2" in validator_ids:
        dimensions = {**dimensions, "facade_table_headers": int("table_spans" not in validator_ids)}
        wtpdf = "wtpdf_accessibility" in validator_ids
        validate_claims(data, wtpdf=wtpdf)
        report("independent inspection of PDF/UA-2 and applicable WTPDF identification and embedded font bundles")
        if "structure_semantics" not in validator_ids:
            VALIDATORS["structure_semantics"](data, dimensions, report)
    for validator_id in validator_ids:
        if validator_id not in PROFILE_VALIDATORS:
            VALIDATORS[validator_id](data, dimensions, report)

PREFLIGHT_CHECKS["chapter_templates"] = PreflightCheck("check_chapter_templates.py", True)

PREFLIGHT_CHECKS["associated_files"] = PreflightCheck("check_associated_files.py", True)

PREFLIGHT_CHECKS["fillable_forms"] = PreflightCheck("check_fillable_forms.py", True)

PREFLIGHT_CHECKS["footnotes"] = PreflightCheck("check_footnotes.py", True)
