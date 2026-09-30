import pdf.Color
import pdf.Conformance
import pdf.Document
import pdf.Font
import pdf.Image
import pdf.KernelBuiltInFont
import pdf.KernelColor
import pdf.KernelContent
import pdf.KernelFacadeFragments
import pdf.KernelFacadeFurniture
import pdf.KernelFacadeLines
import pdf.KernelFacadeOutput
import pdf.KernelFacadePages
import pdf.KernelFacadePipeline
import pdf.KernelFacadeScenes
import pdf.KernelFacadeSemantics
import pdf.KernelFacadeShape
import pdf.KernelFacadeSources
import pdf.KernelFacadeText
import pdf.KernelFont
import pdf.KernelFontPlan
import pdf.KernelImage
import pdf.KernelLineLayout
import pdf.KernelNavigation
import pdf.KernelObject
import pdf.KernelObjectPlan
import pdf.KernelPageLayout
import pdf.KernelPdfFont
import pdf.KernelPdfText
import pdf.KernelScene
import pdf.KernelSemantics
import pdf.KernelShape
import pdf.KernelSrgbProfile
import pdf.KernelTaggedTextStructure
import pdf.KernelTextSemantics
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme
import "../assets/NotoSansSC-CJK-Fixture.ttf" as cjk_font_bytes : List(U8)

## Page templates, furniture, and page fields through the public `Pdf`
## constructors (`reference-documents-v6`).
##
## - `letter xN`: the reference letter's templates: a first-page header with
##   a logo image, a semantic letterhead in the lead region, and a centered
##   footer; continuation pages with a start-slot header and `Page N of M`
##   in an end-aligned reserved width. N body paragraphs, a numbered list,
##   an unsplit signature block, and a schedule table after an explicit
##   break. The 20/200 pair (6 and 36 pages) is the linear scale pair.
## - `report`: a first page with only a `Page N of M` footer; continuation
##   pages add a running title and a full-width vector rule at the bottom
##   of the header region.
## - `ordered`: the report under an ordered policy of the packaged face
##   and a Han fixture face: the body uses only the packaged face, and the
##   continuation header `Quarterly operations report · 中 · Q1 FY2027`
##   selects its Han cluster onto the Han face, which becomes an extra
##   output font; pieces split at the face boundaries. Its rejections:
##   furniture text in an undeclared script (`text.unsupported_script`)
##   and a Han cluster no policy face covers (`text.coverage_missing`),
##   each at its furniture item path.
## - `numbering`: page fields in every number style across five pages.
## - `images`: raster and vector furniture drawings in both templates.
## - `page_sizes`: a landscape A4 report (842 × 595 pt) whose templates,
##   margins, and wide table lay out against the landscape frame, beside
##   a US Letter landscape and a 6 × 9 in custom document that must
##   prepare, and the `layout.page_size` rejections of custom sides that
##   are too small, too large, fractional, or negative, and of a custom
##   page too small for the theme's margins.
## - `backdrops xN`: N pages whose header region has a full-width rule
##   backdrop under start-slot title text and end-slot `Page N of M`, and
##   whose footer region is a tinted band backdrop behind centered footer
##   text; the first page's header is a backdrop only. Rejections: a
##   backdrop taller than its region or wider than the frame
##   (`layout.template_region_overflow` at `.backdrop`) and a backdrop on
##   `no_region` (`layout.template_region_empty`). The 3/30 pair is the
##   linear scale pair.
## - `slot_inset`: a header whose start and end text sit 3 pt above a
##   bottom rule backdrop and a footer whose text hangs 4 pt below a top
##   rule backdrop (`Pdf.with_slot_inset`). The furniture plan of the same
##   document without insets is resolved beside it: every header piece's
##   baseline must rise by exactly 3 pt, every footer piece's must drop by
##   exactly 4 pt, and every backdrop must stay where it was. Rejections:
##   a 6 pt inset that pushes a one-line stack out of its 16 pt region
##   (`layout.template_region_overflow` at the slot), a negative inset
##   (`layout.spacer_negative` at `.inset`), and an inset on `no_region`
##   (`layout.template_region_empty`).
## - `furniture_groups`: one mark drawing (a square, a bar, and an image)
##   reused three times through `Scene.Drawing.group` in a header item,
##   nested twice in a footer item, and grouped inside a backdrop; the
##   flattened marks must land where their offsets put them. It rejects
##   groups nested nine deep (`layout.furniture_drawing`).
## - `atomic_negatives`: every template rejection with its stable dotted
##   code and template path, and no bytes.
##
## Bytes always come from `Pdf.to_bytes_with` (the default `Archive`
## profile). Work comes from one additional facade pipeline probe, through
## pagination, furniture, text, and fragments, over the same normalized
## authoring.
Fixture :: [].{
	EvidenceError : [EvidenceFailure, InvalidScale, MissingRejection(U64)]

	letter : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	letter = |paragraphs| {
		if paragraphs == 0 or paragraphs > 200 {
			return Err(InvalidScale)
		}
		field_width = if paragraphs > 60 96 else 72
		evidence(letter_document(paragraphs, field_width), letter_theme)
	}

	report : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	report = |sections| {
		if sections == 0 or sections > 100 {
			return Err(InvalidScale)
		}
		evidence(report_document(sections), report_theme)
	}

	ordered : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	ordered = |sections| {
		if sections == 0 or sections > 100 {
			return Err(InvalidScale)
		}
		run_ordered(sections)
	}

	numbering : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	numbering = |context| evidence(numbering_document(context), report_theme)

	images : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	images = |context| evidence(images_document(context), report_theme)

	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |context| run_negatives(context)

	page_sizes : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	page_sizes = |context| run_page_sizes(context)

	furniture_groups : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	furniture_groups = |context| run_furniture_groups(context)

	slot_inset : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	slot_inset = |context| run_slot_inset(context)

	backdrops : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	backdrops = |pages| {
		if pages == 0 or pages > 100 {
			return Err(InvalidScale)
		}
		run_backdrops(pages)
	}
}

points : I64 -> Layout.Unit
points = |value| Layout.Unit.points(value)

