import pdf.KernelColor
import pdf.KernelContent
import pdf.KernelFacadeFragments
import pdf.KernelFacadeLines
import pdf.KernelFacadeOutput
import pdf.KernelFacadePages
import pdf.KernelFacadeScenes
import pdf.KernelFacadeSemantics
import pdf.KernelFacadeShape
import pdf.KernelFacadeSources
import pdf.KernelFacadeText
import pdf.KernelFontPlan
import pdf.KernelImage
import pdf.KernelLineLayout
import pdf.KernelNavigation
import pdf.KernelObject
import pdf.KernelObjectPlan
import pdf.KernelPageLayout
import pdf.KernelPdfText
import pdf.KernelScene
import pdf.KernelSemantics
import pdf.KernelShape
import pdf.KernelSrgbProfile
import pdf.KernelTaggedTextStructure
import pdf.KernelTextSemantics
import pdf.Color
import pdf.Document
import pdf.Font
import pdf.KernelBuiltInFont
import pdf.KernelFacadePipeline
import pdf.KernelPdfFont
import pdf.Layout
import pdf.Pdf
import pdf.Theme
import "../assets/NotoSansSC-CJK-Fixture.ttf" as cjk_bytes : List(U8)
import "../../examples/source-blocks/fonts/SourceCodePro-Regular.ttf" as mono_bytes : List(U8)

## Bytes use only the public facade. The additional styled compiler probe
## retains exact stage work on the same source, typography and page geometry.
Fixture :: [].{
	Error : [InvalidCase, FontFailure, PdfFailure(Pdf.Error), PipelineFailure, ReportFailure, MissingRejection(U64)]
	foregrounds : U64, U64, Bool -> Try({ bytes : List(U8), work : List(U64) }, Error)
	foregrounds = |kind, lines, colored| foreground_evidence(kind, lines, colored)
	foreground_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	foreground_negatives = |context| evidence({ text: short_text, scale: context, foreground_negative: True })
	han_only : Bool -> Try({ bytes : List(U8), work : List(U64) }, Error)
	han_only = |same_body| evidence({ text: "中\n\n中\n", han: True, source_only: True, same_body })
	multiple : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	multiple = |context| multiple_evidence(context)
	only_text : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	only_text = |context| evidence({ text: "a\n\n    b\n", scale: context, source_only: True })
	bare_blank : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	bare_blank = |context| evidence({ text: "", scale: context, defaults: True, source_only: True })
	han : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	han = |context| evidence({ text: "中\n\n中\n", scale: context, han: True })
	defaults : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	defaults = |context| evidence({ text: "defaults = 42\nnext = defaults", scale: context, defaults: True })
	blank : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	blank = |lines| {
		if lines > 10 {
			return Err(InvalidCase)
		}
		text = match Str.from_utf8(List.repeat(10, lines)) {
			Ok(value) => value
			Err(_) => crash "source fixture LF"
		}
		evidence({ text, scale: lines, source_only: True })
	}
	short : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	short = |context| evidence({ text: short_text, scale: context })
	long : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	long = |lines| evidence({ text: long_text(lines), scale: lines })
	near_bottom : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	near_bottom = |lines| evidence({ text: long_text(lines), scale: lines, spacer: 600 })
	wrapping : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	wrapping = |context| evidence({ text: wrap_text, scale: context })
	unicode : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	unicode = |context| evidence({ text: unicode_text, scale: context })
	negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	negatives = |context| evidence({ text: short_text, scale: context, negative: True })
}

short_text : Str
short_text = "\tlet value = 42\r\n\r\n\n  print(value)  \n"

unicode_text : Str
unicode_text = "  let café = \"Ångström\"\n\n  print(\"naïve café\")\n"

wrap_text : Str
wrap_text = {
	token = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
	"https://example.test/releases/download/package/abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789.tar.zst\n${token}\n  final = 42"
}

long_text : U64 -> Str
long_text = |lines| {
	var $bytes = []
	var $line = 0
	while $line < lines {
		if $line > 0 {
			$bytes = $bytes.append(10)
		}
		for byte in "line ${($line + 1).to_str()} = \"kept exactly once\"".to_utf8() {
			$bytes = $bytes.append(byte)
		}
		$line = $line + 1
	}
	match Str.from_utf8($bytes) {
		Ok(value) => value
		Err(_) => crash "source fixture UTF-8"
	}
}

