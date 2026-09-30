import Callout
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

## The custom-block seam and the preparation report
## (`reference-documents-v9`).
##
## - `report`: the reference report's first sections through the public
##   `Pdf` constructors, with the "Key figures" callout authored by the
##   separately written `Callout` extension, a table that continues with
##   repeated header rows, a 600 x 900 pt figure scaled to fit (REP-A6b),
##   and rich inline content. It is prepared with `Pdf.prepare_with_report`;
##   the fixture checks that the prepared bytes equal `Pdf.to_bytes_with`
##   and maps named report observations back to the authored paths.
## - `callouts xN`: N sections, each a heading, a paragraph, and a callout.
##   The 10/100 pair is the linear scale pair for layout and the report.
## - `atomic_negatives`: every custom-block rejection with its stable
##   dotted code and authored path (REP-A10 among them), and report budget
##   exhaustion for entries and for text bytes, each with no bytes and no
##   report.
##
## Bytes come from the prepared document. Work comes from one facade
## pipeline probe through text materialization over the same normalized
## authoring (lines and pages; a probe has no document facts, so it can
## neither paint a tinted panel nor lower navigation), and from the
## report's own counts.
Fixture :: [].{
	EvidenceError : [EvidenceFailure, BytesDiffer, InvalidScale, MissingObservation(U64), MissingRejection(U64)]

	report : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	report = |context| {
		document = report_document(context)
		evidence(document, report_observations)
	}

	callouts : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	callouts = |count| {
		if count == 0 or count > 100 {
			return Err(InvalidScale)
		}
		evidence(callouts_document(count), |observed| callout_observations(observed, count))
	}

	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |context| run_negatives(context)
}

points : I64 -> Layout.Unit
points = |value| Layout.Unit.points(value)

## The reference report theme: an A4 body frame of 483 x 746 pt.
report_theme : Theme
report_theme = Theme.with_page_margin(Theme.default, { bottom: points(48), left: points(56), right: points(56), top: points(48) })

options : Pdf.Options
options = Pdf.Options.with_theme(Pdf.Options.default, report_theme)

ink : Color.SourceValue
ink = Color.srgb8({ blue: 40, green: 40, red: 40 })

sea : Color.SourceValue
sea = Color.srgb8({ blue: 140, green: 90, red: 20 })

## The "Key figures" callout of the reference report, full body width.
key_figures : Document.Block
key_figures = Callout.key_figures(report_theme, { lines: ["Revenue: AUD 9.22 m (+5.0%)", "On-time delivery: 96.4%", "Certified timber: 88%"], name: "Key figures", width: points(483) })

## A 600 x 900 pt plan drawing (REP-A6b), scaled to fit.
site_plan : Scene.Drawing
site_plan = Scene.drawing({}).path(Scene.path({}).rectangle(Layout.rect(4, 4, 592, 892)).finish(), Scene.solid_stroke(ink, points(4)))
	.path(Scene.path({}).rectangle(Layout.rect(60, 40, 480, 820)).finish(), Scene.solid_fill(sea))

supplier_row : U64 -> Pdf.Row
supplier_row = |index| {
	number = (index + 1).to_str()
	supplier = if index == 7 Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")]) else Pdf.text("Supplier ${number} Pty Ltd")
	Pdf.row([
		Pdf.header_cell(Row, [supplier]),
		Pdf.cell([Pdf.text(if index % 3 == 0 "Hobart TAS" else if index % 3 == 1 "Launceston TAS" else "Lyon, France")]),
		Pdf.cell([Pdf.text(if index % 2 == 0 "Timber" else "Hardware")]),
		Pdf.cell([Pdf.text("${(100 + index * 7).to_str()}")]),
		Pdf.cell([Pdf.text(if index % 4 == 0 "No" else "Yes")]),
	])
}