## The reference themes: A4 body frames of 451 × 746 pt (letter) and
## 483 × 746 pt (report).
letter_theme : Theme
letter_theme = Theme.with_page_margin(Theme.default, { bottom: points(48), left: points(72), right: points(72), top: points(48) })

report_theme : Theme
report_theme = Theme.with_page_margin(Theme.default, { bottom: points(48), left: points(56), right: points(56), top: points(48) })

## A small raster logo: an 8 × 4 sRGB image in two bands.
logo_image : Image.Source
logo_image = {
	band = |red, green, blue| List.repeat([red, green, blue], 8).join()
	pixels = [band(20, 90, 140), band(20, 90, 140), band(240, 180, 40), band(240, 180, 40)].join()
	Image.Source.rgb8({ alpha: NoAlpha, dimensions: { height: 4, width: 8 }, pixels, row_stride: 24 })
}

## A gray mark for footers: 4 × 2 gray pixels.
gray_mark : Image.Source
gray_mark = Image.Source.gray8({ alpha: NoAlpha, dimensions: { height: 2, width: 4 }, pixels: [0, 80, 160, 240, 240, 160, 80, 0], row_stride: 4 })

logo : I64, I64 -> Pdf.Furniture
logo = |width, height| Pdf.furniture_image(Scene.drawing({}).image(logo_image, Layout.rect(0, 0, width, height)))

## `Page N of M`, end-aligned in a reserved width.
page_of : I64 -> Pdf.Inline
page_of = |width| Pdf.reserved_width(points(width), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])

sentences : List(Str)
sentences = [
	"Thank you for choosing Harbour & Finch for the Level 2 to 5 fit-out at Kestrel Parade.",
	"We are pleased to extend the warranty on every covered item by a further three years.",
	"The extension applies to frames, desktops, chairs, lamps, and cable trays delivered under purchase order PO 88213.",
	"Our installers will inspect each level in November and record the serial number of every desk frame.",
	"Where a part needs replacement, we will supply it within ten business days at no charge.",
	"The extension does not cover damage from misuse, relocation by third parties, or unapproved modifications.",
	"Please keep this letter with your asset register so that your facilities team can quote it when lodging a claim.",
	"If you would like the inspection scheduled outside business hours, let us know by the end of October.",
]

