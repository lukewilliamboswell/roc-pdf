import pdf.Color
import pdf.Conformance
import pdf.Document
import pdf.Font
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
import pdf.Theme
import "../assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)
import "../assets/NotoSansSC-CJK-Fixture.ttf" as cjk_font_bytes : List(U8)

## Rich inline evidence through the public `Pdf` constructors.
##
## - `mixed`: styled runs (themed `Strong`, `Em`, and `Code` colors),
##   expansions with `/E`, French `Span`s inside `en-AU` text (one inside a
##   `Quote`), nested inline elements inside a section beside a bulleted list
##   and a plain paragraph, an inline internal link to a destination heading,
##   and an inline URI link containing `Strong` that wraps across a line
##   break.
## - `paragraphs xN`: N rich paragraphs, each with eight inline elements
##   including a URI link, the scale pair for linear inline planning,
##   shaping, line layout, and annotation lowering.
## - `ordered`: a rich paragraph through an ordered caller-font policy, with
##   a `zh-Hans` span selected onto the Han face and a French span.
## - `atomic_negatives`: every inline rejection with its stable dotted code
##   and inline path, the eight-deep accepted boundary, and no bytes.
##
## Bytes always come from `Pdf.to_bytes_with` (the default `Archive`
## profile). Work comes from one additional semantic planning pass and one
## facade pipeline build over the same normalized authoring.
Fixture :: [].{
	EvidenceError : [EvidenceFailure, InvalidScale, MissingRejection(U64)]

	mixed : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	mixed = |context| {
		theme = Theme.default
			.with_emphasis_color(Color.srgb8({ blue: 140, green: 70, red: 20 }))
			.with_strong_color(Color.srgb8({ blue: 30, green: 30, red: 150 }))
			.with_code_color(Color.srgb8({ blue: 60, green: 100, red: 20 }))
		evidence(mixed_document(context), theme, BuiltInFace)
	}

	paragraphs : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	paragraphs = |count| {
		if count == 0 or count > 1000 {
			return Err(InvalidScale)
		}
		evidence(paragraph_document(count), Theme.default, BuiltInFace)
	}

	ordered : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	ordered = |context| {
		registered = register_faces(context)?
		evidence(ordered_document(context), Theme.with_font_policy(Theme.default, registered.policy), Policy(registered))
	}

	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |context| run_negatives(context)
}

Faces : [BuiltInFace, Policy({ policy : Font.PolicyId, registry : Font.Registry })]

mixed_document : U64 -> Document
mixed_document = |context| {
	suffix = if context == 0 "" else " (${context.to_str()})"
	Pdf.document({
		contents: [
			Pdf.title("Quarterly summary${suffix}"),
			Pdf.destination_heading("summary", 1, "1 Summary"),
			Pdf.rich_paragraph([
				Pdf.text("Q1 "),
				Pdf.expansion("FY2027", "financial year 2027"),
				Pdf.text(": July to September 2026 · Prepared by the finance team."),
			]),
			Pdf.rich_paragraph([
				Pdf.text("Revenue rose "),
				Pdf.strong([Pdf.text("5.0%")]),
				Pdf.text(" to AUD 9.22 million, led by "),
				Pdf.emphasis([Pdf.text("Queensland")]),
				Pdf.text(". Freight costs fell for the second quarter; see "),
				Pdf.inline_internal_link([Pdf.text("section 3, "), Pdf.emphasis([Pdf.text("Operations")])], "operations"),
				Pdf.text("."),
			]),
			Pdf.rich_paragraph([
				Pdf.text("Revenue is reported net of "),
				Pdf.expansion("GST", "Goods and Services Tax"),
				Pdf.text(". Stock counts come from the warehouse system "),
				Pdf.code("WMS-7"),
				Pdf.text(", which records every "),
				Pdf.in_language("fr", [Pdf.text("Cafetière « Élégance »")]),
				Pdf.text(" shipment."),
			]),
			Pdf.destination_heading("operations", 1, "3 Operations"),
			Pdf.rich_paragraph([
				Pdf.text("Our oak supplier "),
				Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")]),
				Pdf.text(" puts it simply: "),
				Pdf.quote([Pdf.in_language("fr", [Pdf.text("« Le bois ne ment pas. »")])]),
				Pdf.text(" Read "),
				Pdf.inline_link(
					[
						Pdf.text("our published sustainability commitments, including the "),
						Pdf.strong([Pdf.text("2026 timber audit")]),
						Pdf.text(" and its appendix"),
					],
					"https://harbourfinch.example/sustainability",
				),
				Pdf.text(" before the next review."),
			]),
			Pdf.section([
				Pdf.rich_paragraph([
					Pdf.emphasis([Pdf.text("Nested "), Pdf.strong([Pdf.text("strong and "), Pdf.code("code")]), Pdf.text(" text")]),
					Pdf.text(" closes the summary."),
				]),
				Pdf.bullets(["Receiving hours are 7 am to 3 pm", "Dispatch follows confirmation order"]),
				Pdf.paragraph("A plain paragraph shares the page with rich text."),
			]),
		],
		language: "en-AU",
		title: "Quarterly summary${suffix}",
	})
}

