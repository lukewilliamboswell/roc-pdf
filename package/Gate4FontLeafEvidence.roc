import Color
import Font
import Image
import KernelColor
import KernelContent
import KernelEmit
import KernelFont
import KernelFontLeaf
import KernelFontPlan
import KernelFontSubset
import KernelForm
import KernelGate2Objects
import KernelGate4FormObjects
import KernelGate4FormStructure
import KernelImage
import KernelObject
import KernelPdfFont
import KernelPdfText
import KernelResourceGraph
import KernelResourceUse
import KernelScene
import KernelSemantics
import KernelTagged
import KernelTextOwnership
import KernelTextSemantics
import Layout
import Scene
import Semantics
import Text
import "../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)
import "../tests/assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)

## Gate 4 canonical font-leaf evidence.
##
## Every pipeline scenario authors validated shaped runs over real inspected
## faces, derives one canonical font-leaf recipe per authored font, runs the
## complete production pipeline (facts, ownership, text lowering, canonical
## planning, content lowering, object planning, assembly, sealing, emission),
## and emits real PDF bytes plus deterministic work counters:
##
## - `showcase`: one exact subset shared by placements on two pages and
##   inside a Form XObject, an independently authored equivalent bundle that
##   collapses into it, a distinct-closure leaf, and a different source
##   face — with the fully reversed authored font order byte-compared.
## - `facts`: the distinctness matrix — same face with a different glyph
##   closure, equal glyph sets with different ToUnicode facts (deliberately
##   sharing one BaseFont tag), equal glyph sets under a different
##   descriptor policy, and a different source face.
## - `unique`/`shared`: one-shot versus deliberately retained input.
## - `share`: one canonical subset under N placements.
## - `dedupe`: N independently authored equivalent bundles collapsing to one.
## - `distinct`: N genuinely different closures staying distinct, with the
##   reversed authored order byte-compared.
## - `collide`: derived recipes forced into one digest bucket through the
##   graph's white-box test seam; exact equality collapses only true twins.
## - `negative`: the atomic rejection sweep; no plan or PDF byte escapes.
Gate4FontLeafEvidence :: [].{
	EvidenceError : [
		AdversarialOrderDiverged,
		CollisionDiverged,
		EvidenceFailure,
		InvalidScale,
		MissingRejection(U64),
		SharedInputDiverged,
		SharingDiverged,
	]

	scenario : Str, U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	scenario = |mode, scale| run_scenario(mode, scale)
}

unit : I64 -> Layout.Unit
unit = |raw| Layout.Unit.from_raw(raw)

rect : I64, I64, I64, I64 -> Layout.Rect
rect = |x, y, width, height| { origin: { x: unit(x), y: unit(y) }, size: { height: unit(height), width: unit(width) } }

translate : I64, I64 -> Scene.Matrix
translate = |x, y| { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(x), f: unit(y) }

empty_range : Semantics.Range
empty_range = Semantics.Range.from_start_and_length(0, 0)

span : U64, U64 -> Semantics.Range
span = |start, length| Semantics.Range.from_start_and_length(start, length)

page_box : Layout.Rect
page_box = rect(0, 0, 100000, 100000)

## Exactly one function body restores each packed font-bytes literal; every
## consumer goes through it (the roc-lang/roc#10697-family workaround shape).
builtin_bytes : {} -> List(U8)
builtin_bytes = |_| built_in_font_bytes

caller_bytes : {} -> List(U8)
caller_bytes = |_| caller_font_bytes

FaceKind := [BuiltIn, CallerFace]

## One authored font: a validated face, a descriptor policy, and the exact
## scalar set whose glyphs the subset retains.
FontSpec := { face : FaceKind, policy : KernelPdfFont.Descriptor, scalars : List(U32) }

## One shaped run: the authored font it selects, its page, its paint site,
## the occurrence text scalars, and the scalars whose glyphs it paints.
RunSite := [InForm({ x : I64, y : I64 }), OnPage({ x : I64, y : I64 })]

RunSpec := { font : U64, glyphs : List(U32), page : U64, site : RunSite, text : List(U32) }

Spec := { fonts : List(FontSpec), pages : U64, runs : List(RunSpec) }

standard_policy : KernelPdfFont.Descriptor
standard_policy = { flags: 32, italic_angle: 0, stem_v: 80 }

text_colors : Color.Store
text_colors = {
	profiles: [],
	spaces: [{ id: Color.SpaceId.from_index(0), space: CalibratedGray({ black_point: { x: 0, y: 0, z: 0 }, white_point: { x: 950000, y: 1000000, z: 1089000 } }) }],
	tags: [],
}

color_limits : KernelColor.Limits
color_limits = KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 })

no_image_limits : KernelImage.Limits
no_image_limits = KernelImage.Limits.make({ max_decoded_bytes: 0, max_encoded_bytes: 0, max_height: 0, max_markers: 0, max_resources: 0, max_width: 0 })

text_paint : Scene.TextPaint
text_paint = {
	fill: { channels: Gray(0), space: Color.SpaceId.from_index(0) },
	mode: Fill,
	opacity: 65535,
	stroke: NoStroke,
}

graph_limits : KernelResourceGraph.Limits
graph_limits = {
	max_collision_entries: 8192,
	max_edges: 16384,
	max_equality_bytes: 8388608,
	max_hash_bytes: 8388608,
	max_hashes: 8192,
	max_ordering_work: 8388608,
	max_payload_bytes: 8388608,
	max_placements: 8192,
	max_resources: 8192,
	max_root_uses: 8192,
	max_roots: 8,
	max_topological_work: 1048576,
}

form_limits : KernelForm.Limits
form_limits = KernelForm.Limits.make({ graph: graph_limits, max_mask_depth: 4, max_opacity_depth: 64, max_recipe_bytes: 4194304 })

scene_limits : KernelScene.Limits
scene_limits = KernelScene.Limits.make({
	max_commands: 65536,
	max_dash_lengths: 0,
	max_graphics_depth: 8,
	max_groups: 4096,
	max_pages: 4,
	max_path_segments: 0,
	max_paths: 0,
})

form_scene_limits : KernelScene.FormLimits
form_scene_limits = KernelScene.FormLimits.make({ max_form_commands: 64, max_forms: 4 })

## The inspection limits carry the runtime guard (always zero) so the
## pipelines below are runtime work under the measurement boundary rather
## than compile-time constants.
font_inspection_limits : U64 -> KernelFont.Limits
font_inspection_limits = |guard| KernelFont.Limits.make({ max_bytes: 200000 + guard, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })

font_plan_limits : KernelFontPlan.Limits
font_plan_limits = KernelFontPlan.Limits.make({ max_retained_glyphs: 256 })

text_limits : KernelPdfText.Limits
text_limits = KernelPdfText.Limits.make({ max_actual_text_scalars: 64, max_content_bytes: 1048576, max_mappings: 4096, max_placements: 0, max_source_scalars: 4096 })

content_limits : KernelContent.Limits
content_limits = KernelContent.Limits.make({ max_content_bytes: 1048576, max_content_streams: 4 })

