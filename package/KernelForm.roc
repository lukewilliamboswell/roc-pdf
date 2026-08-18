import Color
import Font
import KernelColor
import KernelContent
import KernelImage
import KernelResourceGraph
import KernelScene
import KernelSrgbProfile
import KernelTagged
import Layout
import Scene
import Semantics
import Text

## Gate 4 Form XObject and leaf-resource normalization.
##
## This stage turns a validated form-aware scene plus the validated color and
## image stores into the canonical facts that content lowering, object
## planning, and serialization consume:
##
## - direct-use facts for every content stream, derived once from validated
##   commands rather than by scanning emitted operators;
## - the explicit direct-edge dependency graph over color spaces, ICC
##   profiles, images, fonts, and forms, validated twice by
##   `KernelResourceGraph`: a structure run over unique ordinal payloads
##   proves acyclicity/closure and yields the deterministic topological order,
##   and a canonical run over derived leaf payloads plus Merkle recipes
##   performs deduplication and planning;
## - canonical leaf identity derived from the validated stores, never from
##   authored dense IDs: an ICC profile is its exact sanitized bytes, a color
##   space is a typed recipe (calibrated parameters, or the referenced
##   profile's identity digest, so `Srgb` and an equivalent `IccBased`
##   declaration share one identity), an image is its color-space digest
##   plus its row-compacted canonical planes or sanitized JPEG bytes, so a
##   padded raster and its compact twin deduplicate while equal pixels under
##   different color spaces never merge, and a font is its derived
##   `KernelFontLeaf` bundle recipe — the emitted facts plus the exact
##   sanitized subset bytes — so exact twins share one emitted bundle while
##   closure, mapping, metric, or face differences never merge;
## - canonical visual form identity: a recipe of the bounding box, the
##   canonical identity matrix, and the command tree with geometry inlined and
##   every nested reference replaced by the referenced resource's identity
##   digest;
## - placement ownership records (placement-site tagging): every page-level
##   placement inherits its owned scene group's fragment or page-artifact
##   ownership, form streams stay ownership-neutral, and text reachable inside
##   a form resolves to the owner of the form's unique placement chain.
##
## All DAG work is iterative: instantiation counts, transitive text facts,
## owner resolution, and leaf/recipe digests are single topological sweeps
## over the node order, never per-path traversals, and a form cycle is
## rejected by the resource graph before any traversal could recurse.
KernelForm :: [].{
	Error : [
		AppearanceTextUnsupported({ form : U64 }),
		ArithmeticOverflow,
		ArtifactTextInForm({ form : U64 }),

		## Pattern content is fully opaque in the initial subset, so an
		## image with an alpha soft mask drawn directly inside a pattern
		## cell is rejected.
		AlphaImageInPattern({ image : U64, pattern : U64 }),

		## A form without an isolated transparency group carries its own
		## non-opaque opacity command while some placement chain executes it
		## under an ambient constant alpha below one. One shared stream cannot
		## encode a per-placement effective product, so the combination is
		## rejected rather than silently changing the compositing semantics.
		FormOpacityInAmbient({ form : U64 }),

		## The soft-mask analogue: a non-group form whose own stream applies
		## a soft mask, executed under an ambient soft mask. The inner mask
		## would replace rather than compose, so the combination is rejected;
		## the supported composition route is an isolated-group form.
		FormMaskInAmbient({ form : U64 }),
		Graph(KernelResourceGraph.Error),
		LeafCountMismatch({ declared : U64, supplied : U64 }),

		## A mask chain (a mask form whose subtree applies further soft
		## masks) exceeded the conservative depth budget.
		MaskDepthExceeded({ attempted : U64, limit : U64 }),

		## A soft mask referenced a form that is not an isolated transparency
		## group. Mask rendering requires the explicit isolated group and its
		## blending space; nothing is upgraded implicitly.
		MaskFormNotIsolated({ command : U64, form : U64 }),

		## The document contains transparency, so its pages need an explicit
		## transparency blending space, but no authored color space declares
		## the packaged ICCBased sRGB profile.
		MissingBlendingSpace({ page : U64 }),
		MissingTextPlan({ form : U64 }),
		MissingTextStore({ command : U64 }),

		## One stream context supports at most one active soft mask; nesting
		## a soft-mask group under another is rejected, and composition is
		## expressed through an isolated-group form instead.
		NestedSoftMask({ command : U64 }),

		## Nested pattern invocation is rejected in the initial subset: a
		## form reachable from a pattern cell may not itself fill with a
		## pattern (a direct cell fill is already rejected at validation,
		## and a cycle through patterns is an ordinary graph cycle).
		NestedPatternInvocation({ form : U64 }),
		OpacityDepthExceeded({ attempted : U64, limit : U64 }),
		RecipeByteLimitExceeded({ attempted : U64, limit : U64 }),
		StoreCountMismatch({ declared : U64, kind : [ColorSpaces, Images, Patterns, Profiles, Shadings], supplied : U64 }),
		TextFormMultiplyPlaced({ form : U64, instances : U64 }),

		## Semantic text transitively reachable in a form placed by a
		## pattern cell would repeat with every tile and lose its unique
		## ownership, so it is rejected like text in a mask rendering.
		TextInPatternForm({ form : U64 }),

		## A form reachable from a pattern cell carries transparency
		## (constant opacity, a soft mask, an alpha image, or an isolated
		## group). Pattern content is fully opaque in the initial subset.
		TransparencyInPattern({ form : U64 }),

		## Text is transitively reachable in a form subtree referenced as a
		## soft mask. Mask rendering carries no marked content, MCIDs, or
		## extraction presence, so semantic text cannot appear there.
		TextInMaskForm({ form : U64 }),
		TextRunRecipeInvalid({ prepared : U64, run : U64 }),
	]

	Limits :: { graph : KernelResourceGraph.Limits, max_mask_depth : U64, max_opacity_depth : U64, max_recipe_bytes : U64 }.{
		make : { graph : KernelResourceGraph.Limits, max_mask_depth : U64, max_opacity_depth : U64, max_recipe_bytes : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	## Which ICC profile, if any, one authored color space references.
	ProfileRef : [NoProfile, WithProfile(U64)]

	## Leaf resource counts and per-node dependency facts, derived once from
	## the validated stores: each image's color space and each color space's
	## profile become explicit direct edges, and each image's alpha fact feeds
	## the transparency analysis. The paint facts are derived from the
	## validated shading and pattern stores: each shading records its color
	## space, its geometry kind and channel arity (its descriptor facts), and
	## its derived function layout — one function for a two-stop gradient,
	## or one segment function per interval plus one stitching function for a
	## multi-stop gradient. `shading_function_offsets` holds the prefix sums
	## of those per-shading counts, and `function_shadings` maps every
	## derived function node back to its shading.
	Counts : {
		color_spaces : U64,
		fonts : U64,
		function_shadings : List(U64),
		image_alpha : List(Bool),
		image_color_spaces : List(U64),
		patterns : U64,
		profiles : U64,
		shading_components : List(U64),
		shading_function_offsets : List(U64),
		shading_spaces : List(U64),
		shading_subtypes : List(U64),
		shadings : U64,
		space_profiles : List(ProfileRef),
	}

	## The validated stores whose leaf facts this stage consumes. Fonts carry
	## their validated count here and their derived canonical recipes (built
	## once by `KernelFontLeaf` from the validated bundle facts) in `Leaves`.
	Stores : { colors : KernelColor.Plan, font_count : U64, images : KernelImage.Plan }

	## A run painted inside a form, owned by the fragment resolved for that
	## form's unique placement chain.
	RunFragment : { fragment : Semantics.FragmentId, run : U64 }

	FactsWork : {
		blending_probe_bytes : U64,
		closure_uses : U64,
		derived_functions : U64,
		direct_edges : U64,
		distinct_opacity_values : U64,
		mask_chain_sweep_visits : U64,
		mask_states : U64,
		max_mask_chain : U64,
		max_opacity_depth : U64,
		nested_form_placements : U64,
		opacity_commands : U64,
		opacity_groups : U64,
		opaque_normalized : U64,
		ownership_sweep_visits : U64,
		page_form_placements : U64,
		pattern_cell_use_visits : U64,
		pattern_sweep_visits : U64,
		root_uses : U64,
		soft_mask_commands : U64,
		text_forms : U64,
		transparency_pages : U64,
		transparency_sweep_visits : U64,
		use_command_visits : U64,
	}

	## Which authored color space, if any, is the document's transparency
	## blending space: the lowest authored space declaring the packaged
	## ICCBased sRGB profile. `NoBlending` is valid exactly while no page
	## contains transparency.
	Blending : [Blending(U64), NoBlending]

	## One derived canonical graphics state: a constant effective alpha, or
	## an alpha soft mask rendered from a mask form. At the facts stage the
	## mask carries the authored form index; the canonical plan exposes the
	## canonical form ordinal instead.
	DerivedState : [AlphaState(U64), MaskState(U64)]

	## One canonical graphics state as emission consumes it: the exact
	## `U16`-range constant alpha, or the canonical mask form ordinal whose
	## stream object the `/SMask /G` entry references.
	StateFact : [Alpha(U64), Mask(U64)]

	## Stage 1: derived direct-use facts, the validated structure run, and the
	## resolved form ownership facts. `run_fragments` feeds text ownership
	## before any recipe or content bytes exist. The opacity pre-pass adds the
	## per-command effective-alpha states (dense per arena, indexing
	## `opacity_values`, with `U64.highest` meaning no emitted state), the
	## per-page transparency facts, and the blending-space selection.
	Facts :: {
		blending : Blending,
		counts : Counts,
		direct_text : List(Bool),
		edges : List(KernelResourceGraph.Edge),
		derived_states : List(DerivedState),
		form_command_states : List(U64),
		form_instances : List(U64),
		form_isolated : List(Bool),
		form_owners : List(FormOwner),
		nested_offsets : List(U64),
		nested_children : List(U64),
		order : List(U64),
		page_command_states : List(U64),
		page_placements : List({ ambient : Bool, ambient_mask : Bool, form : U64, owner : Scene.GroupOwner, page : U64 }),
		page_transparency : List(Bool),
		appearance_uses : List(AppearanceUse),
		root_uses : List(KernelResourceGraph.RootUse),
		run_fragments : List(RunFragment),
		transitive_text : List(Bool),
		work : FactsWork,
	}.{
		build : KernelScene.FormPlan, Stores, [NoTextStore, WithTextStore(Text.Store)], Limits -> Try(Facts, Error)
		build = |form_plan, stores, text, limits| build_facts(form_plan, stores.colors, derive_counts(stores, Scene.no_shadings, Scene.no_patterns), text, limits, Scene.no_patterns, [])

		## The paint-aware variant: shadings and pattern cells join the node
		## space, cell content contributes each pattern's direct edges, and
		## the pattern-reachability sweep enforces the opaque, text-free,
		## non-recursive cell contract over placed forms.
		build_with_paints : KernelScene.PaintPlan, Stores, [NoTextStore, WithTextStore(Text.Store)], Limits -> Try(Facts, Error)
		build_with_paints = |paint_plan, stores, text, limits| build_facts(
			KernelScene.PaintPlan.forms(paint_plan),
			stores.colors,
			derive_counts(stores, KernelScene.PaintPlan.shadings(paint_plan), KernelScene.PaintPlan.patterns(paint_plan)),
			text,
			limits,
			KernelScene.PaintPlan.patterns(paint_plan),
			[],
		)

		## The navigation-aware variant: annotation appearance references join
		## both graph runs as closure-only uses so appearance forms prove
		## reachable and close their dependencies without resource-dictionary
		## entries, and a form reachable as an appearance rejects transitive
		## semantic text. An empty appearance list is identical to
		## `build_with_paints`.
		build_with_navigation : KernelScene.PaintPlan, Stores, [NoTextStore, WithTextStore(Text.Store)], List(AppearanceUse), Limits -> Try(Facts, Error)
		build_with_navigation = |paint_plan, stores, text, appearances, limits| build_facts(
			KernelScene.PaintPlan.forms(paint_plan),
			stores.colors,
			derive_counts(stores, KernelScene.PaintPlan.shadings(paint_plan), KernelScene.PaintPlan.patterns(paint_plan)),
			text,
			limits,
			KernelScene.PaintPlan.patterns(paint_plan),
			appearances,
		)

		## The authored color-space index of the transparency blending space.
		blending : Facts -> Blending
		blending = |facts| facts.blending

		instances : Facts, U64 -> U64
		instances = |facts, form| list_at(facts.form_instances, form)

		run_fragments : Facts -> List(RunFragment)
		run_fragments = |facts| facts.run_fragments

		work : Facts -> FactsWork
		work = |facts| facts.work
	}

	FormOwner : [ArtifactOwner, FragmentOwner(Semantics.FragmentId), MixedOwner, UnplacedOwner]

	## One annotation normal-appearance reference: the authored form it names
	## and the page whose annotation carries it. Appearance references are
	## closure-only graph uses — the form stays reachable through the
	## annotation's `/AP` reference without entering any content stream's
	## resource dictionary — and an appearance form may not contain semantic
	## text, because an appearance stream has no fragment ownership.
	AppearanceUse : { form : U64, page : U64 }

	Leaf : { descriptor : KernelResourceGraph.Descriptor, payload : List(U8) }

	## The leaf inputs of the canonical run: the validated color and image
	## plans whose payloads this stage derives itself, plus one derived
	## font-leaf recipe per authored font (`KernelFontLeaf` output), so fonts
	## deduplicate by exact canonical identity like every other leaf.
	Leaves : { colors : KernelColor.Plan, fonts : List(Leaf), images : KernelImage.Plan }

	## Direct resource-dictionary contents for one content stream, as dense
	## canonical ordinals per kind, each already in ascending — and therefore
	## canonical dictionary-key — order. Profiles are reachable only through
	## color-space arrays, never through a resource dictionary, so their bucket
	## stays empty for every root and form stream.
	DictionaryPlan : {
		color_spaces : List(U64),
		ext_g_states : List(U64),
		fonts : List(U64),
		forms : List(U64),
		functions : List(U64),
		images : List(U64),
		patterns : List(U64),
		profiles : List(U64),
		shadings : List(U64),
	}

	CanonicalForm : { bbox : Layout.Rect, commands : Semantics.Range, representative : U64 }

	CanonicalPattern : { bbox : Layout.Rect, commands : Semantics.Range, matrix : Scene.Matrix, representative : U64, x_step : Layout.Unit, y_step : Layout.Unit }

	## The emitted facts of one canonical shading: its geometry and extend
	## flags from the representative authored shading, the canonical ordinal
	## of its color space, and the canonical ordinal of its root function.
	ShadingFact : { extend_end : Bool, extend_start : Bool, function : U64, geometry : Scene.ShadingGeometry, representative : U64, space : U64 }

	## The emitted facts of one canonical function: a segment function
	## interpolates between two adjacent stops of its representative
	## authored shading, and a stitching function assembles the canonical
	## ordinals of that shading's segment functions in stop order. Stop
	## offsets and channel values lower from the validated shading store.
	FunctionFact : [
		SegmentFact({ segment : U64, shading : U64 }),
		StitchFact({ children : List(U64), shading : U64 }),
	]

	## Arena facts for one canonical image: the compacted color plane and
	## alpha plane live at `start ..` inside the canonical payload allocation,
	## immediately after the embedded color-space digest.
	ImageRange : { alpha_length : U64, color_length : U64, start : U64 }

	PlanWork : {
		artifact_placements : U64,
		authored_color_spaces : U64,
		authored_fonts : U64,
		authored_forms : U64,
		authored_images : U64,
		authored_profiles : U64,
		canonical_color_spaces : U64,
		canonical_ext_g_states : U64,
		canonical_fonts : U64,
		canonical_forms : U64,
		canonical_mask_states : U64,
		canonical_images : U64,
		canonical_profiles : U64,
		copied_leaf_bytes : U64,
		deduplicated_color_spaces : U64,
		deduplicated_fonts : U64,
		deduplicated_forms : U64,
		deduplicated_images : U64,
		deduplicated_mask_states : U64,
		deduplicated_opacity_groups : U64,
		deduplicated_profiles : U64,
		dictionary_entries : U64,
		font_recipe_bytes : U64,
		form_digests : U64,
		isolated_canonical_forms : U64,
		leaf_digests : U64,
		leaf_recipe_bytes : U64,
		nested_dictionary_entries : U64,
		nested_form_edges : U64,
		recipe_bytes : U64,
		semantic_placements : U64,
		semantically_duplicated_forms : U64,
		shared_artifact_forms : U64,
		state_recipe_bytes : U64,
		transparency_pages : U64,

		authored_functions : U64,
		authored_patterns : U64,
		authored_shadings : U64,
		canonical_functions : U64,
		canonical_patterns : U64,
		canonical_shadings : U64,
		deduplicated_functions : U64,
		deduplicated_patterns : U64,
		deduplicated_shadings : U64,
		function_recipe_bytes : U64,
		pattern_dictionary_entries : U64,
		pattern_recipe_bytes : U64,
		shading_recipe_bytes : U64,
	}

	## Stage 2: the canonical plan. Canonical leaves, graphics states, and
	## forms are ordinal-indexed in canonical-ID order (the documented total
	## order for physical objects); the `*_names` lists map every authored
	## resource to its canonical ordinal; the dictionaries are exact direct
	## uses per stream. The transparency facts carry each arena command's
	## canonical graphics-state ordinal (`U64.highest` meaning none), the
	## per-page transparency-group requirement, each canonical form's
	## isolation fact, and the canonical blending-space ordinal.
	Plan :: {
		blending : Blending,
		canonical_colors : List(U64),
		canonical_fonts : List(U64),
		canonical_forms : List(CanonicalForm),
		canonical_function_facts : List(FunctionFact),
		canonical_images : List(U64),
		canonical_pattern_cells : List(CanonicalPattern),
		canonical_profiles : List(U64),
		canonical_shading_facts : List(ShadingFact),
		color_names : List(U64),
		form_command_gs : List(U64),
		form_dictionaries : List(DictionaryPlan),
		font_names : List(U64),
		form_isolation : List(Bool),
		form_names : List(U64),
		graph : KernelResourceGraph.Plan,
		image_names : List(U64),
		image_ranges : List(ImageRange),
		page_command_gs : List(U64),
		page_dictionaries : List(DictionaryPlan),
		page_transparency : List(Bool),
		pattern_dictionaries : List(DictionaryPlan),
		pattern_names : List(U64),
		placements : List(KernelResourceGraph.Placement),
		profile_names : List(U64),
		shading_names : List(U64),
		state_facts : List(StateFact),
		work : PlanWork,
	}.{
		build : KernelScene.FormPlan, Facts, Leaves, [NoText, WithText(KernelContent.TextPlan)], KernelTagged.Plan, Limits -> Try(Plan, Error)
		build = |form_plan, facts, leaves, text, tagged, limits| build_canonical_plan(form_plan, Scene.no_shadings, Scene.no_patterns, facts, leaves, text, tagged, limits)

		## The paint-aware variant: the validated shading and pattern stores
		## supply the recipes and emission facts for the derived function,
		## shading, and pattern-cell nodes the facts stage declared.
		build_with_paints : KernelScene.PaintPlan, Facts, Leaves, [NoText, WithText(KernelContent.TextPlan)], KernelTagged.Plan, Limits -> Try(Plan, Error)
		build_with_paints = |paint_plan, facts, leaves, text, tagged, limits| build_canonical_plan(
			KernelScene.PaintPlan.forms(paint_plan),
			KernelScene.PaintPlan.shadings(paint_plan),
			KernelScene.PaintPlan.patterns(paint_plan),
			facts,
			leaves,
			text,
			tagged,
			limits,
		)

		canonical_function_count : Plan -> U64
		canonical_function_count = |plan| plan.canonical_function_facts.len()

		canonical_function_fact : Plan, U64 -> FunctionFact
		canonical_function_fact = |plan, ordinal| list_at(plan.canonical_function_facts, ordinal)

		canonical_pattern : Plan, U64 -> CanonicalPattern
		canonical_pattern = |plan, ordinal| list_at(plan.canonical_pattern_cells, ordinal)

		canonical_pattern_count : Plan -> U64
		canonical_pattern_count = |plan| plan.canonical_pattern_cells.len()

		canonical_shading_count : Plan -> U64
		canonical_shading_count = |plan| plan.canonical_shading_facts.len()

		canonical_shading_fact : Plan, U64 -> ShadingFact
		canonical_shading_fact = |plan, ordinal| list_at(plan.canonical_shading_facts, ordinal)

		pattern_dictionary : Plan, U64 -> DictionaryPlan
		pattern_dictionary = |plan, ordinal| list_at(plan.pattern_dictionaries, ordinal)

		pattern_names : Plan -> List(U64)
		pattern_names = |plan| plan.pattern_names

		shading_names : Plan -> List(U64)
		shading_names = |plan| plan.shading_names

		canonical_form : Plan, U64 -> CanonicalForm
		canonical_form = |plan, ordinal| list_at(plan.canonical_forms, ordinal)

		canonical_form_count : Plan -> U64
		canonical_form_count = |plan| plan.canonical_forms.len()

		## Representative authored color space per canonical color ordinal.
		canonical_color_representatives : Plan -> List(U64)
		canonical_color_representatives = |plan| plan.canonical_colors

		## Representative authored font per canonical font ordinal; each
		## canonical bundle lowers once from its lowest authored
		## representative's validated facts.
		canonical_font_representatives : Plan -> List(U64)
		canonical_font_representatives = |plan| plan.canonical_fonts

		canonical_font_count : Plan -> U64
		canonical_font_count = |plan| plan.canonical_fonts.len()

		font_names : Plan -> List(U64)
		font_names = |plan| plan.font_names

		## Whether each canonical image carries an alpha soft-mask plane.
		canonical_image_alpha : Plan -> List(Bool)
		canonical_image_alpha = |plan| {
			var $alpha = List.with_capacity(plan.image_ranges.len())
			var $index = 0
			while $index < plan.image_ranges.len() {
				$alpha = $alpha.append(list_at(plan.image_ranges, $index).alpha_length > 0)
				$index = $index + 1
			}
			$alpha
		}

		## The canonical row-compacted planes of one canonical raster image,
		## as immutable ranges of the canonical payload allocation. A JPEG
		## canonical image has no planes here; its sanitized bytes live in the
		## validated image store.
		canonical_image_planes : Plan, U64 -> { alpha : List(U8), color : List(U8) }
		canonical_image_planes = |plan, ordinal| {
			range = list_at(plan.image_ranges, ordinal)
			{
				alpha: KernelResourceGraph.Plan.payload_slice(plan.graph, range.start + range.color_length, range.alpha_length),
				color: KernelResourceGraph.Plan.payload_slice(plan.graph, range.start, range.color_length),
			}
		}

		canonical_image_representatives : Plan -> List(U64)
		canonical_image_representatives = |plan| plan.canonical_images

		canonical_leaf_counts : Plan -> { color_spaces : U64, images : U64, profiles : U64 }
		canonical_leaf_counts = |plan| {
			color_spaces: plan.canonical_colors.len(),
			images: plan.canonical_images.len(),
			profiles: plan.canonical_profiles.len(),
		}

		canonical_profile_representatives : Plan -> List(U64)
		canonical_profile_representatives = |plan| plan.canonical_profiles

		## The canonical color ordinal of the transparency blending space, or
		## `NoBlending` when no page contains transparency.
		blending : Plan -> Blending
		blending = |plan| plan.blending

		canonical_state_count : Plan -> U64
		canonical_state_count = |plan| plan.state_facts.len()

		## The emitted fact of one canonical graphics state: the exact
		## `U16`-range constant alpha applied to both `/ca` and `/CA` under
		## `/BM /Normal`, or the canonical mask form ordinal the alpha
		## soft mask renders.
		state_fact : Plan, U64 -> StateFact
		state_fact = |plan, ordinal| list_at(plan.state_facts, ordinal)

		## Dense per-command canonical graphics-state ordinals for the page
		## and form command arenas; `U64.highest` marks a command that emits
		## no graphics state (every non-opacity command, and every opacity
		## group whose own alpha is the fully opaque identity).
		page_command_states : Plan -> List(U64)
		page_command_states = |plan| plan.page_command_gs

		form_command_states : Plan -> List(U64)
		form_command_states = |plan| plan.form_command_gs

		## Which pages require an explicit transparency group dictionary.
		page_transparency : Plan -> List(Bool)
		page_transparency = |plan| plan.page_transparency

		## Whether each canonical form is an isolated transparency group.
		form_isolation : Plan -> List(Bool)
		form_isolation = |plan| plan.form_isolation

		color_names : Plan -> List(U64)
		color_names = |plan| plan.color_names

		form_dictionary : Plan, U64 -> DictionaryPlan
		form_dictionary = |plan, ordinal| list_at(plan.form_dictionaries, ordinal)

		form_names : Plan -> List(U64)
		form_names = |plan| plan.form_names

		graph : Plan -> KernelResourceGraph.Plan
		graph = |plan| plan.graph

		graph_work : Plan -> KernelResourceGraph.Work
		graph_work = |plan| KernelResourceGraph.Plan.work(plan.graph)

		image_names : Plan -> List(U64)
		image_names = |plan| plan.image_names

		page_dictionary : Plan, U64 -> DictionaryPlan
		page_dictionary = |plan, page| list_at(plan.page_dictionaries, page)

		placements : Plan -> List(KernelResourceGraph.Placement)
		placements = |plan| plan.placements

		profile_names : Plan -> List(U64)
		profile_names = |plan| plan.profile_names

		work : Plan -> PlanWork
		work = |plan| plan.work
	}
}

TextInput := [NoTextStore, WithTextStore(Text.Store)]

UseState := {
	command_visits : U64,
	direct_text : Bool,
	form_occurrences : List({ command : U64, form : U64 }),
	marks : List(U8),
	text_runs : List(U64),
	touched : List(U64),
}

WalkFrame := { range : Semantics.Range }

## The dense node-space bases the use walker touches derived and paint nodes
## through; all three are arithmetic offsets over one fixed kind order.
NodeBases := { pattern_base : U64, shading_base : U64, state_base : U64 }

## The fully opaque `U16` alpha: the exact multiplicative identity of the
## effective-product semantics, and therefore the value that normalizes away
## without a resource or operator.
opaque_alpha : U64
opaque_alpha = 65535

## Dense per-command state entries use this sentinel for every command that
## emits no graphics state.
state_sentinel : U64
state_sentinel = U64.highest

OpacityFrame := { alpha : U64, depth : U64, mask : Bool, range : Semantics.Range }

## Ambient facts at one form placement site: whether a non-identity constant
## alpha and whether a soft mask is active there.
AmbientSite := { alpha : Bool, mask : Bool }

OpacityRegistry := { mask_index : List(U64), states : List(KernelForm.DerivedState), value_index : List(U64) }

OpacityArena := { ambient : List(AmbientSite), states : List(U64) }

OpacityWalkResult := {
	arena : OpacityArena,
	direct_alpha : Bool,
	direct_mask : Bool,
	direct_opacity : Bool,
	max_depth : U64,
	opacity_commands : U64,
	opacity_groups : U64,
	opaque_normalized : U64,
	registry : OpacityRegistry,
	soft_mask_commands : U64,
	visits : U64,
}

OpacityDerivation := {
	form_ambient : List(AmbientSite),
	form_direct_alpha : List(Bool),
	form_direct_mask : List(Bool),
	form_direct_opacity : List(Bool),
	form_states : List(U64),
	page_ambient : List(AmbientSite),
	page_direct : List(Bool),
	page_states : List(U64),
	states : List(KernelForm.DerivedState),
	work : { max_depth : U64, opacity_commands : U64, opacity_groups : U64, opaque_normalized : U64, soft_mask_commands : U64, visits : U64 },
}

## Exact fixed-width effective alpha: the product of two `U16`-range alphas,
## renormalized by 65535 with round-half-even. Multiplying by the fully
## opaque identity is exact, and a non-identity factor always lands strictly
## below the identity, so an emitted state value can never be 65535.
effective_alpha : U64, U64 -> U64
effective_alpha = |ambient, own| round_half_even_ratio(ambient * own, opaque_alpha)

round_half_even_ratio : U64, U64 -> U64
round_half_even_ratio = |numerator, denominator| {
	quotient = U64.div_by(numerator, denominator)
	remainder = U64.mod_by(numerator, denominator)
	twice = remainder * 2
	if twice > denominator or (twice == denominator and U64.mod_by(quotient, 2) == 1) quotient + 1 else quotient
}

## Distinct effective values and distinct mask forms receive dense indices in
## first-appearance order over the deterministic page-then-form walk, in one
## combined derived-state space. The maps are one allocation each for the
## whole derivation; entries store `index + 1` so zero means unseen.
register_value : OpacityRegistry, U64 -> { index : U64, registry : OpacityRegistry }
register_value = |registry, value| {
	slot = list_at(registry.value_index, value)
	if slot != 0 {
		{ index: slot - 1, registry }
	} else {
		index = registry.states.len()
		{
			index,
			registry: {
				..registry,
				states: registry.states.append(AlphaState(value)),
				value_index: list_set(registry.value_index, value, index + 1),
			},
		}
	}
}

register_mask : OpacityRegistry, U64 -> { index : U64, registry : OpacityRegistry }
register_mask = |registry, form| {
	slot = list_at(registry.mask_index, form)
	if slot != 0 {
		{ index: slot - 1, registry }
	} else {
		index = registry.states.len()
		{
			index,
			registry: {
				..registry,
				mask_index: list_set(registry.mask_index, form, index + 1),
				states: registry.states.append(MaskState(form)),
			},
		}
	}
}

## One iterative walk of one validated root range computing, per command:
## the derived graphics state an opacity or soft-mask group emits (opaque
## opacity groups normalize away; every soft-mask group emits), the ambient
## alpha and mask facts at each form placement site, and the root's direct
## transparency facts. One stream context supports at most one active mask,
## so a soft-mask group under another is rejected here, and a mask must name
## an isolated-group form.
walk_opacity : OpacityArena, OpacityRegistry, Semantics.Range, List(Scene.Command), List(Bool), List(Bool), U64 -> Try(OpacityWalkResult, KernelForm.Error)
walk_opacity = |arena_state, registry, root, arena, image_alpha, isolated, max_depth| {
	var $states = arena_state.states
	var $ambient = arena_state.ambient
	var $registry = registry
	var $direct_alpha = Bool.False
	var $direct_mask = Bool.False
	var $direct_opacity = Bool.False
	var $maximum_depth = 0
	var $commands = 0
	var $groups = 0
	var $mask_commands = 0
	var $opaque = 0
	var $visits = 0
	var $frames = [OpacityFrame.{ alpha: opaque_alpha, depth: 0, mask: Bool.False, range: root }]
	var $frame_index = 0
	var $failure = NoFailure
	while $frame_index < $frames.len() and $failure == NoFailure {
		frame = list_at($frames, $frame_index)
		var $command_index = frame.range.start()
		end = frame.range.start() + frame.range.length()
		while $command_index < end and $failure == NoFailure {
			match list_at(arena, $command_index) {
				Clip({ children, path: _ }) | Transform({ children, matrix: _ }) => {
					$frames = $frames.append(OpacityFrame.{ alpha: frame.alpha, depth: frame.depth, mask: frame.mask, range: children })
				}
				Opacity({ children, opacity }) => {
					$commands = $commands + 1
					if opacity.to_u64() == opaque_alpha {
						$opaque = $opaque + 1
						$frames = $frames.append(OpacityFrame.{ alpha: frame.alpha, depth: frame.depth, mask: frame.mask, range: children })
					} else {
						depth = frame.depth + 1
						if depth > max_depth {
							$failure = Failed(OpacityDepthExceeded({ attempted: depth, limit: max_depth }))
						} else {
							eff = effective_alpha(frame.alpha, opacity.to_u64())
							registered = register_value($registry, eff)
							$registry = registered.registry
							$states = list_set($states, $command_index, registered.index)
							$direct_opacity = Bool.True
							$groups = $groups + 1
							$maximum_depth = U64.max($maximum_depth, depth)
							$frames = $frames.append(OpacityFrame.{ alpha: eff, depth, mask: frame.mask, range: children })
						}
					}
				}
				SoftMask({ children, mask }) => {
					$mask_commands = $mask_commands + 1
					if frame.mask {
						$failure = Failed(NestedSoftMask({ command: $command_index }))
					} else if !list_at(isolated, mask.index()) {
						$failure = Failed(MaskFormNotIsolated({ command: $command_index, form: mask.index() }))
					} else {
						registered = register_mask($registry, mask.index())
						$registry = registered.registry
						$states = list_set($states, $command_index, registered.index)
						$direct_mask = Bool.True
						$frames = $frames.append(OpacityFrame.{ alpha: frame.alpha, depth: frame.depth, mask: Bool.True, range: children })
					}
				}
				DrawImage({ image, placement: _ }) => {
					if list_at(image_alpha, image.index()) {
						$direct_alpha = Bool.True
					}
				}
				PlaceForm(_) => {
					if frame.alpha != opaque_alpha or frame.mask {
						$ambient = list_set($ambient, $command_index, { alpha: frame.alpha != opaque_alpha, mask: frame.mask })
					}
				}
				DrawPath(_) | DrawText(_) | PaintShading(_) => {}
			}
			$command_index = $command_index + 1
			$visits = $visits + 1
		}
		$frame_index = $frame_index + 1
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok({
			arena: { ambient: $ambient, states: $states },
			direct_alpha: $direct_alpha,
			direct_mask: $direct_mask,
			direct_opacity: $direct_opacity,
			max_depth: $maximum_depth,
			opacity_commands: $commands,
			opacity_groups: $groups,
			opaque_normalized: $opaque,
			registry: $registry,
			soft_mask_commands: $mask_commands,
			visits: $visits,
		})
	}
}

## The opacity and soft-mask pre-pass: one walk per page group and per form
## over the two command arenas. It runs before use collection so the later
## passes can touch derived graphics-state nodes by dense index, and before
## the structure run so ambient placement facts exist for the DAG sweeps.
## The 65536-entry value map is allocated only when the validated scene
## actually contains opacity commands, and the per-form mask map only when
## it contains soft-mask commands.
derive_opacity : Scene.Store, Scene.FormStore, List(Bool), List(Bool), Bool, Bool, U64 -> Try(OpacityDerivation, KernelForm.Error)
derive_opacity = |scenes, form_store, image_alpha, isolated, has_opacity, has_masks, max_depth| {
	no_site = AmbientSite.{ alpha: Bool.False, mask: Bool.False }
	var $page_arena = OpacityArena.{ ambient: List.repeat(no_site, scenes.commands.len()), states: List.repeat(state_sentinel, scenes.commands.len()) }
	var $registry = OpacityRegistry.{
		mask_index: if has_masks List.repeat(0, form_store.forms.len()) else [],
		states: [],
		value_index: if has_opacity List.repeat(0, 65536) else [],
	}
	var $page_direct = List.with_capacity(scenes.pages.len())
	var $commands = 0
	var $groups = 0
	var $mask_commands = 0
	var $opaque = 0
	var $maximum_depth = 0
	var $visits = 0
	var $failure = NoFailure

	var $page_index = 0
	while $page_index < scenes.pages.len() and $failure == NoFailure {
		page = list_at(scenes.pages, $page_index)
		var $direct = Bool.False
		var $edge = page.paint_order.start()
		end = $edge + page.paint_order.length()
		while $edge < end and $failure == NoFailure {
			group = list_at(scenes.groups, list_at(scenes.page_groups, $edge).index())
			match walk_opacity($page_arena, $registry, group.commands, scenes.commands, image_alpha, isolated, max_depth) {
				Err(error) => {
					$failure = Failed(error)
				}
				Ok(result) => {
					$page_arena = result.arena
					$registry = result.registry
					$direct = $direct or result.direct_alpha or result.direct_opacity or result.direct_mask
					$commands = $commands + result.opacity_commands
					$groups = $groups + result.opacity_groups
					$mask_commands = $mask_commands + result.soft_mask_commands
					$opaque = $opaque + result.opaque_normalized
					$maximum_depth = U64.max($maximum_depth, result.max_depth)
					$visits = $visits + result.visits
				}
			}
			$edge = $edge + 1
		}
		$page_direct = $page_direct.append($direct)
		$page_index = $page_index + 1
	}

	var $form_arena = OpacityArena.{ ambient: List.repeat(no_site, form_store.commands.len()), states: List.repeat(state_sentinel, form_store.commands.len()) }
	var $form_direct_alpha = List.with_capacity(form_store.forms.len())
	var $form_direct_mask = List.with_capacity(form_store.forms.len())
	var $form_direct_opacity = List.with_capacity(form_store.forms.len())
	var $form_index = 0
	while $form_index < form_store.forms.len() and $failure == NoFailure {
		form = list_at(form_store.forms, $form_index)
		match walk_opacity($form_arena, $registry, form.commands, form_store.commands, image_alpha, isolated, max_depth) {
			Err(error) => {
				$failure = Failed(error)
			}
			Ok(result) => {
				$form_arena = result.arena
				$registry = result.registry
				$form_direct_alpha = $form_direct_alpha.append(result.direct_alpha)
				$form_direct_mask = $form_direct_mask.append(result.direct_mask)
				$form_direct_opacity = $form_direct_opacity.append(result.direct_opacity)
				$commands = $commands + result.opacity_commands
				$groups = $groups + result.opacity_groups
				$mask_commands = $mask_commands + result.soft_mask_commands
				$opaque = $opaque + result.opaque_normalized
				$maximum_depth = U64.max($maximum_depth, result.max_depth)
				$visits = $visits + result.visits
			}
		}
		$form_index = $form_index + 1
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok({
			form_ambient: $form_arena.ambient,
			form_direct_alpha: $form_direct_alpha,
			form_direct_mask: $form_direct_mask,
			form_direct_opacity: $form_direct_opacity,
			form_states: $form_arena.states,
			page_ambient: $page_arena.ambient,
			page_direct: $page_direct,
			page_states: $page_arena.states,
			states: $registry.states,
			work: { max_depth: $maximum_depth, opacity_commands: $commands, opacity_groups: $groups, opaque_normalized: $opaque, soft_mask_commands: $mask_commands, visits: $visits },
		})
	}
}

## The lowest authored color space declaring the packaged ICCBased sRGB
## profile, probed by exact byte equality against the packaged asset (each
## profile once). Only transparency-bearing documents pay the probe.
select_blending : KernelColor.Plan -> { blending : KernelForm.Blending, probe_bytes : U64 }
select_blending = |colors| {
	store = KernelColor.Plan.store(colors)
	var $packaged = List.with_capacity(store.profiles.len())
	var $probe = 0
	var $profile_index = 0
	while $profile_index < store.profiles.len() {
		profile = list_at(store.profiles, $profile_index)
		$probe = $probe + profile.bytes.len()
		$packaged = $packaged.append(profile.bytes == KernelSrgbProfile.bytes)
		$profile_index = $profile_index + 1
	}
	var $space_index = 0
	var $blending = NoBlending
	while $space_index < store.spaces.len() and $blending == NoBlending {
		record = list_at(store.spaces, $space_index)
		reference = match record.space {
			CalibratedGray(_) => NoProfile
			IccBased({ components: _, profile }) => WithProfile(profile.index())
			Srgb(profile) => WithProfile(profile.index())
		}
		match reference {
			NoProfile => {}
			WithProfile(profile) => {
				if list_at($packaged, profile) {
					$blending = Blending($space_index)
				}
			}
		}
		$space_index = $space_index + 1
	}
	{ blending: $blending, probe_bytes: $probe }
}

## Dense node IDs over one fixed kind order: color spaces, images, fonts,
## ICC profiles, forms, the derived graphics states, shadings, patterns, and
## the derived shading functions. The mapping is arithmetic, so no per-node
## table exists.
color_node : U64 -> U64
color_node = |color| color

image_node : KernelForm.Counts, U64 -> U64
image_node = |counts, image| counts.color_spaces + image

font_node : KernelForm.Counts, U64 -> U64
font_node = |counts, font| counts.color_spaces + counts.image_color_spaces.len() + font

profile_node : KernelForm.Counts, U64 -> U64
profile_node = |counts, profile| counts.color_spaces + counts.image_color_spaces.len() + counts.fonts + profile

form_node : KernelForm.Counts, U64 -> U64
form_node = |counts, form| form_base(counts) + form

form_base : KernelForm.Counts -> U64
form_base = |counts| counts.color_spaces + counts.image_color_spaces.len() + counts.fonts + counts.profiles

state_node : KernelForm.Counts, U64, U64 -> U64
state_node = |counts, form_count, state| form_base(counts) + form_count + state

shading_base : KernelForm.Counts, U64, U64 -> U64
shading_base = |counts, form_count, states| form_base(counts) + form_count + states

shading_node : KernelForm.Counts, U64, U64, U64 -> U64
shading_node = |counts, form_count, states, shading| shading_base(counts, form_count, states) + shading

pattern_base : KernelForm.Counts, U64, U64 -> U64
pattern_base = |counts, form_count, states| shading_base(counts, form_count, states) + counts.shadings

pattern_node : KernelForm.Counts, U64, U64, U64 -> U64
pattern_node = |counts, form_count, states, pattern| pattern_base(counts, form_count, states) + pattern

function_base : KernelForm.Counts, U64, U64 -> U64
function_base = |counts, form_count, states| pattern_base(counts, form_count, states) + counts.patterns

function_total : KernelForm.Counts -> U64
function_total = |counts| counts.function_shadings.len()

## The derived root function of one shading is the last function in its
## layout: the single segment of a two-stop gradient, or the stitching
## function assembled over the segments of a multi-stop gradient.
shading_root_function : KernelForm.Counts, U64 -> U64
shading_root_function = |counts, shading| list_at(counts.shading_function_offsets, shading + 1) - 1

node_count : KernelForm.Counts, U64, U64 -> U64
node_count = |counts, forms, states| function_base(counts, forms, states) + function_total(counts)

## Counts and per-node dependency facts come from the validated stores, so
## authored declarations can never disagree with the payloads that leaf
## identity is derived from.
derive_counts : KernelForm.Stores, Scene.ShadingStore, Scene.PatternStore -> KernelForm.Counts
derive_counts = |stores, shading_store, pattern_store| {
	color_store = KernelColor.Plan.store(stores.colors)
	image_store = KernelImage.Plan.store(stores.images)
	var $image_spaces = List.with_capacity(image_store.resources.len())
	var $image_alpha = List.with_capacity(image_store.resources.len())
	var $image_index = 0
	while $image_index < image_store.resources.len() {
		resource = list_at(image_store.resources, $image_index)
		space = match resource.payload {
			Jpeg(jpeg) => jpeg.color_space.index()
			Raster(raster) => raster.color_space.index()
		}
		alpha = match resource.payload {
			Jpeg(_) => Bool.False
			Raster(raster) => match raster.alpha {
				NoAlpha => Bool.False
				PackedAlpha(_) => Bool.True
			}
		}
		$image_spaces = $image_spaces.append(space)
		$image_alpha = $image_alpha.append(alpha)
		$image_index = $image_index + 1
	}
	var $space_profiles = List.with_capacity(color_store.spaces.len())
	var $space_index = 0
	while $space_index < color_store.spaces.len() {
		record = list_at(color_store.spaces, $space_index)
		reference = match record.space {
			CalibratedGray(_) => NoProfile
			IccBased({ components: _, profile }) => WithProfile(profile.index())
			Srgb(profile) => WithProfile(profile.index())
		}
		$space_profiles = $space_profiles.append(reference)
		$space_index = $space_index + 1
	}

	## The derived function layout: a two-stop shading lowers to one
	## exponential function; a multi-stop shading lowers to one segment
	## function per interval plus one stitching function, laid out segments
	## first so the stitching (root) function is always the last node of its
	## shading.
	var $offsets = List.with_capacity(shading_store.shadings.len() + 1)
	$offsets = $offsets.append(0)
	var $function_shadings = []
	var $shading_spaces = List.with_capacity(shading_store.shadings.len())
	var $shading_subtypes = List.with_capacity(shading_store.shadings.len())
	var $shading_components = List.with_capacity(shading_store.shadings.len())
	var $running = 0
	var $shading_index = 0
	while $shading_index < shading_store.shadings.len() {
		shading = list_at(shading_store.shadings, $shading_index)
		stops = shading.stops.length()
		functions = if stops == 2 1 else stops
		$running = $running + functions
		$offsets = $offsets.append($running)
		var $function = 0
		while $function < functions {
			$function_shadings = $function_shadings.append($shading_index)
			$function = $function + 1
		}
		$shading_spaces = $shading_spaces.append(shading.space.index())
		$shading_subtypes = $shading_subtypes.append(
			match shading.geometry {
				Axial(_) => 2
				Radial(_) => 3
			},
		)
		first_stop = list_at(shading_store.stops, shading.stops.start())
		$shading_components = $shading_components.append(
			match first_stop.channels {
				Gray(_) => 1
				Rgb(_) => 3
			},
		)
		$shading_index = $shading_index + 1
	}

	{
		color_spaces: color_store.spaces.len(),
		fonts: stores.font_count,
		function_shadings: $function_shadings,
		image_alpha: $image_alpha,
		image_color_spaces: $image_spaces,
		patterns: pattern_store.cells.len(),
		profiles: color_store.profiles.len(),
		shading_components: $shading_components,
		shading_function_offsets: $offsets,
		shading_spaces: $shading_spaces,
		shading_subtypes: $shading_subtypes,
		shadings: shading_store.shadings.len(),
		space_profiles: $space_profiles,
	}
}

build_facts : KernelScene.FormPlan, KernelColor.Plan, KernelForm.Counts, TextInput, KernelForm.Limits, Scene.PatternStore, List(KernelForm.AppearanceUse) -> Try(KernelForm.Facts, KernelForm.Error)
build_facts = |form_plan, colors, counts, text, limits, pattern_store, appearances| {
	page_plan = KernelScene.FormPlan.page(form_plan)
	scenes = KernelScene.Plan.scenes(page_plan)
	form_store = KernelScene.FormPlan.forms(form_plan)
	form_count = form_store.forms.len()

	var $isolated = List.with_capacity(form_count)
	var $isolated_index = 0
	while $isolated_index < form_count {
		flag = match list_at(form_store.forms, $isolated_index).group {
			IsolatedGroup => Bool.True
			NoGroup => Bool.False
		}
		$isolated = $isolated.append(flag)
		$isolated_index = $isolated_index + 1
	}
	isolated = $isolated

	## The opacity pre-pass derives the per-command effective-alpha states,
	## the distinct state values (the derived graphics-state node space), the
	## ambient placement facts, and the direct transparency facts.
	scene_work = KernelScene.Plan.work(page_plan)
	form_work = KernelScene.FormPlan.work(form_plan)
	has_opacity = scene_work.opacity_commands + form_work.form_opacity_commands > 0
	has_masks = scene_work.soft_mask_commands + form_work.form_soft_mask_commands > 0
	derivation = derive_opacity(scenes, form_store, counts.image_alpha, isolated, has_opacity, has_masks, limits.max_opacity_depth)?
	states_count = derivation.states.len()
	bases = NodeBases.{
		pattern_base: pattern_base(counts, form_count, states_count),
		shading_base: shading_base(counts, form_count, states_count),
		state_base: form_base(counts) + form_count,
	}
	nodes = node_count(counts, form_count, states_count)

	## The blending space is probed only when some transparency fact exists
	## anywhere; a fully opaque document never pays the probe and needs no
	## blending declaration.
	var $any_transparency = any_true(derivation.page_direct) or any_true(derivation.form_direct_alpha) or any_true(derivation.form_direct_opacity) or any_true(derivation.form_direct_mask) or any_true(isolated)
	blending_probe = if $any_transparency select_blending(colors) else { blending: NoBlending, probe_bytes: 0 }
	blending = blending_probe.blending

	## Pass A: one walk per page over its owned groups collects that page's
	## deduplicated direct uses, its form placements with their inherited
	## group ownership and ambient-alpha site facts, and the raw placement
	## multiset.
	var $root_uses = []
	var $page_placements = []
	var $use_command_visits = 0
	var $page_index = 0
	var $failure = NoFailure
	while $page_index < scenes.pages.len() and $failure == NoFailure {
		page = list_at(scenes.pages, $page_index)
		var $state = fresh_use_state(nodes)
		var $edge = page.paint_order.start()
		end = $edge + page.paint_order.length()
		while $edge < end and $failure == NoFailure {
			group = list_at(scenes.groups, list_at(scenes.page_groups, $edge).index())
			collected = collect_range_uses($state, group.commands, scenes.commands, counts, text, derivation.page_states, bases)
			match collected {
				Err(error) => {
					$failure = Failed(error)
				}
				Ok(state) => {
					placement_start = $state.form_occurrences.len()
					$state = state
					var $occurrence = placement_start
					while $occurrence < $state.form_occurrences.len() {
						occurrence = list_at($state.form_occurrences, $occurrence)
						site = list_at(derivation.page_ambient, occurrence.command)
						$page_placements = $page_placements.append({
							ambient: site.alpha,
							ambient_mask: site.mask,
							form: occurrence.form,
							owner: group.owner,
							page: $page_index,
						})
						$occurrence = $occurrence + 1
					}
				}
			}
			$edge = $edge + 1
		}
		if $failure == NoFailure {
			var $touched_index = 0
			while $touched_index < $state.touched.len() {
				$root_uses = $root_uses.append({ resource: list_at($state.touched, $touched_index), root: $page_index })
				$touched_index = $touched_index + 1
			}
			$use_command_visits = $use_command_visits + $state.command_visits
		}
		$page_index = $page_index + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Pass B: one walk per form over the form arena collects each form's
	## deduplicated direct uses (its direct edges), its nested placement
	## multiset with ambient site facts, its directly drawn runs, and its
	## direct-text fact.
	var $edges = []
	var $nested = []
	var $form_runs = []
	var $direct_text = List.repeat(Bool.False, form_count)
	var $form_index = 0
	while $form_index < form_count and $failure == NoFailure {
		form = list_at(form_store.forms, $form_index)
		match collect_range_uses(fresh_use_state(nodes), form.commands, form_store.commands, counts, text, derivation.form_states, bases) {
			Err(error) => {
				$failure = Failed(error)
			}
			Ok(state) => {
				source = form_node(counts, $form_index)
				var $touched_index = 0
				while $touched_index < state.touched.len() {
					$edges = $edges.append({ source, target: list_at(state.touched, $touched_index) })
					$touched_index = $touched_index + 1
				}
				var $occurrence = 0
				while $occurrence < state.form_occurrences.len() {
					occurrence = list_at(state.form_occurrences, $occurrence)
					site = list_at(derivation.form_ambient, occurrence.command)
					$nested = $nested.append({
						ambient: site.alpha,
						ambient_mask: site.mask,
						child: occurrence.form,
						parent: $form_index,
					})
					$occurrence = $occurrence + 1
				}
				var $run_index = 0
				while $run_index < state.text_runs.len() {
					$form_runs = $form_runs.append({ form: $form_index, run: list_at(state.text_runs, $run_index) })
					$run_index = $run_index + 1
				}
				$direct_text = list_set($direct_text, $form_index, state.direct_text)
				$use_command_visits = $use_command_visits + state.command_visits
			}
		}
		$form_index = $form_index + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Pass C: one walk per pattern cell over the pattern arena collects the
	## cell's deduplicated direct uses, which become the pattern's direct
	## edges. Cell content is fully opaque by validation, so the arena has no
	## derived graphics states; a sentinel state map keeps the shared walker
	## total. An alpha image touched directly by a cell is rejected here.
	var $pattern_cell_visits = 0
	cell_states = if counts.patterns > 0 List.repeat(state_sentinel, pattern_store.commands.len()) else []
	var $cell_index = 0
	while $cell_index < counts.patterns and $failure == NoFailure {
		cell = list_at(pattern_store.cells, $cell_index)
		match collect_range_uses(fresh_use_state(nodes), cell.commands, pattern_store.commands, counts, text, cell_states, bases) {
			Err(error) => {
				$failure = Failed(error)
			}
			Ok(state) => {
				source = pattern_node(counts, form_count, states_count, $cell_index)
				var $touched_index = 0
				while $touched_index < state.touched.len() and $failure == NoFailure {
					target = list_at(state.touched, $touched_index)
					if target >= counts.color_spaces and target < counts.color_spaces + counts.image_color_spaces.len() and list_at(counts.image_alpha, target - counts.color_spaces) {
						$failure = Failed(AlphaImageInPattern({ image: target - counts.color_spaces, pattern: $cell_index }))
					} else {
						$edges = $edges.append({ source, target })
					}
					$touched_index = $touched_index + 1
				}
				$pattern_cell_visits = $pattern_cell_visits + state.command_visits
			}
		}
		$cell_index = $cell_index + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Every image names its color space as a direct dependency, so closure
	## holds for color spaces reached only through image data.
	var $image_index = 0
	while $image_index < counts.image_color_spaces.len() {
		$edges = $edges.append({ source: image_node(counts, $image_index), target: color_node(list_at(counts.image_color_spaces, $image_index)) })
		$image_index = $image_index + 1
	}

	## Every ICCBased color space names its profile as a direct dependency,
	## so profiles are reachable exactly through the spaces that use them and
	## an unused profile is rejected as unreachable.
	var $space_index = 0
	while $space_index < counts.space_profiles.len() {
		match list_at(counts.space_profiles, $space_index) {
			NoProfile => {}
			WithProfile(profile) => {
				$edges = $edges.append({ source: color_node($space_index), target: profile_node(counts, profile) })
			}
		}
		$space_index = $space_index + 1
	}

	## Every shading names its color space and its derived root function as
	## direct dependencies, and every stitching function names its segment
	## functions, so functions digest before the shadings that embed them,
	## stay reachable without dictionary entries, and share the graph's
	## cycle and closure proofs.
	var $shading_edge = 0
	while $shading_edge < counts.shadings {
		source = shading_node(counts, form_count, states_count, $shading_edge)
		$edges = $edges.append({ source, target: color_node(list_at(counts.shading_spaces, $shading_edge)) })
		functions_start = function_base(counts, form_count, states_count)
		root_function = functions_start + shading_root_function(counts, $shading_edge)
		$edges = $edges.append({ source, target: root_function })
		segment_start = list_at(counts.shading_function_offsets, $shading_edge)
		segment_count = list_at(counts.shading_function_offsets, $shading_edge + 1) - segment_start
		if segment_count > 1 {
			var $segment = 0
			while $segment < segment_count - 1 {
				$edges = $edges.append({ source: root_function, target: functions_start + segment_start + $segment })
				$segment = $segment + 1
			}
		}
		$shading_edge = $shading_edge + 1
	}

	## Every mask graphics state names its mask form as a direct dependency,
	## so mask forms stay reachable without dictionary entries, mask cycles
	## are graph cycles, and mask-form recipes digest before the states that
	## embed them.
	var $state_edge = 0
	while $state_edge < derivation.states.len() {
		match list_at(derivation.states, $state_edge) {
			AlphaState(_) => {}
			MaskState(mask_form) => {
				$edges = $edges.append({ source: state_node(counts, form_count, $state_edge), target: form_node(counts, mask_form) })
			}
		}
		$state_edge = $state_edge + 1
	}

	## The structure run: unique ordinal payloads, real edges and roots. It
	## validates the direct-edge DAG (cycles, self-cycles, closure, duplicate
	## declarations) and yields the deterministic topological order that the
	## ownership sweeps and recipe construction below rely on. The run's order
	## names its own canonical IDs; unique payloads make that assignment a
	## bijection, so it maps back to authored node IDs exactly. When the
	## document contains transparency, one conservative closure-only use keeps
	## the blending space reachable before per-page transparency is known; the
	## canonical run later re-proves closure with the exact per-page uses.
	var $structure_closure = match blending {
		NoBlending => []
		Blending(space) => if scenes.pages.len() > 0 [{ resource: color_node(space), root: 0 }] else []
	}
	var $appearance_scan = 0
	while $appearance_scan < appearances.len() {
		use = list_at(appearances, $appearance_scan)
		$structure_closure = $structure_closure.append({ resource: form_node(counts, use.form), root: use.page })
		$appearance_scan = $appearance_scan + 1
	}
	structure_closure = $structure_closure
	structure = KernelResourceGraph.Plan.build_with_closure_uses(
		structure_input(counts, form_count, derivation.states, isolated, $edges, scenes.pages.len(), $root_uses),
		structure_closure,
		limits.graph,
	) ? Graph
	canonical_order = KernelResourceGraph.Plan.order(structure)
	var $authored_of = List.repeat(0, nodes)
	var $node = 0
	while $node < nodes {
		$authored_of = list_set($authored_of, KernelResourceGraph.Plan.canonical_index(structure, $node), $node)
		$node = $node + 1
	}
	var $order = List.with_capacity(nodes)
	var $order_index = 0
	while $order_index < nodes {
		$order = $order.append(list_at($authored_of, list_at(canonical_order, $order_index)))
		$order_index = $order_index + 1
	}
	order = $order

	sweep = resolve_ownership(counts, form_count, order, $page_placements, $nested)?
	transitive_text = resolve_transitive_text(counts, form_count, order, $direct_text, sweep.nested_offsets, sweep.nested_children)?

	## The transparency sweeps mirror the text sweeps: one forward pass folds
	## each form's transitive transparency (isolated child groups count as
	## transparency), and one reversed pass resolves whether any placement
	## chain executes a form under a non-identity ambient alpha, stopping at
	## isolated-group boundaries because a group resets the ambient alpha.
	transparency = resolve_transparency(
		counts,
		form_count,
		order,
		{
			direct_alpha: derivation.form_direct_alpha,
			direct_mask: derivation.form_direct_mask,
			direct_opacity: derivation.form_direct_opacity,
			isolated,
			nested_children: sweep.nested_children,
			nested_edge_ambient: sweep.nested_edge_ambient,
			nested_offsets: sweep.nested_offsets,
			page_placements: $page_placements,
		},
	)?

	## A shared non-group stream cannot encode a per-placement effective
	## product, so its own opacity under ambient alpha is rejected; a soft
	## mask under an ambient mask would replace rather than compose, so it is
	## rejected symmetrically. Isolated groups reset both channels.
	$form_index = 0
	while $form_index < form_count and $failure == NoFailure {
		if list_at(derivation.form_direct_opacity, $form_index) and !list_at(isolated, $form_index) and list_at(transparency.in_ambient, $form_index) {
			$failure = Failed(FormOpacityInAmbient({ form: $form_index }))
		} else if list_at(derivation.form_direct_mask, $form_index) and !list_at(isolated, $form_index) and list_at(transparency.in_mask, $form_index) {
			$failure = Failed(FormMaskInAmbient({ form: $form_index }))
		}
		$form_index = $form_index + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Forms reachable inside a mask rendering (the mask forms and everything
	## they place) carry no marked content or extraction presence, so
	## semantic text may not appear there. One reversed-topological sweep
	## marks the mask subtrees; the mask chain sweep then bounds how deep
	## mask renderings may themselves apply further masks.
	var $mask_state_total = 0
	var $state_scan = 0
	while $state_scan < derivation.states.len() {
		match list_at(derivation.states, $state_scan) {
			AlphaState(_) => {}
			MaskState(_) => {
				$mask_state_total = $mask_state_total + 1
			}
		}
		$state_scan = $state_scan + 1
	}
	mask_state_total = $mask_state_total

	## The mask sweeps only run for documents that actually apply masks; a
	## maskless document keeps an empty reachability fact and zero chain.
	mask_facts = if mask_state_total > 0 {
		resolve_masks(
			counts,
			form_count,
			order,
			derivation.states,
			{
				nested_children: sweep.nested_children,
				nested_offsets: sweep.nested_offsets,
			},
			$edges,
			limits.max_mask_depth,
		)?
	} else {
		{ mask_reachable: [], max_chain: 0, visits: 0 }
	}
	$form_index = 0
	while $form_index < mask_facts.mask_reachable.len() and $failure == NoFailure {
		if list_at(mask_facts.mask_reachable, $form_index) and list_at(transitive_text, $form_index) {
			$failure = Failed(TextInMaskForm({ form: $form_index }))
		}
		$form_index = $form_index + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Per-page transparency: direct facts plus every placed form that is an
	## isolated group or transitively carries transparency. Pages that need a
	## transparency group need the blending space.
	var $page_transparency = derivation.page_direct
	var $placement_scan = 0
	while $placement_scan < $page_placements.len() {
		placement = list_at($page_placements, $placement_scan)
		if list_at(isolated, placement.form) or list_at(transparency.transitive, placement.form) {
			$page_transparency = list_set($page_transparency, placement.page, Bool.True)
		}
		$placement_scan = $placement_scan + 1
	}
	var $transparency_pages = 0
	var $closure_uses = 0
	var $missing_blending = NoFailure
	var $page_scan = 0
	while $page_scan < $page_transparency.len() {
		if list_at($page_transparency, $page_scan) {
			$transparency_pages = $transparency_pages + 1
			match blending {
				NoBlending => if $missing_blending == NoFailure {
					$missing_blending = Failed(MissingBlendingSpace({ page: $page_scan }))
				} else {
					{}
				}
				Blending(_) => {
					$closure_uses = $closure_uses + 1
				}
			}
		}
		$page_scan = $page_scan + 1
	}
	match $missing_blending {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Forms reachable from a pattern cell repeat with every tile inside an
	## ownership-neutral stream, so semantic text, transparency, and nested
	## pattern invocation are rejected there. The sweep only runs for
	## documents that declare patterns.
	pattern_facts = if counts.patterns > 0 {
		resolve_pattern_reach(counts, form_count, states_count, order, $edges)
	} else {
		{ nested_pattern: [], reachable: [], visits: 0 }
	}
	var $pattern_form = 0
	while $pattern_form < pattern_facts.reachable.len() and $failure == NoFailure {
		if list_at(pattern_facts.reachable, $pattern_form) {
			if list_at(transitive_text, $pattern_form) {
				$failure = Failed(TextInPatternForm({ form: $pattern_form }))
			} else if list_at(isolated, $pattern_form) or list_at(transparency.transitive, $pattern_form) {
				$failure = Failed(TransparencyInPattern({ form: $pattern_form }))
			} else if list_at(pattern_facts.nested_pattern, $pattern_form) {
				$failure = Failed(NestedPatternInvocation({ form: $pattern_form }))
			} else {
				{}
			}
		}
		$pattern_form = $pattern_form + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	$appearance_scan = 0
	while $appearance_scan < appearances.len() and $failure == NoFailure {
		appearance_form = list_at(appearances, $appearance_scan).form
		if appearance_form < form_count and list_at(transitive_text, appearance_form) {
			$failure = Failed(AppearanceTextUnsupported({ form: appearance_form }))
		}
		$appearance_scan = $appearance_scan + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	var $text_forms = 0
	$form_index = 0
	while $form_index < form_count and $failure == NoFailure {
		if list_at(transitive_text, $form_index) {
			$text_forms = $text_forms + 1
			instances = list_at(sweep.instances, $form_index)
			if instances != 1 {
				$failure = Failed(TextFormMultiplyPlaced({ form: $form_index, instances }))
			} else {
				match list_at(sweep.owners, $form_index) {
					FragmentOwner(_) => {}
					_ => {
						$failure = Failed(ArtifactTextInForm({ form: $form_index }))
					}
				}
			}
		}
		$form_index = $form_index + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	var $run_fragments = List.with_capacity($form_runs.len())
	var $form_run_index = 0
	while $form_run_index < $form_runs.len() and $failure == NoFailure {
		form_run = list_at($form_runs, $form_run_index)
		match list_at(sweep.owners, form_run.form) {
			FragmentOwner(fragment) => {
				$run_fragments = $run_fragments.append({ fragment, run: form_run.run })
			}
			_ => {
				$failure = Failed(ArtifactTextInForm({ form: form_run.form }))
			}
		}
		$form_run_index = $form_run_index + 1
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok(
			KernelForm.Facts.{
				blending,
				counts,
				derived_states: derivation.states,
				direct_text: $direct_text,
				edges: $edges,
				form_command_states: derivation.form_states,
				form_instances: sweep.instances,
				form_isolated: isolated,
				form_owners: sweep.owners,
				nested_offsets: sweep.nested_offsets,
				nested_children: sweep.nested_children,
				order,
				page_command_states: derivation.page_states,
				page_placements: $page_placements,
				page_transparency: $page_transparency,
				appearance_uses: appearances,
				root_uses: $root_uses,
				run_fragments: $run_fragments,
				transitive_text,
				work: {
					blending_probe_bytes: blending_probe.probe_bytes,
					closure_uses: $closure_uses,
					derived_functions: function_total(counts),
					direct_edges: $edges.len(),
					distinct_opacity_values: states_count - mask_state_total,
					mask_chain_sweep_visits: mask_facts.visits,
					mask_states: mask_state_total,
					max_mask_chain: mask_facts.max_chain,
					max_opacity_depth: derivation.work.max_depth,
					nested_form_placements: $nested.len(),
					opacity_commands: derivation.work.opacity_commands,
					opacity_groups: derivation.work.opacity_groups,
					opaque_normalized: derivation.work.opaque_normalized,
					ownership_sweep_visits: sweep.visits,
					page_form_placements: $page_placements.len(),
					pattern_cell_use_visits: $pattern_cell_visits,
					pattern_sweep_visits: pattern_facts.visits,
					root_uses: $root_uses.len(),
					soft_mask_commands: derivation.work.soft_mask_commands,
					text_forms: $text_forms,
					transparency_pages: $transparency_pages,
					transparency_sweep_visits: transparency.visits,
					use_command_visits: $use_command_visits,
				},
			},
		)
	}
}

fresh_use_state : U64 -> UseState
fresh_use_state = |nodes| {
	command_visits: 0,
	direct_text: Bool.False,
	form_occurrences: [],
	marks: List.repeat(0, nodes),
	text_runs: [],
	touched: [],
}

any_true : List(Bool) -> Bool
any_true = |flags| {
	var $index = 0
	var $found = Bool.False
	while $index < flags.len() and !$found {
		if list_at(flags, $index) {
			$found = Bool.True
		}
		$index = $index + 1
	}
	$found
}

## Mask-subtree and mask-chain facts. The reachable sweep marks every form
## a mask rendering can execute (the mask target forms and, transitively,
## every form they place), processing parents before children in reversed
## topological order. The chain sweep then computes, dependencies first, how
## many mask renderings stack: a mask state's chain is one more than its
## target form's chain, and a form's chain is the maximum over its direct
## dependencies — so a mask form whose subtree applies further masks
## accumulates depth, and a cycle is impossible because the graph already
## rejected it. Every mask state's chain must stay within the budget.
resolve_masks : KernelForm.Counts, U64, List(U64), List(KernelForm.DerivedState), { nested_children : List(U64), nested_offsets : List(U64) }, List(KernelResourceGraph.Edge), U64 -> Try({ mask_reachable : List(Bool), max_chain : U64, visits : U64 }, KernelForm.Error)
resolve_masks = |counts, form_count, order, states, nesting, edges, max_mask_depth| {
	base = form_base(counts)
	state_base = base + form_count
	var $visits = 0

	var $mask_reachable = List.repeat(Bool.False, form_count)
	var $state_index = 0
	while $state_index < states.len() {
		match list_at(states, $state_index) {
			AlphaState(_) => {}
			MaskState(mask_form) => {
				$mask_reachable = list_set($mask_reachable, mask_form, Bool.True)
			}
		}
		$state_index = $state_index + 1
	}
	var $reversed = order.len()
	while $reversed > 0 {
		$reversed = $reversed - 1
		node = list_at(order, $reversed)
		if node >= base and node < state_base {
			parent = node - base
			if list_at($mask_reachable, parent) {
				var $edge = list_at(nesting.nested_offsets, parent)
				edge_end = list_at(nesting.nested_offsets, parent + 1)
				while $edge < edge_end {
					$mask_reachable = list_set($mask_reachable, list_at(nesting.nested_children, $edge), Bool.True)
					$edge = $edge + 1
					$visits = $visits + 1
				}
			}
		}
	}

	## Direct-dependency adjacency over the whole node space by counting
	## and prefix sums, so the chain sweep visits each edge once. State
	## nodes occupy the exact `[state_base, state_base + states)` range;
	## paint nodes beyond it fold their dependencies like resources do.
	node_total = node_count(counts, form_count, states.len())
	adjacency = edge_adjacency(edges, node_total)
	state_end = state_base + states.len()

	var $chain = List.repeat(0, node_total)
	var $max_chain = 0
	var $failure = NoFailure
	var $position = 0
	while $position < order.len() and $failure == NoFailure {
		node = list_at(order, $position)
		is_state = node >= state_base and node < state_end
		value = if is_state {
			match list_at(states, node - state_base) {
				AlphaState(_) => 0
				MaskState(mask_form) => {
					depth = list_at($chain, form_node(counts, mask_form)) + 1
					if depth > max_mask_depth {
						$failure = Failed(MaskDepthExceeded({ attempted: depth, limit: max_mask_depth }))
					}
					depth
				}
			}
		} else {
			var $deepest = 0
			var $edge = list_at(adjacency.offsets, node)
			edge_end = list_at(adjacency.offsets, node + 1)
			while $edge < edge_end {
				$deepest = U64.max($deepest, list_at($chain, list_at(adjacency.heads, $edge)))
				$edge = $edge + 1
				$visits = $visits + 1
			}
			$deepest
		}
		$chain = list_set($chain, node, value)
		$max_chain = U64.max($max_chain, if is_state value else 0)
		$position = $position + 1
		$visits = $visits + 1
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok({ mask_reachable: $mask_reachable, max_chain: $max_chain, visits: $visits })
	}
}

## Direct-dependency adjacency grouped by source through counting and prefix
## sums: one visit per edge, no per-node allocation beyond the four dense
## buffers.
edge_adjacency : List(KernelResourceGraph.Edge), U64 -> { heads : List(U64), offsets : List(U64) }
edge_adjacency = |edges, node_total| {
	var $counts_per_node = List.repeat(0, node_total)
	var $edge_index = 0
	while $edge_index < edges.len() {
		source = list_at(edges, $edge_index).source
		$counts_per_node = list_set($counts_per_node, source, list_at($counts_per_node, source) + 1)
		$edge_index = $edge_index + 1
	}
	var $offsets = List.with_capacity(node_total + 1)
	var $running = 0
	$offsets = $offsets.append(0)
	var $node_scan = 0
	while $node_scan < node_total {
		$running = $running + list_at($counts_per_node, $node_scan)
		$offsets = $offsets.append($running)
		$node_scan = $node_scan + 1
	}
	var $cursors = List.repeat(0, node_total)
	var $targets = List.repeat(0, edges.len())
	$edge_index = 0
	while $edge_index < edges.len() {
		edge = list_at(edges, $edge_index)
		write = list_at($offsets, edge.source) + list_at($cursors, edge.source)
		$targets = list_set($targets, write, edge.target)
		$cursors = list_set($cursors, edge.source, list_at($cursors, edge.source) + 1)
		$edge_index = $edge_index + 1
	}
	{ heads: $targets, offsets: $offsets }
}

## Marks every form a pattern rendering can execute: the forms a cell places
## directly and, transitively, every form those forms place. Reversed
## topological order visits each dependent before its targets, so one pass
## over the direct-edge adjacency suffices, and a reachable form's direct
## pattern dependency marks the nested-invocation fact the caller rejects.
## Cycles are impossible because the structure run already rejected them.
resolve_pattern_reach : KernelForm.Counts, U64, U64, List(U64), List(KernelResourceGraph.Edge) -> { nested_pattern : List(Bool), reachable : List(Bool), visits : U64 }
resolve_pattern_reach = |counts, form_count, states_count, order, edges| {
	base = form_base(counts)
	patterns_start = pattern_base(counts, form_count, states_count)
	functions_start = function_base(counts, form_count, states_count)
	node_total = node_count(counts, form_count, states_count)
	adjacency = edge_adjacency(edges, node_total)

	var $reachable = List.repeat(Bool.False, form_count)
	var $nested_pattern = List.repeat(Bool.False, form_count)
	var $visits = 0
	var $reversed = order.len()
	while $reversed > 0 {
		$reversed = $reversed - 1
		node = list_at(order, $reversed)
		is_pattern = node >= patterns_start and node < functions_start
		is_reachable_form = node >= base and node < base + form_count and list_at($reachable, node - base)
		if is_pattern or is_reachable_form {
			var $edge = list_at(adjacency.offsets, node)
			edge_end = list_at(adjacency.offsets, node + 1)
			while $edge < edge_end {
				target = list_at(adjacency.heads, $edge)
				if target >= base and target < base + form_count {
					$reachable = list_set($reachable, target - base, Bool.True)
				} else if is_reachable_form and target >= patterns_start and target < functions_start {
					$nested_pattern = list_set($nested_pattern, node - base, Bool.True)
				} else {
					{}
				}
				$edge = $edge + 1
				$visits = $visits + 1
			}
		}
		$visits = $visits + 1
	}
	{ nested_pattern: $nested_pattern, reachable: $reachable, visits: $visits }
}

## One forward-topological sweep folds transitive transparency (dependencies
## first), and one reversed sweep resolves ambient-alpha execution contexts
## (parents first). Ambient context propagates through non-group parents only:
## entering an isolated group resets the ambient constant alpha to the
## identity (ISO 32000-2, 11.6.6), so a group boundary stops the propagation.
resolve_transparency : KernelForm.Counts,
U64,
List(U64),
{
	direct_alpha : List(Bool),
	direct_mask : List(Bool),
	direct_opacity : List(Bool),
	isolated : List(Bool),
	nested_children : List(U64),
	nested_edge_ambient : List(AmbientSite),
	nested_offsets : List(U64),
	page_placements : List({ ambient : Bool, ambient_mask : Bool, form : U64, owner : Scene.GroupOwner, page : U64 }),
} -> Try({ in_ambient : List(Bool), in_mask : List(Bool), transitive : List(Bool), visits : U64 }, KernelForm.Error)
resolve_transparency = |counts, form_count, order, facts| {
	base = form_base(counts)
	var $visits = 0

	var $transitive = List.repeat(Bool.False, form_count)
	var $position = 0
	while $position < order.len() {
		node = list_at(order, $position)
		if node >= base and node < base + form_count {
			form = node - base
			var $carries = list_at(facts.direct_alpha, form) or list_at(facts.direct_opacity, form) or list_at(facts.direct_mask, form)
			var $edge = list_at(facts.nested_offsets, form)
			edge_end = list_at(facts.nested_offsets, form + 1)
			while $edge < edge_end {
				child = list_at(facts.nested_children, $edge)
				if list_at(facts.isolated, child) or list_at($transitive, child) {
					$carries = Bool.True
				}
				$edge = $edge + 1
				$visits = $visits + 1
			}
			$transitive = list_set($transitive, form, $carries)
		}
		$position = $position + 1
	}

	var $in_ambient = List.repeat(Bool.False, form_count)
	var $in_mask = List.repeat(Bool.False, form_count)
	var $placement_index = 0
	while $placement_index < facts.page_placements.len() {
		placement = list_at(facts.page_placements, $placement_index)
		if placement.ambient {
			$in_ambient = list_set($in_ambient, placement.form, Bool.True)
		}
		if placement.ambient_mask {
			$in_mask = list_set($in_mask, placement.form, Bool.True)
		}
		$visits = $visits + 1
		$placement_index = $placement_index + 1
	}

	## Nested ambient facts propagate along the compressed per-edge flags in
	## reversed topological order: parents resolve before the forms they
	## place, one visit per direct edge. Both ambient channels stop at
	## isolated-group boundaries, because a group resets the constant alpha
	## and the soft mask alike.
	var $reversed = order.len()
	while $reversed > 0 {
		$reversed = $reversed - 1
		node = list_at(order, $reversed)
		if node >= base and node < base + form_count {
			parent = node - base
			parent_context = !list_at(facts.isolated, parent) and list_at($in_ambient, parent)
			parent_mask_context = !list_at(facts.isolated, parent) and list_at($in_mask, parent)
			var $edge = list_at(facts.nested_offsets, parent)
			edge_end = list_at(facts.nested_offsets, parent + 1)
			while $edge < edge_end {
				site = list_at(facts.nested_edge_ambient, $edge)
				if site.alpha or parent_context {
					$in_ambient = list_set($in_ambient, list_at(facts.nested_children, $edge), Bool.True)
				}
				if site.mask or parent_mask_context {
					$in_mask = list_set($in_mask, list_at(facts.nested_children, $edge), Bool.True)
				}
				$edge = $edge + 1
				$visits = $visits + 1
			}
		}
	}

	Ok({ in_ambient: $in_ambient, in_mask: $in_mask, transitive: $transitive, visits: $visits })
}

## Walks one validated command range iteratively and accumulates deduplicated
## node uses plus placement/run occurrence lists. The range was validated by
## `KernelScene`, so index arithmetic cannot escape. Opacity groups touch the
## derived graphics-state node the opacity pre-pass assigned to the command;
## opaque groups carry no state and contribute only their children. Shading
## paints and pattern fills touch their paint nodes through the same bases.
collect_range_uses : UseState, Semantics.Range, List(Scene.Command), KernelForm.Counts, TextInput, List(U64), NodeBases -> Try(UseState, KernelForm.Error)
collect_range_uses = |initial, root, arena, counts, text, command_states, bases| {
	var $state = initial
	var $frames = [WalkFrame.{ range: root }]
	var $frame_index = 0
	var $failure = NoFailure
	while $frame_index < $frames.len() and $failure == NoFailure {
		frame = list_at($frames, $frame_index)
		var $command_index = frame.range.start()
		end = frame.range.start() + frame.range.length()
		while $command_index < end and $failure == NoFailure {
			match list_at(arena, $command_index) {
				Clip({ children, path: _ }) | Transform({ children, matrix: _ }) => {
					$frames = $frames.append(WalkFrame.{ range: children })
				}
				Opacity({ children, opacity: _ }) | SoftMask({ children, mask: _ }) => {
					command_state = list_at(command_states, $command_index)
					if command_state != state_sentinel {
						$state = touch($state, bases.state_base + command_state)
					}
					$frames = $frames.append(WalkFrame.{ range: children })
				}
				DrawImage({ image, placement: _ }) => {
					$state = touch($state, image_node(counts, image.index()))
				}
				DrawPath({ path: _, style }) => {
					$state = touch_style($state, style, bases)
				}
				PaintShading({ shading }) => {
					$state = touch($state, bases.shading_base + shading.index())
				}
				DrawText({ paint, run }) => match text {
					NoTextStore => {
						$failure = Failed(MissingTextStore({ command: $command_index }))
					}
					WithTextStore(store) => {
						record = list_at(store.runs, run.index())
						$state = touch($state, font_node(counts, record.instance.index()))
						$state = touch($state, color_node(paint.fill.space.index()))
						$state = match paint.stroke {
							NoStroke => $state
							Stroke({ color, width: _ }) => touch($state, color_node(color.space.index()))
						}
						$state = { ..$state, direct_text: Bool.True, text_runs: $state.text_runs.append(run.index()) }
					}
				}
				PlaceForm({ form, transform: _ }) => {
					$state = touch($state, form_node(counts, form.index()))
					$state = { ..$state, form_occurrences: $state.form_occurrences.append({ command: $command_index, form: form.index() }) }
				}
			}
			$command_index = $command_index + 1
			$state = { ..$state, command_visits: $state.command_visits + 1 }
		}
		$frame_index = $frame_index + 1
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok($state)
	}
}

touch_style : UseState, Scene.PathStyle, NodeBases -> UseState
touch_style = |state, style, bases| {
	with_fill = match style.fill {
		NoFill => state
		PatternFill({ pattern, rule: _ }) => touch(state, bases.pattern_base + pattern.index())
		SolidFill({ color, rule: _ }) => touch(state, color_node(color.space.index()))
	}
	match style.stroke {
		NoStroke => with_fill
		SolidStroke(stroke) => touch(with_fill, color_node(stroke.color.space.index()))
	}
}

touch : UseState, U64 -> UseState
touch = |state, node| {
	if list_at(state.marks, node) != 0 {
		state
	} else {
		{
			..state,
			marks: list_set(state.marks, node, 1),
			touched: state.touched.append(node),
		}
	}
}

structure_input : KernelForm.Counts, U64, List(KernelForm.DerivedState), List(Bool), List(KernelResourceGraph.Edge), U64, List(KernelResourceGraph.RootUse) -> KernelResourceGraph.Input
structure_input = |counts, form_count, states, isolated, edges, root_count, root_uses| {
	nodes = node_count(counts, form_count, states.len())
	var $bytes = List.with_capacity(nodes * 8)
	var $resources = List.with_capacity(nodes)
	var $node = 0
	while $node < nodes {
		start = $bytes.len()
		$bytes = append_u64_bytes($bytes, $node)
		$resources = $resources.append({ descriptor: node_descriptor(counts, form_count, isolated, states, $node), length: 8, start })
		$node = $node + 1
	}
	{
		digest_policy: DomainSeparatedSha256,
		edges,
		payload_bytes: $bytes,
		placements: [],
		resources: $resources,
		root_count,
		root_uses,
	}
}

## An isolated transparency group is a visual fact of the form's identity, so
## it lives in the descriptor flags: two forms with byte-identical recipes and
## different isolation never merge, and existing group-less form identities
## keep their exact digests. Derived graphics states partition by subtype:
## constant-alpha states keep subtype zero (their digests are unchanged) and
## soft-mask states take subtype one, so the two shapes can never share a
## collision bucket.
node_descriptor : KernelForm.Counts, U64, List(Bool), List(KernelForm.DerivedState), U64 -> KernelResourceGraph.Descriptor
node_descriptor = |counts, form_count, isolated, states, node| {
	base = form_base(counts)
	state_end = base + form_count + states.len()
	shadings_end = state_end + counts.shadings
	patterns_end = shadings_end + counts.patterns
	kind = if node < counts.color_spaces {
		ColorSpace
	} else if node < counts.color_spaces + counts.image_color_spaces.len() {
		Image
	} else if node < counts.color_spaces + counts.image_color_spaces.len() + counts.fonts {
		Font
	} else if node < base {
		IccProfile
	} else if node < base + form_count {
		XObject
	} else if node < state_end {
		ExtGState
	} else if node < shadings_end {
		Shading
	} else if node < patterns_end {
		Pattern
	} else {
		Function
	}
	flags = if kind == XObject and list_at(isolated, node - base) 1 else 0
	components = if kind == Shading list_at(counts.shading_components, node - state_end) else 0

	## Shading subtypes carry the PDF shading type (2 axial, 3 radial),
	## function subtypes the PDF function type (2 exponential segment,
	## 3 stitching), and the pattern subtype is the colored tiling paint
	## policy (PaintType 1), so distinct paint shapes can never share a
	## collision bucket.
	subtype = if kind == XObject {
		1
	} else if kind == ExtGState {
		match list_at(states, node - base - form_count) {
			AlphaState(_) => 0
			MaskState(_) => 1
		}
	} else if kind == Shading {
		list_at(counts.shading_subtypes, node - state_end)
	} else if kind == Pattern {
		1
	} else if kind == Function {
		function_index = node - patterns_end
		shading = list_at(counts.function_shadings, function_index)
		segment_start = list_at(counts.shading_function_offsets, shading)
		segment_count = list_at(counts.shading_function_offsets, shading + 1) - segment_start
		if segment_count > 1 and function_index - segment_start == segment_count - 1 3 else 2
	} else {
		0
	}
	{
		bit_depth: 0,
		components,
		flags,
		height: 0,
		kind,
		subtype,
		width: 0,
	}
}

## One reversed-topological sweep resolves instantiation counts and owners:
## parents are processed before the forms they place, so each nested placement
## contributes its parent's already-final count and owner exactly once. The
## per-edge ambient flags are scattered into the same compressed child order
## so the transparency sweep can consume them without a second grouping pass.
resolve_ownership : KernelForm.Counts,
U64,
List(U64),
List({ ambient : Bool, ambient_mask : Bool, form : U64, owner : Scene.GroupOwner, page : U64 }),
List({ ambient : Bool, ambient_mask : Bool, child : U64, parent : U64 }) -> Try(
	{
		instances : List(U64),
		nested_children : List(U64),
		nested_edge_ambient : List(AmbientSite),
		nested_offsets : List(U64),
		owners : List(KernelForm.FormOwner),
		visits : U64,
	},
	KernelForm.Error,
)
resolve_ownership = |counts, form_count, order, page_placements, nested| {
	base = form_base(counts)
	var $instances = List.repeat(0, form_count)
	var $owners = List.repeat(UnplacedOwner, form_count)
	var $visits = 0

	var $placement_index = 0
	while $placement_index < page_placements.len() {
		placement = list_at(page_placements, $placement_index)
		count = list_at($instances, placement.form)
		next = U64.plus_try(count, 1) ? |_| ArithmeticOverflow
		$instances = list_set($instances, placement.form, next)
		owner_fact = match placement.owner {
			Fragment(fragment) => FragmentOwner(fragment)
			PageArtifact(_) => ArtifactOwner
		}
		$owners = list_set($owners, placement.form, merge_owner(list_at($owners, placement.form), owner_fact))
		$visits = $visits + 1
		$placement_index = $placement_index + 1
	}

	## Nested placements grouped by parent through counting and prefix sums.
	var $parent_counts = List.repeat(0, form_count)
	var $nested_index = 0
	while $nested_index < nested.len() {
		parent = list_at(nested, $nested_index).parent
		$parent_counts = list_set($parent_counts, parent, list_at($parent_counts, parent) + 1)
		$nested_index = $nested_index + 1
	}
	var $offsets = List.with_capacity(form_count + 1)
	var $running = 0
	$offsets = $offsets.append(0)
	var $parent = 0
	while $parent < form_count {
		$running = $running + list_at($parent_counts, $parent)
		$offsets = $offsets.append($running)
		$parent = $parent + 1
	}
	var $cursors = List.repeat(0, form_count)
	var $children = List.repeat(0, nested.len())
	var $edge_ambient = List.repeat(AmbientSite.{ alpha: Bool.False, mask: Bool.False }, nested.len())
	$nested_index = 0
	while $nested_index < nested.len() {
		entry = list_at(nested, $nested_index)
		write = list_at($offsets, entry.parent) + list_at($cursors, entry.parent)
		$children = list_set($children, write, entry.child)
		$edge_ambient = list_set($edge_ambient, write, { alpha: entry.ambient, mask: entry.ambient_mask })
		$cursors = list_set($cursors, entry.parent, list_at($cursors, entry.parent) + 1)
		$nested_index = $nested_index + 1
	}

	var $failure = NoFailure
	var $position = order.len()
	while $position > 0 and $failure == NoFailure {
		$position = $position - 1
		node = list_at(order, $position)
		if node >= base and node < base + form_count {
			parent_form = node - base
			parent_instances = list_at($instances, parent_form)
			parent_owner = if parent_instances == 1 list_at($owners, parent_form) else MixedOwner
			var $edge = list_at($offsets, parent_form)
			edge_end = list_at($offsets, parent_form + 1)
			while $edge < edge_end and $failure == NoFailure {
				child = list_at($children, $edge)
				match U64.plus_try(list_at($instances, child), parent_instances) {
					Err(Overflow) => {
						$failure = Failed(ArithmeticOverflow)
					}
					Ok(next) => {
						$instances = list_set($instances, child, next)
						$owners = list_set($owners, child, merge_owner(list_at($owners, child), parent_owner))
					}
				}
				$edge = $edge + 1
				$visits = $visits + 1
			}
		}
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok({ instances: $instances, nested_children: $children, nested_edge_ambient: $edge_ambient, nested_offsets: $offsets, owners: $owners, visits: $visits })
	}
}

merge_owner : KernelForm.FormOwner, KernelForm.FormOwner -> KernelForm.FormOwner
merge_owner = |current, added| match current {
	UnplacedOwner => added
	MixedOwner => MixedOwner
	ArtifactOwner => match added {
		ArtifactOwner => ArtifactOwner
		UnplacedOwner => ArtifactOwner
		_ => MixedOwner
	}
	FragmentOwner(fragment) => match added {
		FragmentOwner(other) => if Semantics.FragmentId.index(fragment) == Semantics.FragmentId.index(other) FragmentOwner(fragment) else MixedOwner
		UnplacedOwner => FragmentOwner(fragment)
		_ => MixedOwner
	}
}

## One forward-topological sweep: dependencies come first in the structure
## order, so each form's transitive text fact folds its children's final facts.
resolve_transitive_text : KernelForm.Counts, U64, List(U64), List(Bool), List(U64), List(U64) -> Try(List(Bool), KernelForm.Error)
resolve_transitive_text = |counts, form_count, order, direct_text, nested_offsets, nested_children| {
	base = form_base(counts)
	var $transitive = List.repeat(Bool.False, form_count)
	var $position = 0
	while $position < order.len() {
		node = list_at(order, $position)
		if node >= base and node < base + form_count {
			form = node - base
			var $has_text = list_at(direct_text, form)
			var $edge = list_at(nested_offsets, form)
			edge_end = list_at(nested_offsets, form + 1)
			while $edge < edge_end {
				if list_at($transitive, list_at(nested_children, $edge)) {
					$has_text = Bool.True
				}
				$edge = $edge + 1
			}
			$transitive = list_set($transitive, form, $has_text)
		}
		$position = $position + 1
	}
	Ok($transitive)
}

TextRecipes := [NoText, WithText(KernelContent.TextPlan)]

## The leaf-recipe kind tags. Descriptor facts already separate resource
## kinds; these bytes separate variants within one kind so, for example, a
## calibrated-gray recipe can never alias an ICCBased recipe.
calibrated_gray_recipe_tag : U8
calibrated_gray_recipe_tag = 1

icc_based_recipe_tag : U8
icc_based_recipe_tag = 2

## The graphics-state recipes. A constant-alpha state serializes tag, `/ca`,
## `/CA`, and the blend mode (only Normal is representable); a soft-mask
## state serializes its own tag, the Alpha mask subtype (the only
## representable subtype — luminosity does not exist in the typed model),
## and the mask form's identity digest.
ext_g_state_recipe_tag : U8
ext_g_state_recipe_tag = 1

blend_normal_tag : U8
blend_normal_tag = 0

mask_state_recipe_tag : U8
mask_state_recipe_tag = 2

alpha_mask_subtype_tag : U8
alpha_mask_subtype_tag = 1

## The paint recipe tags. Descriptor kinds and subtypes already separate
## shadings from functions and axial from radial; these bytes keep each
## recipe self-describing within its kind.
axial_recipe_tag : U8
axial_recipe_tag = 1

radial_recipe_tag : U8
radial_recipe_tag = 2

segment_function_recipe_tag : U8
segment_function_recipe_tag = 1

stitch_function_recipe_tag : U8
stitch_function_recipe_tag = 2

append_channels : List(U8), Color.Channels -> List(U8)
append_channels = |out, channels| match channels {
	Gray(gray) => append_u16_bytes(out.append(1), gray)
	Rgb({ blue, green, red }) => {
		var $out = append_u16_bytes(out.append(3), red)
		$out = append_u16_bytes($out, green)
		append_u16_bytes($out, blue)
	}
}

build_canonical_plan : KernelScene.FormPlan, Scene.ShadingStore, Scene.PatternStore, KernelForm.Facts, KernelForm.Leaves, TextRecipes, KernelTagged.Plan, KernelForm.Limits -> Try(KernelForm.Plan, KernelForm.Error)
build_canonical_plan = |form_plan, shading_store, pattern_store, facts, leaves, text, tagged, limits| {
	counts = facts.counts
	form_store = KernelScene.FormPlan.forms(form_plan)
	scenes = KernelScene.Plan.scenes(KernelScene.FormPlan.page(form_plan))
	form_count = form_store.forms.len()
	base = form_base(counts)
	color_store = KernelColor.Plan.store(leaves.colors)
	image_store = KernelImage.Plan.store(leaves.images)
	image_count = counts.image_color_spaces.len()

	## The stores supplied here must be the stores the facts were derived
	## from; a disagreement is a caller defect surfaced before any identity.
	if color_store.spaces.len() != counts.color_spaces {
		return Err(StoreCountMismatch({ declared: counts.color_spaces, kind: ColorSpaces, supplied: color_store.spaces.len() }))
	}
	if color_store.profiles.len() != counts.profiles {
		return Err(StoreCountMismatch({ declared: counts.profiles, kind: Profiles, supplied: color_store.profiles.len() }))
	}
	if image_store.resources.len() != image_count {
		return Err(StoreCountMismatch({ declared: image_count, kind: Images, supplied: image_store.resources.len() }))
	}
	if shading_store.shadings.len() != counts.shadings {
		return Err(StoreCountMismatch({ declared: counts.shadings, kind: Shadings, supplied: shading_store.shadings.len() }))
	}
	if pattern_store.cells.len() != counts.patterns {
		return Err(StoreCountMismatch({ declared: counts.patterns, kind: Patterns, supplied: pattern_store.cells.len() }))
	}
	if leaves.fonts.len() != counts.fonts {
		return Err(LeafCountMismatch({ declared: counts.fonts, supplied: leaves.fonts.len() }))
	}

	## Payloads and digests in dependency order over one canonical payload
	## allocation: profiles before the color spaces that embed their digests,
	## color spaces before the images that embed theirs, every leaf before
	## the form recipes, segment functions before the stitching functions
	## that embed their digests, and every function and space before the
	## shadings — the topological order over the direct edges guarantees all
	## of it. Graphics-state recipes are leaves with no dependencies, so any
	## position in `facts.order` is dependency-safe.
	states_count = facts.derived_states.len()
	bases = NodeBases.{
		pattern_base: pattern_base(counts, form_count, states_count),
		shading_base: shading_base(counts, form_count, states_count),
		state_base: form_base(counts) + form_count,
	}
	functions_start = function_base(counts, form_count, states_count)
	pattern_command_states = if counts.patterns > 0 List.repeat(state_sentinel, pattern_store.commands.len()) else []
	nodes = node_count(counts, form_count, states_count)
	var $payload = []
	var $sources = List.repeat({ descriptor: node_descriptor(counts, form_count, facts.form_isolated, facts.derived_states, 0), length: 0, start: 0 }, nodes)
	var $digests = List.repeat([], nodes)
	var $image_ranges = List.repeat({ alpha_length: 0, color_length: 0, start: 0 }, image_count)
	var $copied_leaf_bytes = 0
	var $leaf_recipe_bytes = 0
	var $font_recipe_bytes = 0
	var $leaf_digests = 0
	var $recipe_bytes = 0
	var $state_recipe_bytes = 0
	var $shading_recipe_bytes = 0
	var $pattern_recipe_bytes = 0
	var $function_recipe_bytes = 0
	var $form_digests = 0
	var $failure = NoFailure
	var $position = 0
	while $position < facts.order.len() and $failure == NoFailure {
		node = list_at(facts.order, $position)
		start = $payload.len()
		if node < counts.color_spaces {
			record = list_at(color_store.spaces, node)
			recipe = match record.space {
				CalibratedGray({ black_point, white_point }) => {
					var $recipe = [calibrated_gray_recipe_tag]
					$recipe = append_i64_bytes($recipe, white_point.x)
					$recipe = append_i64_bytes($recipe, white_point.y)
					$recipe = append_i64_bytes($recipe, white_point.z)
					$recipe = append_i64_bytes($recipe, black_point.x)
					$recipe = append_i64_bytes($recipe, black_point.y)
					append_i64_bytes($recipe, black_point.z)
				}
				IccBased({ components: _, profile }) => [icc_based_recipe_tag].concat(list_at($digests, profile_node(counts, profile.index())))
				Srgb(profile) => [icc_based_recipe_tag].concat(list_at($digests, profile_node(counts, profile.index())))
			}
			$payload = $payload.concat(recipe)
			$leaf_recipe_bytes = $leaf_recipe_bytes + recipe.len()
			descriptor = {
				bit_depth: 0,
				components: component_rank(KernelColor.Plan.components(leaves.colors, record.id)),
				flags: 0,
				height: 0,
				kind: ColorSpace,
				subtype: 0,
				width: 0,
			}
			$sources = list_set($sources, node, { descriptor, length: $payload.len() - start, start })
			$leaf_digests = $leaf_digests + 1
		} else if node < counts.color_spaces + image_count {
			image_ordinal = node - counts.color_spaces
			resource = list_at(image_store.resources, image_ordinal)
			space_digest = list_at($digests, color_node(list_at(counts.image_color_spaces, image_ordinal)))
			$payload = $payload.concat(space_digest)
			$leaf_recipe_bytes = $leaf_recipe_bytes + space_digest.len()
			plane_start = $payload.len()
			descriptor = match resource.payload {
				Jpeg(jpeg) => {
					$payload = $payload.concat(jpeg.bytes)
					$copied_leaf_bytes = $copied_leaf_bytes + jpeg.bytes.len()
					$image_ranges = list_set($image_ranges, image_ordinal, { alpha_length: 0, color_length: jpeg.bytes.len(), start: plane_start })
					{
						bit_depth: 8,
						components: component_rank(jpeg.components),
						flags: 0,
						height: jpeg.dimensions.height.to_u64(),
						kind: Image,
						subtype: 1,
						width: jpeg.dimensions.width.to_u64(),
					}
				}
				Raster(raster) => {
					components = match raster.format {
						Gray8 => 1
						Rgb8 => 3
					}
					row_bytes = raster.dimensions.width.to_u64() * components
					height = raster.dimensions.height.to_u64()
					$payload = append_compact_rows($payload, raster.pixels, raster.row_stride, row_bytes, height)
					color_length = row_bytes * height
					alpha_length = match raster.alpha {
						NoAlpha => 0
						PackedAlpha(alpha) => {
							$payload = append_compact_rows($payload, alpha.bytes, alpha.row_stride, raster.dimensions.width.to_u64(), height)
							raster.dimensions.width.to_u64() * height
						}
					}
					$copied_leaf_bytes = $copied_leaf_bytes + color_length + alpha_length
					$image_ranges = list_set($image_ranges, image_ordinal, { alpha_length, color_length, start: plane_start })
					{
						bit_depth: 8,
						components,
						flags: if alpha_length > 0 1 else 0,
						height,
						kind: Image,
						subtype: 0,
						width: raster.dimensions.width.to_u64(),
					}
				}
			}
			$sources = list_set($sources, node, { descriptor, length: $payload.len() - start, start })
			$leaf_digests = $leaf_digests + 1
		} else if node < counts.color_spaces + image_count + counts.fonts {

			## A font leaf: the derived canonical bundle recipe from
			## `KernelFontLeaf` — typed emitted facts plus the exact sanitized
			## subset bytes — never the caller's whole font program, which
			## therefore no longer enters the identity arena.
			leaf = list_at(leaves.fonts, node - counts.color_spaces - image_count)
			$payload = $payload.concat(leaf.payload)
			$font_recipe_bytes = $font_recipe_bytes + leaf.payload.len()
			$sources = list_set($sources, node, { descriptor: leaf.descriptor, length: leaf.payload.len(), start })
			$leaf_digests = $leaf_digests + 1
		} else if node < base {
			profile = list_at(color_store.profiles, node - counts.color_spaces - image_count - counts.fonts)
			$payload = $payload.concat(profile.bytes)
			$copied_leaf_bytes = $copied_leaf_bytes + profile.bytes.len()
			descriptor = {
				bit_depth: 0,
				components: component_rank(profile.components),
				flags: 0,
				height: 0,
				kind: IccProfile,
				subtype: match profile.version {
					IccV2 => 2
					IccV4 => 4
				},
				width: 0,
			}
			$sources = list_set($sources, node, { descriptor, length: profile.bytes.len(), start })
			$leaf_digests = $leaf_digests + 1
		} else if node < base + form_count {
			form = list_at(form_store.forms, node - base)
			match serialize_recipe(form, form_store.commands, scenes, $digests, counts, bases, text, facts.form_command_states, facts.derived_states) {
				Err(error) => {
					$failure = Failed(error)
				}
				Ok(recipe) => {
					attempted = U64.plus_try($recipe_bytes, recipe.len()) ? |_| ArithmeticOverflow
					if attempted > limits.max_recipe_bytes {
						$failure = Failed(RecipeByteLimitExceeded({ attempted, limit: limits.max_recipe_bytes }))
					} else {
						$recipe_bytes = attempted
						$payload = $payload.concat(recipe)
						$sources = list_set($sources, node, { descriptor: node_descriptor(counts, form_count, facts.form_isolated, facts.derived_states, node), length: recipe.len(), start })
						$form_digests = $form_digests + 1
					}
				}
			}
		} else if node < bases.shading_base {

			## A graphics-state recipe: every emitted fact of the canonical
			## ExtGState, in fixed order. A constant-alpha state serializes
			## its non-stroking and stroking alphas (equal in this slice) and
			## the Normal blend mode; a soft-mask state serializes its tag,
			## the Alpha mask subtype, and the mask form's identity digest,
			## which is available because the state's direct edge orders the
			## mask form first. Distinct facts therefore never merge and
			## equal facts share one recipe by construction.
			recipe = match list_at(facts.derived_states, node - base - form_count) {
				AlphaState(value) => append_u16_bytes(append_u16_bytes([ext_g_state_recipe_tag], value.to_u16_wrap()), value.to_u16_wrap()).append(blend_normal_tag)
				MaskState(mask_form) => [mask_state_recipe_tag, alpha_mask_subtype_tag].concat(list_at($digests, form_node(counts, mask_form)))
			}
			$payload = $payload.concat(recipe)
			$state_recipe_bytes = $state_recipe_bytes + recipe.len()
			$sources = list_set($sources, node, { descriptor: node_descriptor(counts, form_count, facts.form_isolated, facts.derived_states, node), length: recipe.len(), start })
			$leaf_digests = $leaf_digests + 1
		} else if node < bases.pattern_base {

			## A shading recipe: the shading kind, the exact fixed-point
			## geometry, the extend flags, the color-space identity digest,
			## and the root function's identity digest — which transitively
			## commits every stop position and color. Distinct geometry,
			## stops, extension, or spaces therefore never merge.
			shading = list_at(shading_store.shadings, node - bases.shading_base)
			var $recipe = match shading.geometry {
				Axial({ end, start: axis_start }) => {
					var $axial = [axial_recipe_tag]
					$axial = append_i64_bytes($axial, axis_start.x.raw())
					$axial = append_i64_bytes($axial, axis_start.y.raw())
					$axial = append_i64_bytes($axial, end.x.raw())
					append_i64_bytes($axial, end.y.raw())
				}
				Radial({ end_center, end_radius, start_center, start_radius }) => {
					var $radial = [radial_recipe_tag]
					$radial = append_i64_bytes($radial, start_center.x.raw())
					$radial = append_i64_bytes($radial, start_center.y.raw())
					$radial = append_i64_bytes($radial, start_radius.raw())
					$radial = append_i64_bytes($radial, end_center.x.raw())
					$radial = append_i64_bytes($radial, end_center.y.raw())
					append_i64_bytes($radial, end_radius.raw())
				}
			}
			$recipe = $recipe.append(if shading.extend_start 1 else 0)
			$recipe = $recipe.append(if shading.extend_end 1 else 0)
			$recipe = $recipe.concat(list_at($digests, color_node(shading.space.index())))
			$recipe = $recipe.concat(list_at($digests, functions_start + shading_root_function(counts, node - bases.shading_base)))
			$payload = $payload.concat($recipe)
			$shading_recipe_bytes = $shading_recipe_bytes + $recipe.len()
			$sources = list_set($sources, node, { descriptor: node_descriptor(counts, form_count, facts.form_isolated, facts.derived_states, node), length: $recipe.len(), start })
			$leaf_digests = $leaf_digests + 1
		} else if node < functions_start {

			## A pattern recipe: bounds, steps, matrix, and the canonical
			## cell-command recipe, sharing the form recipe-byte budget.
			cell = list_at(pattern_store.cells, node - bases.pattern_base)
			match serialize_pattern_recipe(cell, pattern_store.commands, scenes, $digests, counts, bases, text, pattern_command_states, facts.derived_states) {
				Err(error) => {
					$failure = Failed(error)
				}
				Ok(recipe) => {
					attempted = U64.plus_try($recipe_bytes, recipe.len()) ? |_| ArithmeticOverflow
					if attempted > limits.max_recipe_bytes {
						$failure = Failed(RecipeByteLimitExceeded({ attempted, limit: limits.max_recipe_bytes }))
					} else {
						$recipe_bytes = attempted
						$pattern_recipe_bytes = $pattern_recipe_bytes + recipe.len()
						$payload = $payload.concat(recipe)
						$sources = list_set($sources, node, { descriptor: node_descriptor(counts, form_count, facts.form_isolated, facts.derived_states, node), length: recipe.len(), start })
						$form_digests = $form_digests + 1
					}
				}
			}
		} else {

			## A function recipe: a segment function serializes its channel
			## arity and the two adjacent stop colors it interpolates (the
			## domain, encode, and exponent are constants of the emission
			## site); a stitching function serializes its segment digests
			## and the exact interior stop offsets that become its bounds.
			function_index = node - functions_start
			function_shading = list_at(counts.function_shadings, function_index)
			shading = list_at(shading_store.shadings, function_shading)
			segment_start = list_at(counts.shading_function_offsets, function_shading)
			segment_count = list_at(counts.shading_function_offsets, function_shading + 1) - segment_start
			within = function_index - segment_start
			recipe = if segment_count > 1 and within == segment_count - 1 {
				var $stitch = [stitch_function_recipe_tag]
				$stitch = append_u64_bytes($stitch, segment_count - 1)
				var $child = 0
				while $child < segment_count - 1 {
					$stitch = $stitch.concat(list_at($digests, functions_start + segment_start + $child))
					$child = $child + 1
				}
				var $bound = 1
				while $bound < shading.stops.length() - 1 {
					$stitch = append_u16_bytes($stitch, list_at(shading_store.stops, shading.stops.start() + $bound).offset)
					$bound = $bound + 1
				}
				$stitch
			} else {
				first = list_at(shading_store.stops, shading.stops.start() + within)
				second = list_at(shading_store.stops, shading.stops.start() + within + 1)
				var $segment = [segment_function_recipe_tag]
				$segment = append_channels($segment, first.channels)
				append_channels($segment, second.channels)
			}
			$payload = $payload.concat(recipe)
			$function_recipe_bytes = $function_recipe_bytes + recipe.len()
			$sources = list_set($sources, node, { descriptor: node_descriptor(counts, form_count, facts.form_isolated, facts.derived_states, node), length: recipe.len(), start })
			$leaf_digests = $leaf_digests + 1
		}
		if $failure == NoFailure {
			source = list_at($sources, node)
			match KernelResourceGraph.identity_digest(source, $payload) {
				Err(error) => {
					$failure = Failed(Graph(error))
				}
				Ok(digest) => {
					$digests = list_set($digests, node, digest)
				}
			}
		}
		$position = $position + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Placement-site ownership facts: page-level placements inherit their
	## group owner; artifact placements stay reusable, semantic placements are
	## placement-specific by construction.
	marked = KernelTagged.Plan.marked_fragments(tagged)
	var $placements = List.with_capacity(facts.page_placements.len())
	var $placement_index = 0
	while $placement_index < facts.page_placements.len() {
		placement = list_at(facts.page_placements, $placement_index)
		graph_placement = match placement.owner {
			Fragment(fragment) => {
				reference = list_at(marked, Semantics.FragmentId.index(fragment))
				{
					ownership: Semantic({ fragment, mcid: reference.mcid }),
					resource: form_node(counts, placement.form),
					reuse: PlacementSpecific,
				}
			}
			PageArtifact(kind) => {
				ownership: Artifact(kind),
				resource: form_node(counts, placement.form),
				reuse: Reusable,
			}
		}
		$placements = $placements.append(graph_placement)
		$placement_index = $placement_index + 1
	}

	## The exact per-page transparency-group blending uses: closure-only, so
	## the blending space stays reachable without a dictionary entry.
	var $closure_uses = []
	var $appearance_closure = 0
	while $appearance_closure < facts.appearance_uses.len() {
		use = list_at(facts.appearance_uses, $appearance_closure)
		$closure_uses = $closure_uses.append({ resource: form_node(counts, use.form), root: use.page })
		$appearance_closure = $appearance_closure + 1
	}
	match facts.blending {
		NoBlending => {}
		Blending(space) => {
			var $closure_page = 0
			while $closure_page < facts.page_transparency.len() {
				if list_at(facts.page_transparency, $closure_page) {
					$closure_uses = $closure_uses.append({ resource: color_node(space), root: $closure_page })
				}
				$closure_page = $closure_page + 1
			}
		}
	}

	graph = KernelResourceGraph.Plan.build_with_closure_uses(
		{
			digest_policy: DomainSeparatedSha256,
			edges: facts.edges,
			payload_bytes: $payload,
			placements: $placements,
			resources: $sources,
			root_count: scenes.pages.len(),
			root_uses: facts.root_uses,
		},
		$closure_uses,
		limits.graph,
	) ? Graph

	nodes_of = node_count(counts, form_count, states_count)
	var $canonical_of = List.with_capacity(nodes_of)
	var $node = 0
	while $node < nodes_of {
		$canonical_of = $canonical_of.append(KernelResourceGraph.Plan.canonical_index(graph, $node))
		$node = $node + 1
	}
	canonical_of = $canonical_of
	canonical_count = KernelResourceGraph.Plan.resource_count(graph)

	## Canonical per-kind ordinals in canonical-ID order — the documented
	## total order for physical leaf, graphics-state, and form objects.
	var $kinds = List.repeat({ kind: 0, ordinal: 0 }, canonical_count)
	var $color_reps = []
	var $font_reps = []
	var $image_reps = []
	var $profile_reps = []
	var $state_count = 0
	var $form_ordinals = List.repeat(U64.highest, canonical_count)
	var $ordinal_canonicals = []
	var $canonical_forms = []
	var $shading_reps = []
	var $pattern_ordinal_canonicals = []
	var $canonical_pattern_cells = []
	var $function_reps = []
	var $canonical_id = 0
	while $canonical_id < canonical_count {
		descriptor = KernelResourceGraph.Plan.descriptor(graph, $canonical_id)
		match descriptor.kind {
			ColorSpace => {
				$kinds = list_set($kinds, $canonical_id, { kind: kind_color, ordinal: $color_reps.len() })
				$color_reps = $color_reps.append(U64.highest)
			}
			ExtGState => {
				$kinds = list_set($kinds, $canonical_id, { kind: kind_state, ordinal: $state_count })
				$state_count = $state_count + 1
			}
			Font => {
				$kinds = list_set($kinds, $canonical_id, { kind: kind_font, ordinal: $font_reps.len() })
				$font_reps = $font_reps.append(U64.highest)
			}
			Function => {
				$kinds = list_set($kinds, $canonical_id, { kind: kind_function, ordinal: $function_reps.len() })
				$function_reps = $function_reps.append(U64.highest)
			}
			Image => {
				$kinds = list_set($kinds, $canonical_id, { kind: kind_image, ordinal: $image_reps.len() })
				$image_reps = $image_reps.append(U64.highest)
			}
			IccProfile => {
				$kinds = list_set($kinds, $canonical_id, { kind: kind_profile, ordinal: $profile_reps.len() })
				$profile_reps = $profile_reps.append(U64.highest)
			}
			Pattern => {
				$kinds = list_set($kinds, $canonical_id, { kind: kind_pattern, ordinal: $canonical_pattern_cells.len() })
				$pattern_ordinal_canonicals = $pattern_ordinal_canonicals.append($canonical_id)
				$canonical_pattern_cells = $canonical_pattern_cells.append({ bbox: zero_rect, commands: Semantics.Range.from_start_and_length(0, 0), matrix: identity_matrix, representative: U64.highest, x_step: Layout.Unit.from_raw(0), y_step: Layout.Unit.from_raw(0) })
			}
			Shading => {
				$kinds = list_set($kinds, $canonical_id, { kind: kind_shading, ordinal: $shading_reps.len() })
				$shading_reps = $shading_reps.append(U64.highest)
			}
			XObject => {
				$form_ordinals = list_set($form_ordinals, $canonical_id, $canonical_forms.len())
				$kinds = list_set($kinds, $canonical_id, { kind: kind_form, ordinal: $canonical_forms.len() })
				$ordinal_canonicals = $ordinal_canonicals.append($canonical_id)
				$canonical_forms = $canonical_forms.append({ bbox: zero_rect, commands: Semantics.Range.from_start_and_length(0, 0), representative: U64.highest })
			}
		}
		$canonical_id = $canonical_id + 1
	}

	## Authored-to-canonical name maps plus the lowest authored
	## representative per canonical leaf, whose validated store record lowers
	## once at emission.
	var $color_names = List.repeat(0, counts.color_spaces)
	var $space = 0
	while $space < counts.color_spaces {
		ordinal = list_at($kinds, list_at(canonical_of, color_node($space))).ordinal
		$color_names = list_set($color_names, $space, ordinal)
		if list_at($color_reps, ordinal) == U64.highest {
			$color_reps = list_set($color_reps, ordinal, $space)
		}
		$space = $space + 1
	}
	var $image_names = List.repeat(0, image_count)
	var $canonical_image_ranges = List.repeat({ alpha_length: 0, color_length: 0, start: 0 }, $image_reps.len())
	var $image = 0
	while $image < image_count {
		ordinal = list_at($kinds, list_at(canonical_of, image_node(counts, $image))).ordinal
		$image_names = list_set($image_names, $image, ordinal)
		if list_at($image_reps, ordinal) == U64.highest {
			$image_reps = list_set($image_reps, ordinal, $image)
			$canonical_image_ranges = list_set($canonical_image_ranges, ordinal, list_at($image_ranges, $image))
		}
		$image = $image + 1
	}
	var $profile_names = List.repeat(0, counts.profiles)
	var $profile = 0
	while $profile < counts.profiles {
		ordinal = list_at($kinds, list_at(canonical_of, profile_node(counts, $profile))).ordinal
		$profile_names = list_set($profile_names, $profile, ordinal)
		if list_at($profile_reps, ordinal) == U64.highest {
			$profile_reps = list_set($profile_reps, ordinal, $profile)
		}
		$profile = $profile + 1
	}
	var $font_names = List.repeat(0, counts.fonts)
	var $font = 0
	while $font < counts.fonts {
		ordinal = list_at($kinds, list_at(canonical_of, font_node(counts, $font))).ordinal
		$font_names = list_set($font_names, $font, ordinal)
		if list_at($font_reps, ordinal) == U64.highest {
			$font_reps = list_set($font_reps, ordinal, $font)
		}
		$font = $font + 1
	}

	## Canonical forms in canonical-ID order; each keeps its lowest authored
	## form as the representative whose validated command range lowers once.
	## Isolation is a descriptor fact, so every authored twin of one canonical
	## form shares the representative's flag by construction.
	var $form_names = List.repeat(0, form_count)
	var $form_isolation = List.repeat(Bool.False, $canonical_forms.len())
	var $form_index = 0
	while $form_index < form_count {
		canonical = list_at(canonical_of, form_node(counts, $form_index))
		ordinal = list_at($form_ordinals, canonical)
		$form_names = list_set($form_names, $form_index, ordinal)
		existing = list_at($canonical_forms, ordinal)
		if existing.representative == U64.highest {
			form = list_at(form_store.forms, $form_index)
			$canonical_forms = list_set($canonical_forms, ordinal, { bbox: form.bbox, commands: form.commands, representative: $form_index })
			$form_isolation = list_set($form_isolation, ordinal, list_at(facts.form_isolated, $form_index))
		}
		$form_index = $form_index + 1
	}

	## Canonical shadings, patterns, and functions in canonical-ID order,
	## each keeping its lowest authored representative; the emitted facts
	## resolve through the name maps below once every map exists.
	var $shading_names = List.repeat(0, counts.shadings)
	var $shading_index = 0
	while $shading_index < counts.shadings {
		ordinal = list_at($kinds, list_at(canonical_of, shading_node(counts, form_count, states_count, $shading_index))).ordinal
		$shading_names = list_set($shading_names, $shading_index, ordinal)
		if list_at($shading_reps, ordinal) == U64.highest {
			$shading_reps = list_set($shading_reps, ordinal, $shading_index)
		}
		$shading_index = $shading_index + 1
	}
	var $pattern_names = List.repeat(0, counts.patterns)
	var $pattern_index = 0
	while $pattern_index < counts.patterns {
		canonical = list_at(canonical_of, pattern_node(counts, form_count, states_count, $pattern_index))
		ordinal = list_at($kinds, canonical).ordinal
		$pattern_names = list_set($pattern_names, $pattern_index, ordinal)
		existing_cell = list_at($canonical_pattern_cells, ordinal)
		if existing_cell.representative == U64.highest {
			cell = list_at(pattern_store.cells, $pattern_index)
			$canonical_pattern_cells = list_set($canonical_pattern_cells, ordinal, { bbox: cell.bbox, commands: cell.commands, matrix: cell.matrix, representative: $pattern_index, x_step: cell.x_step, y_step: cell.y_step })
		}
		$pattern_index = $pattern_index + 1
	}
	total_functions = function_total(counts)
	var $function_names = List.repeat(0, total_functions)
	var $function_index = 0
	while $function_index < total_functions {
		ordinal = list_at($kinds, list_at(canonical_of, functions_start + $function_index)).ordinal
		$function_names = list_set($function_names, $function_index, ordinal)
		if list_at($function_reps, ordinal) == U64.highest {
			$function_reps = list_set($function_reps, ordinal, $function_index)
		}
		$function_index = $function_index + 1
	}

	## The emitted facts: each canonical shading resolves its space and root
	## function through the canonical maps; each canonical function resolves
	## its representative's segment stops, and a stitching function the
	## canonical ordinals of its representative shading's segments.
	var $shading_facts = List.repeat({ extend_end: Bool.False, extend_start: Bool.False, function: 0, geometry: Axial({ end: { x: Layout.Unit.from_raw(0), y: Layout.Unit.from_raw(0) }, start: { x: Layout.Unit.from_raw(0), y: Layout.Unit.from_raw(0) } }), representative: 0, space: 0 }, $shading_reps.len())
	var $shading_ordinal = 0
	while $shading_ordinal < $shading_reps.len() {
		representative = list_at($shading_reps, $shading_ordinal)
		shading = list_at(shading_store.shadings, representative)
		$shading_facts = list_set(
			$shading_facts,
			$shading_ordinal,
			{
				extend_end: shading.extend_end,
				extend_start: shading.extend_start,
				function: list_at($function_names, shading_root_function(counts, representative)),
				geometry: shading.geometry,
				representative,
				space: list_at($color_names, shading.space.index()),
			},
		)
		$shading_ordinal = $shading_ordinal + 1
	}
	var $function_facts = List.repeat(SegmentFact({ segment: 0, shading: 0 }), $function_reps.len())
	var $function_ordinal = 0
	while $function_ordinal < $function_reps.len() {
		representative = list_at($function_reps, $function_ordinal)
		function_shading = list_at(counts.function_shadings, representative)
		segment_start = list_at(counts.shading_function_offsets, function_shading)
		segment_count = list_at(counts.shading_function_offsets, function_shading + 1) - segment_start
		within = representative - segment_start
		fact = if segment_count > 1 and within == segment_count - 1 {
			var $children = List.with_capacity(segment_count - 1)
			var $child = 0
			while $child < segment_count - 1 {
				$children = $children.append(list_at($function_names, segment_start + $child))
				$child = $child + 1
			}
			StitchFact({ children: $children, shading: function_shading })
		} else {
			SegmentFact({ segment: within, shading: function_shading })
		}
		$function_facts = list_set($function_facts, $function_ordinal, fact)
		$function_ordinal = $function_ordinal + 1
	}

	## Alpha states pre-deduplicate by exact value during derivation, and
	## mask states by authored mask form; the canonical run additionally
	## merges mask states whose mask forms deduplicated. Each canonical
	## state ordinal records the emitted fact — the exact alpha, or the
	## canonical mask form ordinal resolved through the form name map.
	var $state_names = List.repeat(0, states_count)
	var $state_facts = List.repeat(Alpha(0), $state_count)
	var $canonical_mask_states = List.repeat(Bool.False, $state_count)
	var $state_index = 0
	while $state_index < states_count {
		ordinal = list_at($kinds, list_at(canonical_of, state_node(counts, form_count, $state_index))).ordinal
		$state_names = list_set($state_names, $state_index, ordinal)
		fact = match list_at(facts.derived_states, $state_index) {
			AlphaState(value) => Alpha(value)
			MaskState(mask_form) => Mask(list_at($form_names, mask_form))
		}
		$state_facts = list_set($state_facts, ordinal, fact)
		$canonical_mask_states = list_set(
			$canonical_mask_states,
			ordinal,
			match fact {
				Alpha(_) => Bool.False
				Mask(_) => Bool.True
			},
		)
		$state_index = $state_index + 1
	}
	var $canonical_mask_count = 0
	var $mask_flag_scan = 0
	while $mask_flag_scan < $canonical_mask_states.len() {
		if list_at($canonical_mask_states, $mask_flag_scan) {
			$canonical_mask_count = $canonical_mask_count + 1
		}
		$mask_flag_scan = $mask_flag_scan + 1
	}
	canonical_mask_state_count = $canonical_mask_count

	## Dense per-command canonical graphics-state ordinals for content
	## lowering: the value index the opacity pre-pass assigned, mapped through
	## the canonical ordinal.
	var $page_command_gs = List.repeat(state_sentinel, facts.page_command_states.len())
	var $page_command = 0
	while $page_command < facts.page_command_states.len() {
		command_state = list_at(facts.page_command_states, $page_command)
		if command_state != state_sentinel {
			$page_command_gs = list_set($page_command_gs, $page_command, list_at($state_names, command_state))
		}
		$page_command = $page_command + 1
	}
	var $form_command_gs = List.repeat(state_sentinel, facts.form_command_states.len())
	var $form_command = 0
	while $form_command < facts.form_command_states.len() {
		command_state = list_at(facts.form_command_states, $form_command)
		if command_state != state_sentinel {
			$form_command_gs = list_set($form_command_gs, $form_command, list_at($state_names, command_state))
		}
		$form_command = $form_command + 1
	}

	## Exact direct dictionaries per stream, partitioned by kind with keys in
	## ascending canonical-ordinal (and therefore canonical byte) order.
	var $page_dictionaries = List.with_capacity(scenes.pages.len())
	var $dictionary_entries = 0
	var $page = 0
	while $page < scenes.pages.len() {
		dictionary = partition_dictionary(KernelResourceGraph.Plan.root_dictionary(graph, $page), $kinds)
		$dictionary_entries = $dictionary_entries + dictionary_size(dictionary)
		$page_dictionaries = $page_dictionaries.append(dictionary)
		$page = $page + 1
	}
	var $form_dictionaries = List.with_capacity($canonical_forms.len())
	var $nested_dictionary_entries = 0
	var $ordinal = 0
	while $ordinal < $canonical_forms.len() {
		dictionary = partition_dictionary(KernelResourceGraph.Plan.direct_dependencies(graph, list_at($ordinal_canonicals, $ordinal)), $kinds)
		$nested_dictionary_entries = $nested_dictionary_entries + dictionary_size(dictionary)
		$form_dictionaries = $form_dictionaries.append(dictionary)
		$ordinal = $ordinal + 1
	}

	## Each pattern stream receives exactly its direct nested resource
	## dictionary from the same normalized facts.
	var $pattern_dictionaries = List.with_capacity($canonical_pattern_cells.len())
	var $pattern_dictionary_entries = 0
	var $pattern_ordinal = 0
	while $pattern_ordinal < $canonical_pattern_cells.len() {
		dictionary = partition_dictionary(KernelResourceGraph.Plan.direct_dependencies(graph, list_at($pattern_ordinal_canonicals, $pattern_ordinal)), $kinds)
		$pattern_dictionary_entries = $pattern_dictionary_entries + dictionary_size(dictionary)
		$pattern_dictionaries = $pattern_dictionaries.append(dictionary)
		$pattern_ordinal = $pattern_ordinal + 1
	}

	## Sharing evidence: placements grouped per canonical form.
	var $semantic_placements = 0
	var $artifact_placements = 0
	var $artifact_counts = List.repeat(0, $canonical_forms.len())
	var $semantic_counts = List.repeat(0, $canonical_forms.len())
	graph_placements = KernelResourceGraph.Plan.placements(graph)
	$placement_index = 0
	while $placement_index < graph_placements.len() {
		placement = list_at(graph_placements, $placement_index)
		ordinal = list_at($form_ordinals, placement.resource)
		match placement.ownership {
			Artifact(_) => {
				$artifact_placements = $artifact_placements + 1
				$artifact_counts = list_set($artifact_counts, ordinal, list_at($artifact_counts, ordinal) + 1)
			}
			Semantic(_) => {
				$semantic_placements = $semantic_placements + 1
				$semantic_counts = list_set($semantic_counts, ordinal, list_at($semantic_counts, ordinal) + 1)
			}
		}
		$placement_index = $placement_index + 1
	}
	var $shared_artifact_forms = 0
	$ordinal = 0
	while $ordinal < $canonical_forms.len() {
		if list_at($artifact_counts, $ordinal) > 1 and list_at($semantic_counts, $ordinal) == 0 {
			$shared_artifact_forms = $shared_artifact_forms + 1
		}
		$ordinal = $ordinal + 1
	}

	nested_form_edges = count_nested_form_edges(facts.edges, base)
	deduplicated_forms = form_count - $canonical_forms.len()

	blending_ordinal = match facts.blending {
		NoBlending => NoBlending
		Blending(space) => Blending(list_at($color_names, space))
	}
	var $transparency_pages = 0
	var $transparency_scan = 0
	while $transparency_scan < facts.page_transparency.len() {
		if list_at(facts.page_transparency, $transparency_scan) {
			$transparency_pages = $transparency_pages + 1
		}
		$transparency_scan = $transparency_scan + 1
	}
	var $isolated_canonical = 0
	var $isolation_scan = 0
	while $isolation_scan < $form_isolation.len() {
		if list_at($form_isolation, $isolation_scan) {
			$isolated_canonical = $isolated_canonical + 1
		}
		$isolation_scan = $isolation_scan + 1
	}

	Ok(
		KernelForm.Plan.{
			blending: blending_ordinal,
			canonical_colors: $color_reps,
			canonical_fonts: $font_reps,
			canonical_forms: $canonical_forms,
			canonical_function_facts: $function_facts,
			canonical_images: $image_reps,
			canonical_pattern_cells: $canonical_pattern_cells,
			canonical_profiles: $profile_reps,
			canonical_shading_facts: $shading_facts,
			color_names: $color_names,
			font_names: $font_names,
			form_command_gs: $form_command_gs,
			form_dictionaries: $form_dictionaries,
			form_isolation: $form_isolation,
			form_names: $form_names,
			graph,
			image_names: $image_names,
			image_ranges: $canonical_image_ranges,
			page_command_gs: $page_command_gs,
			page_dictionaries: $page_dictionaries,
			page_transparency: facts.page_transparency,
			pattern_dictionaries: $pattern_dictionaries,
			pattern_names: $pattern_names,
			placements: graph_placements,
			profile_names: $profile_names,
			shading_names: $shading_names,
			state_facts: $state_facts,
			work: {
				artifact_placements: $artifact_placements,
				authored_color_spaces: counts.color_spaces,
				authored_fonts: counts.fonts,
				authored_forms: form_count,
				authored_images: image_count,
				authored_profiles: counts.profiles,
				canonical_color_spaces: $color_reps.len(),
				canonical_ext_g_states: $state_facts.len(),
				canonical_fonts: $font_reps.len(),
				canonical_mask_states: canonical_mask_state_count,
				canonical_forms: $canonical_forms.len(),
				canonical_images: $image_reps.len(),
				canonical_profiles: $profile_reps.len(),
				copied_leaf_bytes: $copied_leaf_bytes,
				deduplicated_color_spaces: counts.color_spaces - $color_reps.len(),
				deduplicated_fonts: counts.fonts - $font_reps.len(),
				deduplicated_forms,
				deduplicated_images: image_count - $image_reps.len(),

				deduplicated_mask_states: facts.work.mask_states - canonical_mask_state_count,

				## Every non-opaque opacity command beyond its value's first
				## occurrence shares that value's one canonical alpha state.
				deduplicated_opacity_groups: facts.work.opacity_groups - ($state_facts.len() - canonical_mask_state_count),
				deduplicated_profiles: counts.profiles - $profile_reps.len(),
				dictionary_entries: $dictionary_entries,
				font_recipe_bytes: $font_recipe_bytes,
				form_digests: $form_digests,
				isolated_canonical_forms: $isolated_canonical,
				leaf_digests: $leaf_digests,
				leaf_recipe_bytes: $leaf_recipe_bytes,
				nested_dictionary_entries: $nested_dictionary_entries,
				nested_form_edges,
				recipe_bytes: $recipe_bytes,
				semantic_placements: $semantic_placements,

				## Placement-site tagging keeps every physical form
				## ownership-neutral, so no semantic placement forces a copy;
				## the counter exists so a future in-form structure capability
				## must surface its duplication explicitly.
				semantically_duplicated_forms: 0,
				shared_artifact_forms: $shared_artifact_forms,
				state_recipe_bytes: $state_recipe_bytes,
				transparency_pages: $transparency_pages,

				authored_functions: total_functions,
				authored_patterns: counts.patterns,
				authored_shadings: counts.shadings,
				canonical_functions: $function_facts.len(),
				canonical_patterns: $canonical_pattern_cells.len(),
				canonical_shadings: $shading_facts.len(),
				deduplicated_functions: total_functions - $function_facts.len(),
				deduplicated_patterns: counts.patterns - $canonical_pattern_cells.len(),
				deduplicated_shadings: counts.shadings - $shading_facts.len(),
				function_recipe_bytes: $function_recipe_bytes,
				pattern_dictionary_entries: $pattern_dictionary_entries,
				pattern_recipe_bytes: $pattern_recipe_bytes,
				shading_recipe_bytes: $shading_recipe_bytes,
			},
		},
	)
}

component_rank : Color.ComponentCount -> U64
component_rank = |components| match components {
	One => 1
	Three => 3
}

## Row-compacted canonical plane bytes: padding never reaches identity or
## emission, so a padded raster and its compact twin share one canonical
## payload.
append_compact_rows : List(U8), List(U8), U64, U64, U64 -> List(U8)
append_compact_rows = |output, source, stride, row_bytes, height| {
	var $output = output.reserve(row_bytes * height)
	var $row = 0
	while $row < height {
		start = $row * stride
		var $column = 0
		while $column < row_bytes {
			$output = $output.append(list_at(source, start + $column))
			$column = $column + 1
		}
		$row = $row + 1
	}
	$output
}

zero_rect : Layout.Rect
zero_rect = { origin: { x: Layout.Unit.from_raw(0), y: Layout.Unit.from_raw(0) }, size: { height: Layout.Unit.from_raw(0), width: Layout.Unit.from_raw(0) } }

kind_color : U64
kind_color = 0

kind_image : U64
kind_image = 1

kind_font : U64
kind_font = 2

kind_form : U64
kind_form = 3

kind_profile : U64
kind_profile = 4

kind_state : U64
kind_state = 5

kind_shading : U64
kind_shading = 6

kind_pattern : U64
kind_pattern = 7

kind_function : U64
kind_function = 8

identity_matrix : Scene.Matrix
identity_matrix = { a: Layout.Unit.from_raw(1000), b: Layout.Unit.from_raw(0), c: Layout.Unit.from_raw(0), d: Layout.Unit.from_raw(1000), e: Layout.Unit.from_raw(0), f: Layout.Unit.from_raw(0) }

partition_dictionary : List(U64), List({ kind : U64, ordinal : U64 }) -> KernelForm.DictionaryPlan
partition_dictionary = |canonical_ids, kinds| {
	var $color_spaces = []
	var $ext_g_states = []
	var $fonts = []
	var $forms = []
	var $functions = []
	var $images = []
	var $patterns = []
	var $profiles = []
	var $shadings = []
	var $index = 0
	while $index < canonical_ids.len() {
		entry = list_at(kinds, list_at(canonical_ids, $index))
		if entry.kind == kind_color {
			$color_spaces = insert_sorted($color_spaces, entry.ordinal)
		} else if entry.kind == kind_image {
			$images = insert_sorted($images, entry.ordinal)
		} else if entry.kind == kind_font {
			$fonts = insert_sorted($fonts, entry.ordinal)
		} else if entry.kind == kind_profile {
			$profiles = insert_sorted($profiles, entry.ordinal)
		} else if entry.kind == kind_state {
			$ext_g_states = insert_sorted($ext_g_states, entry.ordinal)
		} else if entry.kind == kind_shading {
			$shadings = insert_sorted($shadings, entry.ordinal)
		} else if entry.kind == kind_pattern {
			$patterns = insert_sorted($patterns, entry.ordinal)
		} else if entry.kind == kind_function {
			$functions = insert_sorted($functions, entry.ordinal)
		} else {
			$forms = insert_sorted($forms, entry.ordinal)
		}
		$index = $index + 1
	}
	{ color_spaces: $color_spaces, ext_g_states: $ext_g_states, fonts: $fonts, forms: $forms, functions: $functions, images: $images, patterns: $patterns, profiles: $profiles, shadings: $shadings }
}

## Deterministic insertion into ascending order; dictionary fan-out is bounded
## by a stream's direct dependencies, so the quadratic worst case is bounded by
## direct-edge counts, not the whole graph.
insert_sorted : List(U64), U64 -> List(U64)
insert_sorted = |values, value| {
	var $position = 0
	while $position < values.len() and list_at(values, $position) < value {
		$position = $position + 1
	}
	var $out = List.with_capacity(values.len() + 1)
	var $index = 0
	while $index < $position {
		$out = $out.append(list_at(values, $index))
		$index = $index + 1
	}
	$out = $out.append(value)
	while $index < values.len() {
		$out = $out.append(list_at(values, $index))
		$index = $index + 1
	}
	$out
}

dictionary_size : KernelForm.DictionaryPlan -> U64
dictionary_size = |dictionary| dictionary.color_spaces.len() + dictionary.ext_g_states.len() + dictionary.fonts.len() + dictionary.forms.len() + dictionary.functions.len() + dictionary.images.len() + dictionary.patterns.len() + dictionary.profiles.len() + dictionary.shadings.len()

count_nested_form_edges : List(KernelResourceGraph.Edge), U64 -> U64
count_nested_form_edges = |edges, base| {
	var $count = 0
	var $index = 0
	while $index < edges.len() {
		edge = list_at(edges, $index)
		if edge.source >= base and edge.target >= base {
			$count = $count + 1
		}
		$index = $index + 1
	}
	$count
}

## Canonical recipe serialization. Geometry, styles, and dash values are
## inlined from the shared stores; nested references become the referenced
## resource's identity digest; text commands embed the referenced font
## leaf's identity digest, the exact size, and the prepared run bytes.
## Opacity groups serialize in normalized lowered form: an opaque group is
## transparent to the recipe (its children serialize inline, exactly as its
## stream emits no operators), and a non-opaque group serializes its
## effective alpha, so the recipe stays bijective with the emitted stream
## structure and visually distinct nestings never merge.
serialize_recipe : Scene.Form, List(Scene.Command), Scene.Store, List(List(U8)), KernelForm.Counts, NodeBases, TextRecipes, List(U64), List(KernelForm.DerivedState) -> Try(List(U8), KernelForm.Error)
serialize_recipe = |form, arena, scenes, digests, counts, bases, text, command_states, derived_states| {
	initial = append_rect(List.with_capacity(64), form.bbox)
	serialize_range(initial, MissingTextPlan({ form: Scene.FormId.index(form.id) }), form.commands, arena, scenes, digests, counts, bases, text, command_states, derived_states)
}

## A pattern recipe contains every emitted or visually significant cell
## fact: the bounding box, the tile steps, the pattern-to-target-space
## matrix, and the canonical cell-command recipe with every nested
## reference replaced by the referenced resource's identity digest.
serialize_pattern_recipe : Scene.PatternCell, List(Scene.Command), Scene.Store, List(List(U8)), KernelForm.Counts, NodeBases, TextRecipes, List(U64), List(KernelForm.DerivedState) -> Try(List(U8), KernelForm.Error)
serialize_pattern_recipe = |cell, arena, scenes, digests, counts, bases, text, command_states, derived_states| {
	var $initial = append_rect(List.with_capacity(96), cell.bbox)
	$initial = append_i64_bytes($initial, cell.x_step.raw())
	$initial = append_i64_bytes($initial, cell.y_step.raw())
	$initial = append_matrix($initial, cell.matrix)
	serialize_range($initial, MissingTextPlan({ form: Scene.PatternId.index(cell.id) }), cell.commands, arena, scenes, digests, counts, bases, text, command_states, derived_states)
}

serialize_range : List(U8), KernelForm.Error, Semantics.Range, List(Scene.Command), Scene.Store, List(List(U8)), KernelForm.Counts, NodeBases, TextRecipes, List(U64), List(KernelForm.DerivedState) -> Try(List(U8), KernelForm.Error)
serialize_range = |initial, missing_text, root, arena, scenes, digests, counts, bases, text, command_states, derived_states| {
	var $out = initial
	var $frames = []
	var $active = 0
	var $current = RecipeFrame.{ close: Bool.False, end: root.start() + root.length(), next: root.start() }
	var $done = Bool.False
	var $failure = NoFailure
	while !$done and $failure == NoFailure {
		if $current.next >= $current.end {
			if $current.close {
				$out = $out.append(2)
			}
			if $active == 0 {
				$done = Bool.True
			} else {
				$active = $active - 1
				$current = list_at($frames, $active)
			}
		} else {
			command_index = $current.next
			$current = { ..$current, next: $current.next + 1 }
			match list_at(arena, command_index) {
				Clip({ children, path }) => {
					$out = append_path($out.append(1), path, scenes)
					$frames = push_recipe_frame($frames, $active, $current)
					$active = $active + 1
					$current = RecipeFrame.{ close: Bool.True, end: children.start() + children.length(), next: children.start() }
				}
				DrawImage({ image, placement }) => {
					$out = append_rect($out.append(3), placement)
					$out = $out.concat(list_at(digests, image_node(counts, image.index())))
				}
				DrawPath({ path, style }) => {
					$out = append_style($out.append(4), style, scenes, digests, bases)
					$out = append_path($out, path, scenes)
				}
				DrawText({ paint, run }) => match text {
					NoText => {
						$failure = Failed(missing_text)
					}
					WithText(plan) => if run.index() >= KernelContent.TextPlan.run_count(plan) {
						$failure = Failed(TextRunRecipeInvalid({ prepared: KernelContent.TextPlan.run_count(plan), run: run.index() }))
					} else {

						## The font selection serializes as the referenced font
						## leaf's identity digest plus the exact size, mirroring
						## the emitted `Tf` operator, so recipes never depend on
						## authored font numbering.
						$out = append_text_paint($out.append(5), paint, digests)
						prepared = KernelContent.TextPlan.run(plan, run.index())
						$out = $out.concat(list_at(digests, font_node(counts, prepared.font)))
						$out = append_i64_bytes($out, prepared.size.raw())
						$out = append_u64_bytes($out, prepared.actual_text_begin.len())
						$out = $out.concat(prepared.actual_text_begin)
						$out = append_u64_bytes($out, prepared.body.len())
						$out = $out.concat(prepared.body)
						$out = $out.append(if prepared.close_actual_text 1 else 0)
					}
				}
				Opacity({ children, opacity: _ }) => {
					command_state = list_at(command_states, command_index)
					if command_state == state_sentinel {
						$frames = push_recipe_frame($frames, $active, $current)
						$active = $active + 1
						$current = RecipeFrame.{ close: Bool.False, end: children.start() + children.length(), next: children.start() }
					} else {
						effective = match list_at(derived_states, command_state) {
							AlphaState(value) => value
							MaskState(_) => {
								crash "validated opacity command resolved to a mask state"
							}
						}
						$out = append_u16_bytes($out.append(8), effective.to_u16_wrap())
						$frames = push_recipe_frame($frames, $active, $current)
						$active = $active + 1
						$current = RecipeFrame.{ close: Bool.True, end: children.start() + children.length(), next: children.start() }
					}
				}
				SoftMask({ children, mask: _ }) => {
					command_state = list_at(command_states, command_index)
					mask_form = match list_at(derived_states, command_state) {
						MaskState(form_index) => form_index
						AlphaState(_) => {
							crash "validated soft-mask command resolved to an alpha state"
						}
					}
					$out = $out.append(9).concat(list_at(digests, form_node(counts, mask_form)))
					$frames = push_recipe_frame($frames, $active, $current)
					$active = $active + 1
					$current = RecipeFrame.{ close: Bool.True, end: children.start() + children.length(), next: children.start() }
				}
				PaintShading({ shading }) => {
					$out = $out.append(10).concat(list_at(digests, bases.shading_base + shading.index()))
				}
				PlaceForm({ form: child, transform }) => {
					$out = append_matrix($out.append(6), transform)
					$out = $out.concat(list_at(digests, form_node(counts, child.index())))
				}
				Transform({ children, matrix }) => {
					$out = append_matrix($out.append(7), matrix)
					$frames = push_recipe_frame($frames, $active, $current)
					$active = $active + 1
					$current = RecipeFrame.{ close: Bool.True, end: children.start() + children.length(), next: children.start() }
				}
			}
		}
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok($out)
	}
}

RecipeFrame := { close : Bool, end : U64, next : U64 }

push_recipe_frame : List(RecipeFrame), U64, RecipeFrame -> List(RecipeFrame)
push_recipe_frame = |frames, index, frame| if index < frames.len() list_set(frames, index, frame) else frames.append(frame)

append_style : List(U8), Scene.PathStyle, Scene.Store, List(List(U8)), NodeBases -> List(U8)
append_style = |out, style, scenes, digests, bases| {
	with_fill = match style.fill {
		NoFill => out.append(0)
		SolidFill({ color, rule }) => {
			tagged = out.append(1).append(
				match rule {
					EvenOdd => 0
					Nonzero => 1
				},
			)
			append_color(tagged, color, digests)
		}
		PatternFill({ pattern, rule }) => {
			tagged = out.append(2).append(
				match rule {
					EvenOdd => 0
					Nonzero => 1
				},
			)
			tagged.concat(list_at(digests, bases.pattern_base + pattern.index()))
		}
	}
	match style.stroke {
		NoStroke => with_fill.append(0)
		SolidStroke(stroke) => {
			var $out = with_fill.append(1)
			$out = append_color($out, stroke.color, digests)
			$out = append_i64_bytes($out, stroke.width.raw())
			$out = append_i64_bytes($out, stroke.miter_limit.raw())
			$out = $out.append(
				match stroke.cap {
					ButtCap => 0
					ProjectingSquareCap => 1
					RoundCap => 2
				},
			)
			$out = $out.append(
				match stroke.join {
					BevelJoin => 0
					MiterJoin => 1
					RoundJoin => 2
				},
			)
			match stroke.dash {
				SolidLine => $out.append(0)
				Dashed({ lengths, phase }) => {
					var $dashed = $out.append(1)
					$dashed = append_i64_bytes($dashed, phase.raw())
					$dashed = append_u64_bytes($dashed, lengths.length())
					var $index = lengths.start()
					end = $index + lengths.length()
					while $index < end {
						$dashed = append_i64_bytes($dashed, list_at(scenes.dash_lengths, $index).raw())
						$index = $index + 1
					}
					$dashed
				}
			}
		}
	}
}

append_text_paint : List(U8), Scene.TextPaint, List(List(U8)) -> List(U8)
append_text_paint = |out, paint, digests| {
	var $out = append_color(out, paint.fill, digests)
	$out = $out.append(
		match paint.mode {
			Fill => 0
			FillAndStroke => 1
		},
	)
	$out = append_u16_bytes($out, paint.opacity)
	match paint.stroke {
		NoStroke => $out.append(0)
		Stroke({ color, width }) => append_i64_bytes(append_color($out.append(1), color, digests), width.raw())
	}
}

append_color : List(U8), Color.Value, List(List(U8)) -> List(U8)
append_color = |out, color, digests| {
	var $out = out.concat(list_at(digests, color_node(color.space.index())))
	match color.channels {
		Gray(gray) => append_u16_bytes($out.append(1), gray)
		Rgb({ blue, green, red }) => {
			$out = append_u16_bytes($out.append(3), red)
			$out = append_u16_bytes($out, green)
			append_u16_bytes($out, blue)
		}
	}
}

append_path : List(U8), Scene.PathId, Scene.Store -> List(U8)
append_path = |out, path_id, scenes| {
	path = list_at(scenes.paths, Scene.PathId.index(path_id))
	var $out = append_u64_bytes(out, path.segments.length())
	var $index = path.segments.start()
	end = $index + path.segments.length()
	while $index < end {
		$out = match list_at(scenes.path_segments, $index) {
			Close => $out.append(0)
			CubicTo({ control_1, control_2, end: endpoint }) => append_point(append_point(append_point($out.append(1), control_1), control_2), endpoint)
			LineTo(point) => append_point($out.append(2), point)
			MoveTo(point) => append_point($out.append(3), point)
			Rectangle(rectangle) => append_rect($out.append(4), rectangle)
		}
		$index = $index + 1
	}
	$out
}

append_point : List(U8), Layout.Point -> List(U8)
append_point = |out, point| append_i64_bytes(append_i64_bytes(out, point.x.raw()), point.y.raw())

append_rect : List(U8), Layout.Rect -> List(U8)
append_rect = |out, rect| {
	var $out = append_i64_bytes(out, rect.origin.x.raw())
	$out = append_i64_bytes($out, rect.origin.y.raw())
	$out = append_i64_bytes($out, rect.size.width.raw())
	append_i64_bytes($out, rect.size.height.raw())
}

append_matrix : List(U8), Scene.Matrix -> List(U8)
append_matrix = |out, matrix| {
	var $out = append_i64_bytes(out, matrix.a.raw())
	$out = append_i64_bytes($out, matrix.b.raw())
	$out = append_i64_bytes($out, matrix.c.raw())
	$out = append_i64_bytes($out, matrix.d.raw())
	$out = append_i64_bytes($out, matrix.e.raw())
	append_i64_bytes($out, matrix.f.raw())
}

append_u64_bytes : List(U8), U64 -> List(U8)
append_u64_bytes = |output, value| output
	.append(value.shr_wrap(56).to_u8_wrap())
	.append(value.shr_wrap(48).to_u8_wrap())
	.append(value.shr_wrap(40).to_u8_wrap())
	.append(value.shr_wrap(32).to_u8_wrap())
	.append(value.shr_wrap(24).to_u8_wrap())
	.append(value.shr_wrap(16).to_u8_wrap())
	.append(value.shr_wrap(8).to_u8_wrap())
	.append(value.to_u8_wrap())

append_i64_bytes : List(U8), I64 -> List(U8)
append_i64_bytes = |output, value| append_u64_bytes(output, value.to_u64_wrap())

append_u16_bytes : List(U8), U16 -> List(U8)
append_u16_bytes = |output, value| output.append(value.shr_wrap(8).to_u8_wrap()).append(value.to_u8_wrap())

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated form-plan index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated form-plan update escaped"
	}
}

## Fully opaque is an exact multiplicative identity at both positions, and
## zero annihilates exactly: the endpoints of the documented `U16` semantics.
expect {
	identity = effective_alpha(opaque_alpha, 32768) == 32768 and effective_alpha(32768, opaque_alpha) == 32768 and effective_alpha(opaque_alpha, opaque_alpha) == opaque_alpha
	zero = effective_alpha(0, 32768) == 0 and effective_alpha(32768, 0) == 0
	identity and zero
}

## Representative interior products round deterministically, and a
## non-identity factor always lands strictly below the identity, so an
## emitted state value can never be 65535.
expect {
	half = effective_alpha(32768, 32768) == 16384
	near = effective_alpha(65534, 65534) == 65533
	quarter = effective_alpha(49151, 21845) == 16384
	half and near and quarter
}

## Distinct effective values and distinct mask forms register dense
## first-appearance indices in one combined derived-state space, and
## repeated facts reuse their index.
expect {
	registry = OpacityRegistry.{ mask_index: List.repeat(0, 4), states: [], value_index: List.repeat(0, 65536) }
	first = register_value(registry, 32768)
	second = register_mask(first.registry, 2)
	third = register_value(second.registry, 16384)
	repeat_value = register_value(third.registry, 32768)
	repeat_mask = register_mask(repeat_value.registry, 2)
	first.index == 0 and second.index == 1 and third.index == 2 and repeat_value.index == 0 and repeat_mask.index == 1 and repeat_mask.registry.states == [AlphaState(32768), MaskState(2), AlphaState(16384)]
}

## The derived function layout: a two-stop shading derives one segment, a
## four-stop shading three segments plus a stitching root laid out last,
## and the descriptor subtypes carry the exact PDF shading and function
## types with the channel arity.
expect {
	colors = KernelColor.Plan.build({ profiles: [], spaces: [], tags: [] }, KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 0, max_tags: 0 }))?
	images = KernelImage.Plan.build({ resources: [] }, colors, KernelImage.Limits.make({ max_decoded_bytes: 0, max_encoded_bytes: 0, max_height: 0, max_markers: 0, max_resources: 0, max_width: 0 }))?
	point = |x, y| { x: Layout.Unit.from_raw(x), y: Layout.Unit.from_raw(y) }
	stop = |offset, level| { channels: Gray(level), offset }
	shading_store : Scene.ShadingStore
	shading_store = {
		shadings: [
			{
				extend_end: Bool.False,
				extend_start: Bool.False,
				geometry: Axial({ end: point(9000, 0), start: point(1000, 0) }),
				id: Scene.ShadingId.from_index(0),
				space: Color.SpaceId.from_index(0),
				stops: Semantics.Range.from_start_and_length(0, 2),
			},
			{
				extend_end: Bool.True,
				extend_start: Bool.False,
				geometry: Radial({ end_center: point(5000, 0), end_radius: Layout.Unit.from_raw(2000), start_center: point(1000, 0), start_radius: Layout.Unit.from_raw(0) }),
				id: Scene.ShadingId.from_index(1),
				space: Color.SpaceId.from_index(0),
				stops: Semantics.Range.from_start_and_length(2, 4),
			},
		],
		stops: [stop(0, 0), stop(65535, 65535), stop(0, 0), stop(16384, 32768), stop(49152, 16384), stop(65535, 65535)],
	}
	counts = derive_counts({ colors, font_count: 0, images }, shading_store, Scene.no_patterns)
	layout = counts.shading_function_offsets == [0, 1, 5] and counts.function_shadings == [0, 1, 1, 1, 1]
	roots = shading_root_function(counts, 0) == 0 and shading_root_function(counts, 1) == 4
	subtypes = counts.shading_subtypes == [2, 3] and counts.shading_components == [1, 1]
	segment = node_descriptor(counts, 0, [], [], function_base(counts, 0, 0) + 1)
	stitch = node_descriptor(counts, 0, [], [], function_base(counts, 0, 0) + 4)
	kinds = segment.kind == Function and segment.subtype == 2 and stitch.kind == Function and stitch.subtype == 3
	layout and roots and subtypes and kinds
}