paragraph_document : U64 -> Document
paragraph_document = |count| {
	var $contents = List.with_capacity(count + 1)
	$contents = $contents.append(Pdf.title("Inline scale"))
	var $index = 0
	while $index < count {
		label = (1 + $index).to_str()
		$contents = $contents.append(
			Pdf.rich_paragraph([
				Pdf.text("Entry ${label} reports "),
				Pdf.strong([Pdf.text("${label}.0%")]),
				Pdf.text(" growth in "),
				Pdf.emphasis([Pdf.text("Queensland")]),
				Pdf.text(" under "),
				Pdf.expansion("GST", "Goods and Services Tax"),
				Pdf.text(", supplied by "),
				Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")]),
				Pdf.text(", counted in "),
				Pdf.code("WMS-${label}"),
				Pdf.text(", and quoted as "),
				Pdf.quote([Pdf.text("“steady”")]),
				Pdf.text("; see "),
				Pdf.inline_link([Pdf.text("the "), Pdf.emphasis([Pdf.text("entry ${label}")]), Pdf.text(" record")], "https://harbourfinch.example/entries/${label}"),
				Pdf.text("."),
			]),
		)
		$index = $index + 1
	}
	Pdf.document({ contents: $contents, language: "en-AU", title: "Inline scale" })
}

ordered_document : U64 -> Document
ordered_document = |context| {
	suffix = if context == 0 "" else " ${context.to_str()}"
	Pdf.document({
		contents: [
			Pdf.rich_paragraph([
				Pdf.in_language("fr", [Pdf.text("Café")]),
				Pdf.in_language("zh-Hans", [Pdf.text("中")]),
				Pdf.emphasis([Pdf.text("PDF${suffix}")]),
			]),
		],
		language: "en-AU",
		title: "Ordered spans",
	})
}

register_faces : U64 -> Try({ policy : Font.PolicyId, registry : Font.Registry }, Fixture.EvidenceError)
register_faces = |context| {
	limits = if context == 0 Font.ValidationLimits.default else Font.ValidationLimits.make({ max_bytes: 0, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 })
	latin = match Font.Registry.empty.register(caller_font_bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits) {
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

evidence : Document, Theme, Faces -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
evidence = |document, theme, faces| {
	options = match faces {
		BuiltInFace => Pdf.Options.with_theme(Pdf.Options.default, theme)
		Policy(policy) => Pdf.Options.with_font_registry(Pdf.Options.with_theme(Pdf.Options.default, theme), policy.registry)
	}
	bytes = Pdf.to_bytes_with(document, options) ? |_| EvidenceFailure
	authoring = Document.normalize(document)
	plan = KernelFacadeSemantics.Plan.build(authoring, semantic_limits) ? |_| EvidenceFailure
	work = KernelFacadeSemantics.Plan.work(plan)
	semantic_work = KernelSemantics.Plan.work(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(plan)))

	## Work comes from the default theme: themed inline colors change only
	## paint facts, never shaping, line, page, or fragment counts.
	pipeline = match faces {
		BuiltInFace => {
			font = KernelFont.inspect(KernelBuiltInFont.bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })) ? |_| EvidenceFailure
			KernelFacadePipeline.Plan.build(authoring, font, Theme.default, page_size, descriptor, pipeline_limits) ? |_| EvidenceFailure
		}
		Policy(policy) => KernelFacadePipeline.Plan.build_ordered(authoring, policy, theme, page_size, descriptor, pipeline_limits) ? |_| EvidenceFailure
	}
	flow = KernelFacadePipeline.Plan.work(pipeline)
	Ok({
		bytes,
		work: [
			work.node_writes,
			work.inline_elements,
			work.inline_leaves,
			work.content_writes,
			work.occurrence_writes,
			semantic_work.node_visits,
			semantic_work.containment_edges,
			flow.shaped_runs,
			flow.lines,
			flow.final_runs,
			flow.fragments,
			flow.pages,
			bytes.len(),
		],
	})
}

page_size : Layout.Size
page_size = { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) }

descriptor : KernelPdfFont.Descriptor
descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

rejects : Document, Conformance.DiagnosticCode, Str, Str -> U64
rejects = |document, expected_code, expected_feature, expected_path| match Pdf.to_bytes(document) {
	Err(InvalidDocument({ diagnostics: [{ code, details, feature: Feature(feature), location: Document, stage: AuthoringValidation, .. }], truncation: Complete, .. })) => if code == expected_code and feature == expected_feature and details == [expected_path] 1 else 0
	_ => 0
}