object_limits : KernelObject.Limits
object_limits = {
	max_array_items: 65536,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 65536,
	max_direct_depth: 8,
	max_name_bytes: 65536,
	max_names: 8192,
	max_objects: 8192,
	max_payload_bytes: 8388608,
	max_payloads: 4096,
	max_streams: 4096,
	max_text_string_bytes: 65536,
	max_text_strings: 2048,
	max_values: 262144,
}

structure_limits : KernelGate4FormStructure.Limits
structure_limits = KernelGate4FormStructure.Limits.make({
	font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 65536, max_unicode_mappings: 4096, max_unicode_scalars: 8192 }),
	object_limits,
})

semantic_limits : U64, U64, U64 -> KernelSemantics.Limits
semantic_limits = |nodes, spine, fragments| KernelSemantics.Limits.make({
	max_attributes: 0,
	max_content_spine: spine,
	max_fragments: fragments,
	max_namespaces: 1,
	max_nodes: nodes,
	max_occurrences: nodes,
	max_semantic_depth: 2,
})

text_semantic_limits : U64, U64 -> KernelTextSemantics.Limits
text_semantic_limits = |source_bytes, source_scalars| KernelTextSemantics.Limits.make({
	max_text_properties: 0,
	max_text_property_bytes: 0,
	max_text_source_bytes: source_bytes,
	max_text_source_scalars: source_scalars,
	max_text_sources: 1,
})

BuildFailure := [
	ColorFailure(KernelColor.Error),
	ContentFailure(KernelContent.Error),
	EmitFailure,
	FactsFailure(KernelForm.Error),
	FontFailure(KernelFont.Error),
	FontLeafFailure(KernelFontLeaf.Error),
	FontPlanFailure(KernelFontPlan.Error),
	FormObjectFailure(KernelGate4FormObjects.Error),
	FormPlanFailure(KernelForm.Error),
	FormSceneFailure(KernelScene.Error),
	ImageFailure(KernelImage.Error),
	ObjectFailure(KernelGate2Objects.Error),
	OwnershipFailure(KernelTextOwnership.Error),
	ResourceUseFailure(KernelResourceUse.Error),
	SemanticFailure,
	SubsetFailure(KernelFontSubset.Error),
	StructureFailure(KernelGate4FormStructure.Error),
	TextFailure(KernelPdfText.Error),
	UncoveredScalar(U32),
]

Built := {
	bytes : List(U8),
	content : KernelContent.Plan,
	facts : KernelForm.Facts,
	form_plan : KernelForm.Plan,
	ownership : KernelTextOwnership.Plan,
	structure : KernelGate4FormStructure.Plan,
	text : KernelPdfText.ScenePlan,
}

## One prepared authored font: its shared inspection plus its own closure
## plan and sanitized subset.
PreparedFont := { font : KernelFont.Inspection, plan : KernelFontPlan.Plan, policy : KernelPdfFont.Descriptor, subset : KernelFontSubset.Subset }

utf8_length : U32 -> U64
utf8_length = |scalar| if scalar < 0x80 1 else if scalar < 0x800 2 else if scalar < 0x10000 3 else 4

append_utf8 : List(U8), U32 -> List(U8)
append_utf8 = |bytes, scalar| {
	if scalar < 0x80 {
		bytes.append(scalar.to_u8_wrap())
	} else if scalar < 0x800 {
		bytes
			.append(0xc0 + scalar.shr_wrap(6).to_u8_wrap())
			.append(0x80 + scalar.bitwise_and(0x3f).to_u8_wrap())
	} else if scalar < 0x10000 {
		bytes
			.append(0xe0 + scalar.shr_wrap(12).to_u8_wrap())
			.append(0x80 + scalar.shr_wrap(6).bitwise_and(0x3f).to_u8_wrap())
			.append(0x80 + scalar.bitwise_and(0x3f).to_u8_wrap())
	} else {
		bytes
			.append(0xf0 + scalar.shr_wrap(18).to_u8_wrap())
			.append(0x80 + scalar.shr_wrap(12).bitwise_and(0x3f).to_u8_wrap())
			.append(0x80 + scalar.shr_wrap(6).bitwise_and(0x3f).to_u8_wrap())
			.append(0x80 + scalar.bitwise_and(0x3f).to_u8_wrap())
	}
}

## Prepare each authored font once: shared inspection per face, then the
## deterministic closure plan and sanitized subset for its exact scalar set.
prepare_fonts : List(FontSpec), U64 -> Try(List(PreparedFont), BuildFailure)
prepare_fonts = |specs, guard| {
	builtin = KernelFont.inspect(builtin_bytes({}), font_inspection_limits(guard)) ? FontFailure
	var $uses_caller = Bool.False
	var $scan = 0
	while $scan < specs.len() {
		match list_at(specs, $scan).face {
			BuiltIn => {}
			CallerFace => {
				$uses_caller = Bool.True
			}
		}
		$scan = $scan + 1
	}
	caller = if $uses_caller {
		inspected = KernelFont.inspect(caller_bytes({}), font_inspection_limits(guard)) ? FontFailure
		[inspected]
	} else {
		[]
	}
	var $prepared = List.with_capacity(specs.len())
	var $index = 0
	var $failure = NoFailure
	while $index < specs.len() and $failure == NoFailure {
		spec = list_at(specs, $index)
		inspection = match spec.face {
			BuiltIn => builtin
			CallerFace => list_at(caller, 0)
		}
		var $usages = List.with_capacity(spec.scalars.len())
		var $scalar_index = 0
		while $scalar_index < spec.scalars.len() and $failure == NoFailure {
			scalar = list_at(spec.scalars, $scalar_index)
			match KernelFont.glyph_for_scalar(inspection, scalar) {
				None => {
					$failure = Failed(UncoveredScalar(scalar))
				}
				Some(glyph) => {
					$usages = $usages.append({ glyph: glyph })
				}
			}
			$scalar_index = $scalar_index + 1
		}
		if $failure == NoFailure {
			match KernelFontPlan.plan(inspection, $usages, font_plan_limits) {
				Err(error) => {
					$failure = Failed(FontPlanFailure(error))
				}
				Ok(plan) => match KernelFontSubset.build(inspection, plan) {
					Err(error) => {
						$failure = Failed(SubsetFailure(error))
					}
					Ok(subset) => {
						$prepared = $prepared.append({ font: inspection, plan, policy: spec.policy, subset })
					}
				}
			}
		}
		$index = $index + 1
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok($prepared)
	}
}