body_paragraph : U64 -> Document.Block
body_paragraph = |index| {
	start = index % sentences.len()
	var $text = ""
	var $offset = 0
	while $offset < 6 {
		sentence = match sentences.get((start + $offset) % sentences.len()) {
			Ok(value) => value
			Err(OutOfBounds) => crash "letter sentence escaped"
		}
		$text = if $offset == 0 sentence else "${$text} ${sentence}"
		$offset = $offset + 1
	}
	if index == 2 {
		Pdf.rich_paragraph([Pdf.text("Our oak supplier "), Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")]), Pdf.text(" in Lyon has confirmed the timber grades. ${$text}")])
	} else {
		Pdf.paragraph("${$text} (${(index + 1).to_str()})")
	}
}

letter_templates : I64 -> { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
letter_templates = |field_width| {
	first: Pdf.first_page_template({
		footer: Pdf.region({ center: [Pdf.furniture_text([Pdf.text("harbourfinch.example")])], end: [], height: points(16), start: [] }),
		gap: points(12),
		header: Pdf.region({ center: [], end: [logo(140, 48)], height: points(48), start: [] }),
		lead: Pdf.lead_region(
			points(60),
			[
				Pdf.rich_paragraph([Pdf.strong([Pdf.text("Harbour & Finch Pty Ltd")])]),
				Pdf.rich_paragraph([Pdf.text("Level 3, 18 Wharf Street, Hobart TAS 7000"), Pdf.line_break, Pdf.text("(03) 5550 0142 · hello@harbourfinch.example · ABN 00 123 456 789")]),
			],
		),
	}),
	continuation: Pdf.page_template({
		footer: Pdf.no_region,
		gap: points(12),
		header: Pdf.region({ center: [], end: [Pdf.furniture_text([page_of(field_width)])], height: points(16), start: [Pdf.furniture_text([Pdf.text("Northstar Cooperative Ltd · 21 September 2026")])] }),
	}),
}

letter_document : U64, I64 -> Document
letter_document = |paragraphs, field_width| {
	var $body = List.with_capacity(paragraphs)
	var $index = 0
	while $index < paragraphs {
		$body = $body.append(body_paragraph($index))
		$index = $index + 1
	}
	terms = [
		"Frames and motors are covered until 30 September 2031.",
		"Desktops are covered against warping and delamination.",
		"Chairs are covered for mechanisms and upholstery seams.",
		"Replacement parts ship within ten business days.",
	]
	schedule = Pdf.table({
		body_rows: ["HF-DSK-140", "HF-TOP-OAK", "HF-CHR-ERG", "HF-CAF-ELG", "HF-LMP-LED", "HF-CBL-TRY", "HF-INS-HRS", "HF-DEL-MET"].map(|code| Pdf.row([Pdf.header_cell(Row, [Pdf.text(code)]), Pdf.cell([Pdf.text("Covered item ${code}")]), Pdf.cell([Pdf.text("30 September 2031")])])),
		caption: Pdf.caption("Items covered by the extended warranty"),
		columns: [{ align: Start, width: Content }, { align: Start, width: Share(1) }, { align: End, width: Fixed(points(96)) }],
		footer_rows: [],
		header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Code")]), Pdf.header_cell(Column, [Pdf.text("Description")]), Pdf.header_cell(Column, [Pdf.text("Warranty until")])])],
		row_split: KeepRows,
	})
	contents = List.concat(
		[
			Pdf.paragraph("21 September 2026"),
			Pdf.rich_paragraph([Pdf.text("Ms Priya Raman"), Pdf.line_break, Pdf.text("Operations Manager"), Pdf.line_break, Pdf.text("Northstar Cooperative Ltd"), Pdf.line_break, Pdf.text("42 Kestrel Parade"), Pdf.line_break, Pdf.text("Fremantle WA 6160")]),
			Pdf.spacer(points(12)),
			Pdf.paragraph("Dear Ms Raman,"),
			Pdf.rich_paragraph([Pdf.text("Subject: "), Pdf.strong([Pdf.text("Extended warranty for your Level 2–5 fit-out")])]),
		],
		List.concat(
			$body,
			[
				Pdf.numbered_list({ start: 1, style: Decimal }, terms.map(|term| Pdf.list_item([Pdf.paragraph(term)]))),
				Pdf.paragraph("Please call me if you have any questions about the extension."),
				Pdf.paragraph("We look forward to supporting Northstar Cooperative for many years."),
				Pdf.keep_together([Pdf.paragraph("Yours sincerely,"), Pdf.spacer(points(36)), Pdf.paragraph("Tom Finch"), Pdf.paragraph("Director, Harbour & Finch Pty Ltd")]),
				Pdf.paragraph("Enclosure: Schedule 1, covered items"),
				Pdf.page_break,
				Pdf.section([Pdf.heading(1, "Schedule 1. Covered items"), schedule]),
			],
		),
	)
	Pdf.with_page_templates(
		Pdf.document({
			contents,
			language: "en-AU",
			title: "Letter to Northstar Cooperative about the warranty extension, 21 September 2026",
		}),
		letter_templates(field_width),
	)
}

## A full-width 0.5 pt rule as a vector drawing.
rule : Pdf.Furniture
rule = Pdf.furniture_image(Scene.rectangle(Scene.drawing({}), { origin: { x: points(0), y: points(0) }, size: { height: Layout.Unit.millipoints(500), width: points(483) } }, Color.srgb8({ blue: 110, green: 90, red: 60 })))

report_footer : Pdf.Region
report_footer = Pdf.region({ center: [], end: [Pdf.furniture_text([page_of(64)])], height: points(16), start: [] })

report_document : U64 -> Document
report_document = |sections| report_with_header(sections, "Quarterly operations report · Q1 FY2027")

report_with_header : U64, Str -> Document
report_with_header = |sections, running_title| {
	var $contents = [Pdf.title("Quarterly operations report")]
	var $index = 0
	while $index < sections {
		number = ($index + 1).to_str()
		$contents = $contents.append(
			Pdf.section([
				Pdf.heading(1, "${number}. Operations area ${number}"),
				body_paragraph($index),
				body_paragraph($index + 3),
				body_paragraph($index + 5),
			]),
		)
		$index = $index + 1
	}
	Pdf.with_page_templates(
		Pdf.document({ contents: $contents, language: "en-AU", title: "Harbour & Finch quarterly operations report, Q1 FY2027" }),
		{
			continuation: Pdf.page_template({
				footer: report_footer,
				gap: points(12),
				header: Pdf.region({ center: [], end: [], height: points(24), start: [Pdf.furniture_text([Pdf.text(running_title)]), rule] }),
			}),
			first: Pdf.first_page_template({ footer: report_footer, gap: points(12), header: Pdf.no_region, lead: Pdf.no_lead }),
		},
	)
}

numbering_document : U64 -> Document
numbering_document = |context| {
	styled = |label, style| Pdf.furniture_text([Pdf.text("${label} "), Pdf.page_number(style), Pdf.text(" of "), Pdf.total_pages(style)])
	footer = Pdf.region({
		center: [styled("Decimal", Decimal), styled("Lower alpha", LowerAlpha), styled("Upper alpha", UpperAlpha)],
		end: [styled("Lower roman", LowerRoman), styled("Upper roman", UpperRoman)],
		height: points(42),
		start: [],
	})
	template = Pdf.page_template({ footer, gap: points(12), header: Pdf.no_region })
	var $contents = []
	var $page = 0
	while $page < numbering_pages {
		if $page > 0 {
			$contents = $contents.append(Pdf.page_break)
		}
		$contents = $contents.append(Pdf.paragraph("Page body ${($page + 1).to_str()}${if context == 0 "." else "!"}"))
		$page = $page + 1
	}
	Pdf.with_page_templates(
		Pdf.document({ contents: $contents, language: "en-AU", title: "Page field number styles" }),
		{ continuation: template, first: Pdf.first_page_template({ footer, gap: points(12), header: Pdf.no_region, lead: Pdf.no_lead }) },
	)
}

numbering_pages : U64
numbering_pages = 5

image_pages : U64
image_pages = 3

images_document : U64 -> Document
images_document = |context| {
	stroke = Scene.drawing({}).path(Scene.path({}).move_to(Layout.point(1, 1)).line_to(Layout.point(119, 1)).finish(), Scene.solid_stroke(Color.srgb8({ blue: 40, green: 40, red: 160 }), points(1)))
	boxed = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 24, 12), Color.srgb8({ blue: 0, green: 0, red: 0 }))
	mark = Pdf.furniture_image(Scene.drawing({}).image(gray_mark, Layout.rect(0, 0, 16, 8)))
	var $contents = []
	var $page = 0
	while $page < image_pages {
		if $page > 0 {
			$contents = $contents.append(Pdf.page_break)
		}
		$contents = $contents.append(Pdf.paragraph("Furniture drawing page ${($page + 1).to_str()}${if context == 0 "." else "!"}"))
		$page = $page + 1
	}
	Pdf.with_page_templates(
		Pdf.document({ contents: $contents, language: "en-AU", title: "Furniture drawings" }),
		{
			continuation: Pdf.page_template({
				footer: Pdf.region({ center: [mark], end: [], height: points(16), start: [Pdf.furniture_text([Pdf.text("Continued")])] }),
				gap: points(12),
				header: Pdf.region({ center: [Pdf.furniture_image(boxed)], end: [Pdf.furniture_image(stroke)], height: points(20), start: [logo(40, 20)] }),
			}),
			first: Pdf.first_page_template({
				footer: Pdf.region({ center: [mark], end: [Pdf.furniture_text([page_of(64)])], height: points(16), start: [] }),
				gap: points(12),
				header: Pdf.region({ center: [], end: [], height: points(48), start: [logo(140, 48)] }),
				lead: Pdf.no_lead,
			}),
		},
	)
}

## Bytes come from `Pdf.to_bytes_with`; work comes from one facade pipeline
## probe through fragments over the same normalized authoring.
## The packaged face and the Han fixture face in one ordered policy.
##
## The limits depend on the runtime case so the registration is not
## evaluated at compile time.
ordered_faces : U64 -> Try({ policy : Font.PolicyId, registry : Font.Registry }, Fixture.EvidenceError)
ordered_faces = |sections| {
	limits = if sections > 0 Font.ValidationLimits.default else Font.ValidationLimits.make({ max_bytes: 0, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 })
	latin = match Font.Registry.empty.register(KernelBuiltInFont.bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits) {
		Err(_) => return Err(EvidenceFailure)
		Ok(value) => value
	}
	cjk = match latin.registry.register(cjk_font_bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Hani")] }, limits) {
		Err(_) => return Err(EvidenceFailure)
		Ok(value) => value
	}
	configured = match cjk.registry.with_policy([latin.face, cjk.face]) {
		Err(_) => return Err(EvidenceFailure)
		Ok(value) => value
	}
	Ok({ policy: configured.policy, registry: configured.registry })
}

run_ordered : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_ordered = |sections| {
	ordered = ordered_faces(sections)?
	theme = Theme.with_font_policy(report_theme, ordered.policy)
	options = Pdf.Options.with_font_registry(Pdf.Options.with_theme(Pdf.Options.default, theme), ordered.registry)
	document = report_with_header(sections, "Quarterly operations report · Q1 FY2027 · Office中")
	bytes = Pdf.to_bytes_with(document, options) ? |_| EvidenceFailure
	flow = KernelFacadePipeline.probe_ordered(Document.normalize(document), ordered, theme, page_size, pipeline_limits) ? |_| EvidenceFailure
	rejected = |running_title, feature| match Pdf.to_bytes_with(report_with_header(6, running_title), options) {
		Err(InvalidDocument({ diagnostics: [{ code: FontCoverageMissing, details: ["templates.continuation.header.start[0]"], feature: Feature(found), .. }], .. })) => if found == feature 1 else 0
		_ => 0
	}
	rejections = rejected("Report שלום", "text.unsupported_script") + rejected("Report 中文", "text.coverage_missing")
	if rejections != 2 {
		return Err(MissingRejection(rejections))
	}
	Ok({
		bytes,
		work: [
			flow.lines,
			flow.pages,
			flow.reference_passes,
			flow.field_resolutions,
			flow.furniture_items,
			flow.fragments,
			flow.final_runs - flow.fragments,
			rejections,
			bytes.len(),
		],
	})
}

evidence : Document, Theme -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
evidence = |document, theme| {
	bytes = Pdf.to_bytes_with(document, Pdf.Options.with_theme(Pdf.Options.default, theme)) ? |_| EvidenceFailure
	font = KernelFont.inspect(KernelBuiltInFont.bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })) ? |_| EvidenceFailure
	flow = KernelFacadePipeline.probe(Document.normalize(document), font, theme, page_size, descriptor, pipeline_limits, FragmentsReady) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			flow.lines,
			flow.pages,
			flow.reference_passes,
			flow.field_resolutions,
			flow.furniture_items,
			flow.fragments,
			flow.final_runs - flow.fragments,
			bytes.len(),
		],
	})
}

