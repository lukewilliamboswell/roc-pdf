import pdf.Color
import pdf.Conformance
import pdf.Document
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

	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |context| run_negatives(context)
}

points : I64 -> Layout.Unit
points = |value| Layout.Unit.points(value)

## The reference report theme: an A4 body frame of 483 × 746 pt.
report_theme : Theme
report_theme = Theme.with_page_margin(Theme.default, { bottom: points(48), left: points(56), right: points(56), top: points(48) })

ink : Color.SourceValue
ink = Color.srgb8({ blue: 40, green: 40, red: 40 })

oak : Color.SourceValue
oak = Color.srgb8({ blue: 60, green: 130, red: 190 })

sea : Color.SourceValue
sea = Color.srgb8({ blue: 140, green: 90, red: 20 })

## A full-width divider: a 0.75 pt rule 6 pt above the next block.
divider : Scene.Drawing
divider = Scene.rectangle(Scene.drawing({}), { origin: Layout.point(0, 6), size: { height: Layout.Unit.millipoints(750), width: points(483) } }, sea)

## One region's paired bars, drawn from the group's own origin.
bar_pair : I64, I64 -> Scene.Drawing
bar_pair = |previous, current| Scene.rectangle(Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 36, previous), sea), Layout.rect(40, 0, 36, current), oak)

## A grouped vector bar chart `height` tall and 483 pt wide: two axes and
## one translated group of paired bars per region.
bar_chart : I64, List((I64, I64)) -> Scene.Drawing
bar_chart = |height, regions| {
	axes = Scene.drawing({})
		.path(Scene.path({}).move_to(Layout.point(24, 20)).line_to(Layout.point(480, 20)).finish(), Scene.solid_stroke(ink, points(1)))
		.path(Scene.path({}).move_to(Layout.point(24, 20)).line_to(Layout.point(24, height - 1)).finish(), Scene.solid_stroke(ink, points(1)))
	var $chart = axes
	var $index = 0
	for (previous, current) in regions {
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
leaf_mark = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 48, 48), oak)
	.path(Scene.path({}).move_to(Layout.point(8, 8)).line_to(Layout.point(40, 40)).finish(), Scene.solid_stroke(ink, points(2)))

## A 600 × 900 pt plan drawing: a frame and a grouped grid of cells.
site_plan : Scene.Drawing
site_plan = {
	cell = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 120, 160), sea)
	var $plan = Scene.drawing({}).path(Scene.path({}).rectangle(Layout.rect(4, 4, 592, 892)).finish(), Scene.solid_stroke(ink, points(4)))
	var $row = 0
	while $row < 4 {
		var $column = 0
		var $cells = Scene.drawing({})
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
	photo = Scene.drawing({}).image(photo_image, Layout.rect(0, 0, 320, 160))
	contents = [
		Pdf.title(title),
		paragraph(0),
		Pdf.section([
			Pdf.heading(1, "1 Revenue by region"),
			paragraph(1),
			Pdf.figure(bar_chart(220, regions), "Bar chart comparing revenue in four regions for two years: every region grew, the Tasmanian yards most; Table 1 gives the exact values.", Pdf.caption("Figure 1. Revenue by region, AUD thousands")),
			paragraph(2),
			Pdf.figure(leaf_mark, "The Harbour & Finch leaf mark", Pdf.no_caption),
		]),
		Pdf.decoration(divider),
		Pdf.section([
			Pdf.heading(1, "2 Timber sourcing"),
			paragraph(3),
			Pdf.figure(photo, "Stacked Tasmanian oak boards air-drying under cover at the Moonah yard.", Pdf.caption("Figure 2. Air-drying boards at the Moonah yard.")),
			paragraph(0),
			paragraph(1),
		]),
		Pdf.decoration(divider),
		Pdf.section([
			Pdf.heading(1, "3 Site plan"),
			paragraph(2),
			Pdf.figure_fit(Pdf.figure(site_plan, "Plan of the Moonah yard: twelve drying bays in four rows of three inside the yard boundary.", Pdf.caption("Figure 3. Moonah yard plan, scaled to fit.")), ScaleToFit({ minimum_percent: 50 })),
			paragraph(3),
		]),
	]
	page_of = Pdf.reserved_width(points(64), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])
	footer = Pdf.region({ center: [], end: [Pdf.furniture_text([page_of])], height: points(16), start: [] })
	Pdf.with_page_templates(
		Pdf.document({ contents, language: "en-AU", title }),
		{
			continuation: Pdf.page_template({ footer, gap: points(12), header: Pdf.region({ center: [], end: [], height: points(16), start: [Pdf.furniture_text([Pdf.text("Harbour & Finch — Annual timber report")])] }) }),
			first: Pdf.first_page_template({ footer, gap: points(12), header: Pdf.no_region, lead: Pdf.no_lead }),
		},
	)
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
			.append(Pdf.decoration(divider))
			.append(Pdf.heading(1, "Region ${number}"))
			.append(paragraph($index))
			.append(Pdf.figure(bar_chart(120, shifted), "Bar chart ${number}: revenue grew in all four yards.", Pdf.caption("Figure ${number}. Revenue by yard, AUD thousands")))
		$index = $index + 1
	}
	Pdf.document({ contents: $contents, language: "en-AU", title: "Regional figures" })
}