## The shaped-run store: one glyph record, glyph index, and one-to-one
## cluster per painted scalar, one run per run spec, all over one flat
## arena. Advances are fixed positive values; positions come from the
## enclosing scene transforms.
build_text_store : Spec, List(PreparedFont) -> Try({ source_bytes : List(U8), store : Text.Store }, BuildFailure)
build_text_store = |spec, prepared| {
	var $glyphs = []
	var $glyph_indices = []
	var $clusters = []
	var $runs = List.with_capacity(spec.runs.len())
	var $source_bytes = []
	var $failure = NoFailure
	var $run_index = 0
	while $run_index < spec.runs.len() and $failure == NoFailure {
		run = list_at(spec.runs, $run_index)
		font = list_at(prepared, run.font)
		glyph_start = $glyphs.len()
		cluster_start = $clusters.len()
		run_scalar_count = run.text.len()
		var $byte_offset = 0
		var $entry = 0
		while $entry < run_scalar_count and $failure == NoFailure {
			glyph_scalar = list_at(run.glyphs, $entry)
			text_scalar = list_at(run.text, $entry)
			match KernelFont.glyph_for_scalar(font.font, glyph_scalar) {
				None => {
					$failure = Failed(UncoveredScalar(glyph_scalar))
				}
				Some(glyph) => {
					$glyph_indices = $glyph_indices.append($glyphs.len())
					$glyphs = $glyphs.append({
						advance_x: unit(6000),
						advance_y: unit(0),
						id: Text.GlyphId.from_raw(glyph),
						offset_x: unit(0),
						offset_y: unit(0),
					})
					$clusters = $clusters.append({
						glyphs: span(glyph_start + $entry, 1),
						kind: OneToOne,
						source: {
							scalars: span($entry, 1),
							utf8_bytes: span($byte_offset, utf8_length(text_scalar)),
						},
					})
					$source_bytes = append_utf8($source_bytes, text_scalar)
					$byte_offset = $byte_offset + utf8_length(text_scalar)
				}
			}
			$entry = $entry + 1
		}
		$runs = $runs.append({
			actual_text: FromOccurrence,
			clusters: span(cluster_start, run_scalar_count),
			direction: LeftToRight,
			glyphs: span(glyph_start, run_scalar_count),
			id: Text.RunId.from_index($run_index),
			instance: Font.InstanceId.from_index(run.font),
			language: Language("en-AU"),
			occurrence: Semantics.OccurrenceId.from_index($run_index),
			script: Font.Script.from_iso15924("Latn"),
			size: unit(11000),
			source: { scalars: span(0, run_scalar_count), utf8_bytes: span(0, $byte_offset) },
			substitutions: empty_range,
			transformations: empty_range,
			writing_mode: Horizontal,
		})
		$run_index = $run_index + 1
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok({
			source_bytes: $source_bytes,
			store: {
				clusters: $clusters,
				glyph_indices: $glyph_indices,
				glyphs: $glyphs,
				runs: $runs,
				substitutions: [],
				transformations: [],
			},
		})
	}
}

## One meaningful paragraph per run whose logical order is the run order;
## each occurrence covers its run's exact scalar range of the one shared
## text source, and each fragment lives on its run's page and stream.
build_semantics : Spec, List(U8) -> Try(Semantics.Store, BuildFailure)
build_semantics = |spec, source_bytes| {
	source = Str.from_utf8(source_bytes) ? |_| SemanticFailure
	run_count = spec.runs.len()
	var $spine = List.with_capacity(run_count * 2)
	var $index = 0
	while $index < run_count {
		$spine = $spine.append(ChildNode(Semantics.NodeId.from_index($index + 1)))
		$index = $index + 1
	}
	var $nodes = List.with_capacity(run_count + 1)
	$nodes = $nodes.append({
		attributes: empty_range,
		content: span(0, run_count),
		element_identifier: NoElementIdentifier,
		id: Semantics.NodeId.from_index(0),
		language: Language("en-AU"),
		parent: DocumentRoot,
		role: { local_name: "Document", namespace: Semantics.NamespaceId.from_index(0) },
		structure_element: Semantics.StructureElementId.from_index(0),
		text_properties: empty_range,
	})
	var $occurrences = List.with_capacity(run_count)
	var $occurrence_fragments = List.with_capacity(run_count)
	var $fragments = List.with_capacity(run_count)
	var $scalar_cursor = 0
	var $byte_cursor = 0
	$index = 0
	while $index < run_count {
		run = list_at(spec.runs, $index)
		var $byte_length = 0
		var $scalar_scan = 0
		while $scalar_scan < run.text.len() {
			$byte_length = $byte_length + utf8_length(list_at(run.text, $scalar_scan))
			$scalar_scan = $scalar_scan + 1
		}
		range = {
			scalars: span($scalar_cursor, run.text.len()),
			utf8_bytes: span($byte_cursor, $byte_length),
		}
		$spine = $spine.append(ContentOccurrence(Semantics.OccurrenceId.from_index($index)))
		$occurrences = $occurrences.append({
			fragments: span($index, 1),
			id: Semantics.OccurrenceId.from_index($index),
			language: Language("en-AU"),
			source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange(range)),
			text_properties: empty_range,
		})
		$occurrence_fragments = $occurrence_fragments.append(Semantics.FragmentId.from_index($index))
		$fragments = $fragments.append({
			content_stream: Semantics.ContentStreamId.from_index(run.page),
			continuation_index: 0,
			id: Semantics.FragmentId.from_index($index),
			occurrence: Semantics.OccurrenceId.from_index($index),
			page: Semantics.PageId.from_index(run.page),
			source_range: UnicodeRange(range),
		})
		$nodes = $nodes.append({
			attributes: empty_range,
			content: span(run_count + $index, 1),
			element_identifier: NoElementIdentifier,
			id: Semantics.NodeId.from_index($index + 1),
			language: Language("en-AU"),
			parent: ParentNode(Semantics.NodeId.from_index(0)),
			role: { local_name: "P", namespace: Semantics.NamespaceId.from_index(0) },
			structure_element: Semantics.StructureElementId.from_index($index + 1),
			text_properties: empty_range,
		})
		$scalar_cursor = $scalar_cursor + run.text.len()
		$byte_cursor = $byte_cursor + $byte_length
		$index = $index + 1
	}
	Ok({
		annotations: [],
		assertions: [],
		attribute_roles: [],
		attributes: [],
		content_spine: $spine,
		contextual_artifacts: [],
		document_root: Semantics.NodeId.from_index(0),
		element_identifiers: [],
		fragments: $fragments,
		mathml_subtrees: [],
		namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
		nodes: $nodes,
		non_text_sources: [],
		occurrence_fragments: $occurrence_fragments,
		occurrences: $occurrences,
		relationships: [],
		role_mappings: [],
		text_properties: [],
		text_sources: [{ unicode: source }],
	})
}