page_size : Layout.Size
page_size = { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) }

descriptor : KernelPdfFont.Descriptor
descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

rejects : Document, Conformance.DiagnosticCode, Str, List(Str) -> U64
rejects = |document, expected_code, expected_feature, expected_paths| match Pdf.to_bytes_with(document, Pdf.Options.with_theme(Pdf.Options.default, letter_theme)) {
	Err(InvalidDocument({ diagnostics: [{ code, details, feature: Feature(feature), location: Document, stage: AuthoringValidation, .. }], truncation: Complete, .. })) => if code == expected_code and feature == expected_feature and details == expected_paths 1 else 0
	_ => 0
}

## Each document differs from a valid templated letter in one template
## fact. Every rejection is transactional: a stable code, the template path
## of each participating source, and no bytes.
run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_negatives = |context| {
	title = if context == 0 "Template negatives" else "guarded"
	offset = context % 1
	body = [Pdf.paragraph("Body text.")]
	templated = |contents, templates| Pdf.with_page_templates(Pdf.document({ contents, language: "en-AU", title }), templates)
	header = |items| Pdf.region({ center: [], end: [], height: points(16), start: items })
	simple = |first_header, next_header| {
		continuation: Pdf.page_template({ footer: Pdf.no_region, gap: points(12), header: next_header }),
		first: Pdf.first_page_template({ footer: Pdf.no_region, gap: points(12), header: first_header, lead: Pdf.no_lead }),
	}
	text_header = header([Pdf.furniture_text([Pdf.text("Header")])])
	lead_of = |height, blocks| {
		continuation: Pdf.page_template({ footer: Pdf.no_region, gap: points(12), header: text_header }),
		first: Pdf.first_page_template({ footer: Pdf.no_region, gap: points(12), header: text_header, lead: Pdf.lead_region(points(height), blocks) }),
	}
	two_pages = [Pdf.paragraph("First page."), Pdf.page_break, Pdf.paragraph("Second page.")]
	ten_pages = List.repeat([Pdf.paragraph("A page."), Pdf.page_break], 9).join().append(Pdf.paragraph("The last page."))
	one_digit = header([Pdf.furniture_text([Pdf.reserved_width(points(8), End, [Pdf.page_number(Decimal)])])])
	long = Str.repeat("Northstar Cooperative Ltd ", 2 + offset)
	checks = [
		rejects(templated(body, lead_of(700, [Pdf.paragraph("Letterhead")])), LayoutConstraintViolated, "layout.template_body_space", ["templates.first"]),
		rejects(templated(body, lead_of(60, List.repeat(Pdf.paragraph("A letterhead line"), 12))), LayoutConstraintViolated, "layout.template_region_overflow", ["templates.first.lead"]),
		rejects(templated(two_pages, simple(text_header, Pdf.region({ center: [], end: [Pdf.furniture_text([Pdf.text(long)])], height: points(16), start: [Pdf.furniture_text([Pdf.text("Northstar Cooperative Ltd · 21 September 2026")])] }))), LayoutConstraintViolated, "layout.template_region_overflow", ["templates.continuation.header"]),
		rejects(templated(ten_pages, simple(one_digit, one_digit)), LayoutConstraintViolated, "layout.field_overflow", ["templates.continuation.header.start[0].inlines[0].inlines[0]"]),
		rejects(templated(body, simple(Pdf.region({ center: [], end: [], height: points(16), start: [] }), text_header)), LayoutConstraintViolated, "layout.template_region_empty", ["templates.first.header"]),
		rejects(templated(body, simple(header([Pdf.furniture_image(Scene.drawing({}))]), text_header)), InvalidRelationship, "layout.furniture_drawing", ["templates.first.header.start[0]"]),
		rejects(templated(body, simple(header([Pdf.furniture_text([Pdf.text("Header "), Pdf.emphasis([Pdf.text("styled")])])]), text_header)), LayoutConstraintViolated, "layout.furniture_inline", ["templates.first.header.start[0].inlines[1]"]),
		rejects(templated(body, simple(header([Pdf.furniture_text([])]), text_header)), InvalidRelationship, "semantics.inline_empty", ["templates.first.header.start[0]"]),
		rejects(templated(body, simple(Pdf.region({ center: [], end: [], height: points(10), start: [Pdf.furniture_text([Pdf.text("Too tall")])] }), text_header)), LayoutConstraintViolated, "layout.template_region_overflow", ["templates.first.header.start"]),
		rejects(templated(body, { continuation: Pdf.page_template({ footer: Pdf.no_region, gap: points(-1), header: text_header }), first: Pdf.first_page_template({ footer: Pdf.no_region, gap: points(12), header: text_header, lead: Pdf.no_lead }) }), LayoutConstraintViolated, "layout.spacer_negative", ["templates.continuation.gap"]),
		rejects(templated([], simple(text_header, text_header)), LayoutConstraintViolated, "layout.template_body_empty", []),
		rejects(templated(body, lead_of(60, [Pdf.paragraph("Letterhead"), Pdf.page_break, Pdf.paragraph("More")])), LayoutConstraintViolated, "layout.page_break_position", ["templates.first.lead.contents[1]"]),
		rejects(Pdf.document({ contents: [Pdf.paragraph("Lead"), Pdf.rich_paragraph([Pdf.text("Page "), Pdf.page_number(Decimal)])], language: "en-AU", title }), FeatureUnavailable, "document.generated_reference", ["contents[1].inlines[1]"]),
	]
	passed = checks.sum()
	if passed != checks.len() {
		return Err(MissingRejection(passed))
	}
	carrier = Pdf.to_bytes_with(templated([Pdf.title("Template carrier"), Pdf.paragraph("A valid templated page.")], simple(text_header, text_header)), Pdf.Options.with_theme(Pdf.Options.default, letter_theme)) ? |_| EvidenceFailure
	Ok({ bytes: carrier, work: [passed, carrier.len()] })
}

