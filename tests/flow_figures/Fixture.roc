import pdf.Color
import pdf.Conformance
import pdf.Document
import pdf.Font
import pdf.Image
import pdf.KernelBuiltInFont
import pdf.KernelColor
import pdf.KernelContent
import pdf.KernelFacadeFragments
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
import "../assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)
import "../assets/NotoSansMono-Code-Fixture.ttf" as mono_font_bytes : List(U8)

## Flow figures and decorations through the public `Pdf` constructors
## (`reference-documents-v7`).
##
## - `report`: the reference report's figures under page templates: a
##   grouped vector bar chart and a raster photograph with captions, an
##   uncaptioned vector mark, a 600 × 900 pt drawing scaled to fit with
##   `ScaleToFit({ minimum_percent: 50 })`, and full-width decoration rules
##   between sections.
## - `sections xN`: N sections, each a heading, a paragraph, a decoration
##   rule, and a captioned grouped vector chart. The 10/100 pair is the
##   linear scale pair.
## - `label_faces xN`: N charts whose title is set in the theme's `Strong`
##   face, tick values in its `Code` face, and region names in the body
##   face (`Scene.Drawing.text_in`), under style faces: the packaged face
##   for the body, the caller fixture face for `Strong`, and the monospace
##   fixture for `Code`. No body text uses either role face, so the label
##   faces must join the output fonts on their own. The title's text also
##   appears as a body-face label, so one interned source is shaped in two
##   faces (the fixture `Strong` face covers only `CDFPafé`, so the title
##   is "Café"). It rejects a `Code` label the monospace face does not cover
##   (`text.coverage_missing` at the figure). The 10/50 pair is the linear
##   scale pair.
## - `labels xN`: N sections whose bar chart carries text labels (region
##   names centered under the bars, tick values right-aligned beside the
##   axis, an axis title), a labelled 600 × 900 pt plan scaled to fit (its
##   labels scale with it), and a custom block whose panel is labelled.
##   Labels are `Decoration` artifact text in the body face; the 10/50 pair
##   is the linear scale pair. Its rejections: a label wider than its
##   drawing, a label the face does not cover, a label in another script,
##   an empty label, a labelled decoration, a labelled furniture drawing,
##   and labels under an ordered font policy.
## - `spaced_decorations xN`: N sections, each a divider rule with 12 pt
##   above and 6 pt below it (no empty drawing area), and a heading over a
##   tinted band that overlaps the heading by its full height and paints
##   behind its text. Rejections: negative space above, and an overlap
##   deeper than the drawing (`layout.decoration_drawing`). The 10/100 pair
##   is the linear scale pair.
## - `bound_diagnostics`: a figure, a decoration, and a furniture drawing
##   whose path reaches below or left of the origin through its own
##   geometry, a Bézier control point, or only its stroke's half-width;
##   each diagnostic names the command, the cause, and the coordinate. The
##   same curve moved inside the origin by a group is accepted.
## - `atomic_negatives`: every figure and decoration rejection with its
##   stable dotted code and authored path, and no bytes.
##
## Bytes always come from `Pdf.to_bytes_with` (the default `Archive`
## profile). Work comes from one additional facade pipeline probe, through
## scenes, over the same normalized authoring.
Fixture :: [].{
	EvidenceError : [EvidenceFailure, InvalidScale, MissingRejection(U64)]

	report : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	report = |context| evidence(report_document(context))

	sections : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	sections = |count| {
		if count == 0 or count > 100 {
			return Err(InvalidScale)
		}
		evidence(sections_document(count))
	}

	bound_diagnostics : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	bound_diagnostics = |context| run_bound_diagnostics(context)

	spaced_decorations : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	spaced_decorations = |count| {
		if count == 0 or count > 100 {
			return Err(InvalidScale)
		}
		run_spaced_decorations(count)
	}

	labels : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	labels = |count| run_labels(count)

	label_faces : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	label_faces = |count| run_label_faces(count)

	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |context| run_negatives(context)
}

## The region names under the labelled chart's bar pairs.
region_names : List(Str)
region_names = ["Hobart", "Launceston", "Moonah", "Fremantle"]