nest_emphasis : List(Pdf.Inline), U64 -> Pdf.Inline
nest_emphasis = |inner, depth| {
	var $inline = Pdf.emphasis(inner)
	var $level = 1
	while $level < depth {
		$inline = Pdf.emphasis([$inline])
		$level = $level + 1
	}
	$inline
}

## Each document differs from a valid authoring in one inline fact. Every
## rejection is transactional: a stable code, the inline's authored path,
## and no bytes.
run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_negatives = |context| {
	title = if context == 0 "Inline negatives" else "guarded"
	document = |contents| Pdf.document({ contents, language: "en-AU", title })
	offset = U64.mod_by(context, 1)
	lead = Pdf.paragraph("Lead")
	uri = "https://harbourfinch.example/"
	checks = [
		rejects(document([lead, Pdf.rich_paragraph([])]), InvalidRelationship, "semantics.inline_empty", "contents[1]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("Lead "), Pdf.emphasis([Pdf.text("")])])]), InvalidRelationship, "semantics.inline_empty", "contents[1].inlines[1].inlines[0]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.strong([]), Pdf.text("after")])]), InvalidRelationship, "semantics.inline_empty", "contents[1].inlines[0]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("See "), Pdf.inline_link([], uri)])]), InvalidRelationship, "semantics.link_text_empty", "contents[1].inlines[1]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.inline_link([Pdf.text("outer "), Pdf.emphasis([Pdf.inline_link([Pdf.text("inner")], uri)])], uri)])]), InvalidRelationship, "semantics.nested_link", "contents[1].inlines[0].inlines[1].inlines[0]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("Deep "), nest_emphasis([Pdf.text("text")], 9 + offset)])]), BudgetExceeded, "semantics.inline_depth", "contents[1].inlines[1]${Str.repeat(".inlines[0]", 8)}"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.in_language("fr_CA", [Pdf.text("Québec")])])]), InvalidLanguage, "semantics.language_tag", "contents[1].inlines[0]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("Visit "), Pdf.inline_link([Pdf.text("the site")], "harbourfinch example")])]), InvalidRelationship, "semantics.link_uri", "contents[1].inlines[1]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("Greek "), Pdf.in_language("el", [Pdf.text("Ωμέγα")])])]), FontCoverageMissing, "text.unsupported_script", "contents[1].inlines[1].inlines[0]"),
		rejects(document([lead, Pdf.rich_paragraph([Pdf.text("Cafe"), Pdf.emphasis([Pdf.text("\u(301)")])])]), FontCoverageMissing, "text.unsupported_cluster", "contents[1].inlines[0]"),
		rejects(document([Pdf.section([Pdf.heading(1, "Grouped"), Pdf.rich_paragraph([Pdf.text("Empty "), Pdf.strong([])])])]), InvalidRelationship, "semantics.inline_empty", "contents[0].contents[1].inlines[1]"),
	]
	passed = checks.sum()
	if passed != checks.len() {
		return Err(MissingRejection(passed))
	}
	unknown = match Pdf.to_bytes(document([Pdf.rich_paragraph([Pdf.text("Go to${Str.repeat(" ", offset)} "), Pdf.inline_internal_link([Pdf.text("nowhere")], "missing")])])) {
		Err(InvalidNavigation(UnknownDestinationName({ annotation: 0 }))) => 1
		_ => return Err(MissingRejection(passed))
	}

	## The deepest accepted inline nesting is the facade bound itself.
	boundary = Pdf.to_bytes(document([Pdf.title("Boundary"), Pdf.rich_paragraph([Pdf.text("Deep "), nest_emphasis([Pdf.text("text")], 8 + offset)])])) ? |_| EvidenceFailure
	carrier = Pdf.to_bytes(document([Pdf.title("Inline carrier"), Pdf.rich_paragraph([Pdf.text("A "), Pdf.strong([Pdf.text("valid")]), Pdf.text(" rich paragraph.")])])) ? |_| EvidenceFailure
	Ok({ bytes: carrier, work: [passed + unknown, boundary.len(), carrier.len()] })
}