## A landscape report with a wide ledger table. The pipeline probe runs
## against the same landscape size the options select.
run_page_sizes : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_page_sizes = |context| {
	title = if context == 0 "Landscape ledger" else "guarded"
	landscape = { height: Layout.Unit.from_raw(595000), width: Layout.Unit.from_raw(842000) }
	options = |size| Pdf.Options.with_page_size(Pdf.Options.with_theme(Pdf.Options.default, report_theme), size)
	heading_cell = |value| Pdf.header_cell(Column, [Pdf.text(value)])
	var $rows = []
	var $index = 0
	while $index < 36 + context % 1 {
		$rows = $rows.append(ledger_row($index))
		$index = $index + 1
	}
	rows = $rows
	header = Pdf.region({ center: [], end: [Pdf.furniture_text([Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])], height: points(16), start: [Pdf.furniture_text([Pdf.text(title)])] })
	templates = {
		continuation: Pdf.page_template({ footer: Pdf.no_region, gap: points(12), header }),
		first: Pdf.first_page_template({ footer: Pdf.no_region, gap: points(12), header, lead: Pdf.no_lead }),
	}
	document = Pdf.with_page_templates(
		Pdf.document({
			contents: [
				Pdf.title(title),
				Pdf.paragraph("A wide ledger lays out against the landscape body frame: 730 pt between the margins instead of 483 pt."),
				Pdf.table({
					body_rows: rows,
					caption: Pdf.caption("Settlement ledger"),
					columns: [{ align: Start, width: Content }, { align: Start, width: Content }, { align: Start, width: Share(1) }, { align: Start, width: Share(2) }, { align: End, width: Fixed(points(72)) }, { align: End, width: Fixed(points(72)) }, { align: End, width: Fixed(points(72)) }, { align: Start, width: Content }],
					footer_rows: [],
					header_rows: [Pdf.row([heading_cell("Batch"), heading_cell("Date"), heading_cell("Depot"), heading_cell("Street"), heading_cell("Gross"), heading_cell("Fees"), heading_cell("Net"), heading_cell("Status")])],
					row_split: KeepRows,
				}),
			],
			language: "en-AU",
			title,
		}),
		templates,
	)
	bytes = Pdf.to_bytes_with(document, options(A4Landscape)) ? |_| EvidenceFailure
	letter = Pdf.to_bytes_with(document, options(LetterLandscape)) ? |_| EvidenceFailure
	custom = Pdf.to_bytes_with(Pdf.document({ contents: [Pdf.title("Six by nine"), Pdf.paragraph("A custom 432 × 648 pt page.")], language: "en-AU", title }), options(Custom({ height: points(648), width: points(432) }))) ? |_| EvidenceFailure
	blank = Pdf.to_bytes_with(Pdf.document({ contents: [], language: "en-AU", title }), options(Custom({ height: points(648), width: points(432) }))) ? |_| EvidenceFailure
	rejects_size = |size, feature, paths| match Pdf.to_bytes_with(Pdf.document({ contents: [Pdf.paragraph("Body.")], language: "en-AU", title }), options(size)) {
		Err(InvalidDocument({ diagnostics: [{ code: LayoutConstraintViolated, details, feature: Feature(found), .. }], truncation: Complete, .. })) => if found == feature and details == paths 1 else 0
		_ => 0
	}
	custom_side = |width_raw, height_raw| Custom({ height: Layout.Unit.from_raw(height_raw), width: Layout.Unit.from_raw(width_raw) })
	checks = [
		rejects_size(custom_side(2000, 648000), "layout.page_size", ["options.page_size"]),
		rejects_size(custom_side(432000, 14401000), "layout.page_size", ["options.page_size"]),
		rejects_size(custom_side(432500, 648000), "layout.page_size", ["options.page_size"]),
		rejects_size(custom_side(-432000, 648000), "layout.page_size", ["options.page_size"]),
		rejects_size(custom_side(100000, 100000), "layout.page_margin", ["theme.page_margin", "options.page_size"]),
	]

	rejections = checks.sum()
	if rejections != checks.len() {
		return Err(MissingRejection(rejections))
	}
	font = KernelFont.inspect(KernelBuiltInFont.bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })) ? |_| EvidenceFailure
	flow = KernelFacadePipeline.probe(Document.normalize(document), font, report_theme, landscape, descriptor, pipeline_limits, FragmentsReady) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			flow.lines,
			flow.pages,
			flow.fragments,
			letter.len(),
			custom.len(),
			blank.len(),
			rejections,
			bytes.len(),
		],
	})
}

