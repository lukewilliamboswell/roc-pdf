import Font
import KernelEmit
import KernelFont
import KernelFontPlan
import KernelFontSubset
import KernelGate3TextStructure
import KernelObject
import KernelPdfFont
import KernelPdfText
import KernelShape
import KernelStructure
import KernelUnicode
import Layout
import Semantics
import Text
import "../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)

Gate3TextEvidence :: [].{
	visible_text : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	visible_text = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		sample = build_sample({}) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(KernelGate3TextStructure.Plan.structure(sample.structure)) ? |_| EvidenceFailure
		text_work = KernelPdfText.Plan.work(sample.text)
		structure_work = KernelGate3TextStructure.Plan.work(sample.structure)
		Ok({
			bytes,
			work: [
				sample.font.bytes.len(),
				sample.shape.store.runs.len(),
				sample.shape.store.glyphs.len(),
				sample.font_plan.entries.len(),
				sample.subset.work.output_bytes,
				text_work.source_scalar_visits,
				text_work.run_visits,
				text_work.placement_visits,
				text_work.glyph_visits,
				text_work.mappings,
				text_work.content_bytes,
				structure_work.fonts,
				structure_work.font_objects,
				structure_work.objects,
				structure_work.payload_bytes,
				bytes.len(),
			],
		})
	}
}

Sample := {
	font : KernelFont.Inspection,
	font_plan : KernelFontPlan.Plan,
	shape : KernelShape.Shape,
	structure : KernelGate3TextStructure.Plan,
	subset : KernelFontSubset.Subset,
	text : KernelPdfText.Plan,
}

build_sample : {} -> Try(Sample, [AnalysisFailure, FontFailure, FontPlanFailure, ShapeFailure, StructureFailure, SubsetFailure, TextFailure])
build_sample = |_| {
	analysis = KernelUnicode.analyze(
		source,
		{ max_graphemes: 32, max_line_boundaries: 33, max_scalars: 32, max_script_runs: 8 },
	) ? |_| AnalysisFailure
	font = KernelFont.inspect(
		built_in_font_bytes,
		KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
	) ? |_| FontFailure
	shape = KernelShape.shape_simple(
		font,
		source,
		analysis,
		{
			direction: LeftToRight,
			instance: Font.InstanceId.from_index(0),
			language: Language("en-AU"),
			occurrence: Semantics.OccurrenceId.from_index(0),
			script: Font.Script.from_iso15924("Latn"),
			size: Layout.Unit.from_raw(11000),
			writing_mode: Horizontal,
		},
		KernelShape.Limits.make({ max_clusters: 32, max_glyphs: 32, max_scalars: 32, max_source_bytes: 128 }),
	) ? |_| ShapeFailure
	usages = glyph_usages(shape.store.glyphs)
	font_plan = KernelFontPlan.plan(font, usages, KernelFontPlan.Limits.make({ max_retained_glyphs: 64 })) ? |_| FontPlanFailure
	subset = KernelFontSubset.build(font, font_plan) ? |_| SubsetFailure
	text = KernelPdfText.Plan.build(
		semantics,
		shape.store,
		[font_plan],
		[{ origin: { x: Layout.Unit.from_raw(72000), y: Layout.Unit.from_raw(700000) }, run: Text.RunId.from_index(0) }],
		KernelPdfText.Limits.make({ max_content_bytes: 4096, max_mappings: 64, max_placements: 8, max_source_scalars: 64 }),
	) ? |_| TextFailure
	structure = KernelGate3TextStructure.Plan.build(
		text,
		[{ descriptor, font, plan: font_plan, subset }],
		{ height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) },
		KernelGate3TextStructure.Limits.make({
			font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 8192, max_unicode_mappings: 64, max_unicode_scalars: 128 }),
			object_limits,
		}),
	) ? |_| StructureFailure
	Ok({ font, font_plan, shape, structure, subset, text })
}

glyph_usages : List(Text.Glyph) -> List(KernelFontPlan.Usage)
glyph_usages = |glyphs| {
	var $usages = List.with_capacity(glyphs.len())
	var $index = 0
	while $index < glyphs.len() {
		$usages = $usages.append({ glyph: list_at(glyphs, $index).id.raw() })
		$index = $index + 1
	}
	$usages
}

source : Str
source = "Café PDF"

source_range : Semantics.TextRange
source_range = {
	scalars: Semantics.Range.from_start_and_length(0, 8),
	utf8_bytes: Semantics.Range.from_start_and_length(0, 9),
}

empty_range : Semantics.Range
empty_range = Semantics.Range.from_start_and_length(0, 0)