faces : Bool -> Try({ body : Font.FaceId, mono : Font.FaceId, registry : Font.Registry }, Fixture.Error)
faces = |han| {
	body = Font.Registry.empty.register(KernelBuiltInFont.bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, Font.ValidationLimits.default) ? |_| FontFailure
	mono = body.registry.register(if han cjk_bytes else mono_bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924(if han "Hani" else "Latn")] }, Font.ValidationLimits.default) ? |_| FontFailure
	Ok({ body: body.face, mono: mono.face, registry: mono.registry })
}

EvidenceProps :: { text : Str, spacer : I64 ?? 0, scale : U64 ?? 0, negative : Bool ?? False, defaults : Bool ?? False, han : Bool ?? False, source_only : Bool ?? False, same_body : Bool ?? False, foregrounds : List(Pdf.SourceForeground) ?? [], foreground_negative : Bool ?? False, highlighted : Bool ?? False, repeat_source : Bool ?? False, source_body : Bool ?? False }

evidence : EvidenceProps -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
evidence = |EvidenceProps.{ text, spacer, scale, negative, defaults, han, source_only, same_body, foregrounds, foreground_negative, highlighted, repeat_source, source_body }| {
	if scale > 1000 {
		return Err(InvalidCase)
	}
	registered = faces(han)?
	props : Pdf.SourceBlockProps
	props = if defaults { text, face: if source_body registered.body else registered.mono, foregrounds } else { text, face: if source_body registered.body else registered.mono, foregrounds, size: 9, leading: 12, color: Color.srgb8({ red: 20, green: 40, blue: 80 }), padding: 8, background: Background(Color.srgb8({ red: 240, green: 242, blue: 245 })) }
	header = Pdf.region({ height: 10, start: [Pdf.furniture_text([Pdf.text("Quiet running header")])] })
	templates = Templates({ first: Pdf.first_page_template({ header: header }), continuation: Pdf.page_template({ header: header }) })
	make = |block| Pdf.document({
		title: "Preformatted source blocks",
		language: "en",
		page_templates: if defaults and !source_only templates else NoTemplates,
		contents: if source_only [block] else if repeat_source [Pdf.paragraph("Body before source."), Pdf.spacer(Layout.Unit.points(spacer)), block, Pdf.source_block({ ..props, foregrounds: [], color: Theme.black, background: NoBackground }), Pdf.paragraph("Body after source."), Pdf.paragraph("Body spacing stays unchanged.")] else [Pdf.paragraph("Body before source."), Pdf.spacer(Layout.Unit.points(spacer)), block, Pdf.paragraph("Body after source."), Pdf.paragraph("Body spacing stays unchanged.")],
	})
	document = make(Pdf.source_block(props))
	theme : Theme
	theme = { face: if same_body registered.mono else registered.body, body: { size: 11, leading: 15 }, furniture: Own({ size: 8, leading: 10 }), paragraph_spacing: 8 }
	options : Pdf.Options
	options = { theme, fonts: Registered(registered.registry) }
	{ prepared, report } = Pdf.prepare_with_report(document, options) ? PdfFailure
	bytes = Pdf.to_bytes_prepared(prepared) ? PdfFailure
	reported = if highlighted source_report_counts(report) else report_evidence(report, text, source_only)?
	body_font = registered.registry.prepared_face(registered.body) ? |_| FontFailure
	mono_font = registered.registry.prepared_face(registered.mono) ? |_| FontFailure
	styled = { faces: [registered.body, registered.mono], fonts: [body_font, mono_font], roles: { code: Inherited, emphasis: Inherited, quote: Inherited, strong: Inherited } }
	# Color requires a profile at emission. The work probe uses black text
	# and a black background; geometry and the panel paint work agree.
	probe_background = if defaults NoBackground else Background(Theme.black)
	probe_document = make(Pdf.source_block({ ..props, color: Theme.black, background: probe_background, foregrounds: foregrounds.map(|range| { ..range, color: Theme.black }) }))
	pipeline = KernelFacadePipeline.Plan.build_styled_with_facts(Document.normalize(probe_document), styled, theme, page_size, descriptor, NoDocumentFacts, pipeline_limits) ? |_| PipelineFailure
	flow = KernelFacadePipeline.Plan.work(pipeline)
	rejections = if foreground_negative {
		reject = |source, range, byte, reason| foreground_rejected(Pdf.to_bytes_with(make(Pdf.source_block(source)), options), "source.foreground_range", range, byte, reason)
		red : Color.SourceValue
		red = "#cc0000"
		checks = [
			foreground_rejected(Pdf.to_bytes_with(make(Pdf.source_block({ ..props, text: "x", foregrounds: [{ start: 0, end: 1, color: Color.gray8(128) }] })), options), "source.foreground_color", 0, 0, "supported sRGB"),
			reject({ ..props, text: "abc", foregrounds: [{ start: 1, end: 1, color: red }] }, 0, 1, "EmptyOrReversed"),
			reject({ ..props, text: "abc", foregrounds: [{ start: 2, end: 1, color: red }] }, 0, 2, "EmptyOrReversed"),
			reject({ ..props, text: "abc", foregrounds: [{ start: 0, end: 4, color: red }] }, 0, 4, "OutOfBounds"),
			reject({ ..props, text: "abc", foregrounds: [{ start: 0, end: 2, color: red }, { start: 1, end: 3, color: red }] }, 1, 1, "Overlap"),
			reject({ ..props, text: "abc", foregrounds: [{ start: 2, end: 3, color: red }, { start: 0, end: 1, color: red }] }, 1, 0, "Overlap"),
			reject({ ..props, text: "éx", foregrounds: [{ start: 1, end: 2, color: red }] }, 0, 1, "ClusterBoundary"),
			reject({ ..props, text: "éx", foregrounds: [{ start: 0, end: 1, color: red }] }, 0, 1, "ClusterBoundary"),
			reject({ ..props, text: "éx", foregrounds: [{ start: 0, end: 1, color: red }] }, 0, 1, "ClusterBoundary"),
			reject({ ..props, text: "éx", foregrounds: [{ start: 1, end: 3, color: red }] }, 0, 1, "ClusterBoundary"),
			reject({ ..props, text: "a\r\nb", foregrounds: [{ start: 0, end: 2, color: red }] }, 0, 2, "ClusterBoundary"),
			reject({ ..props, text: "a\r\nb", foregrounds: [{ start: 2, end: 4, color: red }] }, 0, 2, "ClusterBoundary"),
		]
		for rejected in checks {
			if !rejected {
				return Err(MissingRejection(checks.len()))
			}
		}
		checks.len()
	} else if negative {
		reject = |source, feature| source_rejected(Pdf.to_bytes_with(make(Pdf.source_block(source)), options), feature)
		policy = registered.registry.with_policy([registered.body]) ? |_| FontFailure
		policy_options = { ..options, fonts: Registered(policy.registry), theme: { ..theme, font_selection: Policy(policy.policy) } }
		checks = [
			reject({ ..props, text: "a\rb" }, "source.carriage_return"),
			reject({ ..props, text: "α" }, "text.unsupported_script"),
			reject({ ..props, text: "é" }, "text.unsupported_cluster"),
			reject({ ..props, text: "a\t", tabs: RejectTabs }, "source.tab"),
			reject({ ..props, tabs: ExpandTo(0) }, "source.tab_width"),
			reject({ ..props, text: wrap_text, wrap: RejectLongToken }, "layout.unbreakable_token"),
			reject({ ..props, text: long_text(100), fragmentation: Unsplittable }, "source.oversize"),
			source_rejected(Pdf.to_bytes_with(document, { theme: theme }), "source.face"),
			source_rejected(Pdf.to_bytes_with(document, policy_options), "source.font_policy"),
			reject({ ..props, leading: 8 }, "source.style"),
			reject({ ..props, padding: -1 }, "source.style"),
			reject({ ..props, padding: 300 }, "source.content_width"),
		]
		for rejected in checks {
			if !rejected {
				return Err(MissingRejection(checks.len()))
			}
		}
		checks.len()
	} else 0
	work = [text.count_utf8_bytes(), flow.shaped_runs, flow.lines, flow.pages, flow.final_runs, flow.fragments, flow.scene_commands, flow.objects, flow.shape_metric_reads, flow.line_candidate_visits, flow.page_candidate_visits, reported.fragments, reported.lines, rejections, bytes.len()]
	Ok({ bytes, work: if highlighted work.concat([flow.source_foreground_ranges, flow.source_paint_clusters, flow.source_paint_ranges]) else work })
}