run_furniture_groups : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_furniture_groups = |context| {
	square = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 10, 10), Color.srgb8({ blue: 140, green: 70, red: 20 }))
	mark = Scene.rectangle(square, Layout.rect(12, 3, 18, 4), Color.srgb8({ blue: 40, green: 150, red: 230 })).image(gray_mark, Layout.rect(32, 0, 8, 10))
	row = Scene.drawing({}).group(Layout.point(0, 0), mark).group(Layout.point(48, 0), mark).group(Layout.point(96, 0), mark)
	nested = Scene.drawing({}).group(Layout.point(4, 2), Scene.drawing({}).group(Layout.point(6, 0), mark))
	underline = Scene.drawing({}).group(Layout.point(0, 0), Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 483, 1), Color.srgb8({ blue: 140, green: 70, red: 20 })))
	header = Pdf.region({ center: [], end: [Pdf.furniture_text([page_of(80)])], height: points(20), start: [Pdf.furniture_image(row)], backdrop: Backdrop(underline) })
	footer = Pdf.region({ center: [Pdf.furniture_image(nested)], end: [], height: points(16), start: [] })
	document = Pdf.with_page_templates(
		Pdf.document({ contents: [Pdf.title("Reused marks"), body_paragraph(context), Pdf.page_break, body_paragraph(context + 1)], language: "en-AU", title: "Furniture groups" }),
		{
			continuation: Pdf.page_template({ footer, gap: points(12), header }),
			first: Pdf.first_page_template({ footer, gap: points(12), header, lead: Pdf.no_lead }),
		},
	)
	evidenced = evidence(document, report_theme)?
	var $deep = mark
	var $depth = 0
	while $depth < 9 {
		$deep = Scene.drawing({}).group(Layout.point(1, 0), $deep)
		$depth = $depth + 1
	}
	deep_header = Pdf.region({ center: [], end: [], height: points(20), start: [Pdf.furniture_image($deep)] })
	rejected = rejects(Pdf.with_page_templates(Pdf.document({ contents: [Pdf.paragraph("Body.")], language: "en-AU", title: "Deep groups" }), { continuation: Pdf.page_template({ footer: Pdf.no_region, gap: points(12), header: deep_header }), first: Pdf.first_page_template({ footer: Pdf.no_region, gap: points(12), header: deep_header, lead: Pdf.no_lead }) }), InvalidRelationship, "layout.furniture_drawing", ["templates.first.header.start[0]"])
	if rejected != 1 {
		return Err(MissingRejection(rejected))
	}
	Ok({ bytes: evidenced.bytes, work: evidenced.work.append(rejected) })
}

backdrop_templates : Layout.Unit -> { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
backdrop_templates = |rule_width| {
	rule_mark = Scene.rectangle(Scene.drawing({}), { origin: Layout.point(0, 0), size: { height: Layout.Unit.from_raw(750), width: rule_width } }, Color.srgb8({ blue: 110, green: 60, red: 20 }))
	band = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 483, 20), Color.srgb8({ blue: 245, green: 238, red: 232 }))
	header = Pdf.region({ center: [], end: [Pdf.furniture_text([page_of(80)])], height: points(20), start: [Pdf.furniture_text([Pdf.text("Quarterly operations report")])], backdrop: Backdrop(rule_mark) })
	footer = Pdf.region({ center: [Pdf.furniture_text([Pdf.text("Harbour & Finch Pty Ltd · Confidential")])], end: [], height: points(20), start: [], backdrop: Backdrop(band) })
	{
		continuation: Pdf.page_template({ footer, gap: points(12), header }),
		first: Pdf.first_page_template({ footer, gap: points(12), header: Pdf.region({ center: [], end: [], height: points(6), start: [], backdrop: Backdrop(rule_mark) }), lead: Pdf.no_lead }),
	}
}

