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
import KernelUnicode
import Layout
import Semantics
import Text
import Theme
import "../tests/assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)
import "../tests/assets/CallerFont-Restricted.ttf" as restricted_font_bytes : List(U8)

Gate3CallerTextEvidence :: [].{
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
				sample.registration.input_bytes,
				sample.registration.retained_input_bytes,
				sample.registration.copied_input_bytes,
				sample.registration.table_visits,
				sample.registration.glyph_visits,
				sample.registration.cmap_mapping_visits,
				sample.registration.component_edge_visits,
				sample.selected_face,
				sample.shape.store.runs.len(),
				sample.shape.store.glyphs.len(),
				sample.font_plan.entries.len(),
				sample.subset.work.output_bytes,
				text_work.source_scalar_visits,
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
	font_plan : KernelFontPlan.Plan,
	registration : Font.RegistrationWork,
	selected_face : U64,
	shape : KernelShape.Shape,
	structure : KernelGate3TextStructure.Plan,
	subset : KernelFontSubset.Subset,
	text : KernelPdfText.Plan,
}

build_sample : {} -> Try(Sample, [AnalysisFailure, FontFailure, FontPlanFailure, ShapeFailure, StructureFailure, SubsetFailure, TextFailure])
build_sample = |_| {
	registered = Font.Registry.empty.register(
		caller_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		Font.ValidationLimits.default,
	) ? |_| FontFailure
	font = registered.registry.prepared_face(registered.face) ? |_| FontFailure
	theme = Theme.with_font(Theme.default, registered.face)
	if theme.body_font().index() != registered.face.index() {
		return Err(FontFailure)
	}
	analysis = KernelUnicode.analyze(
		source,
		{ max_graphemes: 32, max_line_boundaries: 33, max_scalars: 32, max_script_runs: 8 },
	) ? |_| AnalysisFailure
	shape = KernelShape.shape_simple(
		font,
		source,
		analysis,
		{
			direction: LeftToRight,
			instance: registered.instance,
			language: Language("en-AU"),
			occurrence: Semantics.OccurrenceId.from_index(0),
			script: Font.Script.from_iso15924("Latn"),
			size: Layout.Unit.from_raw(11000),
			writing_mode: Horizontal,
		},
		KernelShape.Limits.make({ max_clusters: 32, max_glyphs: 32, max_scalars: 32, max_source_bytes: 128 }),
	) ? |_| ShapeFailure
	font_plan = KernelFontPlan.plan(font, glyph_usages(shape.store.glyphs), KernelFontPlan.Limits.make({ max_retained_glyphs: 64 })) ? |_| FontPlanFailure
	subset = KernelFontSubset.build(font, font_plan) ? |_| SubsetFailure
	text = KernelPdfText.Plan.build(
		semantics,
		shape.store,
		[font_plan],
		[{ origin: { x: Layout.Unit.from_raw(72000), y: Layout.Unit.from_raw(700000) }, run: Text.RunId.from_index(0) }],
		KernelPdfText.Limits.make({ max_actual_text_scalars: 64, max_content_bytes: 4096, max_mappings: 64, max_placements: 8, max_source_scalars: 64 }),
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
	Ok({
		font_plan,
		registration: registered.work,
		selected_face: theme.body_font().index(),
		shape,
		structure,
		subset,
		text,
	})
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
descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

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

## The prohibited twin is checksum-valid but never returns usable handles.
expect match Font.Registry.empty.register(
	restricted_font_bytes,
	{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
	Font.ValidationLimits.default,
) {
	Err(EmbeddingRightsProhibited({ fs_type: 2 })) => Bool.True
	_ => Bool.False
}

expect {
	sample = build_sample({})?
	KernelGate3TextStructure.Plan.work(sample.structure).fonts == 1 and sample.selected_face == 0
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "Gate 3 caller text evidence index escaped"
	}
	Ok(value) => value
}
