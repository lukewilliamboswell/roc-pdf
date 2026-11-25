import fuzz.Model
import pdf.Font
import pdf.KernelFacadeFragments
import pdf.KernelFacadeText
import pdf.KernelFixture
import pdf.KernelNavigation
import pdf.KernelSemantics
import pdf.KernelTextSemantics
import pdf.Layout
import pdf.Semantics
import pdf.Text

LinkRegionModel := [].{}

World : { wrap : Bool, continuation : Bool, repeated_header : Bool }

Action : [AddWrap, ContinueOnNextPage, RepeatHeader]

Bounds : { left : I64, right : I64, bottom : I64, top : I64 }

Placement : { page : U64, source : U64, owner : [Link(U64), Plain, RepeatedHeader], painted : Bounds }

Group : { owner : U64, page : U64, regions : List(Bounds) }

machine : Model.Machine(World, Action)
machine = {
	init: { wrap: False, continuation: False, repeated_header: False },
	actions: |world| {
		var $actions = []
		if !world.wrap {
			$actions = $actions.append(AddWrap)
		}
		if !world.continuation {
			$actions = $actions.append(ContinueOnNextPage)
		}
		if world.continuation and !world.repeated_header {
			$actions = $actions.append(RepeatHeader)
		}
		$actions
	},
	step: |world, action| match action {
		AddWrap => { ..world, wrap: True }
		ContinueOnNextPage => { ..world, continuation: True }
		RepeatHeader => { ..world, repeated_header: True }
	},
	rules: [
		Model.always("validated annotation regions and OBJR ownership agree with authored link fragments", |world| check(world)),
		Model.sometimes("styled runs touch on one line and a distinct link starts at their end", |world| !world.wrap and !world.continuation),
		Model.sometimes("a linked span has a same-page wrap and continues after a repeated header", |world| world.wrap and world.repeated_header),
	],
}