run_backdrops : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_backdrops = |pages| {
	var $contents = [Pdf.title("Quarterly operations report")]
	var $page = 0
	while $page < pages {
		if $page > 0 {
			$contents = $contents.append(Pdf.page_break)
		}
		$contents = $contents.append(body_paragraph($page))
		$page = $page + 1
	}
	document = Pdf.with_page_templates(Pdf.document({ contents: $contents, language: "en-AU", title: "Backdrops (${pages.to_str()} pages)" }), backdrop_templates(points(483)))
	evidenced = evidence(document, report_theme)?
	body = [Pdf.paragraph("Body.")]
	templated = |templates| Pdf.with_page_templates(Pdf.document({ contents: body, language: "en-AU", title: "Backdrop negatives" }), templates)
	text_header = Pdf.region({ center: [], end: [], height: points(16), start: [Pdf.furniture_text([Pdf.text("Header")])] })
	simple = |first_header| {
		continuation: Pdf.page_template({ footer: Pdf.no_region, gap: points(12), header: text_header }),
		first: Pdf.first_page_template({ footer: Pdf.no_region, gap: points(12), header: first_header, lead: Pdf.no_lead }),
	}
	tall = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 100, 30), Color.srgb8({ blue: 0, green: 0, red: 0 }))
	checks = [
		rejects(templated(simple(Pdf.with_backdrop(text_header, tall))), LayoutConstraintViolated, "layout.template_region_overflow", ["templates.first.header.backdrop"]),
		rejects(templated(backdrop_templates(points(452 + (pages % 1).to_i64_wrap()))), LayoutConstraintViolated, "layout.template_region_overflow", ["templates.first.header.backdrop"]),
		rejects(templated(simple(Pdf.with_backdrop(Pdf.no_region, tall))), LayoutConstraintViolated, "layout.template_region_empty", ["templates.first.header"]),
	]
	rejections = checks.sum()
	if rejections != checks.len() {
		return Err(MissingRejection(rejections))
	}
	Ok({ bytes: evidenced.bytes, work: evidenced.work.append(rejections) })
}

## Header text over a bottom rule and footer text under a top rule, with
## the given slot insets.
inset_templates : Layout.Unit, Layout.Unit -> { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
inset_templates = |header_inset, footer_inset| {
	edge_rule = |y| Scene.rectangle(Scene.drawing({}), { origin: Layout.point(0, y), size: { height: Layout.Unit.from_raw(750), width: points(483) } }, Color.srgb8({ blue: 110, green: 60, red: 20 }))
	header = Pdf.region({ center: [], end: [Pdf.furniture_text([page_of(80)])], height: points(24), start: [Pdf.furniture_text([Pdf.text("Quarterly operations report")])], backdrop: Backdrop(edge_rule(0)), slot_inset: header_inset })
	footer = Pdf.region({ center: [Pdf.furniture_text([Pdf.text("Harbour & Finch Pty Ltd · Confidential")])], end: [], height: points(24), start: [], backdrop: Backdrop(edge_rule(23)), slot_inset: footer_inset })
	{
		continuation: Pdf.page_template({ footer, gap: points(12), header }),
		first: Pdf.first_page_template({ footer, gap: points(12), header, lead: Pdf.no_lead }),
	}
}

## The resolved furniture plan of a two-page document under `templates`.
inset_plan : Document, Theme -> Try(KernelFacadeFurniture.Plan, Fixture.EvidenceError)
inset_plan = |document, theme| {
	font = KernelFont.inspect(KernelBuiltInFont.bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })) ? |_| EvidenceFailure
	static = KernelFacadeFurniture.Static.build(Document.normalize(document), theme, page_size) ? |_| EvidenceFailure
	shape = KernelShape.Limits.make({ max_clusters: 1000000, max_glyphs: 1000000, max_scalars: 1000000, max_source_bytes: 1000000 })
	sources = KernelFacadeSources.Limits.make({ max_hash_probes: 4000000, max_inputs: 1000000, max_source_bytes: 1000000, max_source_scalars: 1000000, max_table_slots: 2097152, max_unique_sources: 1000000, unicode: { max_graphemes: 1000000, max_line_boundaries: 1000001, max_scalars: 1000000, max_script_runs: 2048 } })
	KernelFacadeFurniture.Plan.resolve(static, 2, SingleFace(font), Language("en-AU"), 0, KernelFacadeFurniture.Limits.make({ max_inputs: 1000000, max_items: 4096, max_pieces: 1000000, shape, sources })).map_err(|_| EvidenceFailure)
}

run_slot_inset : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_slot_inset = |context| {
	inset_document = |templates| Pdf.with_page_templates(Pdf.document({ contents: [Pdf.title("Quarterly operations report"), body_paragraph(context), Pdf.page_break, body_paragraph(context + 1)], language: "en-AU", title: "Slot insets" }), templates)
	document = inset_document(inset_templates(points(3), points(4)))
	evidenced = evidence(document, report_theme)?
	inset = inset_plan(document, report_theme)?
	plain = inset_plan(inset_document(inset_templates(points(0), points(0))), report_theme)?
	inset_pieces = KernelFacadeFurniture.Plan.pieces(inset)
	plain_pieces = KernelFacadeFurniture.Plan.pieces(plain)
	if inset_pieces.len() != plain_pieces.len() or inset_pieces.is_empty() {
		return Err(EvidenceFailure)
	}
	var $moved = 0
	var $index = 0
	while $index < inset_pieces.len() {
		after = list_at(inset_pieces, $index)
		before = list_at(plain_pieces, $index)
		shift = after.origin.y.raw() - before.origin.y.raw()
		expected = match after.band {
			Above => 3000
			Below => -4000
		}
		if shift != expected or after.origin.x != before.origin.x {
			return Err(EvidenceFailure)
		}
		$moved = $moved + 1
		$index = $index + 1
	}
	origins = |plan| KernelFacadeFurniture.Plan.drawing_paints(plan).map(|paint| (paint.origin.x.raw(), paint.origin.y.raw(), paint.page))
	if origins(inset) != origins(plain) {
		return Err(EvidenceFailure)
	}
	body = [Pdf.paragraph("Body.")]
	templated = |header| Pdf.with_page_templates(Pdf.document({ contents: body, language: "en-AU", title: "Inset negatives" }), { continuation: Pdf.page_template({ footer: Pdf.no_region, gap: points(12), header }), first: Pdf.first_page_template({ footer: Pdf.no_region, gap: points(12), header, lead: Pdf.no_lead }) })
	text_header = Pdf.region({ center: [], end: [], height: points(16), start: [Pdf.furniture_text([Pdf.text("Header")])] })
	checks = [
		rejects(templated(Pdf.with_slot_inset(text_header, points(6))), LayoutConstraintViolated, "layout.template_region_overflow", ["templates.first.header.start"]),
		rejects(templated(Pdf.with_slot_inset(text_header, points(-1))), LayoutConstraintViolated, "layout.spacer_negative", ["templates.first.header.inset"]),
		rejects(templated(Pdf.with_slot_inset(Pdf.no_region, points(2))), LayoutConstraintViolated, "layout.template_region_empty", ["templates.first.header"]),
	]
	rejections = checks.sum()
	if rejections != checks.len() {
		return Err(MissingRejection(rejections))
	}
	Ok({ bytes: evidenced.bytes, work: evidenced.work.append($moved).append(rejections) })
}