## `bar_chart` with its labels: each region's name centered under its bar
## pair, tick values right-aligned left of the axis every 50, and an axis
## title above the axis.
labelled_chart : I64, List((I64, I64)) -> Scene.Drawing
labelled_chart = |height, pairs| {
	var $chart = bar_chart(height, pairs)
	var $index = 0
	for name in region_names {
		$chart = $chart.text({ align: Center, color: ink, origin: Layout.point(48 + $index * 108 + 38, 8), size: 8, text: name })
		$index = $index + 1
	}
	var $tick = 0
	while $tick * 50 + 20 < height - 12 {
		$chart = $chart.text({ align: End, color: ink, origin: Layout.point(20, 18 + $tick * 50), size: 7, text: ($tick * 50).to_str() })
		$tick = $tick + 1
	}
	$chart.text({ align: Start, color: sea, origin: Layout.point(28, height - 10), size: 8, text: "AUD thousands" })
}

## The site plan with a label in every bay, scaled with the plan.
labelled_plan : Scene.Drawing
labelled_plan = {
	var $plan = site_plan
	var $row = 0
	while $row < 4 {
		var $column = 0
		while $column < 3 {
			$plan = $plan.text({ align: Center, color: Color.srgb8({ blue: 255, green: 255, red: 255 }), origin: Layout.point(60 + $column * 180 + 60, 40 + $row * 210 + 70), size: 24, text: "Bay ${($row * 3 + $column + 1).to_str()}" })
			$column = $column + 1
		}
		$row = $row + 1
	}
	$plan
}

labels_document : U64 -> Document
labels_document = |count| {
	var $contents = List.with_capacity(count * 4 + 4)
	$contents = $contents.append(Pdf.title("Labelled figures"))
	var $index = 0
	while $index < count {
		number = ($index + 1).to_str()
		shifted = regions.map(|(previous, current)| (previous // 2 + ($index % 7).to_i64_wrap(), current // 2 + ($index % 5).to_i64_wrap()))
		$contents = $contents
			.append(Pdf.heading(1, "Region ${number}"))
			.append(paragraph($index))
			.append(Pdf.figure({ drawing: labelled_chart(140, shifted), alt: "Bar chart ${number}: revenue grew in Hobart, Launceston, Moonah, and Fremantle.", caption: Pdf.caption("Figure ${number}. Revenue by yard, AUD thousands") }))
		$index = $index + 1
	}
	panel = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 300, 70), Color.srgb8({ blue: 230, green: 240, red: 245 }))
		.text({ align: End, color: sea, origin: Layout.point(292, 58), size: 7, text: "KEY FIGURES" })
	callout = Pdf.custom_block({ contents: [Pdf.paragraph("Kiln capacity rose by a third.")], inset: 10, name: "Key figures", panel, size: { height: 70, width: 300 } })
	plan = Pdf.figure({ drawing: labelled_plan, alt: "Plan of the Moonah yard: twelve numbered drying bays in four rows of three.", caption: Pdf.caption("Moonah yard plan, scaled to fit."), fit: ScaleToFit({ minimum_percent: 50 }) })
	Pdf.document({ contents: $contents.append(callout).append(plan), language: "en-AU", title: "Labelled figures" })
}

