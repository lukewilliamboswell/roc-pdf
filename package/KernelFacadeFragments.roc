import Document
import KernelFacadeFurniture
import KernelFacadePages
import KernelFacadeText
import KernelNavigation
import KernelSemantics
import KernelTextSemantics
import Layout
import Semantics
import Text

KernelFacadeFragments :: [].{
	Dimension : [Fragments, Occurrences, Pages]
	Error : [
		ArithmeticOverflow,
		Navigation(Document.NavigationError),
		InvalidOccurrence({ available : U64, run : U64 }),
		InvalidPage({ page : U64 }),
		InvalidPlacement({ placement : U64 }),
		InvalidPreliminaryFragments({ fragments : U64, reverse_entries : U64 }),
		InvalidRun({ run : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		SourceRangeMismatch({ run : U64 }),
		TextSemantics(KernelTextSemantics.Error),
	]
	Limits :: {
		max_fragments : U64,
		max_occurrences : U64,
		max_pages : U64,
	}.{
		make : { max_fragments : U64, max_occurrences : U64, max_pages : U64 } -> Limits
		make = |limits| Limits.(limits)
	}
	Work : {
		continuation_reads : U64,
		continuation_writes : U64,
		fragment_writes : U64,
		page_visits : U64,
		placement_visits : U64,
	}
	Prepared : {
		pages : List(KernelFacadeText.Page),
		placements : List(KernelFacadeText.Placement),
		text : Text.Store,
	}

	## The authored navigation facts the post-layout stage consumes: link and
	## destination records from the semantic stage plus the document outline
	## and page-label ranges.
	NavigationAuthoring : [
		NoNavigationAuthoring,
		WithNavigationAuthoring(
			{
				destinations : List({ anchor : Semantics.OccurrenceId, name : Str, target : Semantics.NodeId }),
				links : List({ node : Semantics.NodeId, occurrences : Semantics.Range, target : [InternalDestination(Str), Uri(Str)] }),
				outline : List(Document.OutlineEntry),
				page_labels : List(Document.PageLabelRange),
				underline : LinkUnderline,
			},
		),
	]

	## The theme's link underline: a decoration below every painted line
	## run of a link, `offset` below its baseline and `thickness` thick.
	LinkUnderline : [NoUnderline, Underline({ offset : Layout.Unit, thickness : Layout.Unit })]
	Arena :: { fragments : List(Semantics.LayoutFragment), work : Work }.{

		## Focused phase evidence stops at the flat fragment arena. The production
		## `Plan.build` additionally rebuilds the validated semantic reverse index.
		build : KernelTextSemantics.Plan, KernelFacadeText.Plan, Limits -> Try(Arena, Error)
		build = |preliminary, text, limits| build_arena(preliminary, prepare_text(text), KernelFacadeText.Plan.artifact_runs(text), limits)

		build_prepared : KernelTextSemantics.Plan, Prepared, Limits -> Try(Arena, Error)
		build_prepared = |preliminary, prepared, limits| build_arena(preliminary, prepared, [], limits)

		fragments : Arena -> List(Semantics.LayoutFragment)
		fragments = |arena| arena.fragments

		work : Arena -> Work
		work = |arena| arena.work
	}
	Plan :: { anchor_rects : List(KernelNavigation.AnchorRect), arena : Arena, navigation : [NoNavigationStore, WithNavigationStore(KernelNavigation.Store)], semantics : KernelTextSemantics.Plan, text : KernelFacadeText.Plan }.{
		build : KernelTextSemantics.Plan, KernelFacadeText.Plan, Limits, KernelSemantics.Limits -> Try(Plan, Error)
		build = |preliminary, text, limits, semantic_limits| build_plan(preliminary, text, NoNavigationAuthoring, limits, semantic_limits, no_navigation_limits)

		## The navigation-aware build: after pagination, every link lowers to
		## one annotation per page its line runs land on — each page's
		## quadrilaterals are the exact painted line boxes and the annotation
		## rectangle is their union — the content spine gains the per-page
		## annotation occurrences inside each Link node, per-fragment anchor
		## rectangles are derived for destination resolution, and the whole
		## navigation store validates once. `NoNavigationAuthoring` is
		## identical to `build`.
		build_with_navigation : KernelTextSemantics.Plan, KernelFacadeText.Plan, NavigationAuthoring, Limits, KernelSemantics.Limits, KernelNavigation.Limits -> Try(Plan, Error)
		build_with_navigation = |preliminary, text, navigation, limits, semantic_limits, navigation_limits| build_plan(preliminary, text, navigation, limits, semantic_limits, navigation_limits)

		anchor_rects : Plan -> List(KernelNavigation.AnchorRect)
		anchor_rects = |plan| plan.anchor_rects

		fragments : Plan -> List(Semantics.LayoutFragment)
		fragments = |plan| plan.arena.fragments

		navigation : Plan -> [NoNavigationStore, WithNavigationStore(KernelNavigation.Store)]
		navigation = |plan| plan.navigation

		semantics : Plan -> KernelTextSemantics.Plan
		semantics = |plan| plan.semantics

		text : Plan -> KernelFacadeText.Plan
		text = |plan| plan.text

		work : Plan -> Work
		work = |plan| plan.arena.work
	}
}

## Artifact text sources are bounded by the furniture stage (pages times
## furniture lines); these bounds only guard the Unicode store's totals.
artifact_source_limits : KernelTextSemantics.Limits
artifact_source_limits = KernelTextSemantics.Limits.make({ max_text_properties: 0, max_text_property_bytes: 0, max_text_source_bytes: 16000000, max_text_source_scalars: 16000000, max_text_sources: 1000000 })

no_navigation_limits : KernelNavigation.Limits
no_navigation_limits = KernelNavigation.Limits.make({
	max_annotations: 0,
	max_description_bytes: 0,
	max_destinations: 0,
	max_label_prefix_bytes: 0,
	max_label_ranges: 0,
	max_name_bytes: 0,
	max_outline_depth: 0,
	max_outline_entries: 0,
	max_outline_title_bytes: 0,
	max_quads: 0,
	max_uri_bytes: 0,
})

build_plan : KernelTextSemantics.Plan, KernelFacadeText.Plan, KernelFacadeFragments.NavigationAuthoring, KernelFacadeFragments.Limits, KernelSemantics.Limits, KernelNavigation.Limits -> Try(KernelFacadeFragments.Plan, KernelFacadeFragments.Error)
build_plan = |preliminary, text, navigation, limits, semantic_limits, navigation_limits| {
	arena = build_arena(preliminary, prepare_text(text), KernelFacadeText.Plan.artifact_runs(text), limits)?

	## Page furniture's artifact text sources join the Unicode store after
	## the semantic sources, before the final store validates. The plan is
	## handed on in each branch rather than bound by a value-producing
	## match, so its stores stay uniquely owned.
	## Drawing-label sources follow the furniture sources.
	labels = KernelFacadeText.Plan.label_sources(text)
	match KernelFacadeText.Plan.furniture(text) {
		NoFurniture => if labels.is_empty() {
			attach_plan(preliminary, arena, text, navigation, semantic_limits, navigation_limits)
		} else {
			with_sources = KernelTextSemantics.Plan.attach_artifact_sources(preliminary, labels, artifact_source_limits) ? TextSemantics
			attach_plan(with_sources, arena, text, navigation, semantic_limits, navigation_limits)
		}
		WithFurniture(furniture) => {
			sources = if labels.is_empty() KernelFacadeFurniture.Plan.sources(furniture) else KernelFacadeFurniture.Plan.sources(furniture).concat(labels)
			with_sources = KernelTextSemantics.Plan.attach_artifact_sources(preliminary, sources, artifact_source_limits) ? TextSemantics
			attach_plan(with_sources, arena, text, navigation, semantic_limits, navigation_limits)
		}
	}
}

attach_plan : KernelTextSemantics.Plan, KernelFacadeFragments.Arena, KernelFacadeText.Plan, KernelFacadeFragments.NavigationAuthoring, KernelSemantics.Limits, KernelNavigation.Limits -> Try(KernelFacadeFragments.Plan, KernelFacadeFragments.Error)
attach_plan = |preliminary, arena, text, navigation, semantic_limits, navigation_limits| {
	page_count = KernelFacadeText.Plan.pages(text).len()
	match navigation {
		NoNavigationAuthoring => {
			semantics = KernelTextSemantics.Plan.attach_fragments(preliminary, arena.fragments, page_count, page_count, semantic_limits) ? TextSemantics
			Ok(KernelFacadeFragments.Plan.{ anchor_rects: [], arena, navigation: NoNavigationStore, semantics, text })
		}
		WithNavigationAuthoring(authored) => {
			store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(preliminary))
			geometry = derive_run_geometry(text)?
			grouped = group_link_annotations(store, text, geometry.rects, authored.links, page_count)?
			underlined = match authored.underline {
				NoUnderline => text
				Underline(underline) => {
					rules = underline_rules(text, authored.links, store, underline)?
					if rules.is_empty() text else KernelFacadeText.Plan.with_rules(text, merge_rules(KernelFacadeText.Plan.rules(text), rules))
				}
			}
			patch = patch_spine(store, authored.links, grouped.per_link)?
			navigation_input = {
				annotations: grouped.annotations,
				destinations: authored.destinations,
				outline: authored.outline,
				page_labels: authored.page_labels,
			}
			context = {
				forms: 0,
				nodes: patch.nodes.len(),
				occurrences: store.occurrences.len(),
				pages: page_count,
				semantic_annotations: patch.annotations.len(),
			}
			validated = KernelNavigation.validate(navigation_input, context, navigation_limits) ? Navigation
			semantics = KernelTextSemantics.Plan.attach_fragments_navigation(
				preliminary,
				{ annotations: patch.annotations, content_spine: patch.content_spine, nodes: patch.nodes },
				arena.fragments,
				page_count,
				page_count,
				semantic_limits,
			) ? TextSemantics
			Ok(KernelFacadeFragments.Plan.{ anchor_rects: geometry.rects, arena, navigation: WithNavigationStore(validated.store), semantics, text: underlined })
		}
	}
}

## The underline of every painted line run of a link: a filled rectangle
## in the run's fill color from its baseline start across its exact glyph
## advance sum, `offset` below the baseline, `thickness` tall. Repainted
## header runs and furniture are artifacts and join no link. Rules follow
## the runs' page order.
underline_rules : KernelFacadeText.Plan, List({ node : Semantics.NodeId, occurrences : Semantics.Range, target : [InternalDestination(Str), Uri(Str)] }), Semantics.Store, { offset : Layout.Unit, thickness : Layout.Unit } -> Try(List(KernelFacadePages.Rule), KernelFacadeFragments.Error)
underline_rules = |text_plan, links, store, underline| {
	owners = link_owners(links, store.occurrences.len())?
	sentinel = links.len()
	text = KernelFacadeText.Plan.text(text_plan)
	placements = KernelFacadeText.Plan.placements(text_plan)
	styles = KernelFacadeText.Plan.styles(text_plan)
	artifact_runs = KernelFacadeText.Plan.artifact_runs(text_plan)
	var $rules = []
	var $artifact_cursor = 0
	var $run_index = 0
	while $run_index < text.runs.len() {
		if $artifact_cursor < artifact_runs.len() and list_at(artifact_runs, $artifact_cursor) == $run_index {
			$artifact_cursor = $artifact_cursor + 1
		} else {
			run = list_at(text.runs, $run_index)
			owner = match run.unicode {
				OccurrenceText(occurrence) => if occurrence.index() < owners.len() list_at(owners, occurrence.index()) else sentinel
				_ => sentinel
			}
			if owner != sentinel {
				placement = list_at(placements, $run_index)
				var $width = 0
				var $glyph = run.glyphs.start()
				glyph_end = run.glyphs.start() + run.glyphs.length()
				while $glyph < glyph_end {
					$width = checked_i64(list_at(text.glyphs, $glyph).advance_x.raw(), $width)?
					$glyph = $glyph + 1
				}

				## A run that ends its line stops before the spaces it ends
				## with, which the line carries but never shows.
				next = $run_index + 1
				ends_line = next >= text.runs.len() or list_at(placements, next).page.index() != placement.page.index() or list_at(placements, next).origin.y.raw() != placement.origin.y.raw()
				trailing = if ends_line trailing_space_advance(text, run, store)? else 0
				visible = $width - trailing
				if visible > 0 {
					bottom = placement.origin.y.raw() - underline.offset.raw() - underline.thickness.raw()
					$rules = $rules.append({
						color: list_at(styles, $run_index).color,
						layer: Front,
						page: placement.page.index(),
						rect: {
							origin: { x: placement.origin.x, y: Layout.Unit.from_raw(bottom) },
							size: { height: underline.thickness, width: Layout.Unit.from_raw(visible) },
						},
					})
				}
			}
		}
		$run_index = $run_index + 1
	}
	Ok($rules)
}

## The advance of the U+0020 spaces a run ends with. The run's clusters are
## relative to its occurrence, whose text is a range of one source; each
## byte is read through a slice of the source, never a copy.
trailing_space_advance : Text.Store, Text.Run, Semantics.Store -> Try(I64, KernelFacadeFragments.Error)
trailing_space_advance = |text, run, store| {
	located = match run.unicode {
		OccurrenceText(occurrence) => match store.occurrences.get(occurrence.index()) {
			Ok({ source: Text(id, UnicodeRange(range)), .. }) => match store.text_sources.get(id.index()) {
				Ok(source) => Found({ base: range.utf8_bytes.start(), source: source.unicode })
				Err(OutOfBounds) => Missing
			}
			_ => Missing
		}
		_ => Missing
	}
	match located {
		Missing => Ok(0)
		Found({ base, source }) => {
			var $advance = 0
			var $cluster = run.clusters.start() + run.clusters.length()
			var $trimming = True
			while $trimming and $cluster > run.clusters.start() {
				cluster = list_at(text.clusters, $cluster - 1)
				space = cluster.source.utf8_bytes.length() == 1 and (match source.drop_first_bytes(base + cluster.source.utf8_bytes.start()) {
					Ok(rest) => rest.starts_with(" ")
					Err(_) => False
				})
				if space {
					var $reference = cluster.glyphs.start()
					while $reference < cluster.glyphs.start() + cluster.glyphs.length() {
						$advance = checked_i64($advance, list_at(text.glyphs, list_at(text.glyph_indices, $reference)).advance_x.raw())?
						$reference = $reference + 1
					}
					$cluster = $cluster - 1
				} else {
					$trimming = False
				}
			}
			Ok($advance)
		}
	}
}

## Two page-ordered rule lists as one: on each page the earlier list's
## rules (table rules) paint before the later list's (link underlines).
merge_rules : List(KernelFacadePages.Rule), List(KernelFacadePages.Rule) -> List(KernelFacadePages.Rule)
merge_rules = |first, second| {
	var $merged = List.with_capacity(first.len() + second.len())
	var $left = 0
	var $right = 0
	while $left < first.len() or $right < second.len() {
		take_left = $right >= second.len() or ($left < first.len() and list_at(first, $left).page <= list_at(second, $right).page)
		if take_left {
			$merged = $merged.append(list_at(first, $left))
			$left = $left + 1
		} else {
			$merged = $merged.append(list_at(second, $right))
			$right = $right + 1
		}
	}
	$merged
}

## One deterministic layout box per placed line run: the placement origin is
## the baseline start, the width is the run's exact glyph advance sum, the
## box rises one font size above the baseline, and the box height is the
## style leading (never less than the size).
derive_run_geometry : KernelFacadeText.Plan -> Try({ rects : List(KernelNavigation.AnchorRect) }, KernelFacadeFragments.Error)
derive_run_geometry = |text_plan| {
	text = KernelFacadeText.Plan.text(text_plan)
	placements = KernelFacadeText.Plan.placements(text_plan)
	styles = KernelFacadeText.Plan.styles(text_plan)
	artifact_runs = KernelFacadeText.Plan.artifact_runs(text_plan)
	var $rects = List.with_capacity(text.runs.len() - artifact_runs.len())
	var $artifact_cursor = 0
	var $run_index = 0
	while $run_index < text.runs.len() {
		if $artifact_cursor < artifact_runs.len() and list_at(artifact_runs, $artifact_cursor) == $run_index {
			## A repainted header run is a page artifact: it anchors no
			## destination and joins no link.
			$artifact_cursor = $artifact_cursor + 1
		} else {
			run = list_at(text.runs, $run_index)
			placement = list_at(placements, $run_index)
			var $width = 0
			var $glyph = run.glyphs.start()
			glyph_end = run.glyphs.start() + run.glyphs.length()
			while $glyph < glyph_end {
				$width = checked_i64(list_at(text.glyphs, $glyph).advance_x.raw(), $width)?
				$glyph = $glyph + 1
			}
			size = run.size.raw()
			leading = list_at(styles, $run_index).leading.raw()
			height = if leading > size leading else size
			top = checked_i64(placement.origin.y.raw(), size)?
			bottom = top - height
			$rects = $rects.append(
				AnchorAt({
					origin: { x: placement.origin.x, y: Layout.Unit.from_raw(bottom) },
					size: { height: Layout.Unit.from_raw(height), width: Layout.Unit.from_raw($width) },
				}),
			)
		}
		$run_index = $run_index + 1
	}
	Ok({ rects: $rects })
}

## Group each link's line runs by page, in run order: one annotation input
## per (link, page) with the page's line boxes as quadrilaterals and their
## union as the rectangle. Keyboard order is the per-page annotation
## creation order, which follows the links' spine order.
group_link_annotations : Semantics.Store, KernelFacadeText.Plan, List(KernelNavigation.AnchorRect), List({ node : Semantics.NodeId, occurrences : Semantics.Range, target : [InternalDestination(Str), Uri(Str)] }), U64 -> Try({ annotations : List(KernelNavigation.AnnotationInput), per_link : List(U64) }, KernelFacadeFragments.Error)
group_link_annotations = |store, text_plan, rects, links, page_count| {
	text = KernelFacadeText.Plan.text(text_plan)
	placements = KernelFacadeText.Plan.placements(text_plan)
	sentinel = links.len()
	link_of_occurrence = link_owners(links, store.occurrences.len())?

	## Per link: the list of page groups in ascending page order. Repainted
	## header runs are page artifacts and never join a link; `rects` holds
	## one box per fragment (every other run, in order).
	artifact_runs = KernelFacadeText.Plan.artifact_runs(text_plan)
	var $groups = List.repeat([], links.len())
	var $artifact_cursor = 0
	var $fragment = 0
	var $run_index = 0
	while $run_index < text.runs.len() {
		run = list_at(text.runs, $run_index)
		artifact = $artifact_cursor < artifact_runs.len() and list_at(artifact_runs, $artifact_cursor) == $run_index
		if artifact {
			$artifact_cursor = $artifact_cursor + 1
		}
		owner = if artifact sentinel else {
			match run.unicode {
				OccurrenceText(occurrence) => list_at(link_of_occurrence, occurrence.index())
				ArtifactText(_) => return Err(InvalidRun({ run: $run_index }))
			}
		}
		if owner != sentinel {
			placement = list_at(placements, $run_index)
			quad = match list_at(rects, $fragment) {
				AnchorAt(rect) => {
					x_left: rect.origin.x,
					x_right: Layout.Unit.from_raw(checked_i64(rect.origin.x.raw(), rect.size.width.raw())?),
					y_bottom: rect.origin.y,
					y_top: Layout.Unit.from_raw(checked_i64(rect.origin.y.raw(), rect.size.height.raw())?),
				}
				NoAnchor => {
					crash "facade run geometry escaped"
				}
			}
			var $link_groups = list_at($groups, owner)
			appended = match $link_groups.last() {
				Ok(group) => if group.page == placement.page.index() {
					## Adjacent runs of one link on one line (an inline link
					## containing differently styled text) extend the line's
					## quadrilateral rather than adding a second one, so each
					## painted line of a link contributes exactly one quad.
					quads = match group.quads.last() {
						Ok(previous) => if previous.y_bottom.raw() == quad.y_bottom.raw() and previous.y_top.raw() == quad.y_top.raw() and previous.x_right.raw() == quad.x_left.raw() {
							list_set(group.quads, group.quads.len() - 1, { ..previous, x_right: quad.x_right })
						} else {
							group.quads.append(quad)
						}
						Err(_) => group.quads.append(quad)
					}
					updated = { ..group, quads }
					{ groups: list_set($link_groups, $link_groups.len() - 1, updated), new_group: Bool.False }
				} else {
					{ groups: $link_groups.append({ page: placement.page.index(), quads: [quad] }), new_group: Bool.True }
				}
				Err(_) => { groups: $link_groups.append({ page: placement.page.index(), quads: [quad] }), new_group: Bool.True }
			}
			$groups = list_set($groups, owner, appended.groups)
		}
		if !artifact {
			$fragment = $fragment + 1
		}
		$run_index = $run_index + 1
	}

	var $annotations = []
	var $per_link = List.with_capacity(links.len())
	var $page_counters = List.repeat(0, page_count)
	var $link_index = 0
	while $link_index < links.len() {
		link = list_at(links, $link_index)
		link_groups = list_at($groups, $link_index)
		$per_link = $per_link.append(link_groups.len())
		var $group_index = 0
		while $group_index < link_groups.len() {
			group = list_at(link_groups, $group_index)
			rect = union_quads(group.quads)?
			keyboard_order = list_at($page_counters, group.page)
			$page_counters = list_set($page_counters, group.page, keyboard_order + 1)
			action = match link.target {
				Uri(uri) => Uri(uri)
				InternalDestination(name) => GoToName(name)
			}
			$annotations = $annotations.append({
				action,
				appearance: NoAppearance,
				description: NoDescription,
				keyboard_order,
				page: Semantics.PageId.from_index(group.page),
				print: Bool.True,
				quads: group.quads,
				rect,
			})
			$group_index = $group_index + 1
		}
		$link_index = $link_index + 1
	}
	Ok({ annotations: $annotations, per_link: $per_link })
}

## The owning link of every occurrence (`links.len()` for none), in one
## flat pass over the links' dense occurrence ranges.
link_owners : List({ node : Semantics.NodeId, occurrences : Semantics.Range, target : [InternalDestination(Str), Uri(Str)] }), U64 -> Try(List(U64), KernelFacadeFragments.Error)
link_owners = |links, occurrence_count| {
	sentinel = links.len()
	var $owners = List.repeat(sentinel, occurrence_count)
	var $link_index = 0
	var $occurrence = 0
	var $link_end = 0
	while $link_index < links.len() {
		if $occurrence < $link_end {
			$owners = list_set($owners, $occurrence, $link_index)
			$occurrence = $occurrence + 1
			if $occurrence == $link_end {
				$link_index = $link_index + 1
			}
		} else {
			link = list_at(links, $link_index)
			first = link.occurrences.start()
			count = link.occurrences.length()
			if count == 0 or first >= occurrence_count or count > occurrence_count - first {
				return Err(InvalidOccurrence({ available: occurrence_count, run: first }))
			}
			$occurrence = first
			$link_end = first + count
		}
	}
	Ok($owners)
}

union_quads : List(KernelNavigation.Quad) -> Try(Layout.Rect, KernelFacadeFragments.Error)
union_quads = |quads| {
	first = match quads.first() {
		Ok(quad) => quad
		Err(_) => {
			crash "facade link annotation without quads escaped"
		}
	}
	var $x_left = first.x_left.raw()
	var $x_right = first.x_right.raw()
	var $y_bottom = first.y_bottom.raw()
	var $y_top = first.y_top.raw()
	var $index = 1
	while $index < quads.len() {
		quad = list_at(quads, $index)
		$x_left = I64.min($x_left, quad.x_left.raw())
		$x_right = I64.max($x_right, quad.x_right.raw())
		$y_bottom = I64.min($y_bottom, quad.y_bottom.raw())
		$y_top = I64.max($y_top, quad.y_top.raw())
		$index = $index + 1
	}
	Ok({
		origin: { x: Layout.Unit.from_raw($x_left), y: Layout.Unit.from_raw($y_bottom) },
		size: { height: Layout.Unit.from_raw($y_top - $y_bottom), width: Layout.Unit.from_raw($x_right - $x_left) },
	})
}

## Rebuild the content spine with each Link node's per-page annotation
## occurrences appended to its span, in node order, assigning dense
## annotation identities and logical ranks in the same pass.
patch_spine : Semantics.Store, List({ node : Semantics.NodeId, occurrences : Semantics.Range, target : [InternalDestination(Str), Uri(Str)] }), List(U64) -> Try({ annotations : List(Semantics.Annotation), content_spine : List(Semantics.ContentSpineItem), nodes : List(Semantics.Node) }, KernelFacadeFragments.Error)
patch_spine = |store, links, per_link| {
	sentinel = links.len()
	var $link_of_node = List.repeat(sentinel, store.nodes.len())
	var $link_index = 0
	while $link_index < links.len() {
		link = list_at(links, $link_index)
		if link.node.index() >= store.nodes.len() {
			return Err(InvalidOccurrence({ available: store.nodes.len(), run: link.node.index() }))
		}
		$link_of_node = list_set($link_of_node, link.node.index(), $link_index)
		$link_index = $link_index + 1
	}
	var $annotation_starts = List.with_capacity(links.len())
	var $running = 0
	$link_index = 0
	while $link_index < links.len() {
		$annotation_starts = $annotation_starts.append($running)
		$running = checked_add($running, list_at(per_link, $link_index))?
		$link_index = $link_index + 1
	}
	total = $running
	var $spine = List.with_capacity(checked_add(store.content_spine.len(), total)?)
	var $nodes = store.nodes
	var $annotations = List.with_capacity(total)
	var $logical = 0
	var $node_index = 0
	while $node_index < store.nodes.len() {
		node = list_at(store.nodes, $node_index)
		new_start = $spine.len()
		var $item = node.content.start()
		item_end = node.content.start() + node.content.length()
		while $item < item_end {
			$spine = $spine.append(list_at(store.content_spine, $item))
			$item = $item + 1
		}
		owner_link = list_at($link_of_node, $node_index)
		if owner_link != sentinel {
			count = list_at(per_link, owner_link)
			start = list_at($annotation_starts, owner_link)
			var $slot = 0
			while $slot < count {
				annotation_id = start + $slot
				$spine = $spine.append(AnnotationOccurrence(Semantics.AnnotationId.from_index(annotation_id)))
				$annotations = $annotations.append({
					id: Semantics.AnnotationId.from_index(annotation_id),
					logical_order: $logical,
					owner: node.id,
				})
				$logical = $logical + 1
				$slot = $slot + 1
			}
		}
		$nodes = list_set($nodes, $node_index, { ..node, content: Semantics.Range.from_start_and_length(new_start, $spine.len() - new_start) })
		$node_index = $node_index + 1
	}
	Ok({ annotations: $annotations, content_spine: $spine, nodes: $nodes })
}

checked_i64 : I64, I64 -> Try(I64, KernelFacadeFragments.Error)
checked_i64 = |left, right| match I64.plus_try(left, right) {
	Ok(value) => Ok(value)
	Err(_) => Err(ArithmeticOverflow)
}

prepare_text : KernelFacadeText.Plan -> KernelFacadeFragments.Prepared
prepare_text = |text_plan| {
	pages: KernelFacadeText.Plan.pages(text_plan),
	placements: KernelFacadeText.Plan.placements(text_plan),
	text: KernelFacadeText.Plan.text(text_plan),
}

## `artifact_runs` (ascending) are repainted header runs: page artifacts
## with no layout fragment. Every other run is one fragment, dense in run
## order.
build_arena : KernelTextSemantics.Plan, KernelFacadeFragments.Prepared, List(U64), KernelFacadeFragments.Limits -> Try(KernelFacadeFragments.Arena, KernelFacadeFragments.Error)
build_arena = |preliminary, prepared, artifact_runs, limits| {
	semantic_store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(preliminary))
	text = prepared.text
	placements = prepared.placements
	pages = prepared.pages
	if semantic_store.fragments.len() != 0 or semantic_store.occurrence_fragments.len() != 0 {
		return Err(InvalidPreliminaryFragments({ fragments: semantic_store.fragments.len(), reverse_entries: semantic_store.occurrence_fragments.len() }))
	}
	check_limit(text.runs.len(), limits.max_fragments, Fragments)?
	check_limit(semantic_store.occurrences.len(), limits.max_occurrences, Occurrences)?
	check_limit(pages.len(), limits.max_pages, Pages)?
	if placements.len() != text.runs.len() {
		return Err(InvalidPlacement({ placement: placements.len() }))
	}
	var $occurrence_index = 0
	while $occurrence_index < semantic_store.occurrences.len() {
		if list_at(semantic_store.occurrences, $occurrence_index).fragments.length() != 0 {
			return Err(InvalidPreliminaryFragments({ fragments: semantic_store.fragments.len(), reverse_entries: semantic_store.occurrence_fragments.len() }))
		}
		$occurrence_index = $occurrence_index + 1
	}
	var $placement_cursor = 0
	var $page_index = 0
	while $page_index < pages.len() {
		page = list_at(pages, $page_index)
		if page.id.index() != $page_index or page.runs.start() != $placement_cursor or !range_fits(page.runs, placements.len()) {
			return Err(InvalidPage({ page: $page_index }))
		}
		page_end = checked_add(page.runs.start(), page.runs.length())?
		while $placement_cursor < page_end {
			placement = list_at(placements, $placement_cursor)
			if placement.page.index() != $page_index or placement.run.index() != $placement_cursor {
				return Err(InvalidPlacement({ placement: $placement_cursor }))
			}
			$placement_cursor = $placement_cursor + 1
		}
		$page_index = $page_index + 1
	}
	if $placement_cursor != placements.len() {
		return Err(InvalidPlacement({ placement: $placement_cursor }))
	}
	var $continuations = List.repeat(0, semantic_store.occurrences.len())
	var $fragments = List.with_capacity(text.runs.len() - artifact_runs.len())
	var $artifact_cursor = 0
	var $run_index = 0
	while $run_index < text.runs.len() {
		run = list_at(text.runs, $run_index)
		placement = list_at(placements, $run_index)
		if run.id.index() != $run_index or placement.run.index() != $run_index {
			return Err(InvalidRun({ run: $run_index }))
		}
		artifact = $artifact_cursor < artifact_runs.len() and list_at(artifact_runs, $artifact_cursor) == $run_index
		if artifact {
			$artifact_cursor = $artifact_cursor + 1
		} else {
			occurrence_id = match run.unicode {
				OccurrenceText(id) => id
				ArtifactText(_) => return Err(InvalidRun({ run: $run_index }))
			}
			occurrence_index = occurrence_id.index()
			if occurrence_index >= semantic_store.occurrences.len() {
				return Err(InvalidOccurrence({ available: semantic_store.occurrences.len(), run: $run_index }))
			}
			occurrence = list_at(semantic_store.occurrences, occurrence_index)
			occurrence_range = match occurrence.source {
				Text(_, UnicodeRange(range)) => range
				_ => return Err(SourceRangeMismatch({ run: $run_index }))
			}
			if !relative_range_fits(run.source, occurrence_range) {
				return Err(SourceRangeMismatch({ run: $run_index }))
			}
			fragment_range = {
				scalars: Semantics.Range.from_start_and_length(checked_add(occurrence_range.scalars.start(), run.source.scalars.start())?, run.source.scalars.length()),
				utf8_bytes: Semantics.Range.from_start_and_length(checked_add(occurrence_range.utf8_bytes.start(), run.source.utf8_bytes.start())?, run.source.utf8_bytes.length()),
			}
			continuation = list_at($continuations, occurrence_index)
			$continuations = list_set($continuations, occurrence_index, checked_add(continuation, 1)?)
			$fragments = $fragments.append({
				content_stream: Semantics.ContentStreamId.from_index(placement.page.index()),
				continuation_index: continuation,
				id: Semantics.FragmentId.from_index($fragments.len()),
				occurrence: occurrence_id,
				page: placement.page,
				source_range: UnicodeRange(fragment_range),
			})
		}
		$run_index = $run_index + 1
	}
	Ok(
		KernelFacadeFragments.Arena.{
			fragments: $fragments,
			work: {
				continuation_reads: $fragments.len(),
				continuation_writes: $fragments.len(),
				fragment_writes: $fragments.len(),
				page_visits: pages.len(),
				placement_visits: placements.len(),
			},
		},
	)
}

relative_range_fits : Semantics.TextRange, Semantics.TextRange -> Bool
relative_range_fits = |relative, occurrence| range_fits(relative.scalars, occurrence.scalars.length()) and range_fits(relative.utf8_bytes, occurrence.utf8_bytes.length())

range_fits : Semantics.Range, U64 -> Bool
range_fits = |range, available| range.start() <= available and range.length() <= available - range.start()

check_limit : U64, U64, KernelFacadeFragments.Dimension -> Try({}, KernelFacadeFragments.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelFacadeFragments.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Ok(value) => Ok(value)
	Err(_) => Err(ArithmeticOverflow)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated facade-fragment index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated facade-fragment update escaped"
	}
}