ledger_row : U64 -> Pdf.Row
ledger_row = |index| {
	n = (index + 1).to_str()
	day = (index % 28 + 1).to_str()
	cell = |value| Pdf.cell([Pdf.text(value)])
	Pdf.row([Pdf.header_cell(Row, [Pdf.text("Batch ${n}")]), cell("2026-09-${if day.count_utf8_bytes() == 1 "0${day}" else day}"), cell("Hobart"), cell("${n} Kestrel Parade"), cell("${n}4.20"), cell("${n}1.75"), cell("${n}2.45"), cell("Settled")])
}

## The facade's standard pipeline limits (package/Pdf.roc).
pipeline_limits : KernelFacadePipeline.Limits
pipeline_limits = KernelFacadePipeline.Limits.make({
	fragment_semantics: KernelSemantics.Limits.make({ max_attributes: 65536, max_content_spine: 65536 + 65536, max_fragments: 1000000, max_namespaces: 2, max_nodes: 16384, max_occurrences: 16384, max_semantic_depth: 48 }),
	fragments: KernelFacadeFragments.Limits.make({ max_fragments: 1000000, max_occurrences: 16384, max_pages: 1024 }),
	navigation: KernelNavigation.standard_limits,
	lines: KernelFacadeLines.Limits.make({
		line: KernelLineLayout.BatchLimits.make({
			line: KernelLineLayout.Limits.make({ max_boundaries: 1000001, max_candidates: 2000000, max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_lines: 1000000 }),
			max_key_probes: 4000000,
			max_lines: 1000000,
			max_runs: 65536,
			max_table_slots: 262144,
			max_templates: 65536,
		}),
		max_blocks: 16384,
		max_runs: 65536,
	}),
	output: KernelFacadeOutput.Limits.make({
		content: KernelContent.Limits.make({ max_content_bytes: 16000000, max_content_streams: 1024 }),
		font_plan: KernelFontPlan.Limits.make({ max_retained_glyphs: 10000 }),
		images: KernelImage.Limits.make({ max_decoded_bytes: 67108864, max_encoded_bytes: 67108864, max_height: 16384, max_markers: 4096, max_resources: 2048, max_width: 16384 }),
		max_objects: 65536,
		objects: KernelObjectPlan.Limits.make({ max_objects: 65527, max_pages: 1024 }),
		structure: KernelTaggedTextStructure.Limits.make({
			font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 1000000, max_unicode_mappings: 10000, max_unicode_scalars: 1000000 }),
			object_limits: object_limits,
		}),
		text: KernelPdfText.Limits.make({ max_actual_text_scalars: 1000000, max_content_bytes: 16000000, max_mappings: 10000, max_placements: 0, max_source_scalars: 16000000 }),
	}),
	pages: KernelFacadePages.Limits.make({
		max_blocks: 16384,
		max_rows: 1000000,
		page: KernelPageLayout.Limits.make({ max_blocks: 16384, max_fragments: 1000000, max_lines: 1000000, max_pages: 1024, max_placements: 1000000 }),
	}),
	scenes: KernelFacadeScenes.Limits.make({
		color: KernelColor.Limits.make({ max_icc_bytes: KernelSrgbProfile.byte_count, max_profiles: 1, max_spaces: 2, max_tags: KernelSrgbProfile.tag_count }),
		max_commands: 2000000,
		max_groups: 1000000,
		max_page_group_edges: 1000000,
		max_pages: 1024,
		scene: KernelScene.Limits.make({ max_commands: 2000000, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 1000000, max_pages: 1024, max_path_segments: 1000000, max_paths: 1000000 }),
	}),
	semantics: KernelFacadeSemantics.Limits.make({
		max_container_depth: 16,
		max_content_spine: 65536,
		max_inline_depth: 8,
		max_nodes: 16384,
		max_occurrences: 16384,
		max_properties: 16384,
		max_source_inputs: 16384,
		semantics: KernelSemantics.Limits.make({ max_attributes: 65536, max_content_spine: 65536, max_fragments: 0, max_namespaces: 2, max_nodes: 16384, max_occurrences: 16384, max_semantic_depth: 48 }),
		sources: KernelFacadeSources.Limits.make({
			max_hash_probes: 4000000,
			max_inputs: 16384,
			max_source_bytes: 1000000,
			max_source_scalars: 1000000,
			max_table_slots: 65536,
			max_unique_sources: 16384,
			unicode: { max_graphemes: 1000000, max_line_boundaries: 1000001, max_scalars: 1000000, max_script_runs: 2048 },
		}),
		text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 16384, max_text_property_bytes: 1000000, max_text_source_bytes: 1000000, max_text_source_scalars: 1000000, max_text_sources: 16384 }),
	}),
	shape: KernelFacadeShape.Limits.make({ max_requests: 65536, shape: KernelShape.Limits.make({ max_clusters: 1000000, max_glyphs: 1000000, max_scalars: 1000000, max_source_bytes: 1000000 }) }),
	text: KernelFacadeText.Limits.make({ max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_pages: 1024, max_placements: 1000000, max_runs: 1000000 }),
})

object_limits : KernelObject.Limits
object_limits = {
	max_array_items: 4000000,
	max_byte_string_bytes: 8388608,
	max_byte_strings: 1000000,
	max_dictionary_entries: 4000000,
	max_direct_depth: 8,
	max_name_bytes: 8388608,
	max_names: 1000000,
	max_objects: 65536,
	max_payload_bytes: 16000000,
	max_payloads: 100000,
	max_streams: 100000,
	max_text_string_bytes: 1000000,
	max_text_strings: 16384,
	max_values: 4000000,
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "page-template evidence index escaped"
}
