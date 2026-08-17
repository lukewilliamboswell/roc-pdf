import Color
import Font
import KernelColor
import KernelContent
import KernelImage
import KernelResourceGraph
import KernelScene
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
##   declaration share one identity), and an image is its color-space digest
##   plus its row-compacted canonical planes or sanitized JPEG bytes, so a
##   padded raster and its compact twin deduplicate while equal pixels under
##   different color spaces never merge;
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
		ArithmeticOverflow,
		ArtifactTextInForm({ form : U64 }),
		DuplicateLeafPayload({ canonical : U64, first : U64, second : U64 }),
		Graph(KernelResourceGraph.Error),
		LeafCountMismatch({ declared : U64, supplied : U64 }),
		MissingTextPlan({ form : U64 }),
		MissingTextStore({ command : U64 }),
		RecipeByteLimitExceeded({ attempted : U64, limit : U64 }),
		StoreCountMismatch({ declared : U64, kind : [ColorSpaces, Images, Profiles], supplied : U64 }),
		TextFormMultiplyPlaced({ form : U64, instances : U64 }),
		TextRunRecipeInvalid({ prepared : U64, run : U64 }),
	]

	Limits :: { graph : KernelResourceGraph.Limits, max_recipe_bytes : U64 }.{
		make : { graph : KernelResourceGraph.Limits, max_recipe_bytes : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	## Which ICC profile, if any, one authored color space references.
	ProfileRef : [NoProfile, WithProfile(U64)]

	## Leaf resource counts and per-node dependency facts, derived once from
	## the validated stores: each image's color space and each color space's
	## profile become explicit direct edges.
	Counts : {
		color_spaces : U64,
		fonts : U64,
		image_color_spaces : List(U64),
		profiles : U64,
		space_profiles : List(ProfileRef),
	}

	## The validated stores whose leaf facts this stage consumes. Fonts keep a
	## caller-supplied opaque count here and caller-supplied `Leaf` payloads in
	## `Leaves`; their derived identity joins a later slice.
	Stores : { colors : KernelColor.Plan, font_count : U64, images : KernelImage.Plan }

	## A run painted inside a form, owned by the fragment resolved for that
	## form's unique placement chain.
	RunFragment : { fragment : Semantics.FragmentId, run : U64 }

	FactsWork : {
		direct_edges : U64,
		nested_form_placements : U64,
		ownership_sweep_visits : U64,
		page_form_placements : U64,
		root_uses : U64,
		text_forms : U64,
		use_command_visits : U64,
	}

	## Stage 1: derived direct-use facts, the validated structure run, and the
	## resolved form ownership facts. `run_fragments` feeds text ownership
	## before any recipe or content bytes exist.
	Facts :: {
		counts : Counts,
		direct_text : List(Bool),
		edges : List(KernelResourceGraph.Edge),
		form_instances : List(U64),
		form_owners : List(FormOwner),
		nested_offsets : List(U64),
		nested_children : List(U64),
		order : List(U64),
		page_placements : List({ form : U64, owner : Scene.GroupOwner }),
		root_uses : List(KernelResourceGraph.RootUse),
		run_fragments : List(RunFragment),
		transitive_text : List(Bool),
		work : FactsWork,
	}.{
		build : KernelScene.FormPlan, Stores, [NoTextStore, WithTextStore(Text.Store)], Limits -> Try(Facts, Error)
		build = |form_plan, stores, text, limits| build_facts(form_plan, derive_counts(stores), text, limits)

		instances : Facts, U64 -> U64
		instances = |facts, form| list_at(facts.form_instances, form)

		run_fragments : Facts -> List(RunFragment)
		run_fragments = |facts| facts.run_fragments

		work : Facts -> FactsWork
		work = |facts| facts.work
	}

	FormOwner : [ArtifactOwner, FragmentOwner(Semantics.FragmentId), MixedOwner, UnplacedOwner]

	Leaf : { descriptor : KernelResourceGraph.Descriptor, payload : List(U8) }

	## The leaf inputs of the canonical run: the validated color and image
	## plans whose payloads this stage derives itself, plus the caller-supplied
	## font leaves that stay 1:1 in this slice.
	Leaves : { colors : KernelColor.Plan, fonts : List(Leaf), images : KernelImage.Plan }

	## Direct resource-dictionary contents for one content stream, as dense
	## canonical ordinals per kind, each already in ascending — and therefore
	## canonical dictionary-key — order. Profiles are reachable only through
	## color-space arrays, never through a resource dictionary, so their bucket
	## stays empty for every root and form stream.
	DictionaryPlan : {
		color_spaces : List(U64),
		fonts : List(U64),
		forms : List(U64),
		images : List(U64),
		profiles : List(U64),
	}

	CanonicalForm : { bbox : Layout.Rect, commands : Semantics.Range, representative : U64 }

	## Arena facts for one canonical image: the compacted color plane and
	## alpha plane live at `start ..` inside the canonical payload allocation,
	## immediately after the embedded color-space digest.
	ImageRange : { alpha_length : U64, color_length : U64, start : U64 }

	PlanWork : {
		artifact_placements : U64,
		authored_color_spaces : U64,
		authored_forms : U64,
		authored_images : U64,
		authored_profiles : U64,
		canonical_color_spaces : U64,
		canonical_forms : U64,
		canonical_images : U64,
		canonical_profiles : U64,
		copied_leaf_bytes : U64,
		deduplicated_color_spaces : U64,
		deduplicated_forms : U64,
		deduplicated_images : U64,
		deduplicated_profiles : U64,
		dictionary_entries : U64,
		form_digests : U64,
		leaf_digests : U64,
		leaf_recipe_bytes : U64,
		nested_dictionary_entries : U64,
		nested_form_edges : U64,
		recipe_bytes : U64,
		semantic_placements : U64,
		semantically_duplicated_forms : U64,
		shared_artifact_forms : U64,
	}

	## Stage 2: the canonical plan. Canonical leaves and forms are
	## ordinal-indexed in canonical-ID order (the documented total order for
	## physical objects); the `*_names` lists map every authored resource to
	## its canonical ordinal; the dictionaries are exact direct uses per
	## stream. Fonts stay 1:1, so their canonical ordinals are the authored
	## ordinals.
	Plan :: {
		canonical_colors : List(U64),
		canonical_forms : List(CanonicalForm),
		canonical_images : List(U64),
		canonical_profiles : List(U64),
		color_names : List(U64),
		form_dictionaries : List(DictionaryPlan),
		form_names : List(U64),
		graph : KernelResourceGraph.Plan,
		image_names : List(U64),
		image_ranges : List(ImageRange),
		page_dictionaries : List(DictionaryPlan),
		placements : List(KernelResourceGraph.Placement),
		profile_names : List(U64),
		work : PlanWork,
	}.{
		build : KernelScene.FormPlan, Facts, Leaves, [NoText, WithText(KernelContent.TextPlan)], KernelTagged.Plan, Limits -> Try(Plan, Error)
		build = |form_plan, facts, leaves, text, tagged, limits| build_canonical_plan(form_plan, facts, leaves, text, tagged, limits)

		canonical_form : Plan, U64 -> CanonicalForm
		canonical_form = |plan, ordinal| list_at(plan.canonical_forms, ordinal)

		canonical_form_count : Plan -> U64
		canonical_form_count = |plan| plan.canonical_forms.len()

		## Representative authored color space per canonical color ordinal.
		canonical_color_representatives : Plan -> List(U64)
		canonical_color_representatives = |plan| plan.canonical_colors

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
	form_occurrences : List(U64),
	marks : List(U8),
	text_runs : List(U64),
	touched : List(U64),
}

WalkFrame := { range : Semantics.Range }

## Dense node IDs over one fixed kind order: color spaces, images, fonts,
## ICC profiles, and then forms. The mapping is arithmetic, so no per-node
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

node_count : KernelForm.Counts, U64 -> U64
node_count = |counts, forms| form_base(counts) + forms

## Counts and per-node dependency facts come from the validated stores, so
## authored declarations can never disagree with the payloads that leaf
## identity is derived from.
derive_counts : KernelForm.Stores -> KernelForm.Counts
derive_counts = |stores| {
	color_store = KernelColor.Plan.store(stores.colors)
	image_store = KernelImage.Plan.store(stores.images)
	var $image_spaces = List.with_capacity(image_store.resources.len())
	var $image_index = 0
	while $image_index < image_store.resources.len() {
		resource = list_at(image_store.resources, $image_index)
		space = match resource.payload {
			Jpeg(jpeg) => jpeg.color_space.index()
			Raster(raster) => raster.color_space.index()
		}
		$image_spaces = $image_spaces.append(space)
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
	{
		color_spaces: color_store.spaces.len(),
		fonts: stores.font_count,
		image_color_spaces: $image_spaces,
		profiles: color_store.profiles.len(),
		space_profiles: $space_profiles,
	}
}

build_facts : KernelScene.FormPlan, KernelForm.Counts, TextInput, KernelForm.Limits -> Try(KernelForm.Facts, KernelForm.Error)
build_facts = |form_plan, counts, text, limits| {
	page_plan = KernelScene.FormPlan.page(form_plan)
	scenes = KernelScene.Plan.scenes(page_plan)
	form_store = KernelScene.FormPlan.forms(form_plan)
	form_count = form_store.forms.len()
	nodes = node_count(counts, form_count)

	## Pass A: one walk per page over its owned groups collects that page's
	## deduplicated direct uses, its form placements with their inherited
	## group ownership, and the raw placement multiset.
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
			collected = collect_range_uses($state, group.commands, scenes.commands, counts, text)
			match collected {
				Err(error) => {
					$failure = Failed(error)
				}
				Ok(state) => {
					placement_start = $state.form_occurrences.len()
					$state = state
					var $occurrence = placement_start
					while $occurrence < $state.form_occurrences.len() {
						$page_placements = $page_placements.append({ form: list_at($state.form_occurrences, $occurrence), owner: group.owner })
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
	## multiset, its directly drawn runs, and its direct-text fact.
	var $edges = []
	var $nested = []
	var $form_runs = []
	var $direct_text = List.repeat(Bool.False, form_count)
	var $form_index = 0
	while $form_index < form_count and $failure == NoFailure {
		form = list_at(form_store.forms, $form_index)
		match collect_range_uses(fresh_use_state(nodes), form.commands, form_store.commands, counts, text) {
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
					$nested = $nested.append({ child: list_at(state.form_occurrences, $occurrence), parent: $form_index })
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

	## The structure run: unique ordinal payloads, real edges and roots. It
	## validates the direct-edge DAG (cycles, self-cycles, closure, duplicate
	## declarations) and yields the deterministic topological order that the
	## ownership sweeps and recipe construction below rely on. The run's order
	## names its own canonical IDs; unique payloads make that assignment a
	## bijection, so it maps back to authored node IDs exactly.
	structure = KernelResourceGraph.Plan.build(structure_input(counts, form_count, $edges, scenes.pages.len(), $root_uses), limits.graph) ? Graph
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
				counts,
				direct_text: $direct_text,
				edges: $edges,
				form_instances: sweep.instances,
				form_owners: sweep.owners,
				nested_offsets: sweep.nested_offsets,
				nested_children: sweep.nested_children,
				order,
				page_placements: $page_placements,
				root_uses: $root_uses,
				run_fragments: $run_fragments,
				transitive_text,
				work: {
					direct_edges: $edges.len(),
					nested_form_placements: $nested.len(),
					ownership_sweep_visits: sweep.visits,
					page_form_placements: $page_placements.len(),
					root_uses: $root_uses.len(),
					text_forms: $text_forms,
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

## Walks one validated command range iteratively and accumulates deduplicated
## node uses plus placement/run occurrence lists. The range was validated by
## `KernelScene`, so index arithmetic cannot escape.
collect_range_uses : UseState, Semantics.Range, List(Scene.Command), KernelForm.Counts, TextInput -> Try(UseState, KernelForm.Error)
collect_range_uses = |initial, root, arena, counts, text| {
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
				Clip({ children, path: _ }) | Opacity({ children, opacity: _ }) | Transform({ children, matrix: _ }) => {
					$frames = $frames.append(WalkFrame.{ range: children })
				}
				DrawImage({ image, placement: _ }) => {
					$state = touch($state, image_node(counts, image.index()))
				}
				DrawPath({ path: _, style }) => {
					$state = touch_style($state, style)
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
					$state = { ..$state, form_occurrences: $state.form_occurrences.append(form.index()) }
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

touch_style : UseState, Scene.PathStyle -> UseState
touch_style = |state, style| {
	with_fill = match style.fill {
		NoFill => state
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

structure_input : KernelForm.Counts, U64, List(KernelResourceGraph.Edge), U64, List(KernelResourceGraph.RootUse) -> KernelResourceGraph.Input
structure_input = |counts, form_count, edges, root_count, root_uses| {
	nodes = node_count(counts, form_count)
	var $bytes = List.with_capacity(nodes * 8)
	var $resources = List.with_capacity(nodes)
	var $node = 0
	while $node < nodes {
		start = $bytes.len()
		$bytes = append_u64_bytes($bytes, $node)
		$resources = $resources.append({ descriptor: node_descriptor(counts, form_count, $node), length: 8, start })
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

node_descriptor : KernelForm.Counts, U64, U64 -> KernelResourceGraph.Descriptor
node_descriptor = |counts, _form_count, node| {
	kind = if node < counts.color_spaces {
		ColorSpace
	} else if node < counts.color_spaces + counts.image_color_spaces.len() {
		Image
	} else if node < counts.color_spaces + counts.image_color_spaces.len() + counts.fonts {
		Font
	} else if node < form_base(counts) {
		IccProfile
	} else {
		XObject
	}
	{
		bit_depth: 0,
		components: 0,
		flags: 0,
		height: 0,
		kind,
		subtype: if kind == XObject 1 else 0,
		width: 0,
	}
}

## One reversed-topological sweep resolves instantiation counts and owners:
## parents are processed before the forms they place, so each nested placement
## contributes its parent's already-final count and owner exactly once.
resolve_ownership : KernelForm.Counts,
U64,
List(U64),
List({ form : U64, owner : Scene.GroupOwner }),
List({ child : U64, parent : U64 }) -> Try(
	{
		instances : List(U64),
		nested_children : List(U64),
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
	$nested_index = 0
	while $nested_index < nested.len() {
		entry = list_at(nested, $nested_index)
		write = list_at($offsets, entry.parent) + list_at($cursors, entry.parent)
		$children = list_set($children, write, entry.child)
		$cursors = list_set($cursors, entry.parent, list_at($cursors, entry.parent) + 1)
		$nested_index = $nested_index + 1
	}

	var $failure = NoFailure
	var $position = order.len()
	while $position > 0 and $failure == NoFailure {
		$position = $position - 1
		node = list_at(order, $position)
		if node >= base {
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
		NoFailure => Ok({ instances: $instances, nested_children: $children, nested_offsets: $offsets, owners: $owners, visits: $visits })
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
		if node >= base {
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

build_canonical_plan : KernelScene.FormPlan, KernelForm.Facts, KernelForm.Leaves, TextRecipes, KernelTagged.Plan, KernelForm.Limits -> Try(KernelForm.Plan, KernelForm.Error)
build_canonical_plan = |form_plan, facts, leaves, text, tagged, limits| {
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
	if leaves.fonts.len() != counts.fonts {
		return Err(LeafCountMismatch({ declared: counts.fonts, supplied: leaves.fonts.len() }))
	}

	## Payloads and digests in dependency order over one canonical payload
	## allocation: profiles before the color spaces that embed their digests,
	## color spaces before the images that embed theirs, every leaf before
	## the form recipes. `facts.order` is exactly that topological order.
	nodes = node_count(counts, form_count)
	var $payload = []
	var $sources = List.repeat({ descriptor: node_descriptor(counts, form_count, 0), length: 0, start: 0 }, nodes)
	var $digests = List.repeat([], nodes)
	var $image_ranges = List.repeat({ alpha_length: 0, color_length: 0, start: 0 }, image_count)
	var $copied_leaf_bytes = 0
	var $leaf_recipe_bytes = 0
	var $leaf_digests = 0
	var $recipe_bytes = 0
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
			leaf = list_at(leaves.fonts, node - counts.color_spaces - image_count)
			$payload = $payload.concat(leaf.payload)
			$copied_leaf_bytes = $copied_leaf_bytes + leaf.payload.len()
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
		} else {
			form = list_at(form_store.forms, node - base)
			match serialize_recipe(form, form_store.commands, scenes, $digests, counts, text) {
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
						$sources = list_set($sources, node, { descriptor: node_descriptor(counts, form_count, node), length: recipe.len(), start })
						$form_digests = $form_digests + 1
					}
				}
			}
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

	graph = KernelResourceGraph.Plan.build(
		{
			digest_policy: DomainSeparatedSha256,
			edges: facts.edges,
			payload_bytes: $payload,
			placements: $placements,
			resources: $sources,
			root_count: scenes.pages.len(),
			root_uses: facts.root_uses,
		},
		limits.graph,
	) ? Graph

	nodes_of = node_count(counts, form_count)
	var $canonical_of = List.with_capacity(nodes_of)
	var $node = 0
	while $node < nodes_of {
		$canonical_of = $canonical_of.append(KernelResourceGraph.Plan.canonical_index(graph, $node))
		$node = $node + 1
	}
	canonical_of = $canonical_of
	canonical_count = KernelResourceGraph.Plan.resource_count(graph)

	## Fonts stay 1:1 in this slice, so two byte-identical authored font
	## leaves (which would orphan an emitted object) are rejected explicitly.
	font_start = counts.color_spaces + image_count
	var $leaf_seen = List.repeat(U64.highest, canonical_count)
	var $leaf_check = font_start
	while $leaf_check < font_start + counts.fonts and $failure == NoFailure {
		canonical = list_at(canonical_of, $leaf_check)
		first = list_at($leaf_seen, canonical)
		if first != U64.highest {
			$failure = Failed(DuplicateLeafPayload({ canonical, first, second: $leaf_check - font_start }))
		} else {
			$leaf_seen = list_set($leaf_seen, canonical, $leaf_check - font_start)
		}
		$leaf_check = $leaf_check + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Canonical per-kind ordinals in canonical-ID order — the documented
	## total order for physical leaf and form objects. Fonts receive their
	## authored ordinal below because they stay 1:1.
	var $kinds = List.repeat({ kind: 0, ordinal: 0 }, canonical_count)
	var $color_reps = []
	var $image_reps = []
	var $profile_reps = []
	var $form_ordinals = List.repeat(U64.highest, canonical_count)
	var $ordinal_canonicals = []
	var $canonical_forms = []
	var $canonical_id = 0
	while $canonical_id < canonical_count {
		descriptor = KernelResourceGraph.Plan.descriptor(graph, $canonical_id)
		match descriptor.kind {
			ColorSpace => {
				$kinds = list_set($kinds, $canonical_id, { kind: kind_color, ordinal: $color_reps.len() })
				$color_reps = $color_reps.append(U64.highest)
			}
			Image => {
				$kinds = list_set($kinds, $canonical_id, { kind: kind_image, ordinal: $image_reps.len() })
				$image_reps = $image_reps.append(U64.highest)
			}
			IccProfile => {
				$kinds = list_set($kinds, $canonical_id, { kind: kind_profile, ordinal: $profile_reps.len() })
				$profile_reps = $profile_reps.append(U64.highest)
			}
			XObject => {
				$form_ordinals = list_set($form_ordinals, $canonical_id, $canonical_forms.len())
				$kinds = list_set($kinds, $canonical_id, { kind: kind_form, ordinal: $canonical_forms.len() })
				$ordinal_canonicals = $ordinal_canonicals.append($canonical_id)
				$canonical_forms = $canonical_forms.append({ bbox: zero_rect, commands: Semantics.Range.from_start_and_length(0, 0), representative: U64.highest })
			}
			_ => {}
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
	var $font = 0
	while $font < counts.fonts {
		canonical = list_at(canonical_of, font_node(counts, $font))
		$kinds = list_set($kinds, canonical, { kind: kind_font, ordinal: $font })
		$font = $font + 1
	}

	## Canonical forms in canonical-ID order; each keeps its lowest authored
	## form as the representative whose validated command range lowers once.
	var $form_names = List.repeat(0, form_count)
	var $form_index = 0
	while $form_index < form_count {
		canonical = list_at(canonical_of, form_node(counts, $form_index))
		ordinal = list_at($form_ordinals, canonical)
		$form_names = list_set($form_names, $form_index, ordinal)
		existing = list_at($canonical_forms, ordinal)
		if existing.representative == U64.highest {
			form = list_at(form_store.forms, $form_index)
			$canonical_forms = list_set($canonical_forms, ordinal, { bbox: form.bbox, commands: form.commands, representative: $form_index })
		}
		$form_index = $form_index + 1
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

	Ok(
		KernelForm.Plan.{
			canonical_colors: $color_reps,
			canonical_forms: $canonical_forms,
			canonical_images: $image_reps,
			canonical_profiles: $profile_reps,
			color_names: $color_names,
			form_dictionaries: $form_dictionaries,
			form_names: $form_names,
			graph,
			image_names: $image_names,
			image_ranges: $canonical_image_ranges,
			page_dictionaries: $page_dictionaries,
			placements: graph_placements,
			profile_names: $profile_names,
			work: {
				artifact_placements: $artifact_placements,
				authored_color_spaces: counts.color_spaces,
				authored_forms: form_count,
				authored_images: image_count,
				authored_profiles: counts.profiles,
				canonical_color_spaces: $color_reps.len(),
				canonical_forms: $canonical_forms.len(),
				canonical_images: $image_reps.len(),
				canonical_profiles: $profile_reps.len(),
				copied_leaf_bytes: $copied_leaf_bytes,
				deduplicated_color_spaces: counts.color_spaces - $color_reps.len(),
				deduplicated_forms,
				deduplicated_images: image_count - $image_reps.len(),
				deduplicated_profiles: counts.profiles - $profile_reps.len(),
				dictionary_entries: $dictionary_entries,
				form_digests: $form_digests,
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

partition_dictionary : List(U64), List({ kind : U64, ordinal : U64 }) -> KernelForm.DictionaryPlan
partition_dictionary = |canonical_ids, kinds| {
	var $color_spaces = []
	var $fonts = []
	var $forms = []
	var $images = []
	var $profiles = []
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
		} else {
			$forms = insert_sorted($forms, entry.ordinal)
		}
		$index = $index + 1
	}
	{ color_spaces: $color_spaces, fonts: $fonts, forms: $forms, images: $images, profiles: $profiles }
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
dictionary_size = |dictionary| dictionary.color_spaces.len() + dictionary.fonts.len() + dictionary.forms.len() + dictionary.images.len() + dictionary.profiles.len()

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
## resource's identity digest; text commands embed the prepared run bytes.
serialize_recipe : Scene.Form, List(Scene.Command), Scene.Store, List(List(U8)), KernelForm.Counts, TextRecipes -> Try(List(U8), KernelForm.Error)
serialize_recipe = |form, arena, scenes, digests, counts, text| {
	var $out = List.with_capacity(64)
	$out = append_rect($out, form.bbox)
	var $frames = []
	var $active = 0
	var $current = RecipeFrame.{ close: Bool.False, end: form.commands.start() + form.commands.length(), next: form.commands.start() }
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
					$out = append_style($out.append(4), style, scenes, digests)
					$out = append_path($out, path, scenes)
				}
				DrawText({ paint, run }) => match text {
					NoText => {
						$failure = Failed(MissingTextPlan({ form: Scene.FormId.index(form.id) }))
					}
					WithText(plan) => if run.index() >= KernelContent.TextPlan.run_count(plan) {
						$failure = Failed(TextRunRecipeInvalid({ prepared: KernelContent.TextPlan.run_count(plan), run: run.index() }))
					} else {
						$out = append_text_paint($out.append(5), paint, digests)
						prepared = KernelContent.TextPlan.run(plan, run.index())
						$out = append_u64_bytes($out, prepared.actual_text_begin.len())
						$out = $out.concat(prepared.actual_text_begin)
						$out = append_u64_bytes($out, prepared.body.len())
						$out = $out.concat(prepared.body)
						$out = $out.append(if prepared.close_actual_text 1 else 0)
					}
				}
				Opacity(_) => {
					crash "validated form recipe met a rejected opacity command"
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

append_style : List(U8), Scene.PathStyle, Scene.Store, List(List(U8)) -> List(U8)
append_style = |out, style, scenes, digests| {
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