run_labels : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_labels = |count| {
	if count == 0 or count > 100 {
		return Err(InvalidScale)
	}
	document = labels_document(count)
	result = evidence(document)?
	number = count.to_str()
	document_of = |contents| Pdf.document({ contents, language: "en-AU", title: "Label negatives ${number}" })
	labelled = |text| Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 60, 30), oak).text({ align: Start, color: ink, origin: Layout.point(4, 8), size: 8, text })
	figure = |drawing| Pdf.figure({ drawing: drawing, alt: "A labelled mark", caption: Pdf.no_caption })
	furniture = Pdf.region({ height: 16, start: [Pdf.furniture_image(labelled("Mark"))] })
	checks = [
		rejects(document_of([Pdf.paragraph("Lead"), figure(labelled("A label far wider than its drawing"))]), LayoutConstraintViolated, "layout.drawing_label_bounds", ["contents[1]"]),
		rejects(document_of([Pdf.paragraph("Lead"), figure(labelled("中"))]), FontCoverageMissing, "text.unsupported_script", ["contents[1]"]),
		rejects(document_of([Pdf.paragraph("Lead"), figure(labelled("ƀ"))]), FontCoverageMissing, "text.coverage_missing", ["contents[1]"]),
		rejects(document_of([Pdf.paragraph("Lead"), figure(labelled(""))]), InvalidRelationship, "document.figure_drawing", ["contents[1]"]),
		rejects(document_of([Pdf.paragraph("Lead"), Pdf.decoration({ drawing: labelled("Mark") }), Pdf.paragraph("Body")]), InvalidRelationship, "layout.decoration_drawing", ["contents[1]"]),
		rejects(document_of([Pdf.paragraph("Body")]).with_page_templates({ continuation: Pdf.page_template({ gap: 12, header: furniture }), first: Pdf.first_page_template({ gap: 12, header: furniture }) }), InvalidRelationship, "layout.furniture_drawing", ["templates.first.header.start[0]"]),
	]
	passed = checks.sum()
	if passed != checks.len() {
		return Err(MissingRejection(passed))
	}
	policy_rejected = match Font.Registry.empty.register_built_in(if count > 0 Font.ValidationLimits.default else Font.ValidationLimits.make({ max_bytes: 0, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 })) {
		Err(_) => 0
		Ok(registered) => {
			options = Pdf.Options.{ theme: { ..report_theme, font_selection: Policy(registered.policy) }, fonts: Registered(registered.registry) }
			match Pdf.to_bytes_with(document_of([Pdf.paragraph("Lead"), figure(labelled("Mark"))]), options) {
				Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, feature: Feature("text.drawing_label_policy"), .. }], .. })) => 1
				_ => 0
			}
		}
	}
	if policy_rejected != 1 {
		return Err(MissingRejection(passed))
	}
	Ok({ bytes: result.bytes, work: result.work.append(passed + policy_rejected) })
}

## The body face (packaged), a `Strong` face, and a `Code` face.
label_face_options : U64 -> Try(Pdf.Options, Fixture.EvidenceError)
label_face_options = |context| {
	limits = if context > 0 Font.ValidationLimits.default else Font.ValidationLimits.make({ max_bytes: 0, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 })
	body = Font.Registry.empty.register_built_in(limits) ? |_| EvidenceFailure
	strong = body.registry.register(caller_font_bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits) ? |_| EvidenceFailure
	code = strong.registry.register(mono_font_bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits) ? |_| EvidenceFailure
	theme = { ..report_theme, face: body.face, inline: { ..report_theme.inline, code: { ..report_theme.inline.code, font: Face(code.face) }, strong: { ..report_theme.inline.strong, font: Face(strong.face) } } }
	Ok(Pdf.Options.{ theme: theme, fonts: Registered(code.registry) })
}

## A chart titled in the `Strong` face, with tick values in the `Code`
## face and region names (and a repeat of the title) in the body face.
faced_chart : I64, List((I64, I64)) -> Scene.Drawing
faced_chart = |height, pairs| {
	var $chart = bar_chart(height, pairs)
	var $index = 0
	for name in region_names {
		$chart = $chart.text({ align: Center, color: ink, origin: Layout.point(48 + $index * 108 + 38, 8), size: 8, text: name })
		$index = $index + 1
	}
	var $tick = 0
	while $tick * 50 + 20 < height - 22 {
		$chart = $chart.text_in(Code, { align: End, color: ink, origin: Layout.point(20, 18 + $tick * 50), size: 7, text: ($tick * 50).to_str() })
		$tick = $tick + 1
	}
	$chart
		.text_in(Strong, { align: Start, color: sea, origin: Layout.point(28, height - 12), size: 9, text: "Café" })
		.text({ align: End, color: sea, origin: Layout.point(475, height - 12), size: 7, text: "Café" })
}