report_evidence : Pdf.Report, Str, Bool -> Try({ fragments : U64, lines : U64 }, Fixture.Error)
report_evidence = |report, text, source_only| {
	var $fragments = 0
	var $cursor = 1
	var $whole = 0
	var $first = 0
	var $middle = 0
	var $last = 0
	var $page = 0
	for outcome in report.facts.outcomes {
		match outcome {
			SourceFragmentPlaced(fragment) => {
				expected_path = if source_only "contents[0]" else "contents[2]"
				if fragment.path != expected_path or fragment.page <= $page or fragment.page > report.facts.pages.len() or fragment.visual_lines.first != $cursor or fragment.visual_lines.count == 0 or fragment.rect.origin.x != 72 or fragment.rect.size.width != 451 or fragment.rect.size.height.raw() != fragment.visual_lines.count.to_i64_wrap() * 12000 + 16000 {
					return Err(ReportFailure)
				}
				match fragment.part {
					Whole => {
						$whole = $whole + 1
					}
					First => {
						$first = $first + 1
					}
					Middle => {
						$middle = $middle + 1
					}
					Last => {
						$last = $last + 1
					}
				}
				$cursor = $cursor + fragment.visual_lines.count
				$fragments = $fragments + 1
				$page = fragment.page
			}
			_ => {}
		}
	}
	var $expected = 1
	for byte in text.to_utf8() {
		if byte == 10 {
			$expected = $expected + 1
		}
	}
	if text == wrap_text {
		$expected = 6
	}
	parts_valid = if $fragments == 1 $whole == 1 and $first == 0 and $middle == 0 and $last == 0 else $whole == 0 and $first == 1 and $last == 1 and $middle + 2 == $fragments
	if !parts_valid or $cursor != $expected + 1 {
		return Err(ReportFailure)
	}
	Ok({ fragments: $fragments, lines: $expected })
}