## The scene: one fragment-owned group per run — a positioned page-level
## text object, or the single placement of the text-bearing form — with each
## page painting its groups in reverse logical order, so paint order always
## differs from reading order on multi-run pages.
build_scene : Spec -> { form_store : Scene.FormStore, scene : Scene.Store }
build_scene = |spec| {
	run_count = spec.runs.len()
	var $commands = []
	var $groups = List.with_capacity(run_count)
	var $form_commands = []
	var $forms = []
	var $index = 0
	while $index < run_count {
		run = list_at(spec.runs, $index)
		start = $commands.len()
		match run.site {
			OnPage({ x, y }) => {
				$commands = $commands.append(Transform({ children: span(start + 1, 1), matrix: translate(x, y) }))
				$commands = $commands.append(DrawText({ paint: text_paint, run: Text.RunId.from_index($index) }))
			}
			InForm({ x, y }) => {
				form_start = $form_commands.len()
				$form_commands = $form_commands.append(DrawText({ paint: text_paint, run: Text.RunId.from_index($index) }))
				$forms = $forms.append({
					bbox: rect(0, -3000, 60000, 17000),
					commands: span(form_start, 1),
					group: NoGroup,
					id: Scene.FormId.from_index($forms.len()),
				})
				$commands = $commands.append(PlaceForm({ form: Scene.FormId.from_index($forms.len() - 1), transform: translate(x, y) }))
			}
		}

		## The group owns exactly its one top-level command; a transform's
		## child range is visited through the command tree.
		$groups = $groups.append({
			commands: span(start, 1),
			id: Scene.GroupId.from_index($index),
			owner: Fragment(Semantics.FragmentId.from_index($index)),
		})
		$index = $index + 1
	}

	## Page paint order: each page's groups in reverse logical order.
	var $page_groups = []
	var $pages = List.with_capacity(spec.pages)
	var $page = 0
	while $page < spec.pages {
		order_start = $page_groups.len()
		var $reversed = run_count
		while $reversed > 0 {
			$reversed = $reversed - 1
			if list_at(spec.runs, $reversed).page == $page {
				$page_groups = $page_groups.append(Scene.GroupId.from_index($reversed))
			}
		}
		$pages = $pages.append({
			boxes: { art: page_box, bleed: page_box, crop: page_box, media: page_box, trim: page_box },
			id: Semantics.PageId.from_index($page),
			paint_order: span(order_start, $page_groups.len() - order_start),
			rotation: Rotate0,
		})
		$page = $page + 1
	}
	{
		form_store: { commands: $form_commands, forms: $forms },
		scene: {
			commands: $commands,
			dash_lengths: [],
			groups: $groups,
			page_groups: $page_groups,
			pages: $pages,
			path_segments: [],
			paths: [],
		},
	}
}

## The complete production pipeline for one authored spec.
run_pipeline : Spec, U64 -> Try(Built, BuildFailure)
run_pipeline = |spec, guard| {
	prepared = prepare_fonts(spec.fonts, guard)?
	text_store = build_text_store(spec, prepared)?
	semantics = build_semantics(spec, text_store.source_bytes)?
	built_scene = build_scene(spec)
	semantic = KernelTextSemantics.Plan.build(
		semantics,
		spec.pages,
		spec.pages,
		semantic_limits(semantics.nodes.len(), semantics.content_spine.len(), semantics.fragments.len()),
		text_semantic_limits(text_store.source_bytes.len(), text_store.store.clusters.len() + 8),
	) ? |_| SemanticFailure
	resources = KernelScene.Resources.with_forms({
		color_spaces: 1,
		forms: built_scene.form_store.forms.len(),
		images: 0,
		text_runs: text_store.store.runs.len(),
	})
	form_scene = KernelScene.FormPlan.build(built_scene.scene, built_scene.form_store, resources, scene_limits, form_scene_limits) ? FormSceneFailure
	colors = KernelColor.Plan.build(text_colors, color_limits) ? ColorFailure
	images = KernelImage.Plan.build({ resources: [] }, colors, no_image_limits) ? ImageFailure
	facts = KernelForm.Facts.build(form_scene, { colors, font_count: spec.fonts.len(), images }, WithTextStore(text_store.store), form_limits) ? FactsFailure
	ownership = KernelTextOwnership.Plan.build_with_forms(semantic, KernelScene.FormPlan.page(form_scene), text_store.store, KernelForm.Facts.run_fragments(facts)) ? OwnershipFailure
	var $font_plans = List.with_capacity(prepared.len())
	var $plan_index = 0
	while $plan_index < prepared.len() {
		$font_plans = $font_plans.append(list_at(prepared, $plan_index).plan)
		$plan_index = $plan_index + 1
	}
	text = KernelPdfText.ScenePlan.build(ownership, $font_plans, text_limits) ? TextFailure
	mappings = KernelPdfText.ScenePlan.mappings(text)
	var $leaves = List.with_capacity(prepared.len())
	var $leaf_index = 0
	var $leaf_failure = NoFailure
	while $leaf_index < prepared.len() and $leaf_failure == NoFailure {
		font = list_at(prepared, $leaf_index)
		match KernelFontLeaf.Leaf.build({
			descriptor: font.policy,
			font: font.font,
			mappings: list_at(mappings, $leaf_index),
			plan: font.plan,
			subset: font.subset,
		}) {
			Err(error) => {
				$leaf_failure = Failed(FontLeafFailure(error))
			}
			Ok(leaf) => {
				$leaves = $leaves.append({ descriptor: KernelFontLeaf.Leaf.descriptor(leaf), payload: KernelFontLeaf.Leaf.recipe(leaf) })
			}
		}
		$leaf_index = $leaf_index + 1
	}
	match $leaf_failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}
	tagged = KernelTextOwnership.Plan.tagged(ownership)
	form_plan = KernelForm.Plan.build(form_scene, facts, { colors, fonts: $leaves, images }, WithText(KernelPdfText.ScenePlan.content(text)), tagged, form_limits) ? FormPlanFailure
	content = KernelContent.Plan.build_with_forms_and_text(
		tagged,
		KernelPdfText.ScenePlan.content(text),
		form_context(form_plan, built_scene.form_store),
		content_limits,
	) ? ContentFailure
	resource_use = KernelResourceUse.TextPlan.build_with_forms(form_scene, colors, images) ? ResourceUseFailure
	leaf_counts = KernelForm.Plan.canonical_leaf_counts(form_plan)
	base = KernelGate2Objects.Plan.build_canonical(
		tagged,
		colors,
		images,
		resource_use,
		content,
		{ color_spaces: leaf_counts.color_spaces, image_alpha: KernelForm.Plan.canonical_image_alpha(form_plan), profiles: leaf_counts.profiles },
		KernelGate2Objects.Limits.make({ max_objects: 8192, max_pages: 4 }),
	) ? ObjectFailure
	objects = KernelGate4FormObjects.Plan.build_with_states(
		base,
		KernelForm.Plan.canonical_form_count(form_plan),
		KernelForm.Plan.canonical_state_count(form_plan),
		KernelForm.Plan.canonical_font_count(form_plan),
		8192,
	) ? FormObjectFailure
	var $bundles = List.with_capacity(prepared.len())
	var $bundle_index = 0
	while $bundle_index < prepared.len() {
		font = list_at(prepared, $bundle_index)
		$bundles = $bundles.append({ descriptor: font.policy, font: font.font, plan: font.plan, subset: font.subset })
		$bundle_index = $bundle_index + 1
	}
	structure = KernelGate4FormStructure.Plan.build(
		tagged,
		colors,
		images,
		content,
		form_plan,
		objects,
		WithTextObjects({ fonts: $bundles, text }),
		structure_limits,
	) ? StructureFailure
	bytes = KernelEmit.to_bytes(KernelGate4FormStructure.Plan.structure(structure)) ? |_| EmitFailure
	Ok({ bytes, content, facts, form_plan, ownership, structure, text })
}