label_faces_document : U64 -> Document
label_faces_document = |count| {
	var $contents = List.with_capacity(count * 3 + 1)
	$contents = $contents.append(Pdf.title("Labels in their faces"))
	var $index = 0
	while $index < count {
		number = ($index + 1).to_str()
		shifted = regions.map(|(previous, current)| (previous // 2 + ($index % 7).to_i64_wrap(), current // 2 + ($index % 5).to_i64_wrap()))
		$contents = $contents
			.append(paragraph($index))
			.append(Pdf.figure({ drawing: faced_chart(150, shifted), alt: "Bar chart ${number}: yard revenue grew in Hobart, Launceston, Moonah, and Fremantle.", caption: Pdf.caption("Figure ${number}. Yard revenue, AUD thousands") }))
		$index = $index + 1
	}
	Pdf.document({ contents: $contents, language: "en-AU", title: "Labels in their faces" })
}

## Labels per face across the document's figures: body, `Strong`, `Code`.
face_counts : Document -> { body : U64, code : U64, strong : U64 }
face_counts = |document| {
	var $counts = { body: 0, code: 0, strong: 0 }
	for figure in Document.normalize(document).figures {
		match figure.drawing {
			ValidDrawing(value) => {
				for command in value.commands {
					match command {
						FlowText(boxed) => {
							$counts = match Box.unbox(boxed).face {
								BodyFace => { ..$counts, body: $counts.body + 1 }
								RoleFace(Code) => { ..$counts, code: $counts.code + 1 }
								RoleFace(Strong) => { ..$counts, strong: $counts.strong + 1 }
								RoleFace(_) => $counts
							}
						}
						_ => {}
					}
				}
			}
			InvalidDrawing(_) => {}
		}
	}
	$counts
}

run_label_faces : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_label_faces = |count| {
	if count == 0 or count > 100 {
		return Err(InvalidScale)
	}
	options = label_face_options(count)?
	document = label_faces_document(count)
	bytes = Pdf.to_bytes_with(document, options) ? |_| EvidenceFailure
	font = KernelFont.inspect(KernelBuiltInFont.bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })) ? |_| EvidenceFailure
	flow = KernelFacadePipeline.probe(Document.normalize(document), font, report_theme, page_size, descriptor, pipeline_limits, ScenesReady) ? |_| EvidenceFailure
	counts = face_counts(document)
	uncovered = Pdf.document({
		contents: [Pdf.paragraph("Lead"), Pdf.figure({ drawing: Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 60, 30), oak).text_in(Code, { align: Start, color: ink, origin: Layout.point(4, 8), size: 8, text: "é${count.to_str()}" }), alt: "A labelled mark", caption: Pdf.no_caption })],
		language: "en-AU",
		title: "Uncovered code label",
	})
	rejected = match Pdf.to_bytes_with(uncovered, options) {
		Err(InvalidDocument({ diagnostics: [{ code: FontCoverageMissing, details: ["contents[1]"], feature: Feature("text.coverage_missing"), .. }], truncation: Complete, .. })) => 1
		_ => 0
	}
	if rejected != 1 {
		return Err(MissingRejection(rejected))
	}
	Ok({ bytes, work: [flow.lines, flow.pages, flow.fragments, flow.scene_commands, counts.body, counts.strong, counts.code, bytes.len(), rejected] })
}

## The reference report theme: an A4 body frame of 483 × 746 pt.
report_theme : Theme
report_theme = Theme.{ page_margin: { bottom: 48, left: 56, right: 56, top: 48 } }

ink : Color.SourceValue
ink = Color.srgb8({ blue: 40, green: 40, red: 40 })

oak : Color.SourceValue
oak = Color.srgb8({ blue: 60, green: 130, red: 190 })

sea : Color.SourceValue
sea = Color.srgb8({ blue: 140, green: 90, red: 20 })

## A full-width divider: a 0.75 pt rule 6 pt above the next block.
divider : Scene.Drawing
divider = Scene.Drawing.empty.rectangle({ origin: Layout.point(0, 6), size: { height: 0.75, width: 483 } }, sea)

## One region's paired bars, drawn from the group's own origin.
bar_pair : I64, I64 -> Scene.Drawing
bar_pair = |previous, current| Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 36, previous), sea).rectangle(Layout.rect(40, 0, 36, current), oak)

## A grouped vector bar chart `height` tall and 483 pt wide: two axes and
## one translated group of paired bars per region.
bar_chart : I64, List((I64, I64)) -> Scene.Drawing
bar_chart = |height, pairs| {
	axes = Scene.Drawing.empty
		.path(Scene.PathBuilder.start.move_to(Layout.point(24, 20)).line_to(Layout.point(480, 20)).finish(), Scene.solid_stroke(ink, 1))
		.path(Scene.PathBuilder.start.move_to(Layout.point(24, 20)).line_to(Layout.point(24, height - 1)).finish(), Scene.solid_stroke(ink, 1))
	var $chart = axes
	var $index = 0
	for (previous, current) in pairs {
		$chart = $chart.group(Layout.point(48 + $index * 108, 21), bar_pair(previous, current))
		$index = $index + 1
	}
	$chart
}