semantics : Semantics.Store
semantics = {
	annotations: [],
	assertions: [],
	attribute_roles: [],
	attributes: [],
	content_spine: [ChildNode(Semantics.NodeId.from_index(1)), ContentOccurrence(Semantics.OccurrenceId.from_index(0))],
	contextual_artifacts: [],
	document_root: Semantics.NodeId.from_index(0),
	element_identifiers: [],
	fragments: [
		{
			content_stream: Semantics.ContentStreamId.from_index(0),
			continuation_index: 0,
			id: Semantics.FragmentId.from_index(0),
			occurrence: Semantics.OccurrenceId.from_index(0),
			page: Semantics.PageId.from_index(0),
			source_range: UnicodeRange(source_range),
		},
	],
	mathml_subtrees: [],
	namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
	nodes: [
		{
			attributes: empty_range,
			content: Semantics.Range.from_start_and_length(0, 1),
			element_identifier: NoElementIdentifier,
			id: Semantics.NodeId.from_index(0),
			language: Language("en-AU"),
			parent: DocumentRoot,
			role: { local_name: "Document", namespace: Semantics.NamespaceId.from_index(0) },
			structure_element: Semantics.StructureElementId.from_index(0),
			text_properties: empty_range,
		},
		{
			attributes: empty_range,
			content: Semantics.Range.from_start_and_length(1, 1),
			element_identifier: NoElementIdentifier,
			id: Semantics.NodeId.from_index(1),
			language: Language("en-AU"),
			parent: ParentNode(Semantics.NodeId.from_index(0)),
			role: { local_name: "P", namespace: Semantics.NamespaceId.from_index(0) },
			structure_element: Semantics.StructureElementId.from_index(1),
			text_properties: empty_range,
		},
	],
	non_text_sources: [],
	occurrence_fragments: [Semantics.FragmentId.from_index(0)],
	occurrences: [
		{
			fragments: Semantics.Range.from_start_and_length(0, 1),
			id: Semantics.OccurrenceId.from_index(0),
			language: Language("en-AU"),
			source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange(source_range)),
			text_properties: empty_range,
		},
	],
	relationships: [],
	role_mappings: [],
	text_properties: [],
	text_sources: [{ unicode: source }],
}

descriptor : KernelPdfFont.Descriptor
descriptor = { cap_height: 2076, flags: 32, italic_angle: 0, postscript_name: Str.to_utf8("RocPdfSans-Regular"), stem_v: 80 }

object_limits : KernelObject.Limits
object_limits = {
	max_array_items: 64,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 128,
	max_direct_depth: 8,
	max_name_bytes: 2048,
	max_names: 64,
	max_objects: 14,
	max_payload_bytes: 200000,
	max_payloads: 4,
	max_streams: 4,
	max_text_string_bytes: 32,
	max_text_strings: 2,
	max_values: 256,
}

expect {
	sample = build_sample({})?
	structure = KernelGate3TextStructure.Plan.structure(sample.structure)
	font_objects = KernelGate3TextStructure.Plan.font_objects(sample.structure)
	first = list_at(font_objects, 0)
	KernelStructure.Plan.object_count(structure) == 14 and
		KernelObject.ObjectId.number(first.font_file) == 6 and
			KernelObject.ObjectId.number(first.type0) == 14 and
				KernelPdfText.Plan.mappings(sample.text).len() == 1 and
					list_at(KernelPdfText.Plan.mappings(sample.text), 0).len() == 8
}

## Placement and ActualText failures are atomic rather than guessed or omitted.
expect {
	sample = build_sample({})?
	placement = { origin: { x: Layout.Unit.from_raw(72000), y: Layout.Unit.from_raw(700000) }, run: Text.RunId.from_index(0) }
	limits = KernelPdfText.Limits.make({ max_content_bytes: 4096, max_mappings: 64, max_placements: 8, max_source_scalars: 64 })
	missing_rejected = match KernelPdfText.Plan.build(semantics, sample.shape.store, [sample.font_plan], [], limits) {
		Err(RunInvalid({ run: 0 })) => Bool.True
		_ => Bool.False
	}
	duplicate_rejected = match KernelPdfText.Plan.build(semantics, sample.shape.store, [sample.font_plan], [placement, placement], limits) {
		Err(PlacementInvalid({ placement: 1 })) => Bool.True
		_ => Bool.False
	}
	run = list_at(sample.shape.store.runs, 0)
	override_store = { ..sample.shape.store, runs: [{ ..run, actual_text: SemanticOverride(Semantics.TextPropertyId.from_index(0)) }] }
	override_rejected = match KernelPdfText.Plan.build(semantics, override_store, [sample.font_plan], [placement], limits) {
		Err(ActualTextRequired({ run: 0 })) => Bool.True
		_ => Bool.False
	}
	missing_rejected and duplicate_rejected and override_rejected
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "Gate 3 text evidence index escaped"
	}
	Ok(value) => value
}