form_context : KernelForm.Plan, Scene.FormStore -> KernelContent.FormContext
form_context = |form_plan, form_store| {
	count = KernelForm.Plan.canonical_form_count(form_plan)
	var $streams = List.with_capacity(count)
	var $ordinal = 0
	while $ordinal < count {
		$streams = $streams.append(KernelForm.Plan.canonical_form(form_plan, $ordinal).commands)
		$ordinal = $ordinal + 1
	}
	{
		arena: form_store.commands,
		color_names: KernelForm.Plan.color_names(form_plan),
		font_names: KernelForm.Plan.font_names(form_plan),
		form_names: KernelForm.Plan.form_names(form_plan),
		form_states: KernelForm.Plan.form_command_states(form_plan),
		image_names: KernelForm.Plan.image_names(form_plan),
		page_states: KernelForm.Plan.page_command_states(form_plan),
		pattern_arena: [],
		pattern_names: [],
		pattern_streams: [],
		shading_names: [],
		streams: $streams,
	}
}

work_vector : Built -> List(U64)
work_vector = |built| {
	facts_work = KernelForm.Facts.work(built.facts)
	plan_work = KernelForm.Plan.work(built.form_plan)
	graph_work = KernelForm.Plan.graph_work(built.form_plan)
	ownership_work = KernelTextOwnership.Plan.work(built.ownership)
	text_work = KernelPdfText.ScenePlan.work(built.text)
	content_work = KernelContent.Plan.work(built.content)
	structure_work = KernelGate4FormStructure.Plan.work(built.structure)
	[
		plan_work.authored_fonts,
		plan_work.canonical_fonts,
		plan_work.deduplicated_fonts,
		plan_work.font_recipe_bytes,
		plan_work.leaf_digests,
		plan_work.dictionary_entries,
		plan_work.nested_dictionary_entries,
		plan_work.recipe_bytes,
		facts_work.text_forms,
		facts_work.direct_edges,
		facts_work.use_command_visits,
		graph_work.hashes,
		graph_work.bytes_hashed,
		graph_work.retained_payload_bytes,
		graph_work.collision_entries,
		graph_work.equality_comparisons,
		graph_work.bytes_compared,
		ownership_work.run_visits,
		text_work.glyph_visits,
		text_work.mappings,
		text_work.content_bytes,
		content_work.text_placements,
		content_work.bytes_emitted,
		structure_work.fonts,
		structure_work.font_program_bytes,
		structure_work.objects,
		built.bytes.len(),
	]
}

## Scalars with distinct builtin-face glyphs for the distinct-closure scale
## scenarios: uppercase, lowercase, digits, and two punctuation marks.
distinct_scalar : U64 -> U32
distinct_scalar = |index| {
	if index < 26 {
		0x41 + index.to_u32_wrap()
	} else if index < 52 {
		0x61 + (index - 26).to_u32_wrap()
	} else if index < 62 {
		0x30 + (index - 52).to_u32_wrap()
	} else if index == 62 {
		0x21
	} else {
		0x3f
	}
}

on_grid : U64 -> RunSite
on_grid = |index| OnPage({
	x: 6000 + U64.mod_by(index, 12).to_i64_wrap() * 8000,
	y: 88000 - U64.div_by(index, 12).to_i64_wrap() * 1000,
})

## The showcase: logical fonts 0 and 1 are independently authored equivalent
## bundles over {A, B}; logical font 2 is the distinct closure {C}; logical
## font 3 is the caller face. Runs: page-one text, a text-bearing form, and
## page-two text all share the one canonical bundle; the reversed authored
## font order must produce identical bytes.
showcase_spec : [Forward, Reversed] -> Spec
showcase_spec = |direction| {
	font_count = 4
	font_of = |logical| match direction {
		Forward => logical
		Reversed => font_count - 1 - logical
	}
	var $fonts = List.repeat({ face: BuiltIn, policy: standard_policy, scalars: [0x41, 0x42] }, font_count)
	$fonts = list_set($fonts, font_of(2), { face: BuiltIn, policy: standard_policy, scalars: [0x43] })
	$fonts = list_set($fonts, font_of(3), { face: CallerFace, policy: standard_policy, scalars: [0x43] })
	{
		fonts: $fonts,
		pages: 2,
		runs: [
			{ font: font_of(0), glyphs: [0x41], page: 0, site: OnPage({ x: 10000, y: 80000 }), text: [0x41] },
			{ font: font_of(1), glyphs: [0x41, 0x42], page: 1, site: OnPage({ x: 10000, y: 80000 }), text: [0x41, 0x42] },
			{ font: font_of(0), glyphs: [0x42], page: 0, site: InForm({ x: 40000, y: 60000 }), text: [0x42] },
			{ font: font_of(2), glyphs: [0x43], page: 0, site: OnPage({ x: 70000, y: 30000 }), text: [0x43] },
			{ font: font_of(3), glyphs: [0x43], page: 1, site: OnPage({ x: 60000, y: 40000 }), text: [0x43] },
		],
	}
}

## The distinctness matrix: font 0 is the {A, B} base closure; font 1 is
## the same face with the genuinely different closure {A}; fonts 2 and 3
## share font 1's exact glyph set but differ in one emitted fact each — the
## ToUnicode mapping (A extracted as Å) and the StemV descriptor policy —
## so fonts 1, 2, and 3 also share one BaseFont subset tag while remaining
## three distinct bundles; font 4 is a different source face.
facts_spec : {} -> Spec
facts_spec = |_| {
	fonts: [
		{ face: BuiltIn, policy: standard_policy, scalars: [0x41, 0x42] },
		{ face: BuiltIn, policy: standard_policy, scalars: [0x41] },
		{ face: BuiltIn, policy: standard_policy, scalars: [0x41] },
		{ face: BuiltIn, policy: { flags: 32, italic_angle: 0, stem_v: 96 }, scalars: [0x41] },
		{ face: CallerFace, policy: standard_policy, scalars: [0x43] },
	],
	pages: 1,
	runs: [
		{ font: 0, glyphs: [0x41, 0x42], page: 0, site: OnPage({ x: 8000, y: 84000 }), text: [0x41, 0x42] },
		{ font: 1, glyphs: [0x41], page: 0, site: OnPage({ x: 8000, y: 64000 }), text: [0x41] },
		{ font: 2, glyphs: [0x41], page: 0, site: OnPage({ x: 8000, y: 44000 }), text: [0xc5] },
		{ font: 3, glyphs: [0x41], page: 0, site: OnPage({ x: 8000, y: 24000 }), text: [0x41] },
		{ font: 4, glyphs: [0x43], page: 0, site: OnPage({ x: 8000, y: 8000 }), text: [0x43] },
	],
}

## One canonical subset under N placements: N runs of the same glyph from
## one authored font on one page.
share_spec : U64 -> Spec
share_spec = |scale| {
	var $runs = List.with_capacity(scale)
	var $index = 0
	while $index < scale {
		$runs = $runs.append({ font: 0, glyphs: [0x41], page: 0, site: on_grid($index), text: [0x41] })
		$index = $index + 1
	}
	{
		fonts: [{ face: BuiltIn, policy: standard_policy, scalars: [0x41] }],
		pages: 1,
		runs: $runs,
	}
}