## An 8 × 4 sRGB raster in two bands.
photo_image : Image.Source
photo_image = {
	band = |red, green, blue| List.repeat([red, green, blue], 8).join()
	pixels = [band(150, 110, 70), band(170, 130, 90), band(90, 120, 60), band(60, 90, 40)].join()
	Image.Source.rgb8({ alpha: NoAlpha, dimensions: { height: 4, width: 8 }, pixels, row_stride: 24 })
}

## A small vector mark: a filled square with a stroked diagonal.
leaf_mark : Scene.Drawing
leaf_mark = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 48, 48), oak)
	.path(Scene.PathBuilder.start.move_to(Layout.point(8, 8)).line_to(Layout.point(40, 40)).finish(), Scene.solid_stroke(ink, 2))

## A 600 × 900 pt plan drawing: a frame and a grouped grid of cells.
site_plan : Scene.Drawing
site_plan = {
	cell = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 120, 160), sea)
	var $plan = Scene.Drawing.empty.path(Scene.PathBuilder.start.rectangle(Layout.rect(4, 4, 592, 892)).finish(), Scene.solid_stroke(ink, 4))
	var $row = 0
	while $row < 4 {
		var $column = 0
		var $cells = Scene.Drawing.empty
		while $column < 3 {
			$cells = $cells.group(Layout.point($column * 180, 0), cell)
			$column = $column + 1
		}
		$plan = $plan.group(Layout.point(60, 40 + $row * 210), $cells)
		$row = $row + 1
	}
	$plan
}

sentences : List(Str)
sentences = [
	"Harbour & Finch sourced 18,400 cubic metres of plantation and recovered timber during the year.",
	"Revenue grew in every region, led by the Tasmanian yards and the new Fremantle joinery.",
	"Kiln capacity at Moonah rose by a third after the second chamber was commissioned in March.",
	"Recovered timber now makes up a fifth of the oak supplied to fit-out customers.",
]

paragraph : U64 -> Document.Block
paragraph = |index| {
	start = index % sentences.len()
	var $text = ""
	var $offset = 0
	while $offset < 3 {
		sentence = match sentences.get((start + $offset) % sentences.len()) {
			Ok(value) => value
			Err(OutOfBounds) => crash "report sentence escaped"
		}
		$text = if $offset == 0 sentence else "${$text} ${sentence}"
		$offset = $offset + 1
	}
	Pdf.paragraph($text)
}

regions : List((I64, I64))
regions = [(120, 150), (90, 118), (60, 84), (140, 176)]

report_document : U64 -> Document
report_document = |context| {
	title = if context == 0 "Annual timber report" else "Annual timber report!"
	photo = Scene.Drawing.empty.image(photo_image, Layout.rect(0, 0, 320, 160))
	contents = [
		Pdf.title(title),
		paragraph(0),
		Pdf.section([
			Pdf.heading(1, "1 Revenue by region"),
			paragraph(1),
			Pdf.figure({ drawing: bar_chart(220, regions), alt: "Bar chart comparing revenue in four regions for two years: every region grew, the Tasmanian yards most; Table 1 gives the exact values.", caption: Pdf.caption("Figure 1. Revenue by region, AUD thousands") }),
			paragraph(2),
			Pdf.figure({ drawing: leaf_mark, alt: "The Harbour & Finch leaf mark", caption: Pdf.no_caption }),
		]),
		Pdf.decoration({ drawing: divider }),
		Pdf.section([
			Pdf.heading(1, "2 Timber sourcing"),
			paragraph(3),
			Pdf.figure({ drawing: photo, alt: "Stacked Tasmanian oak boards air-drying under cover at the Moonah yard.", caption: Pdf.caption("Figure 2. Air-drying boards at the Moonah yard.") }),
			paragraph(0),
			paragraph(1),
		]),
		Pdf.decoration({ drawing: divider }),
		Pdf.section([
			Pdf.heading(1, "3 Site plan"),
			paragraph(2),
			Pdf.figure({ drawing: site_plan, alt: "Plan of the Moonah yard: twelve drying bays in four rows of three inside the yard boundary.", caption: Pdf.caption("Figure 3. Moonah yard plan, scaled to fit."), fit: ScaleToFit({ minimum_percent: 50 }) }),
			paragraph(3),
		]),
	]
	page_of = Pdf.reserved_width(64, End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])
	footer = Pdf.region({ end: [Pdf.furniture_text([page_of])], height: 16 })
	Pdf.document({
		contents,
		language: "en-AU",
		title,
		page_templates: Templates({
			continuation: Pdf.page_template({ footer, gap: 12, header: Pdf.region({ height: 16, start: [Pdf.furniture_text([Pdf.text("Harbour & Finch — Annual timber report")])] }) }),
			first: Pdf.first_page_template({ footer, gap: 12 }),
		}),
	})
}

