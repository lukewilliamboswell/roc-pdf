import pdf.Color
import pdf.Font
import pdf.KernelEmit
import pdf.KernelContent
import pdf.KernelColor
import pdf.KernelFont
import pdf.KernelFontPlan
import pdf.KernelFontSubset
import pdf.KernelObjectPlan
import pdf.KernelFontObjects
import pdf.KernelTaggedTextStructure
import pdf.KernelImage
import pdf.KernelObject
import pdf.KernelPdfFont
import pdf.KernelPdfText
import pdf.KernelResourceUse
import pdf.KernelScene
import pdf.KernelSemantics
import pdf.KernelShape
import pdf.KernelTextSemantics
import pdf.KernelTextOwnership
import pdf.KernelUnicode
import pdf.Layout
import pdf.Semantics
import pdf.Scene
import pdf.Text
import pdf.Image
import "../../package/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)

## Kernel lowering of node facts that no public constructor produces yet:
## an `en-AU` Document owning a Table (with `/Alt` and a Table-owned
## `Summary`), one row with a column-scoped TH and a TD whose `Headers`
## attribute names the TH's element identifier, a typed `HeaderFor` relation,
## a nested `fr` language on the TD, and a `fr-FR` Span with `/E` and
## `/ActualText` that owns the painted text. The path has no document facts,
## so the Document's own language is its unexpressed default.
Lowering :: [].{
	lowering : {} -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure])
	lowering = |_| {
		sample = build_sample({}) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(KernelTaggedTextStructure.Plan.structure(sample.structure)) ? |_| EvidenceFailure
		semantic_work = KernelSemantics.Plan.work(KernelTextSemantics.Plan.semantics(sample.semantic))
		tagged_work = KernelTaggedTextStructure.Plan.work(sample.structure).tagged_objects
		Ok({
			bytes,
			work: [
				semantic_work.node_visits,
				semantic_work.containment_edges,
				semantic_work.identifier_visits,
				semantic_work.relationship_visits,
				semantic_work.attribute_visits,
				semantic_work.max_semantic_depth,
				tagged_work.structure_elements,
				tagged_work.attribute_dictionaries,
				tagged_work.id_tree_entries,
				tagged_work.language_entries,
				bytes.len(),
			],
		})
	}
}

Sample := {
	semantic : KernelTextSemantics.Plan,
	structure : KernelTaggedTextStructure.Plan,
}