expect {
	report = Model.explore(machine, { depth: 4, key: |world| world, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 6 and report.steps == 7 and report.depth == 3 and report.reached.len() == 2
}

# A, B and C belong to one Link. B has its own Strong element and paint.
# A second Link shares the same URI and touches C, but owns a separate action
# region and annotation object even when their geometry happens to touch.
authored : World -> List(Placement)
authored = |world| {
	last_page = if (world.continuation) 1 else 0
	middle = if (world.wrap) placed(0, 2, Link(2), 5, 14, 2) else placed(0, 2, Link(2), 12, 20, 2)
	last_x = if (!world.wrap and !world.continuation) 14 else 10
	last_y = if (world.wrap and !world.continuation) 8 else 20
	var $runs = [placed(0, 0, Plain, 3, 25, 3), placed(0, 1, Link(2), 9, 20, 3), middle]
	if world.repeated_header {
		$runs = $runs.append(placed(1, 0, RepeatedHeader, 4, 29, 3))
	}
	$runs.append(placed(last_page, 3, Link(2), last_x, last_y, 3)).append(placed(last_page, 4, Link(4), last_x + 3, last_y, 2))
}

placed : U64, U64, [Link(U64), Plain, RepeatedHeader], I64, I64, I64 -> Placement
placed = |page, source, owner, x, y, width| { page, source, owner, painted: { left: x, right: x + width, bottom: y - 1, top: y + 1 } }

authored_groups : List(Placement) -> List(Group)
authored_groups = |runs| {
	var $groups = []
	for link in [2, 4] {
		for page in [0, 1] {
			regions = runs.keep_if(|run| run.owner == Link(link) and run.page == page).map(|run| run.painted)
			if !regions.is_empty() {
				$groups = $groups.append({ owner: link, page, regions })
			}
		}
	}
	$groups
}

# Count occupied unit cells independently of the order, style, and splitting
# of the input rectangles. Equal-height horizontal fragments merge exactly at
# touching edges. Distinct rows in this small world have vertical clearance.
matches_active_area : List(Bounds), List(Bounds) -> Bool
matches_active_area = |wanted, actual| {
	var $starts = 0
	var $y = 0
	while $y < 32 {
		var $x = 0
		while $x < 24 {
			want = occupies(wanted, $x, $y)
			count = actual.keep_if(|quad| contains(quad, $x, $y)).len()
			if count != (if (want) 1 else 0) {
				return False
			}
			if want and !occupies(wanted, $x - 1, $y) and !occupies(wanted, $x, $y - 1) {
				$starts = $starts + 1
			}
			$x = $x + 1
		}
		$y = $y + 1
	}
	$starts == actual.len()
}

contains : Bounds, I64, I64 -> Bool
contains = |rect, x, y| rect.left <= x and x < rect.right and rect.bottom <= y and y < rect.top

occupies : List(Bounds), I64, I64 -> Bool
occupies = |rects, x, y| rects.any(|rect| contains(rect, x, y))

check : World -> Bool
check = |world| {
	runs = authored(world)
	want = authored_groups(runs)
	match plan(runs, if (world.continuation) 2 else 1) {
		Err(reason) => crash "link-region fixture did not lower: ${Str.inspect(reason)}"
		Ok(fragments) => {
			semantic = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(KernelFacadeFragments.Plan.semantics(fragments)))
			match KernelFacadeFragments.Plan.navigation(fragments) {
				NoNavigationStore => False
				WithNavigationStore(navigation) => matches_output(want, navigation, semantic)
			}
		}
	}
}

matches_output : List(Group), KernelNavigation.Store, Semantics.Store -> Bool
matches_output = |want, navigation, semantic| {
	if navigation.annotations.len() != want.len() or semantic.annotations.len() != want.len() {
		return False
	}
	var $index = 0
	for group in want {
		annotation = get(navigation.annotations, $index)
		owner = get(semantic.annotations, $index)
		if annotation.page.index() != group.page or owner.id.index() != $index or owner.owner.index() != group.owner {
			return False
		}
		rank = want.take_first($index).keep_if(|prior| prior.page == group.page).len()
		if annotation.keyboard_order != rank or owner.logical_order != $index {
			return False
		}
		rect = annotation.rect
		actual_rect = bounds(rect.origin.x, rect.origin.y, Layout.Unit.from_raw(rect.origin.x.raw() + rect.size.width.raw()), Layout.Unit.from_raw(rect.origin.y.raw() + rect.size.height.raw()))
		expected_rect = group.regions.fold(
			get(group.regions, 0),
			|outer, area| {
				left: I64.min(outer.left, area.left),
				bottom: I64.min(outer.bottom, area.bottom),
				right: I64.max(outer.right, area.right),
				top: I64.max(outer.top, area.top),
			},
		)
		if actual_rect != expected_rect {
			return False
		}
		actual = items(navigation.quad_points, annotation.quads).map(|quad| bounds(quad.x_left, quad.y_bottom, quad.x_right, quad.y_top))
		if actual.any(|area| area.left < expected_rect.left or area.right > expected_rect.right or area.bottom < expected_rect.bottom or area.top > expected_rect.top) or !matches_active_area(group.regions, actual) {
			return False
		}
		$index = $index + 1
	}
	var $node_index = 0
	while $node_index < semantic.nodes.len() {
		node = get(semantic.nodes, $node_index)
		var $own_ids = []
		for item in items(semantic.content_spine, node.content) {
			match item {
				AnnotationOccurrence(id) => {
					$own_ids = $own_ids.append(id.index())
				}
				_ => {}
			}
		}
		var $expected = []
		var $annotation_id = 0
		for group in want {
			if group.owner == $node_index {
				$expected = $expected.append($annotation_id)
			}
			$annotation_id = $annotation_id + 1
		}
		if $own_ids != $expected {
			return False
		}
		$node_index = $node_index + 1
	}
	True
}

bounds : Layout.Unit, Layout.Unit, Layout.Unit, Layout.Unit -> Bounds
bounds = |left, bottom, right, top| { left: whole_pt(left), bottom: whole_pt(bottom), right: whole_pt(right), top: whole_pt(top) }

whole_pt : Layout.Unit -> I64
whole_pt = |coordinate| {
	raw = coordinate.raw()
	if raw % 1000 != 0 {
		crash "the link boundary changed a whole-point fixture coordinate"
	}
	raw // 1000
}

plan : List(Placement), U64 -> Try(KernelFacadeFragments.Plan, [Fragments(KernelFacadeFragments.Error), Text(KernelFacadeText.Error), Semantics(KernelTextSemantics.Error)])
plan = |runs, pages| {
	places = runs.map(
		|run| {
			artifact: run.owner == RepeatedHeader,
			line: run.source,
			origin: { x: unit(run.painted.left), y: unit(run.painted.bottom + 1) },
			page: Semantics.PageId.from_index(run.page),
			source_runs: { physical: range(run.source, 1) },
		},
	)
	shape_runs = runs.keep_if(|run| run.owner != RepeatedHeader)
	shape : Text.Store
	shape = {
		clusters: shape_runs.map(|run| { glyphs: range(run.source, 1), kind: OneToOne, source: source_range }),
		glyph_indices: shape_runs.map(|run| run.source),
		glyphs: shape_runs.map(|run| { advance_x: unit(run.painted.right - run.painted.left), advance_y: unit(0), id: Text.GlyphId.from_raw(1), offset_x: unit(0), offset_y: unit(0) }),
		runs: shape_runs.map(|run| shaped_run(run.source)),
		substitutions: [],
		transformations: [],
	}
	styles = shape_runs.map(|run| { color: Srgb(Rgb({ red: if (run.source == 2) 65535 else 0, green: 0, blue: 0 })), leading: unit(2), segment: run.source })
	lines = shape_runs.map(|run| { advance: unit(run.painted.right - run.painted.left), clusters: range(run.source, 1), source: source_range })
	text = KernelFacadeText.Plan.build_positioned({ shape, styles, lines, origins: WholeSources, pages, pieces: places }, [], { decorations: [], figure_scales: [], panels: [] }, KernelFacadeText.Limits.make({ max_clusters: 8, max_glyph_indices: 8, max_glyphs: 8, max_pages: 2, max_placements: 8, max_runs: 8 })) ? Text
	semantics = KernelTextSemantics.Plan.build_navigation(semantic_input, 0, 0, semantic_limits, KernelTextSemantics.Limits.make({ max_text_properties: 0, max_text_property_bytes: 0, max_text_source_bytes: 1, max_text_source_scalars: 1, max_text_sources: 1 })) ? Semantics
	target = Uri("https://example.com/same")
	navigation = WithNavigationAuthoring({
		destinations: [],
		links: [{ node: node_id(2), occurrences: range(1, 3), target }, { node: node_id(4), occurrences: range(4, 1), target }],
		outline: [],
		page_labels: [],
		underline: NoUnderline,
	})
	fragments = KernelFacadeFragments.Plan.build_with_navigation(semantics, text, navigation, KernelFacadeFragments.Limits.make({ max_fragments: 8, max_occurrences: 5, max_pages: 2 }), semantic_limits, KernelNavigation.standard_limits) ? Fragments
	Ok(fragments)
}

shaped_run : U64 -> Text.Run
shaped_run = |index| {
	actual_text: FromOccurrence,
	clusters: range(index, 1),
	direction: LeftToRight,
	glyphs: range(index, 1),
	id: Text.RunId.from_index(index),
	instance: Font.InstanceId.from_index(0),
	language: Language("en"),
	script: Font.Script.from_iso15924("Latn"),
	size: unit(1),
	source: source_range,
	substitutions: range(0, 0),
	transformations: range(0, 0),
	unicode: OccurrenceText(occurrence_id(index)),
	writing_mode: Horizontal,
}

semantic_input : Semantics.Store
semantic_input = {
	..KernelFixture.semantics,
	content_spine: [ChildNode(node_id(1)), ContentOccurrence(occurrence_id(0)), ChildNode(node_id(2)), ChildNode(node_id(4)), ContentOccurrence(occurrence_id(1)), ChildNode(node_id(3)), ContentOccurrence(occurrence_id(3)), ContentOccurrence(occurrence_id(2)), ContentOccurrence(occurrence_id(4))],
	fragments: [],
	nodes: [node(0, "Document", DocumentRoot, 0, 1), node(1, "P", ParentNode(node_id(0)), 1, 3), node(2, "Link", ParentNode(node_id(1)), 4, 3), node(3, "Strong", ParentNode(node_id(2)), 7, 1), node(4, "Link", ParentNode(node_id(1)), 8, 1)],
	non_text_sources: [],
	occurrences: [0, 1, 2, 3, 4].map(|index| { id: occurrence_id(index), fragments: range(0, 0), language: Inherited, source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange(source_range)), text_properties: range(0, 0) }),
	text_sources: [{ unicode: "A" }],
}

node = |index, role, parent, start, length| {
	attributes: range(0, 0),
	content: range(start, length),
	element_identifier: NoElementIdentifier,
	id: node_id(index),
	language: Inherited,
	parent,
	role: { local_name: role, namespace: Semantics.NamespaceId.from_index(0) },
	structure_element: Semantics.StructureElementId.from_index(index),
	text_properties: range(0, 0),
}

semantic_limits = KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 16, max_fragments: 8, max_namespaces: 1, max_nodes: 5, max_occurrences: 5, max_semantic_depth: 4 })

source_range = { scalars: range(0, 1), utf8_bytes: range(0, 1) }

node_id = Semantics.NodeId.from_index

occurrence_id = Semantics.OccurrenceId.from_index

range = |start, length| Semantics.IndexRange.from_start_and_length({ start, length })

unit = |whole| Layout.Unit.from_raw(whole * 1000)

items = |store, span| store.drop_first(span.start()).take_first(span.length())

get = |store, index| match store.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "link-region fixture index escaped"
}