supplier_table : Document.Block
supplier_table = {
	var $rows = List.with_capacity(40)
	var $index = 0
	while $index < 40 {
		$rows = $rows.append(supplier_row($index))
		$index = $index + 1
	}
	Pdf.table({
		body_rows: $rows,
		caption: Pdf.caption("Table 2. Active suppliers at 30 September 2026"),
		columns: [{ align: Start, width: Share(3) }, { align: Start, width: Share(2) }, { align: Start, width: Share(2) }, { align: End, width: Fixed(points(80)) }, { align: Center, width: Fixed(points(56)) }],
		footer_rows: [],
		header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Supplier")]), Pdf.header_cell(Column, [Pdf.text("Location")]), Pdf.header_cell(Column, [Pdf.text("Category")]), Pdf.header_cell(Column, [Pdf.text("Spend (AUD thousands)")]), Pdf.header_cell(Column, [Pdf.text("Certified")])])],
		row_split: KeepRows,
	})
}

report_document : U64 -> Document
report_document = |context| {
	title = if context == 0 "Quarterly operations report" else "Quarterly operations report!"
	contents = [
		Pdf.title(title),
		Pdf.rich_paragraph([Pdf.text("Q1 "), Pdf.expansion("FY2027", "financial year 2027"), Pdf.text(": July to September 2026 · Prepared by the Operations team, 12 October 2026")]),
		Pdf.section([
			Pdf.destination_heading("summary", 1, "1 Summary"),
			Pdf.rich_paragraph([Pdf.text("Revenue rose "), Pdf.strong([Pdf.text("5.0%")]), Pdf.text(" to AUD 9.22 million, led by "), Pdf.emphasis([Pdf.text("Queensland")]), Pdf.text(". Freight costs fell for the second quarter; see "), Pdf.inline_internal_link([Pdf.text("section 3, Supply chain")], "supply-chain"), Pdf.text(".")]),
			Pdf.bullet_list([
				Pdf.list_item([Pdf.paragraph("On-time delivery reached 96.4%.")]),
				Pdf.list_item([Pdf.paragraph("Timber purchasing moved further toward certified sources:"), Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("88% of oak by volume is certified.")]), Pdf.list_item([Pdf.paragraph("All veneer suppliers are now audited annually.")])])]),
				Pdf.list_item([Pdf.paragraph("Warranty claims fell to 0.6% of units shipped.")]),
			]),
			key_figures,
		]),
		Pdf.section([
			Pdf.destination_heading("supply-chain", 1, "3 Supply chain"),
			Pdf.rich_paragraph([Pdf.text("Our partner "), Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")]), Pdf.text(" puts it simply: "), Pdf.quote([Pdf.in_language("fr", [Pdf.text("« Le bois demande de la patience. »")])]), Pdf.text(" (“Timber asks for patience.”)")]),
			Pdf.figure_fit(Pdf.figure(site_plan, "Plan of the Moonah yard: twelve drying bays inside the yard boundary.", Pdf.caption("Figure 3. Moonah yard plan, scaled to fit.")), ScaleToFit({ minimum_percent: 50 })),
		]),
		Pdf.section([
			Pdf.destination_heading("appendix-a", 1, "Appendix A. Supplier register"),
			Pdf.paragraph("Suppliers active at the end of the quarter, with their spend in the quarter."),
			supplier_table,
		]),
	]
	page_of = Pdf.reserved_width(points(64), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])
	footer = Pdf.region({ center: [], end: [Pdf.furniture_text([page_of])], height: points(16), start: [] })
	Pdf.with_page_templates(
		Pdf.document({ contents, language: "en-AU", title }),
		{
			continuation: Pdf.page_template({ footer, gap: points(12), header: Pdf.region({ center: [], end: [], height: points(16), start: [Pdf.furniture_text([Pdf.text("Harbour & Finch — Quarterly operations report · Q1 FY2027")])] }) }),
			first: Pdf.first_page_template({ footer, gap: points(12), header: Pdf.no_region, lead: Pdf.no_lead }),
		},
	)
}