sections_document : U64 -> Document
sections_document = |count| {
	var $contents = List.with_capacity(count * 5 + 1)
	$contents = $contents.append(Pdf.title("Regional figures"))
	var $index = 0
	while $index < count {
		number = ($index + 1).to_str()
		shifted = regions.map(|(previous, current)| (previous // 2 + ($index % 7).to_i64_wrap(), current // 2 + ($index % 5).to_i64_wrap()))
		$contents = $contents
			.append(Pdf.decoration({ drawing: divider }))
			.append(Pdf.heading(1, "Region ${number}"))
			.append(paragraph($index))
			.append(Pdf.figure({ drawing: bar_chart(120, shifted), alt: "Bar chart ${number}: revenue grew in all four yards.", caption: Pdf.caption("Figure ${number}. Revenue by yard, AUD thousands") }))
		$index = $index + 1
	}
	Pdf.document({ contents: $contents, language: "en-AU", title: "Regional figures" })
}

run_bound_diagnostics : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_bound_diagnostics = |context| {
	offset = (context % 1).to_i64_wrap()
	solid = Scene.solid_fill(oak)
	mark = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 20, 20), oak)
	below = mark.path(Scene.PathBuilder.start.move_to(Layout.point(0, 0)).line_to(Layout.point(10, -2 + offset)).line_to(Layout.point(10, 10)).close().finish(), solid)
	curve = mark.path(Scene.PathBuilder.start.move_to(Layout.point(0, 0)).cubic_to({ control_1: Layout.point(-4, 5), control_2: Layout.point(-4, 15), end: Layout.point(0, 20) }).close().finish(), solid)
	stroked = mark.path(Scene.PathBuilder.start.move_to(Layout.point(0, 2)).line_to(Layout.point(20, 2)).finish(), Scene.solid_stroke(oak, 2))
	grouped = Scene.Drawing.empty.group(Layout.point(5, 5), curve)
	message_of = |result| match result {
		Err(InvalidDocument({ diagnostics: [{ message, .. }], .. })) => message
		_ => ""
	}
	options = Pdf.Options.{ theme: report_theme }
	figure = |drawing| message_of(Pdf.to_bytes_with(Pdf.document({ contents: [Pdf.figure({ drawing: drawing, alt: "A mark", caption: Pdf.no_caption })], language: "en-AU", title: "Bounds" }), options))
	decoration = |drawing| message_of(Pdf.to_bytes_with(Pdf.document({ contents: [Pdf.decoration({ drawing: drawing }), Pdf.paragraph("Body")], language: "en-AU", title: "Bounds" }), options))
	furniture = |drawing| {
		header = Pdf.region({ height: 40, start: [Pdf.furniture_image(drawing)] })
		message_of(
			Pdf.to_bytes_with(
				Pdf.document({
					contents: [Pdf.paragraph("Body")],
					language: "en-AU",
					title: "Bounds",
					page_templates: Templates({ continuation: Pdf.page_template({ gap: 12, header }), first: Pdf.first_page_template({ gap: 12, header }) }),
				}),
				options,
			),
		)
	}
	checks = [
		figure(below).contains("command 1 (a path) has a point at (10 pt, -2 pt)"),
		figure(curve).contains("command 1 (a path) has a Bézier control point at (-4 pt, 5 pt)"),
		figure(stroked).contains("its stroke's half-width of 1 pt reaches (-1 pt, 1 pt)"),
		figure(grouped) == "",
		decoration(curve).contains("Bézier control point at (-4 pt, 5 pt)"),
		furniture(curve).contains("command 1 (a path) has a Bézier control point at (-4 pt, 5 pt)"),
		furniture(stroked).contains("stroke's half-width of 1 pt"),
	]
	passed = checks.keep_if(|held| held).len()
	if passed != checks.len() {
		return Err(MissingRejection(passed))
	}
	bytes = Pdf.to_bytes_with(Pdf.document({ contents: [Pdf.title("Drawing bounds"), Pdf.figure({ drawing: Scene.Drawing.empty.group(Layout.point(4, 0), curve), alt: "A curved mark moved inside the origin", caption: Pdf.no_caption })], language: "en-AU", title: "Drawing bounds" }), options) ? |_| EvidenceFailure
	Ok({ bytes, work: [passed, bytes.len()] })
}