## N independently authored equivalent bundles, each used by one run, all
## collapsing to one canonical bundle.
dedupe_spec : U64 -> Spec
dedupe_spec = |scale| {
	var $runs = List.with_capacity(scale)
	var $index = 0
	while $index < scale {
		$runs = $runs.append({ font: $index, glyphs: [0x41], page: 0, site: on_grid($index), text: [0x41] })
		$index = $index + 1
	}
	{
		fonts: List.repeat({ face: BuiltIn, policy: standard_policy, scalars: [0x41] }, scale),
		pages: 1,
		runs: $runs,
	}
}

## N genuinely different closures from one face, each used by one run, in
## either authoring direction.
distinct_spec : U64, [Forward, Reversed] -> Spec
distinct_spec = |scale, direction| {
	var $fonts = List.with_capacity(scale)
	var $runs = List.with_capacity(scale)
	var $index = 0
	while $index < scale {
		font_logical = match direction {
			Forward => $index
			Reversed => scale - 1 - $index
		}
		$fonts = $fonts.append({ face: BuiltIn, policy: standard_policy, scalars: [distinct_scalar(font_logical)] })
		$index = $index + 1
	}
	$index = 0
	while $index < scale {
		font_dense = match direction {
			Forward => $index
			Reversed => scale - 1 - $index
		}
		$runs = $runs.append({ font: font_dense, glyphs: [distinct_scalar($index)], page: 0, site: on_grid($index), text: [distinct_scalar($index)] })
		$index = $index + 1
	}
	{ fonts: $fonts, pages: 1, runs: $runs }
}

## Forced digest collisions over real derived font recipes: half exact
## twins of one bundle, half distinct closures, all forced into one
## fingerprint bucket by the graph's white-box test digest. Exact
## descriptor/length partitioning plus adjacent equality must merge only
## the true twins with at most entries-minus-one comparisons.
run_collision : U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4FontLeafEvidence.EvidenceError)
run_collision = |scale| {
	if scale < 4 or scale > 1024 or U64.mod_by(scale, 2) != 0 {
		return Err(InvalidScale)
	}
	twins = U64.div_by(scale, 2)

	## Prepare the twin bundle once and each distinct bundle once; derive
	## one recipe per authored entry exactly as the pipeline would.
	var $specs = List.with_capacity(scale)
	var $index = 0
	while $index < scale {
		spec = if $index < twins {
			{ face: BuiltIn, policy: standard_policy, scalars: [0x41] }
		} else {
			{ face: BuiltIn, policy: standard_policy, scalars: [distinct_scalar($index - twins + 1)] }
		}
		$specs = $specs.append(spec)
		$index = $index + 1
	}
	guard = U64.mod_by(scale, 2) * 0 + U64.mod_by(scale, 1)
	prepared = prepare_fonts($specs, guard) ? |_| EvidenceFailure
	var $payload = []
	var $resources = List.with_capacity(scale)
	var $root_uses = List.with_capacity(scale)
	var $recipe_total = 0
	$index = 0
	while $index < scale {
		font = list_at(prepared, $index)
		mapping_scalar = if $index < twins 0x41 else distinct_scalar($index - twins + 1)
		content_cid = content_cid_of(font.plan)
		leaf = KernelFontLeaf.Leaf.build({
			descriptor: font.policy,
			font: font.font,
			mappings: [{ cid: content_cid, scalars: [mapping_scalar] }],
			plan: font.plan,
			subset: font.subset,
		}) ? |_| EvidenceFailure
		recipe = KernelFontLeaf.Leaf.recipe(leaf)
		start = $payload.len()
		$payload = $payload.concat(recipe)
		$recipe_total = $recipe_total + recipe.len()
		$resources = $resources.append({ descriptor: KernelFontLeaf.Leaf.descriptor(leaf), length: recipe.len(), start })
		$root_uses = $root_uses.append({ resource: $index, root: 0 })
		$index = $index + 1
	}
	graph = KernelResourceGraph.Plan.build(
		{
			digest_policy: TruncatedTestDigest(1),
			edges: [],
			payload_bytes: $payload,
			placements: [],
			resources: $resources,
			root_count: 1,
			root_uses: $root_uses,
		},
		graph_limits,
	) ? |_| EvidenceFailure
	work = KernelResourceGraph.Plan.work(graph)
	canonical = KernelResourceGraph.Plan.resource_count(graph)

	## Only the true twins may merge; every entry shares the one forced
	## bucket; and the equality work stays strictly below all-pairs.
	if canonical != twins + 1 {
		return Err(CollisionDiverged)
	}
	if work.collision_entries != scale or work.equality_comparisons >= scale or work.bytes_compared > $recipe_total {
		return Err(CollisionDiverged)
	}

	## The carrier document: the single-run sharing pipeline, so the fixture
	## still emits real validated PDF bytes.
	carrier = run_pipeline(share_spec(1), guard) ? |_| EvidenceFailure
	Ok({
		bytes: carrier.bytes,
		work: [
			scale,
			canonical,
			work.unique_payloads,
			work.deduplicated_payloads,
			work.collision_entries,
			work.equality_comparisons,
			work.bytes_compared,
			work.ordering_byte_visits,
			work.hashes,
			work.bytes_hashed,
			carrier.bytes.len(),
		],
	})
}

content_cid_of : KernelFontPlan.Plan -> U32
content_cid_of = |plan| {
	var $index = 0
	var $cid = 0
	while $index < plan.entries.len() {
		entry = list_at(plan.entries, $index)
		if entry.content {
			$cid = entry.cid
		}
		$index = $index + 1
	}
	$cid
}