callouts_document : U64 -> Document
callouts_document = |count| {
	var $contents = List.with_capacity(count * 3 + 1)
	$contents = $contents.append(Pdf.title("Regional key figures"))
	var $index = 0
	while $index < count {
		number = ($index + 1).to_str()
		$contents = $contents
			.append(Pdf.heading(1, "Region ${number}"))
			.append(Pdf.paragraph("Revenue, delivery, and sourcing figures for region ${number} in the first quarter of financial year 2027."))
			.append(Callout.key_figures(report_theme, { lines: ["Revenue: AUD ${(($index % 9) + 1).to_str()}.2 m", "On-time delivery: 9${($index % 10).to_str()}%"], name: "Region ${number} figures", width: points(320) }))
		$index = $index + 1
	}
	Pdf.document({ contents: $contents, language: "en-AU", title: "Regional key figures" })
}

## Prepare once with the report; the prepared bytes must equal the bytes
## of the ordinary one-shot path (inspection does not alter output). Work
## comes from one pipeline probe and from the report's entry counts.
evidence : Document, (Pdf.Report -> List(Bool)) -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
evidence = |document, observe| {
	{ prepared, report } = Pdf.prepare_with_report(document, options) ? |_| EvidenceFailure
	bytes = Pdf.to_bytes_prepared(prepared) ? |_| EvidenceFailure
	plain = Pdf.to_bytes_with(document, options) ? |_| EvidenceFailure
	if bytes != plain {
		return Err(BytesDiffer)
	}
	observed = observe(report)
	var $index = 0
	for held in observed {
		if !held {
			return Err(MissingObservation($index))
		}
		$index = $index + 1
	}
	font = KernelFont.inspect(KernelBuiltInFont.bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })) ? |_| EvidenceFailure
	normalized = Document.normalize(document)
	customs = normalized.customs.len()
	flow = KernelFacadePipeline.probe(normalized, font, report_theme, page_size, descriptor, pipeline_limits, TextReady) ? |_| EvidenceFailure
	facts = report.facts
	Ok({
		bytes,
		work: [
			flow.lines,
			flow.pages,
			facts.pages.map(|page| page.fragments).sum(),
			customs,
			facts.blocks.len(),
			facts.alternatives.len(),
			facts.outcomes.len(),
			facts.coverage.len(),
			report.obligations.len(),
			observed.len(),
			bytes.len(),
		],
	})
}

has_obligation : Pdf.Report, Str, [AlternativeTextMeaningful, ExpansionAccurate, LanguageAccurate, LinkPurposeMeaningful, ReadingOrderMeaningful, TableHeadersMeaningful] -> Bool
has_obligation = |report, path, obligation| report.obligations.any(|entry| entry.path == path and entry.obligation == obligation)

has_block : Pdf.Report, Str, Str -> Bool
has_block = |report, path, role| report.facts.blocks.any(|block| block.path == path and block.role == role and block.fragments > 0)

has_alternative : Pdf.Report, Str, Str -> Bool
has_alternative = |report, path, text| report.facts.alternatives.any(|entry| entry.path == path and entry.text == text)