spaced_document : U64 -> Document
spaced_document = |count| {
	band = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 483, 22), Color.srgb8({ blue: 200, green: 225, red: 240 }))
	rule = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 483, 1), oak)
	var $contents = List.with_capacity(count * 5 + 1)
	$contents = $contents.append(Pdf.title("Spaced decorations"))
	var $index = 0
	while $index < count {
		number = ($index + 1).to_str()
		$contents = $contents
			.append(Pdf.decoration({ drawing: rule, above: 12, below: 6 }))
			.append(Pdf.decoration({ drawing: band, layer: Behind, below: -22 }))
			.append(Pdf.heading(1, "  Region ${number}"))
			.append(paragraph($index))
		$index = $index + 1
	}
	Pdf.document({ contents: $contents, language: "en-AU", title: "Spaced decorations" })
}

run_spaced_decorations : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_spaced_decorations = |count| {
	evidenced = evidence(spaced_document(count))?
	rule = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 100, 2), oak)
	document = |block| Pdf.document({ contents: [Pdf.paragraph("Lead ${count.to_str()}"), block, Pdf.paragraph("Body")], language: "en-AU", title: "Spacing negatives" })
	checks = [
		rejects(document(Pdf.decoration({ drawing: rule, above: -1 })), InvalidRelationship, "layout.decoration_drawing", ["contents[1]"]),
		rejects(document(Pdf.decoration({ drawing: rule, layer: Behind, below: -3 })), InvalidRelationship, "layout.decoration_drawing", ["contents[1]"]),
	]
	rejections = checks.sum()
	if rejections != checks.len() {
		return Err(MissingRejection(rejections))
	}
	Ok({ bytes: evidenced.bytes, work: evidenced.work.append(rejections) })
}

## Bytes come from `Pdf.to_bytes_with`; work comes from one facade pipeline
## probe through scenes over the same normalized authoring.
evidence : Document -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
evidence = |document| {
	bytes = Pdf.to_bytes_with(document, Pdf.Options.{ theme: report_theme }) ? |_| EvidenceFailure
	font = KernelFont.inspect(KernelBuiltInFont.bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })) ? |_| EvidenceFailure
	normalized = Document.normalize(document)
	figures = normalized.figures.len()
	decorations = normalized.decorations.len()
	flow = KernelFacadePipeline.probe(normalized, font, report_theme, page_size, descriptor, pipeline_limits, ScenesReady) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			flow.lines,
			flow.pages,
			flow.fragments,
			flow.scene_commands,
			figures,
			decorations,
			bytes.len(),
		],
	})
}

page_size : Layout.Size
page_size = { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) }

descriptor : KernelPdfFont.Descriptor
descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

rejects : Document, Conformance.DiagnosticCode, Str, List(Str) -> U64
rejects = |document, expected_code, expected_feature, expected_paths| match Pdf.to_bytes_with(document, Pdf.Options.{ theme: report_theme }) {
	Err(InvalidDocument({ diagnostics: [{ code, details, feature: Feature(feature), location: Document, stage: AuthoringValidation, .. }], truncation: Complete, .. })) => if code == expected_code and feature == expected_feature and details == expected_paths 1 else 0
	_ => 0
}