build_sample : {} -> Try(Sample, [AnalysisFailure, ColorFailure, ContentFailure, FontFailure, FontObjectFailure, FontPlanFailure, ImageFailure, ObjectFailure, OwnershipFailure, ResourceFailure, SceneFailure, SemanticFailure, ShapeFailure, StructureFailure, SubsetFailure, TextFailure])
build_sample = |_| {
	analysis = KernelUnicode.analyze(
		source,
		{ max_graphemes: 32, max_line_boundaries: 33, max_scalars: 32, max_script_runs: 8 },
	) ? |_| AnalysisFailure
	semantic = KernelTextSemantics.Plan.build(
		semantics,
		1,
		1,
		KernelSemantics.Limits.make({ max_attributes: 4, max_content_spine: 6, max_fragments: 1, max_namespaces: 1, max_nodes: 6, max_occurrences: 1, max_semantic_depth: 5 }),
		KernelTextSemantics.Limits.make({ max_text_properties: 3, max_text_property_bytes: 64, max_text_source_bytes: 9, max_text_source_scalars: 8, max_text_sources: 1 }),
	) ? |_| SemanticFailure
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
			language: Language("fr-FR"),
			occurrence: Semantics.OccurrenceId.from_index(0),
			script: Font.Script.from_iso15924("Latn"),
			size: Layout.Unit.from_raw(11000),
			writing_mode: Horizontal,
		},
		KernelShape.Limits.make({ max_clusters: 32, max_glyphs: 32, max_scalars: 32, max_source_bytes: 128 }),
	) ? |_| ShapeFailure
	scene = KernelScene.Plan.build(
		text_scene,
		KernelScene.Resources.with_text({ color_spaces: 1, images: 0, text_runs: shape.store.runs.len() }),
		KernelScene.Limits.make({ max_commands: 2, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 1, max_pages: 1, max_path_segments: 0, max_paths: 0 }),
	) ? |_| SceneFailure
	ownership = KernelTextOwnership.Plan.build(semantic, scene, shape.store) ? |_| OwnershipFailure
	usages = shape.store.glyphs.map(|glyph| { glyph: glyph.id.raw() })
	font_plan = KernelFontPlan.plan(font, usages, KernelFontPlan.Limits.make({ max_retained_glyphs: 64 })) ? |_| FontPlanFailure
	subset = KernelFontSubset.build(font, font_plan) ? |_| SubsetFailure
	colors = KernelColor.Plan.build(text_colors, KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 })) ? |_| ColorFailure
	images = KernelImage.Plan.build(
		{ resources: [] },
		colors,
		KernelImage.Limits.make({ max_decoded_bytes: 0, max_encoded_bytes: 0, max_height: 0, max_markers: 0, max_resources: 0, max_width: 0 }),
	) ? |_| ImageFailure
	resource_use = KernelResourceUse.TextPlan.build(scene, colors, images) ? |_| ResourceFailure
	text = KernelPdfText.ScenePlan.build(
		ownership,
		[font_plan],
		KernelPdfText.Limits.make({ max_actual_text_scalars: 64, max_content_bytes: 4096, max_mappings: 64, max_placements: 0, max_source_scalars: 64 }),
	) ? |_| TextFailure
	tagged = KernelTextOwnership.Plan.tagged(ownership)
	content = KernelContent.Plan.build_with_text(
		tagged,
		KernelPdfText.ScenePlan.content(text),
		KernelContent.Limits.make({ max_content_bytes: 4096, max_content_streams: 1 }),
	) ? |_| ContentFailure
	base_objects = KernelObjectPlan.Plan.build_with_text(
		tagged,
		colors,
		images,
		resource_use,
		content,
		KernelObjectPlan.Limits.make({ max_objects: 40, max_pages: 1 }),
	) ? |_| ObjectFailure
	font_objects = KernelFontObjects.Plan.build(base_objects, 1, 40) ? |_| FontObjectFailure
	structure = KernelTaggedTextStructure.Plan.build(
		tagged,
		colors,
		images,
		content,
		font_objects,
		text,
		[{ descriptor: { flags: 32, italic_angle: 0, stem_v: 80 }, font, plan: font_plan, subset }],
		KernelTaggedTextStructure.Limits.make({
			font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 8192, max_unicode_mappings: 64, max_unicode_scalars: 128 }),
			object_limits: object_limits,
		}),
	) ? |_| StructureFailure
	Ok({ semantic, structure })
}

text_scene : Scene.Store
text_scene = {
	commands: [
		Transform({
			children: Semantics.Range.from_start_and_length(1, 1),
			matrix: { a: Layout.Unit.from_raw(1000), b: Layout.Unit.from_raw(0), c: Layout.Unit.from_raw(0), d: Layout.Unit.from_raw(1000), e: Layout.Unit.from_raw(72000), f: Layout.Unit.from_raw(700000) },
		}),
		DrawText({
			paint: {
				fill: { channels: Gray(0), space: Color.SpaceId.from_index(0) },
				mode: Fill,
				opacity: 65535,
				stroke: NoStroke,
			},
			run: Text.RunId.from_index(0),
		}),
	],
	dash_lengths: [],
	groups: [{ commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) }],
	page_groups: [Scene.GroupId.from_index(0)],
	pages: [
		{
			boxes: { art: a4_box, bleed: a4_box, crop: a4_box, media: a4_box, trim: a4_box },
			id: Semantics.PageId.from_index(0),
			paint_order: Semantics.Range.from_start_and_length(0, 1),
			rotation: Rotate0,
		},
	],
	path_segments: [],
	paths: [],
}

a4_box : Layout.Rect
a4_box = { origin: { x: Layout.Unit.from_raw(0), y: Layout.Unit.from_raw(0) }, size: { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) } }

text_colors : Color.Store
text_colors = {
	profiles: [],
	spaces: [{ id: Color.SpaceId.from_index(0), space: CalibratedGray({ black_point: { x: 0, y: 0, z: 0 }, white_point: { x: 950000, y: 1000000, z: 1089000 } }) }],
	tags: [],
}

source : Str
source = "Café PDF"

source_range : Semantics.TextRange
source_range = {
	scalars: Semantics.Range.from_start_and_length(0, 8),
	utf8_bytes: Semantics.Range.from_start_and_length(0, 9),
}

range : U64, U64 -> Semantics.Range
range = |start, length| Semantics.Range.from_start_and_length(start, length)