## Three independently owned placements, two sharing the exact source bytes.
## The distinct middle source gives the repeated source a later arena offset.
multiple_evidence : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
multiple_evidence = |context| {
	if context != 0 {
		return Err(InvalidCase)
	}
	registered = faces(False)?
	shared = "same = 1\n\n  keep = same"
	distinct = "different = 2\n\n    keep = different\n"
	first = Pdf.source_block({ text: shared, face: registered.mono })
	second = Pdf.source_block({ text: distinct, face: registered.mono })
	document = Pdf.document({ title: "Independent source placements", language: "en", contents: [first, Pdf.paragraph("Between source blocks."), second, first] })
	theme : Theme
	theme = { body: { size: 11, leading: 15 } }
	{ prepared, report } = Pdf.prepare_with_report(document, { theme, fonts: Registered(registered.registry) }) ? PdfFailure
	bytes = Pdf.to_bytes_prepared(prepared) ? PdfFailure
	expected = [{ path: "contents[0]", count: 3 }, { path: "contents[2]", count: 4 }, { path: "contents[3]", count: 3 }]
	var $index = 0
	for outcome in report.facts.outcomes {
		match outcome {
			SourceFragmentPlaced(fragment) => {
				entry = match expected.get($index) {
					Ok(value) => value
					Err(_) => return Err(ReportFailure)
				}
				if fragment.path != entry.path or fragment.part != Whole or fragment.page != 1 or fragment.visual_lines.first != 1 or fragment.visual_lines.count != entry.count or fragment.rect.size.height.raw() != entry.count.to_i64_wrap() * 12000 + 16000 {
					return Err(ReportFailure)
				}
				$index = $index + 1
			}
			_ => {}
		}
	}
	if $index != 3 {
		return Err(ReportFailure)
	}
	body_font = registered.registry.prepared_face(registered.body) ? |_| FontFailure
	mono_font = registered.registry.prepared_face(registered.mono) ? |_| FontFailure
	styled = { faces: [registered.body, registered.mono], fonts: [body_font, mono_font], roles: { code: Inherited, emphasis: Inherited, quote: Inherited, strong: Inherited } }
	pipeline = KernelFacadePipeline.Plan.build_styled_with_facts(Document.normalize(document), styled, theme, page_size, descriptor, NoDocumentFacts, pipeline_limits) ? |_| PipelineFailure
	flow = KernelFacadePipeline.Plan.work(pipeline)
	Ok({ bytes, work: [shared.count_utf8_bytes() * 2 + distinct.count_utf8_bytes(), flow.shaped_runs, flow.lines, flow.pages, flow.final_runs, flow.fragments, flow.scene_commands, flow.objects, flow.shape_metric_reads, flow.line_candidate_visits, flow.page_candidate_visits, $index, 10, 0, bytes.len()] })
}