## Named observations of the report document, each mapped back to the
## authored path it came from.
report_observations : Pdf.Report -> List(Bool)
report_observations = |report| {
	facts = report.facts
	[
		facts.title == "Quarterly operations report" and facts.language == "en-AU",
		has_block(report, "contents[0]", "Title"),
		has_block(report, "contents[2].contents[3].contents[0]", "P"),
		has_block(report, "contents[2].contents[3].contents[2]", "P"),
		has_block(report, "contents[4].contents[2].caption", "Caption"),
		has_block(report, "contents[3].contents[2]", "Figure"),
		has_block(report, "contents[3].contents[2].caption", "Caption"),
		has_alternative(report, "contents[1].inlines[1]", "financial year 2027"),
		has_alternative(report, "contents[3].contents[1].inlines[1]", "fr"),
		has_alternative(report, "contents[3].contents[2]", "Plan of the Moonah yard: twelve drying bays inside the yard boundary."),
		facts.outcomes.any(
			|outcome| match outcome {
				CustomBlockPlaced({ height, name, page: _, path }) => path == "contents[2].contents[3]" and name == "Key figures" and height.raw() == Callout.measure(report_theme, 3, points(483)).height.raw()
				_ => False
			},
		),
		facts.outcomes.any(
			|outcome| match outcome {
				FigureScale({ fit: ScaleToFit, path, scale }) => path == "contents[3].contents[2]" and scale < 1000 and scale >= 500
				_ => False
			},
		),
		facts.outcomes.any(
			|outcome| match outcome {
				RepeatedHeader({ page, path, rows }) => path == "contents[4].contents[2]" and rows == 1 and page > 1
				_ => False
			},
		),
		has_obligation(report, "document", ReadingOrderMeaningful),
		has_obligation(report, "contents[2].contents[3]", ReadingOrderMeaningful),
		has_obligation(report, "contents[3].contents[2]", AlternativeTextMeaningful),
		has_obligation(report, "contents[4].contents[2]", TableHeadersMeaningful),
		has_obligation(report, "contents[2].contents[1].inlines[5]", LinkPurposeMeaningful),
		has_obligation(report, "contents[3].contents[1].inlines[1]", LanguageAccurate),
		has_obligation(report, "contents[1].inlines[1]", ExpansionAccurate),
		facts.coverage.any(|covered| covered.path == "contents[2].contents[3].contents[1]" and covered.script == "Latn" and covered.scalars > 0),
		facts.pages.len() > 1 and facts.pages.all(|page| page.fragments > 0),
	]
}

callout_observations : Pdf.Report, U64 -> List(Bool)
callout_observations = |report, count| {
	placed = report.facts.outcomes.count_if(
		|outcome| match outcome {
			CustomBlockPlaced(_) => True
			_ => False
		},
	)
	[
		placed == count,
		report.obligations.count_if(|entry| entry.obligation == ReadingOrderMeaningful) == count + 1,
		has_block(report, "contents[3].contents[1]", "P"),
		report.facts.blocks.len() == 1 + count * 4,
	]
}

page_size : Layout.Size
page_size = { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) }

descriptor : KernelPdfFont.Descriptor
descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

rejects : Document, Conformance.DiagnosticCode, Str, List(Str) -> U64
rejects = |document, expected_code, expected_feature, expected_paths| match Pdf.prepare_with_report(document, options) {
	Err(InvalidDocument({ diagnostics: [{ code, details, feature: Feature(feature), location: Document, stage: AuthoringValidation, .. }], truncation: Complete, .. })) => if code == expected_code and feature == expected_feature and details == expected_paths 1 else 0
	_ => 0
}

budget_rejects : Document, Pdf.ReportBudget -> U64
budget_rejects = |document, budget| match Pdf.prepare_with_report_budget(document, options, budget) {
	Err(InvalidDocument({ diagnostics: [{ code: BudgetExceeded, details: [], feature: Feature("report.budget_exceeded"), location: Document, stage: AuthoringValidation, .. }], truncation: Complete, .. })) => 1
	_ => 0
}