## Each document differs from a valid one in one figure or decoration
## fact. Every rejection is transactional: a stable code, the authored
## path of each participating source, and no bytes.
run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_negatives = |context| {
	title = if context == 0 "Figure negatives" else "guarded"
	offset = (context % 1).to_i64_wrap()
	document = |contents| Pdf.document({ contents, language: "en-AU", title })
	tall = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 600, 900 + offset), oak)
	wide = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 500 + offset, 40), oak)
	nested = |depth| {
		var $drawing = leaf_mark
		var $level = 0
		while $level < depth {
			$drawing = Scene.Drawing.empty.group(Layout.point(1, 1), $drawing)
			$level = $level + 1
		}
		$drawing
	}
	figure = |drawing, caption| Pdf.figure({ drawing: drawing, alt: "A plan drawing", caption: caption })
	lead_templates = {
		continuation: Pdf.page_template({ gap: 12, header: Pdf.region({ height: 16, start: [Pdf.furniture_text([Pdf.text("Header")])] }) }),
		first: Pdf.first_page_template({ gap: 12, lead: Pdf.lead_region(60, [Pdf.paragraph("Letterhead"), Pdf.decoration({ drawing: divider }), Pdf.paragraph("Address")]) }),
	}
	checks = [
		rejects(document([Pdf.paragraph("Lead"), figure(tall, Pdf.caption("Figure 1."))]), LayoutConstraintViolated, "document.figure_oversize", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), Pdf.figure({ drawing: tall, alt: "A plan drawing", caption: Pdf.caption("Figure 1."), fit: ScaleToFit({ minimum_percent: 90 }) })]), LayoutConstraintViolated, "document.figure_oversize", ["contents[1]"]),
		rejects(document([Pdf.section([Pdf.paragraph("Lead"), figure(wide, Pdf.no_caption)])]), LayoutConstraintViolated, "document.figure_oversize", ["contents[0].contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), Pdf.figure({ drawing: leaf_mark, alt: "", caption: Pdf.caption("Figure 2.") })]), InvalidRelationship, "document.figure_alternative_empty", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), figure(Scene.Drawing.empty, Pdf.no_caption)]), InvalidRelationship, "document.figure_drawing", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), figure(nested(9), Pdf.no_caption)]), InvalidRelationship, "document.figure_drawing", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), figure(leaf_mark, Pdf.caption(""))]), InvalidRelationship, "document.figure_caption_empty", ["contents[1].caption"]),
		rejects(document([Pdf.paragraph("Lead"), Pdf.figure({ drawing: leaf_mark, alt: "A plan drawing", caption: Pdf.no_caption, fit: ScaleToFit({ minimum_percent: 101 }) })]), InvalidRelationship, "document.figure_fit", ["contents[1]"]),
		rejects(document([Pdf.section([Pdf.paragraph("Lead"), Pdf.figure({ drawing: leaf_mark, alt: "A plan drawing", caption: Pdf.no_caption, fit: ScaleToFit({ minimum_percent: 255 }) })])]), InvalidRelationship, "document.figure_fit", ["contents[0].contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), Pdf.decoration({ drawing: divider })]), LayoutConstraintViolated, "layout.decoration_position", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Body")]).with_page_templates(lead_templates), LayoutConstraintViolated, "layout.decoration_position", ["templates.first.lead.contents[1]"]),
		rejects(document([Pdf.decoration({ drawing: Scene.Drawing.empty }), Pdf.paragraph("Body")]), InvalidRelationship, "layout.decoration_drawing", ["contents[0]"]),
		rejects(document([Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("Item"), Pdf.decoration({ drawing: divider })])]), Pdf.paragraph("Body")]), InvalidRelationship, "semantics.list_item_content", ["contents[0].items[0].contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), Pdf.decoration({ drawing: tall }), Pdf.paragraph("Body")]), LayoutConstraintViolated, "layout.oversize_block", ["contents[1]"]),
	]
	passed = checks.sum()
	if passed != checks.len() {
		return Err(MissingRejection(passed))
	}
	carrier = Pdf.to_bytes_with(document([Pdf.title("Figure carrier"), Pdf.figure({ drawing: leaf_mark, alt: "The Harbour & Finch leaf mark", caption: Pdf.no_caption })]), Pdf.Options.{ theme: report_theme }) ? |_| EvidenceFailure
	Ok({ bytes: carrier, work: [passed, carrier.len()] })
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