source_rejected : Try(List(U8), Pdf.Error), Str -> Bool
source_rejected = |outcome, feature| match outcome {
	Err(InvalidDocument(batch)) => batch.diagnostics.any(
		|diagnostic| {
			feature_matches = match diagnostic.feature {
				Feature(name) => name == feature
				NoFeature => False
			}
			feature_matches and diagnostic.details == ["contents[2]"]
		},
	)
	_ => False
}

page_size : Layout.Size
page_size = { height: 842, width: 595 }

descriptor : KernelPdfFont.Descriptor
descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

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

foreground_evidence : U64, U64, Bool -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
foreground_evidence = |kind, lines, colored| {
	if lines > 600 {
		return Err(InvalidCase)
	}
	keyword : Color.SourceValue
	keyword = "#8000c0"
	string : Color.SourceValue
	string = "#0050d0"
	comment : Color.SourceValue
	comment = "#008040"
	var $ranges = []
	var $bytes = []
	if kind == 0 or kind == 3 {
		text = "\tlet café = \"blue\"\r\n\r\n  # comment  \n\n"
		# Original UTF-8 offsets, including tab and both CRLF bytes.
		return evidence({ text, highlighted: True, repeat_source: kind == 3, foregrounds: if colored [{ start: 0, end: 4, color: keyword }, { start: 5, end: 10, color: string }, { start: 13, end: 19, color: string }, { start: 25, end: 36, color: comment }] else [] })
	} else if kind == 1 {
		text = "${wrap_text}\n${long_text(80)}"
		return evidence({ text, highlighted: True, foregrounds: if colored [{ start: 0, end: 122, color: string }, { start: 123, end: text.count_utf8_bytes(), color: comment }] else [] })
	} else if kind == 4 {
		text = "iii Www Mmm eek !99 = blue\nsecond line with words\n"
		return evidence({ text, highlighted: True, source_body: True, foregrounds: if colored [{ start: 0, end: 3, color: keyword }, { start: 4, end: 7, color: string }, { start: 8, end: 12, color: comment }] else [] })
	} else if kind == 2 {
		var $line = 0
		while $line < lines {
			start = $bytes.len()
			for byte in "let x = 42 # note\n".to_utf8() {
				$bytes = $bytes.append(byte)
			}
			if colored {
				$ranges = $ranges.append({ start, end: start + 3, color: keyword })
				$ranges = $ranges.append({ start: start + 8, end: start + 10, color: string })
				$ranges = $ranges.append({ start: start + 11, end: start + 16, color: comment })
			}
			$line = $line + 1
		}
		text = match Str.from_utf8($bytes) {
			Ok(value) => value
			Err(_) => crash "foreground fixture UTF8"
		}
		return evidence({ text, scale: lines, highlighted: True, foregrounds: $ranges })
	}
	Err(InvalidCase)
}

source_report_counts : Pdf.Report -> { fragments : U64, lines : U64 }
source_report_counts = |report| {
	var $fragments = 0
	var $lines = 0
	for outcome in report.facts.outcomes {
		match outcome {
			SourceFragmentPlaced(fragment) => {
				$fragments = $fragments + 1
				$lines = $lines + fragment.visual_lines.count
			}
			_ => {}
		}
	}
	{ fragments: $fragments, lines: $lines }
}

foreground_rejected : Try(List(U8), Pdf.Error), Str, U64, U64, Str -> Bool
foreground_rejected = |outcome, feature, range, byte, reason| match outcome {
	Err(InvalidDocument({ diagnostics: [{ details, feature: Feature(name), location: Document, message, .. }], truncation: Complete, .. })) => details == ["contents[2]"] and name == feature and message.contains("range ${range.to_str()} at original UTF-8 byte ${byte.to_str()}") and message.contains(reason)
	_ => False
}