pipeline_limits : KernelFacadePipeline.Limits
pipeline_limits = KernelFacadePipeline.Limits.make({
	fragment_semantics: KernelSemantics.Limits.make({ max_attributes: 8192, max_content_spine: 8192, max_fragments: 100000, max_namespaces: 1, max_nodes: 4096, max_occurrences: 2048, max_semantic_depth: 32 }),
	fragments: KernelFacadeFragments.Limits.make({ max_fragments: 100000, max_occurrences: 2048, max_pages: 1024 }),
	navigation: KernelNavigation.standard_limits,
	lines: KernelFacadeLines.Limits.make({
		line: KernelLineLayout.BatchLimits.make({
			line: KernelLineLayout.Limits.make({ max_boundaries: 1000001, max_candidates: 2000000, max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_lines: 1000000 }),
			max_key_probes: 1000000,
			max_lines: 1000000,
			max_runs: 2048,
			max_table_slots: 8192,
			max_templates: 2048,
		}),
		max_blocks: 2048,
		max_runs: 2048,
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
		text: KernelPdfText.Limits.make({ max_actual_text_scalars: 1000000, max_content_bytes: 16000000, max_mappings: 10000, max_placements: 0, max_source_scalars: 1000000 }),
	}),
	pages: KernelFacadePages.Limits.make({
		max_blocks: 2048,
		max_rows: 1000000,
		page: KernelPageLayout.Limits.make({ max_blocks: 2048, max_fragments: 1000000, max_lines: 1000000, max_pages: 1024, max_placements: 1000000 }),
	}),
	scenes: KernelFacadeScenes.Limits.make({
		color: KernelColor.Limits.make({ max_icc_bytes: KernelSrgbProfile.byte_count, max_profiles: 1, max_spaces: 2, max_tags: KernelSrgbProfile.tag_count }),
		max_commands: 2000000,
		max_groups: 1000000,
		max_page_group_edges: 1000000,
		max_pages: 1024,
		scene: KernelScene.Limits.make({ max_commands: 2000000, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 1000000, max_pages: 1024, max_path_segments: 0, max_paths: 0 }),
	}),
	semantics: KernelFacadeSemantics.Limits.make({
		max_container_depth: 16,
		max_content_spine: 8192,
		max_inline_depth: 8,
		max_nodes: 4096,
		max_occurrences: 2048,
		max_properties: 2048,
		max_source_inputs: 2048,
		semantics: KernelSemantics.Limits.make({ max_attributes: 8192, max_content_spine: 8192, max_fragments: 0, max_namespaces: 1, max_nodes: 4096, max_occurrences: 2048, max_semantic_depth: 32 }),
		sources: KernelFacadeSources.Limits.make({
			max_hash_probes: 1000000,
			max_inputs: 2048,
			max_source_bytes: 1000000,
			max_source_scalars: 1000000,
			max_table_slots: 8192,
			max_unique_sources: 2048,
			unicode: { max_graphemes: 1000000, max_line_boundaries: 1000001, max_scalars: 1000000, max_script_runs: 2048 },
		}),
		text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 2048, max_text_property_bytes: 1000000, max_text_source_bytes: 1000000, max_text_source_scalars: 1000000, max_text_sources: 2048 }),
	}),
	shape: KernelFacadeShape.Limits.make({ max_requests: 2048, shape: KernelShape.Limits.make({ max_clusters: 1000000, max_glyphs: 1000000, max_scalars: 1000000, max_source_bytes: 1000000 }) }),
	text: KernelFacadeText.Limits.make({ max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_pages: 1024, max_placements: 1000000, max_runs: 1000000 }),
})

object_limits : KernelObject.Limits
object_limits = {
	max_array_items: 1000000,
	max_byte_string_bytes: 1048576,
	max_byte_strings: 65536,
	max_dictionary_entries: 1000000,
	max_direct_depth: 8,
	max_name_bytes: 8192,
	max_names: 100000,
	max_objects: 65536,
	max_payload_bytes: 16000000,
	max_payloads: 100000,
	max_streams: 100000,
	max_text_string_bytes: 1000000,
	max_text_strings: 16384,
	max_values: 1000000,
}

semantic_limits : KernelFacadeSemantics.Limits
semantic_limits = KernelFacadeSemantics.Limits.make({
	max_container_depth: 16,
	max_content_spine: 8192,
	max_inline_depth: 8,
	max_nodes: 4096,
	max_occurrences: 2048,
	max_properties: 2048,
	max_source_inputs: 2048,
	semantics: KernelSemantics.Limits.make({ max_attributes: 8192, max_content_spine: 8192, max_fragments: 0, max_namespaces: 1, max_nodes: 4096, max_occurrences: 2048, max_semantic_depth: 32 }),
	sources: KernelFacadeSources.Limits.make({
		max_hash_probes: 1000000,
		max_inputs: 2048,
		max_source_bytes: 1000000,
		max_source_scalars: 1000000,
		max_table_slots: 8192,
		max_unique_sources: 2048,
		unicode: { max_graphemes: 1000000, max_line_boundaries: 1000001, max_scalars: 1000000, max_script_runs: 2048 },
	}),
	text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 2048, max_text_property_bytes: 1000000, max_text_source_bytes: 1000000, max_text_source_scalars: 1000000, max_text_sources: 2048 }),
})