## Each document differs from a valid one in one custom-block fact or one
## report budget. Every rejection is transactional: a stable code, the
## authored path of each participating source, and no bytes or report.
run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_negatives = |context| {
	title = if context == 0 "Custom block negatives" else "guarded"
	offset = (context % 1).to_i64_wrap()
	document = |contents| Pdf.document({ contents, language: "en-AU", title })
	lines = ["Revenue: AUD 9.22 m (+5.0%)", "On-time delivery: 96.4%"]
	sized = |height, width| Callout.with_height(report_theme, { height: points(height + offset), lines, name: "Key figures", width: points(width) })
	custom = |contents, inset, name, panel| Pdf.custom_block({ contents, fragmentation: Unsplittable, inset: points(inset), name, panel, size: { height: points(80), width: points(300) } })
	square = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 300, 80), sea)
	image = Scene.drawing({}).image(Image.Source.rgb8({ alpha: NoAlpha, dimensions: { height: 1, width: 1 }, pixels: [200, 200, 200], row_stride: 3 }), Layout.rect(0, 0, 10, 10))
	lead_templates = {
		continuation: Pdf.page_template({ footer: Pdf.no_region, gap: points(12), header: Pdf.no_region }),
		first: Pdf.first_page_template({ footer: Pdf.no_region, gap: points(12), header: Pdf.no_region, lead: Pdf.lead_region(points(120), [Pdf.paragraph("Letterhead"), key_figures]) }),
	}
	valid = Callout.key_figures(report_theme, { lines, name: "Key figures", width: points(300) })
	many = document(List.repeat(valid, 40))
	checks = [

		## REP-A10: the extension reports a height larger than the body frame.
		rejects(document([Pdf.paragraph("Lead"), sized(900, 300)]), LayoutConstraintViolated, "layout.oversize_block", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), sized(80, 500)]), LayoutConstraintViolated, "layout.oversize_block", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), sized(40, 300)]), LayoutConstraintViolated, "layout.custom_block_measure", ["contents[1]"]),
		rejects(document([Pdf.section([Pdf.paragraph("Lead"), Callout.key_figures(report_theme, { lines: ["A figure line long enough that it must wrap inside a narrow callout panel"], name: "Key figures", width: points(160) })])]), LayoutConstraintViolated, "layout.custom_block_measure", ["contents[0].contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), custom([Pdf.paragraph("Body")], 0, "Key figures", square)]), LayoutConstraintViolated, "layout.custom_block_measure", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), custom([Pdf.paragraph("Body")], 40, "Key figures", square)]), LayoutConstraintViolated, "layout.custom_block_measure", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), custom([Pdf.paragraph("Body"), Pdf.heading(2, "Not in a callout")], 10, "Key figures", square)]), InvalidRelationship, "semantics.custom_block_content", ["contents[1]", "contents[1].contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), custom([Pdf.paragraph("Body"), Pdf.division([Pdf.paragraph("Nested")])], 10, "Key figures", square)]), InvalidRelationship, "semantics.custom_block_content", ["contents[1]", "contents[1].contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), custom([Pdf.paragraph("Body"), Pdf.spacer(points(4)), Pdf.paragraph("More")], 10, "Key figures", square)]), InvalidRelationship, "semantics.custom_block_content", ["contents[1]", "contents[1].contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), custom([Pdf.paragraph("Body")], 10, "", square)]), InvalidRelationship, "semantics.custom_block_name", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), custom([Pdf.paragraph("Body")], 10, "Key figures", image)]), InvalidRelationship, "layout.custom_block_drawing", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), custom([Pdf.paragraph("Body")], 10, "Key figures", Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 320, 80), sea))]), InvalidRelationship, "layout.custom_block_drawing", ["contents[1]"]),
		rejects(document([Pdf.paragraph("Lead"), custom([], 10, "Key figures", square)]), InvalidRelationship, "semantics.empty_container", ["contents[1]"]),
		rejects(Pdf.with_page_templates(document([Pdf.paragraph("Body")]), lead_templates), InvalidRelationship, "semantics.custom_block_content", ["templates.first.lead.contents[1]"]),
		rejects(document([Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("Item"), valid])])]), InvalidRelationship, "semantics.list_item_content", ["contents[0].items[0].contents[1]"]),
		budget_rejects(many, { max_entries: 100, max_text_bytes: 1000000 }),
		budget_rejects(many, { max_entries: 100000, max_text_bytes: 400 }),
	]
	passed = checks.sum()
	if passed != checks.len() {
		return Err(MissingRejection(passed))
	}
	{ prepared, report } = Pdf.prepare_with_report(document([Pdf.title("Custom block carrier"), valid]), options) ? |_| EvidenceFailure
	carrier = Pdf.to_bytes_prepared(prepared) ? |_| EvidenceFailure
	Ok({ bytes: carrier, work: [passed, report.obligations.len(), carrier.len()] })
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