## Bytes come from `Pdf.to_bytes_with`; work comes from one facade pipeline
## probe through scenes over the same normalized authoring.
evidence : Document -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
evidence = |document| {
	bytes = Pdf.to_bytes_with(document, Pdf.Options.with_theme(Pdf.Options.default, report_theme)) ? |_| EvidenceFailure
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
rejects = |document, expected_code, expected_feature, expected_paths| match Pdf.to_bytes_with(document, Pdf.Options.with_theme(Pdf.Options.default, report_theme)) {
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
	tall = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 600, 900 + offset), oak)
	wide = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 500 + offset, 40), oak)
	nested = |depth| {
		var $drawing = leaf_mark
		var $level = 0
		while $level < depth {
			$drawing = Scene.drawing({}).group(Layout.point(1, 1), $drawing)
			$level = $level + 1
		}
		$drawing
	}
	figure = |drawing, caption| Pdf.figure(drawing, "A plan drawing", caption)
	lead_templates = {
		continuation: Pdf.page_template({ footer: Pdf.no_region, gap: points(12), header: Pdf.region({ center: [], end: [], height: points(16), start: [Pdf.furniture_text([Pdf.text("Header")])] }) }),
		first: Pdf.first_page_template({ footer: Pdf.no_region, gap: points(12), header: Pdf.no_region, lead: Pdf.lead_region(points(60), [Pdf.paragraph("Letterhead"), Pdf.decoration(divider), Pdf.paragraph("Address")]) }),
	}
	checks = [
		rejects(document([Pdf.paragraph("Lead"), figure(tall, Pdf.caption("Figure 1."))]), LayoutConstraintViolated, "document.figure_oversize", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), Pdf.figure_fit(figure(tall, Pdf.caption("Figure 1.")), ScaleToFit({ minimum_percent: 90 }))]), LayoutConstraintViolated, "document.figure_oversize", ["contents[1]"]),
		rejects(document([Pdf.section([Pdf.paragraph("Lead"), figure(wide, Pdf.no_caption)])]), LayoutConstraintViolated, "document.figure_oversize", ["contents[0].contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), Pdf.figure(leaf_mark, "", Pdf.caption("Figure 2."))]), InvalidRelationship, "document.figure_alternative_empty", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), figure(Scene.drawing({}), Pdf.no_caption)]), InvalidRelationship, "document.figure_drawing", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), figure(nested(9), Pdf.no_caption)]), InvalidRelationship, "document.figure_drawing", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), figure(leaf_mark, Pdf.caption(""))]), InvalidRelationship, "document.figure_caption_empty", ["contents[1].caption"]),
		rejects(document([Pdf.paragraph("Lead"), Pdf.figure_fit(figure(leaf_mark, Pdf.no_caption), ScaleToFit({ minimum_percent: 101 }))]), InvalidRelationship, "document.figure_fit", ["contents[1]"]),
		rejects(document([Pdf.figure_fit(Pdf.paragraph("Not a figure"), ScaleToFit({ minimum_percent: 50 }))]), InvalidRelationship, "document.figure_fit", []),
		rejects(document([Pdf.paragraph("Lead"), Pdf.decoration(divider)]), LayoutConstraintViolated, "layout.decoration_position", ["contents[1]"]),
		rejects(Pdf.with_page_templates(document([Pdf.paragraph("Body")]), lead_templates), LayoutConstraintViolated, "layout.decoration_position", ["templates.first.lead.contents[1]"]),
		rejects(document([Pdf.decoration(Scene.drawing({})), Pdf.paragraph("Body")]), InvalidRelationship, "layout.decoration_drawing", ["contents[0]"]),
		rejects(document([Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("Item"), Pdf.decoration(divider)])]), Pdf.paragraph("Body")]), InvalidRelationship, "semantics.list_item_content", ["contents[0].items[0].contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), Pdf.decoration(tall), Pdf.paragraph("Body")]), LayoutConstraintViolated, "layout.oversize_block", ["contents[1]"]),
	]
	passed = checks.sum()
	if passed != checks.len() {
		return Err(MissingRejection(passed))
	}
	carrier = Pdf.to_bytes_with(document([Pdf.title("Figure carrier"), Pdf.figure(leaf_mark, "The Harbour & Finch leaf mark", Pdf.no_caption)]), Pdf.Options.with_theme(Pdf.Options.default, report_theme)) ? |_| EvidenceFailure
	Ok({ bytes: carrier, work: [passed, carrier.len()] })
}

## The facade's standard pipeline limits (package/Pdf.roc).
pipeline_limits : KernelFacadePipeline.Limits
pipeline_limits = KernelFacadePipeline.Limits.make({
	fragment_semantics: KernelSemantics.Limits.make({ max_attributes: 65536, max_content_spine: 65536 + 65536, max_fragments: 1000000, max_namespaces: 1, max_nodes: 16384, max_occurrences: 16384, max_semantic_depth: 48 }),
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
		max_artifacts: 0,
		max_container_depth: 16,
		max_content_spine: 65536,
		max_inline_depth: 8,
		max_nodes: 16384,
		max_occurrences: 16384,
		max_properties: 16384,
		max_source_inputs: 16384,
		semantics: KernelSemantics.Limits.make({ max_attributes: 65536, max_content_spine: 65536, max_fragments: 0, max_namespaces: 1, max_nodes: 16384, max_occurrences: 16384, max_semantic_depth: 48 }),
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