node : { attributes : Semantics.Range, content : Semantics.Range, element : [HasElementIdentifier(Semantics.ElementId), NoElementIdentifier], index : U64, language : Semantics.Language, parent : U64, properties : Semantics.Range, role : Str } -> Semantics.Node
node = |spec| {
	attributes: spec.attributes,
	content: spec.content,
	element_identifier: spec.element,
	id: Semantics.NodeId.from_index(spec.index),
	language: spec.language,
	parent: if spec.index == 0 DocumentRoot else ParentNode(Semantics.NodeId.from_index(spec.parent)),
	role: { local_name: spec.role, namespace: Semantics.NamespaceId.from_index(0) },
	structure_element: Semantics.StructureElementId.from_index(spec.index),
	text_properties: spec.properties,
}

## Document > Table > TR > (TH, TD > Span). Element identifiers are stored in
## ascending byte order: `cell-price` (TD) then `hdr-price` (TH).
semantics : Semantics.Store
semantics = {
	annotations: [],
	assertions: [],
	attribute_roles: [],
	attributes: [
		{ applicability: Family(TableRoles), name: Standard("Summary"), owner: Table, value: Text("One priced item with its column header.") },
		{ applicability: Family(TableRoles), name: Standard("Scope"), owner: Table, value: Name("Column") },
		{ applicability: Family(TableRoles), name: Standard("Headers"), owner: Table, value: Names(["hdr-price"]) },
	],
	content_spine: [
		ChildNode(Semantics.NodeId.from_index(1)),
		ChildNode(Semantics.NodeId.from_index(2)),
		ChildNode(Semantics.NodeId.from_index(3)),
		ChildNode(Semantics.NodeId.from_index(4)),
		ChildNode(Semantics.NodeId.from_index(5)),
		ContentOccurrence(Semantics.OccurrenceId.from_index(0)),
	],
	contextual_artifacts: [],
	document_root: Semantics.NodeId.from_index(0),
	element_identifiers: [{ id: Semantics.ElementId.from_index(0), value: "cell-price" }, { id: Semantics.ElementId.from_index(1), value: "hdr-price" }],
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
		node({ attributes: range(0, 0), content: range(0, 1), element: NoElementIdentifier, index: 0, language: Language("en-AU"), parent: 0, properties: range(0, 0), role: "Document" }),
		node({ attributes: range(0, 1), content: range(1, 1), element: NoElementIdentifier, index: 1, language: Inherited, parent: 0, properties: range(0, 1), role: "Table" }),
		node({ attributes: range(1, 0), content: range(2, 2), element: NoElementIdentifier, index: 2, language: Inherited, parent: 1, properties: range(1, 0), role: "TR" }),
		node({ attributes: range(1, 1), content: range(4, 0), element: HasElementIdentifier(Semantics.ElementId.from_index(1)), index: 3, language: Inherited, parent: 2, properties: range(1, 0), role: "TH" }),
		node({ attributes: range(2, 1), content: range(4, 1), element: HasElementIdentifier(Semantics.ElementId.from_index(0)), index: 4, language: Language("fr"), parent: 2, properties: range(1, 0), role: "TD" }),
		node({ attributes: range(3, 0), content: range(5, 1), element: NoElementIdentifier, index: 5, language: Language("fr-FR"), parent: 4, properties: range(1, 2), role: "Span" }),
	],
	non_text_sources: [],
	occurrence_fragments: [Semantics.FragmentId.from_index(0)],
	occurrences: [
		{
			fragments: range(0, 1),
			id: Semantics.OccurrenceId.from_index(0),
			language: Language("fr-FR"),
			source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange(source_range)),
			text_properties: range(3, 0),
		},
	],
	relationships: [HeaderFor({ cell: Semantics.ElementId.from_index(0), header: Semantics.ElementId.from_index(1) })],
	role_mappings: [],
	text_properties: [AlternativeText("A one-row price table"), ExpandedText("Café Portable Document Format"), ActualText("Café PDF")],
	text_sources: [{ unicode: source }],
}

object_limits : KernelObject.Limits
object_limits = {
	max_array_items: 128,
	max_byte_string_bytes: 128,
	max_byte_strings: 16,
	max_dictionary_entries: 192,
	max_direct_depth: 8,
	max_name_bytes: 4096,
	max_names: 160,
	max_objects: 40,
	max_payload_bytes: 200000,
	max_payloads: 4,
	max_streams: 4,
	max_text_string_bytes: 512,
	max_text_strings: 16,
	max_values: 384,
}