run_scenario : Str, U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4FontLeafEvidence.EvidenceError)
run_scenario = |mode, scale| {

	## Always zero at runtime, but derived from a runtime argument, so the
	## measured pipelines cannot be evaluated at compile time.
	guard = U64.mod_by(scale, 1)
	if mode == "showcase" {
		forward = run_pipeline(showcase_spec(Forward), guard) ? |_| EvidenceFailure
		reversed = run_pipeline(showcase_spec(Reversed), guard) ? |_| EvidenceFailure
		if forward.bytes != reversed.bytes {
			return Err(AdversarialOrderDiverged)
		}
		check_sharing(forward, 4, 3, 1)?
		Ok({ bytes: forward.bytes, work: work_vector(forward) })
	} else if mode == "facts" {
		built = run_pipeline(facts_spec({}), guard) ? |_| EvidenceFailure
		check_sharing(built, 5, 5, 0)?
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "unique" {
		built = run_pipeline(showcase_spec(Forward), guard) ? |_| EvidenceFailure
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "shared" {
		spec = showcase_spec(Forward)
		first = run_pipeline(spec, guard) ? |_| EvidenceFailure
		second = run_pipeline(spec, guard) ? |_| EvidenceFailure
		if first.bytes != second.bytes {
			return Err(SharedInputDiverged)
		}
		Ok({ bytes: first.bytes, work: work_vector(first) })
	} else if mode == "share" {
		if scale < 1 or scale > 1000 {
			return Err(InvalidScale)
		}
		built = run_pipeline(share_spec(scale), guard) ? |_| EvidenceFailure
		check_sharing(built, 1, 1, 0)?
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "dedupe" {
		if scale < 1 or scale > 64 {
			return Err(InvalidScale)
		}
		built = run_pipeline(dedupe_spec(scale), guard) ? |_| EvidenceFailure
		check_sharing(built, scale, 1, scale - 1)?
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "distinct" {
		if scale < 1 or scale > 64 {
			return Err(InvalidScale)
		}
		forward = run_pipeline(distinct_spec(scale, Forward), guard) ? |_| EvidenceFailure
		reversed = run_pipeline(distinct_spec(scale, Reversed), guard) ? |_| EvidenceFailure
		if forward.bytes != reversed.bytes {
			return Err(AdversarialOrderDiverged)
		}
		check_sharing(forward, scale, scale, 0)?
		Ok({ bytes: forward.bytes, work: work_vector(forward) })
	} else if mode == "collide" {
		run_collision(scale)
	} else if mode == "negative" {
		run_negatives(scale)
	} else {
		Err(InvalidScale)
	}
}

check_sharing : Built, U64, U64, U64 -> Try({}, Gate4FontLeafEvidence.EvidenceError)
check_sharing = |built, authored, canonical, deduplicated| {
	plan_work = KernelForm.Plan.work(built.form_plan)
	if plan_work.authored_fonts != authored or plan_work.canonical_fonts != canonical or plan_work.deduplicated_fonts != deduplicated {
		return Err(SharingDiverged)
	}
	structure_work = KernelGate4FormStructure.Plan.work(built.structure)
	if structure_work.fonts != canonical {
		return Err(SharingDiverged)
	}
	Ok({})
}

## The atomic rejection sweep: each input differs from the valid single-run
## document in exactly one fact, every rejection is a distinct structured
## diagnostic, and no plan or PDF byte escapes. The carrier snapshot is the
## unrelated single-run sharing document.
run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4FontLeafEvidence.EvidenceError)
run_negatives = |context| {
	if context != 1 {
		return Err(EvidenceFailure)
	}
	guard = U64.mod_by(context, 1)
	rejections = check_negatives(guard)?
	carrier = run_pipeline(share_spec(1), guard) ? |_| EvidenceFailure
	Ok({ bytes: carrier.bytes, work: [rejections, 0, carrier.bytes.len()] })
}

## A prepared single-font context for the leaf-boundary negatives: the valid
## bundle facts the sweep perturbs one fact at a time.
NegativeContext := { mappings : List(KernelPdfFont.UnicodeMapping), prepared : PreparedFont }

build_negative_context : U64 -> Try(NegativeContext, Gate4FontLeafEvidence.EvidenceError)
build_negative_context = |guard| {
	prepared_list = prepare_fonts([{ face: BuiltIn, policy: standard_policy, scalars: [0x41] }], guard) ? |_| EvidenceFailure
	prepared = list_at(prepared_list, 0)
	cid = content_cid_of(prepared.plan)
	Ok(NegativeContext.{ mappings: [{ cid, scalars: [0x41] }], prepared })
}

expect_leaf_rejection : U64, KernelFontLeaf.Bundle, (KernelFontLeaf.Error -> Bool) -> Try({}, Gate4FontLeafEvidence.EvidenceError)
expect_leaf_rejection = |ordinal, bundle, matches| {
	match KernelFontLeaf.Leaf.build(bundle) {
		Err(error) => if matches(error) Ok({}) else Err(MissingRejection(ordinal))
		Ok(_) => Err(MissingRejection(ordinal))
	}
}

check_negatives : U64 -> Try(U64, Gate4FontLeafEvidence.EvidenceError)
check_negatives = |guard| {
	context = build_negative_context(guard)?
	prepared = context.prepared
	base_bundle = {
		descriptor: prepared.policy,
		font: prepared.font,
		mappings: context.mappings,
		plan: prepared.plan,
		subset: prepared.subset,
	}

	## 1: an invalid descriptor policy cannot derive an identity.
	expect_leaf_rejection(
		1,
		{ ..base_bundle, descriptor: { flags: 32, italic_angle: 0, stem_v: 0 } },
		|error| match error {
			DescriptorInvalid => Bool.True
			_ => Bool.False
		},
	)?

	## 2: a corrupted subset tag cannot derive an identity.
	expect_leaf_rejection(
		2,
		{ ..base_bundle, plan: { ..prepared.plan, prefix: [0x41, 0x42, 0x63, 0x44, 0x45, 0x46] } },
		|error| match error {
			InvalidSubsetTag => Bool.True
			_ => Bool.False
		},
	)?

	## 3: subset bytes disagreeing with their recorded length.
	truncated = prepared.subset.bytes.sublist({ len: prepared.subset.bytes.len() - 1, start: 0 })
	expect_leaf_rejection(
		3,
		{ ..base_bundle, subset: { bytes: truncated, work: prepared.subset.work } },
		|error| match error {
			SubsetLengthMismatch(_) => Bool.True
			_ => Bool.False
		},
	)?

	## 4: a content CID without its collected mapping.
	expect_leaf_rejection(
		4,
		{ ..base_bundle, mappings: [] },
		|error| match error {
			MissingUnicodeMapping(_) => Bool.True
			_ => Bool.False
		},
	)?

	## 5: a mapping for a CID that is not a content CID.
	expect_leaf_rejection(
		5,
		{ ..base_bundle, mappings: [{ cid: 0, scalars: [0x41] }].concat(context.mappings) },
		|error| match error {
			UnexpectedUnicodeMapping({ cid: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 6: an empty mapping for a content CID.
	expect_leaf_rejection(
		6,
		{ ..base_bundle, mappings: [{ cid: list_at(context.mappings, 0).cid, scalars: [] }] },
		|error| match error {
			EmptyUnicodeMapping(_) => Bool.True
			_ => Bool.False
		},
	)?

	## 7: a surrogate scalar in a mapping.
	expect_leaf_rejection(
		7,
		{ ..base_bundle, mappings: [{ cid: list_at(context.mappings, 0).cid, scalars: [0xd800] }] },
		|error| match error {
			InvalidUnicodeScalar(0xd800) => Bool.True
			_ => Bool.False
		},
	)?

	## 8: a supplied leaf list disagreeing with the declared font count.
	valid_leaf = KernelFontLeaf.Leaf.build(base_bundle) ? |_| MissingRejection(8)
	pipeline = build_pipeline_prefix(share_spec(1), guard) ? |_| MissingRejection(8)
	short_result = KernelForm.Plan.build(
		pipeline.form_scene,
		pipeline.facts,
		{ colors: pipeline.colors, fonts: [], images: pipeline.images },
		WithText(KernelPdfText.ScenePlan.content(pipeline.text)),
		pipeline.tagged,
		form_limits,
	)
	match short_result {
		Err(LeafCountMismatch({ declared: 1, supplied: 0 })) => {}
		_ => return Err(MissingRejection(8))
	}

	## 9: an authored font no content stream uses is unreachable.
	unused = {
		fonts: [
			{ face: BuiltIn, policy: standard_policy, scalars: [0x41] },
			{ face: BuiltIn, policy: standard_policy, scalars: [0x42] },
		],
		pages: 1,
		runs: [{ font: 0, glyphs: [0x41], page: 0, site: on_grid(0), text: [0x41] }],
	}
	match run_pipeline(unused, guard) {
		Err(FactsFailure(Graph(UnreachableResource(_)))) => {}
		_ => return Err(MissingRejection(9))
	}

	## 10: the graph payload budget bounds recipe bytes transactionally.
	tiny_graph = { ..graph_limits, max_payload_bytes: 64 }
	tiny_limits = KernelForm.Limits.make({ graph: tiny_graph, max_mask_depth: 4, max_opacity_depth: 64, max_recipe_bytes: 4194304 })
	budget_result = KernelForm.Plan.build(
		pipeline.form_scene,
		pipeline.facts,
		{ colors: pipeline.colors, fonts: [{ descriptor: KernelFontLeaf.Leaf.descriptor(valid_leaf), payload: KernelFontLeaf.Leaf.recipe(valid_leaf) }], images: pipeline.images },
		WithText(KernelPdfText.ScenePlan.content(pipeline.text)),
		pipeline.tagged,
		tiny_limits,
	)
	match budget_result {
		Err(Graph(PayloadByteLimitExceeded(_))) => {}
		_ => return Err(MissingRejection(10))
	}

	## 11: an authored bundle list disagreeing with the plan at assembly.
	full = complete_pipeline(pipeline, valid_leaf) ? |_| MissingRejection(11)
	mismatch_result = KernelGate4FormStructure.Plan.build(
		pipeline.tagged,
		pipeline.colors,
		pipeline.images,
		full.content,
		full.form_plan,
		full.objects,
		WithTextObjects({ fonts: [], text: pipeline.text }),
		structure_limits,
	)
	match mismatch_result {
		Err(FontCountMismatch(_)) => {}
		_ => return Err(MissingRejection(11))
	}

	Ok(11)
}

## The pipeline prefix shared by the plan-boundary negatives: everything up
## to (but excluding) the canonical plan.
PipelinePrefix := {
	colors : KernelColor.Plan,
	facts : KernelForm.Facts,
	form_scene : KernelScene.FormPlan,
	form_store : Scene.FormStore,
	images : KernelImage.Plan,
	tagged : KernelTagged.Plan,
	text : KernelPdfText.ScenePlan,
}

build_pipeline_prefix : Spec, U64 -> Try(PipelinePrefix, BuildFailure)
build_pipeline_prefix = |spec, guard| {
	prepared = prepare_fonts(spec.fonts, guard)?
	text_store = build_text_store(spec, prepared)?
	semantics = build_semantics(spec, text_store.source_bytes)?
	built_scene = build_scene(spec)
	semantic = KernelTextSemantics.Plan.build(
		semantics,
		spec.pages,
		spec.pages,
		semantic_limits(semantics.nodes.len(), semantics.content_spine.len(), semantics.fragments.len()),
		text_semantic_limits(text_store.source_bytes.len(), text_store.store.clusters.len() + 8),
	) ? |_| SemanticFailure
	resources = KernelScene.Resources.with_forms({
		color_spaces: 1,
		forms: built_scene.form_store.forms.len(),
		images: 0,
		text_runs: text_store.store.runs.len(),
	})
	form_scene = KernelScene.FormPlan.build(built_scene.scene, built_scene.form_store, resources, scene_limits, form_scene_limits) ? FormSceneFailure
	colors = KernelColor.Plan.build(text_colors, color_limits) ? ColorFailure
	images = KernelImage.Plan.build({ resources: [] }, colors, no_image_limits) ? ImageFailure
	facts = KernelForm.Facts.build(form_scene, { colors, font_count: spec.fonts.len(), images }, WithTextStore(text_store.store), form_limits) ? FactsFailure
	ownership = KernelTextOwnership.Plan.build_with_forms(semantic, KernelScene.FormPlan.page(form_scene), text_store.store, KernelForm.Facts.run_fragments(facts)) ? OwnershipFailure
	var $font_plans = List.with_capacity(prepared.len())
	var $plan_index = 0
	while $plan_index < prepared.len() {
		$font_plans = $font_plans.append(list_at(prepared, $plan_index).plan)
		$plan_index = $plan_index + 1
	}
	text = KernelPdfText.ScenePlan.build(ownership, $font_plans, text_limits) ? TextFailure
	Ok(
		PipelinePrefix.{
			colors,
			facts,
			form_scene,
			form_store: built_scene.form_store,
			images,
			tagged: KernelTextOwnership.Plan.tagged(ownership),
			text,
		},
	)
}

## The valid completion of the shared prefix, up to object planning, for
## the assembly-boundary negative.
complete_pipeline : PipelinePrefix, KernelFontLeaf.Leaf -> Try({ content : KernelContent.Plan, form_plan : KernelForm.Plan, objects : KernelGate4FormObjects.Plan }, BuildFailure)
complete_pipeline = |pipeline, leaf| {
	form_plan = KernelForm.Plan.build(
		pipeline.form_scene,
		pipeline.facts,
		{ colors: pipeline.colors, fonts: [{ descriptor: KernelFontLeaf.Leaf.descriptor(leaf), payload: KernelFontLeaf.Leaf.recipe(leaf) }], images: pipeline.images },
		WithText(KernelPdfText.ScenePlan.content(pipeline.text)),
		pipeline.tagged,
		form_limits,
	) ? FormPlanFailure
	content = KernelContent.Plan.build_with_forms_and_text(
		pipeline.tagged,
		KernelPdfText.ScenePlan.content(pipeline.text),
		form_context(form_plan, pipeline.form_store),
		content_limits,
	) ? ContentFailure
	resource_use = KernelResourceUse.TextPlan.build_with_forms(pipeline.form_scene, pipeline.colors, pipeline.images) ? ResourceUseFailure
	leaf_counts = KernelForm.Plan.canonical_leaf_counts(form_plan)
	base = KernelGate2Objects.Plan.build_canonical(
		pipeline.tagged,
		pipeline.colors,
		pipeline.images,
		resource_use,
		content,
		{ color_spaces: leaf_counts.color_spaces, image_alpha: KernelForm.Plan.canonical_image_alpha(form_plan), profiles: leaf_counts.profiles },
		KernelGate2Objects.Limits.make({ max_objects: 8192, max_pages: 4 }),
	) ? ObjectFailure
	objects = KernelGate4FormObjects.Plan.build_with_states(
		base,
		KernelForm.Plan.canonical_form_count(form_plan),
		KernelForm.Plan.canonical_state_count(form_plan),
		KernelForm.Plan.canonical_font_count(form_plan),
		8192,
	) ? FormObjectFailure
	Ok({ content, form_plan, objects })
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "Gate 4 font-leaf evidence index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "Gate 4 font-leaf evidence update escaped"
	}
}
