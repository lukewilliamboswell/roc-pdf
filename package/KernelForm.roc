import Color
import Font
import KernelContent
import KernelResourceGraph
import KernelScene
import KernelTagged
import Layout
import Scene
import Semantics
import Text

## Gate 4 Form XObject normalization.
##
## This stage turns a validated form-aware scene into the canonical facts that
## content lowering, object planning, and serialization consume:
##
## - direct-use facts for every content stream, derived once from validated
##   commands rather than by scanning emitted operators;
## - the explicit direct-edge dependency graph over color spaces, images,
##   fonts, and forms, validated twice by `KernelResourceGraph`: a structure
##   run over unique ordinal payloads proves acyclicity/closure and yields the
##   deterministic topological order, and a canonical run over real leaf
##   payloads plus Merkle recipes performs deduplication and planning;
## - canonical visual form identity: a recipe of the bounding box, the
##   canonical identity matrix, and the command tree with geometry inlined and
##   every nested reference replaced by the referenced resource's identity
##   digest, so identity never depends on authored dense IDs, insertion order,
##   or incidental resource-name allocation;
## - placement ownership records (placement-site tagging): every page-level
##   placement inherits its owned scene group's fragment or page-artifact
##   ownership, form streams stay ownership-neutral, and text reachable inside
##   a form resolves to the owner of the form's unique placement chain.
##
## All DAG work is iterative: instantiation counts, transitive text facts, and
## owner resolution are single topological sweeps over forms plus nested
## placements, never per-path traversals, and a form cycle is rejected by the
## resource graph before any traversal could recurse.
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
		TextFormMultiplyPlaced({ form : U64, instances : U64 }),
		TextRunRecipeInvalid({ prepared : U64, run : U64 }),
	]

	Limits :: { graph : KernelResourceGraph.Limits, max_recipe_bytes : U64 }.{
		make : { graph : KernelResourceGraph.Limits, max_recipe_bytes : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	## Leaf resource counts and the per-image color-space dependency facts.
	## Leaves stay 1:1 with their authored stores in this slice; forms are the
	## only kind this stage deduplicates.
	Counts : { color_spaces : U64, fonts : U64, image_color_spaces : List(U64) }

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
		build : KernelScene.FormPlan, Counts, [NoTextStore, WithTextStore(Text.Store)], Limits -> Try(Facts, Error)
		build = |form_plan, counts, text, limits| build_facts(form_plan, counts, text, limits)

		instances : Facts, U64 -> U64
		instances = |facts, form| list_at(facts.form_instances, form)

		run_fragments : Facts -> List(RunFragment)
		run_fragments = |facts| facts.run_fragments

		work : Facts -> FactsWork
		work = |facts| facts.work
	}

	FormOwner : [ArtifactOwner, FragmentOwner(Semantics.FragmentId), MixedOwner, UnplacedOwner]

	Leaf : { descriptor : KernelResourceGraph.Descriptor, payload : List(U8) }

	## Direct resource-dictionary contents for one content stream, as dense
	## authored ordinals per kind (forms as canonical ordinals), each already
	## in ascending — and therefore canonical dictionary-key — order.
	DictionaryPlan : {
		color_spaces : List(U64),
		fonts : List(U64),
		forms : List(U64),
		images : List(U64),
	}

	CanonicalForm : { bbox : Layout.Rect, commands : Semantics.Range, representative : U64 }

	PlanWork : {
		artifact_placements : U64,
		authored_forms : U64,
		canonical_forms : U64,
		deduplicated_forms : U64,
		dictionary_entries : U64,
		form_digests : U64,
		leaf_digests : U64,
		nested_dictionary_entries : U64,
		nested_form_edges : U64,
		recipe_bytes : U64,
		semantic_placements : U64,
		semantically_duplicated_forms : U64,
		shared_artifact_forms : U64,
	}

	## Stage 2: the canonical plan. `canonical_forms` is ordinal-indexed in
	## canonical-ID order (the documented total order for physical form
	## objects); `form_names` maps every authored form to its canonical
	## ordinal; the dictionaries are exact direct uses per stream.
	Plan :: {
		canonical_forms : List(CanonicalForm),
		form_dictionaries : List(DictionaryPlan),
		form_names : List(U64),
		graph : KernelResourceGraph.Plan,
		page_dictionaries : List(DictionaryPlan),
		placements : List(KernelResourceGraph.Placement),
		work : PlanWork,
	}.{
		build : KernelScene.FormPlan, Facts, List(Leaf), [NoText, WithText(KernelContent.TextPlan)], KernelTagged.Plan, Limits -> Try(Plan, Error)
		build = |form_plan, facts, leaves, text, tagged, limits| build_canonical_plan(form_plan, facts, leaves, text, tagged, limits)

		canonical_form : Plan, U64 -> CanonicalForm
		canonical_form = |plan, ordinal| list_at(plan.canonical_forms, ordinal)

		canonical_form_count : Plan -> U64
		canonical_form_count = |plan| plan.canonical_forms.len()

		form_dictionary : Plan, U64 -> DictionaryPlan
		form_dictionary = |plan, ordinal| list_at(plan.form_dictionaries, ordinal)

		form_names : Plan -> List(U64)
		form_names = |plan| plan.form_names

		graph : Plan -> KernelResourceGraph.Plan
		graph = |plan| plan.graph

		graph_work : Plan -> KernelResourceGraph.Work
		graph_work = |plan| KernelResourceGraph.Plan.work(plan.graph)

		page_dictionary : Plan, U64 -> DictionaryPlan
		page_dictionary = |plan, page| list_at(plan.page_dictionaries, page)

		placements : Plan -> List(KernelResourceGraph.Placement)
		placements = |plan| plan.placements

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

## Dense node IDs over one fixed kind order: color spaces, images, fonts, and
## then forms. The mapping is arithmetic, so no per-node table exists.
color_node : U64 -> U64
color_node = |color| color

image_node : KernelForm.Counts, U64 -> U64
image_node = |counts, image| counts.color_spaces + image

font_node : KernelForm.Counts, U64 -> U64
font_node = |counts, font| counts.color_spaces + counts.image_color_spaces.len() + font

form_node : KernelForm.Counts, U64 -> U64
form_node = |counts, form| counts.color_spaces + counts.image_color_spaces.len() + counts.fonts + form

form_base : KernelForm.Counts -> U64
form_base = |counts| counts.color_spaces + counts.image_color_spaces.len() + counts.fonts

node_count : KernelForm.Counts, U64 -> U64
node_count = |counts, forms| form_base(counts) + forms

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
	} else if node < form_base(counts) {
		Font
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

build_canonical_plan : KernelScene.FormPlan, KernelForm.Facts, List(KernelForm.Leaf), TextRecipes, KernelTagged.Plan, KernelForm.Limits -> Try(KernelForm.Plan, KernelForm.Error)
build_canonical_plan = |form_plan, facts, leaves, text, tagged, limits| {
	counts = facts.counts
	form_store = KernelScene.FormPlan.forms(form_plan)
	scenes = KernelScene.Plan.scenes(KernelScene.FormPlan.page(form_plan))
	form_count = form_store.forms.len()
	base = form_base(counts)
	if leaves.len() != base {
		return Err(LeafCountMismatch({ declared: base, supplied: leaves.len() }))
	}

	## Leaf payloads first: their identity digests seed the Merkle recipes.
	var $payload = []
	var $sources = List.repeat({ descriptor: node_descriptor(counts, form_count, 0), length: 0, start: 0 }, node_count(counts, form_count))
	var $digests = List.repeat([], node_count(counts, form_count))
	var $leaf_index = 0
	while $leaf_index < leaves.len() {
		leaf = list_at(leaves, $leaf_index)
		start = $payload.len()
		$payload = $payload.concat(leaf.payload)
		$sources = list_set($sources, $leaf_index, { descriptor: leaf.descriptor, length: leaf.payload.len(), start })
		$leaf_index = $leaf_index + 1
	}
	$leaf_index = 0
	var $failure = NoFailure
	while $leaf_index < leaves.len() and $failure == NoFailure {
		match KernelResourceGraph.identity_digest(list_at($sources, $leaf_index), $payload) {
			Err(error) => {
				$failure = Failed(Graph(error))
			}
			Ok(digest) => {
				$digests = list_set($digests, $leaf_index, digest)
			}
		}
		$leaf_index = $leaf_index + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Recipes in dependency order: every referenced digest is already final.
	var $recipe_bytes = 0
	var $form_digests = 0
	var $position = 0
	while $position < facts.order.len() and $failure == NoFailure {
		node = list_at(facts.order, $position)
		if node >= base {
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
						start = $payload.len()
						$payload = $payload.concat(recipe)
						source = { descriptor: node_descriptor(counts, form_count, node), length: recipe.len(), start }
						$sources = list_set($sources, node, source)
						match KernelResourceGraph.identity_digest(source, $payload) {
							Err(error) => {
								$failure = Failed(Graph(error))
							}
							Ok(digest) => {
								$digests = list_set($digests, node, digest)
								$form_digests = $form_digests + 1
							}
						}
					}
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

	## Later stages consume the plan's source-to-canonical map; leaves stay
	## 1:1 in this slice, so two byte-identical authored leaves (which would
	## orphan an emitted object) are rejected explicitly.
	nodes = node_count(counts, form_count)
	var $canonical_of = List.with_capacity(nodes)
	var $node = 0
	while $node < nodes {
		$canonical_of = $canonical_of.append(KernelResourceGraph.Plan.canonical_index(graph, $node))
		$node = $node + 1
	}
	canonical_of = $canonical_of
	canonical_count = KernelResourceGraph.Plan.resource_count(graph)
	var $leaf_seen = List.repeat(U64.highest, canonical_count)
	var $leaf_check = 0
	while $leaf_check < base and $failure == NoFailure {
		canonical = list_at(canonical_of, $leaf_check)
		first = list_at($leaf_seen, canonical)
		if first != U64.highest {
			$failure = Failed(DuplicateLeafPayload({ canonical, first, second: $leaf_check }))
		} else {
			$leaf_seen = list_set($leaf_seen, canonical, $leaf_check)
		}
		$leaf_check = $leaf_check + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Canonical forms in canonical-ID order; each keeps its lowest authored
	## form as the representative whose validated command range lowers once.
	var $form_ordinals = List.repeat(U64.highest, canonical_count)
	var $ordinal_canonicals = []
	var $canonical_forms = []
	var $form_names = List.repeat(0, form_count)
	var $canonical_id = 0
	while $canonical_id < canonical_count {
		descriptor = KernelResourceGraph.Plan.descriptor(graph, $canonical_id)
		if descriptor.kind == XObject and descriptor.subtype == 1 {
			$form_ordinals = list_set($form_ordinals, $canonical_id, $canonical_forms.len())
			$ordinal_canonicals = $ordinal_canonicals.append($canonical_id)
			$canonical_forms = $canonical_forms.append({ bbox: zero_rect, commands: Semantics.Range.from_start_and_length(0, 0), representative: U64.highest })
		}
		$canonical_id = $canonical_id + 1
	}
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
	## ascending ordinal (and therefore canonical byte) order.
	kinds = canonical_kind_table(graph, canonical_of, counts, form_count, $form_ordinals)
	var $page_dictionaries = List.with_capacity(scenes.pages.len())
	var $dictionary_entries = 0
	var $page = 0
	while $page < scenes.pages.len() {
		dictionary = partition_dictionary(KernelResourceGraph.Plan.root_dictionary(graph, $page), kinds)
		$dictionary_entries = $dictionary_entries + dictionary_size(dictionary)
		$page_dictionaries = $page_dictionaries.append(dictionary)
		$page = $page + 1
	}
	var $form_dictionaries = List.with_capacity($canonical_forms.len())
	var $nested_dictionary_entries = 0
	var $ordinal = 0
	while $ordinal < $canonical_forms.len() {
		dictionary = partition_dictionary(KernelResourceGraph.Plan.direct_dependencies(graph, list_at($ordinal_canonicals, $ordinal)), kinds)
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
			canonical_forms: $canonical_forms,
			form_dictionaries: $form_dictionaries,
			form_names: $form_names,
			graph,
			page_dictionaries: $page_dictionaries,
			placements: graph_placements,
			work: {
				artifact_placements: $artifact_placements,
				authored_forms: form_count,
				canonical_forms: $canonical_forms.len(),
				deduplicated_forms,
				dictionary_entries: $dictionary_entries,
				form_digests: $form_digests,
				leaf_digests: leaves.len(),
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

zero_rect : Layout.Rect
zero_rect = { origin: { x: Layout.Unit.from_raw(0), y: Layout.Unit.from_raw(0) }, size: { height: Layout.Unit.from_raw(0), width: Layout.Unit.from_raw(0) } }

canonical_kind_table : KernelResourceGraph.Plan, List(U64), KernelForm.Counts, U64, List(U64) -> List({ kind : U64, ordinal : U64 })
canonical_kind_table = |graph, canonical_of, counts, form_count, form_ordinals| {
	count = KernelResourceGraph.Plan.resource_count(graph)
	var $table = List.repeat({ kind: 0, ordinal: 0 }, count)
	var $node = 0
	while $node < node_count(counts, form_count) {
		canonical = list_at(canonical_of, $node)
		entry = if $node < counts.color_spaces {
			{ kind: kind_color, ordinal: $node }
		} else if $node < counts.color_spaces + counts.image_color_spaces.len() {
			{ kind: kind_image, ordinal: $node - counts.color_spaces }
		} else if $node < form_base(counts) {
			{ kind: kind_font, ordinal: $node - counts.color_spaces - counts.image_color_spaces.len() }
		} else {
			{ kind: kind_form, ordinal: list_at(form_ordinals, canonical) }
		}
		$table = list_set($table, canonical, entry)
		$node = $node + 1
	}
	$table
}

kind_color : U64
kind_color = 0

kind_image : U64
kind_image = 1

kind_font : U64
kind_font = 2

kind_form : U64
kind_form = 3

partition_dictionary : List(U64), List({ kind : U64, ordinal : U64 }) -> KernelForm.DictionaryPlan
partition_dictionary = |canonical_ids, kinds| {
	var $color_spaces = []
	var $fonts = []
	var $forms = []
	var $images = []
	var $index = 0
	while $index < canonical_ids.len() {
		entry = list_at(kinds, list_at(canonical_ids, $index))
		if entry.kind == kind_color {
			$color_spaces = insert_sorted($color_spaces, entry.ordinal)
		} else if entry.kind == kind_image {
			$images = insert_sorted($images, entry.ordinal)
		} else if entry.kind == kind_font {
			$fonts = insert_sorted($fonts, entry.ordinal)
		} else {
			$forms = insert_sorted($forms, entry.ordinal)
		}
		$index = $index + 1
	}
	{ color_spaces: $color_spaces, fonts: $fonts, forms: $forms, images: $images }
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
dictionary_size = |dictionary| dictionary.color_spaces.len() + dictionary.fonts.len() + dictionary.forms.len() + dictionary.images.len()

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
