import Color
import Document
import Image
import KernelColor
import KernelFacadeFragments
import KernelFacadeFurniture
import KernelFacadePages
import KernelFacadeShape
import KernelFacadeText
import KernelScene
import KernelSemantics
import KernelSrgbProfile
import KernelTextOwnership
import KernelTextSemantics
import Layout
import Scene
import Semantics
import Text

KernelFacadeScenes :: [].{
	Dimension : [Commands, Groups, PageGroupEdges, Pages]

	## Whether the validated color store carries the packaged sRGB profile for
	## the document's output intent. Painting is unaffected: the profile joins
	## the store (and its validation and object plan) without adding a color
	## space, so plans without an intent stay byte-identical.
	IntentProfile : [NoIntentProfile, PackagedSrgbIntent]
	Error : [
		ArithmeticOverflow,
		Color(KernelColor.Error),
		InvalidPage({ page : U64 }),
		InvalidPageSize,
		InvalidPlacement({ placement : U64 }),
		InvalidStyleCount({ runs : U64, styles : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		Ownership(KernelTextOwnership.Error),
		Scene(KernelScene.Error),
		UnsupportedColor({ run : U64 }),
	]
	Limits :: {
		color : KernelColor.Limits,
		max_commands : U64,
		max_groups : U64,
		max_page_group_edges : U64,
		max_pages : U64,
		scene : KernelScene.Limits,
	}.{
		make : {
			color : KernelColor.Limits,
			max_commands : U64,
			max_groups : U64,
			max_page_group_edges : U64,
			max_pages : U64,
			scene : KernelScene.Limits,
		} -> Limits
		make = |limits| Limits.(limits)
	}
	Prepared : {
		page_size : Layout.Size,
		pages : List(KernelFacadeText.Page),
		placements : List(KernelFacadeText.Placement),
		styles : List(KernelFacadeShape.RunStyle),
		text : Text.Store,
	}
	ArenaPrepared : {
		page_size : Layout.Size,
		pages : List(KernelFacadeText.Page),
		placements : List(KernelFacadeText.Placement),
		styles : List(KernelFacadeShape.RunStyle),
		text_runs : U64,
	}
	Work : {
		color_checks : U64,
		command_writes : U64,
		group_writes : U64,
		page_group_writes : U64,
		page_writes : U64,
		placement_visits : U64,
	}
	Arena :: { colors : Color.Store, images : Image.SourceStore, scenes : Scene.Store, work : Work }.{
		build_prepared : ArenaPrepared, Limits -> Try(Arena, Error)
		build_prepared = |prepared, limits| build_arena(prepared, limits)

		colors : Arena -> Color.Store
		colors = |arena| arena.colors

		images : Arena -> Image.SourceStore
		images = |arena| arena.images

		scenes : Arena -> Scene.Store
		scenes = |arena| arena.scenes

		work : Arena -> Work
		work = |arena| arena.work
	}
	Plan :: { colors : KernelColor.Plan, images : Image.SourceStore, ownership : KernelTextOwnership.Plan, scene : KernelScene.Plan, work : Work }.{
		build : KernelFacadeFragments.Plan, Layout.Size, Limits -> Try(Plan, Error)
		build = |fragments, page_size, limits| build_plan(fragments, page_size, empty_authoring, NoIntentProfile, limits)

		build_with_intent : KernelFacadeFragments.Plan, Layout.Size, IntentProfile, Limits -> Try(Plan, Error)
		build_with_intent = |fragments, page_size, intent, limits| build_plan(fragments, page_size, empty_authoring, intent, limits)

		build_authoring_with_intent : KernelFacadeFragments.Plan, Layout.Size, Document.NormalizedAuthoring, IntentProfile, Limits -> Try(Plan, Error)
		build_authoring_with_intent = |fragments, page_size, authoring, intent, limits| build_plan(fragments, page_size, authoring, intent, limits)

		build_prepared : KernelTextSemantics.Plan, Prepared, Limits -> Try(Plan, Error)
		build_prepared = |semantics, prepared, limits| build_validated(
			semantics,
			{
				artifact_kinds: RepeatedHeaders,
				artifact_runs: [],
				authoring: empty_authoring,
				flow: no_flow,
				furniture: NoFurniture,
				page_size: prepared.page_size,
				pages: prepared.pages,
				placements: prepared.placements,
				rules: [],
				styles: prepared.styles,
				text: prepared.text,
			},
			NoIntentProfile,
			limits,
		)

		colors : Plan -> KernelColor.Plan
		colors = |plan| plan.colors

		images : Plan -> Image.SourceStore
		images = |plan| plan.images

		ownership : Plan -> KernelTextOwnership.Plan
		ownership = |plan| plan.ownership

		## Downstream resource and content lowering consume the already-validated
		## scene plan rather than rebuilding it from incidental arena data.
		scene : Plan -> KernelScene.Plan
		scene = |plan| plan.scene

		work : Plan -> Work
		work = |plan| plan.work
	}
}

InternalPrepared : {
	artifact_kinds : KernelFacadeText.ArtifactKinds,
	artifact_runs : List(U64),
	authoring : Document.NormalizedAuthoring,
	furniture : [NoFurniture, WithFurniture(KernelFacadeFurniture.Plan)],
	flow : KernelFacadePages.FlowPaints,
	page_size : Layout.Size,
	pages : List(KernelFacadeText.Page),
	placements : List(KernelFacadeText.Placement),
	rules : List(KernelFacadePages.Rule),
	styles : List(KernelFacadeShape.RunStyle),
	text : Text.Store,
}

## `artifact_runs` (ascending) are repainted header runs, owned by a
## `RepeatedHeader` page artifact rather than a fragment; `rules` are table
## rules painted as `Decoration` artifacts at the end of their page.
InternalArenaPrepared : {
	artifact_kinds : KernelFacadeText.ArtifactKinds,
	artifact_runs : List(U64),
	authoring : Document.NormalizedAuthoring,
	figure_by_occurrence : List([Figure(U64), NoFigure]),
	flow : KernelFacadePages.FlowPaints,
	furniture : [NoFurniture, WithFurniture(KernelFacadeFurniture.Plan)],
	page_size : Layout.Size,
	pages : List(KernelFacadeText.Page),
	placements : List(KernelFacadeText.Placement),
	rules : List(KernelFacadePages.Rule),
	run_unicode : List(Text.RunUnicode),
	styles : List(KernelFacadeShape.RunStyle),
}

no_flow : KernelFacadePages.FlowPaints
no_flow = { decorations: [], figure_scales: [], panels: [] }

empty_authoring : Document.NormalizedAuthoring
empty_authoring = { blocks: [], cells: [], customs: [], decorations: [], figures: [], groups: [], inlines: [], language: "", line_breaks: [], lists: [], metadata_title: "", outline: [], page_breaks: [], page_labels: [], rich_paragraphs: [], scopes: [], spacers: [], tables: [], templates: NoTemplates }

build_plan : KernelFacadeFragments.Plan, Layout.Size, Document.NormalizedAuthoring, KernelFacadeScenes.IntentProfile, KernelFacadeScenes.Limits -> Try(KernelFacadeScenes.Plan, KernelFacadeScenes.Error)
build_plan = |fragment_plan, page_size, authoring, intent, limits| {
	text_plan = KernelFacadeFragments.Plan.text(fragment_plan)
	text = KernelFacadeText.Plan.text(text_plan)
	prepared = {
		artifact_kinds: KernelFacadeText.Plan.artifact_kinds(text_plan),
		artifact_runs: KernelFacadeText.Plan.artifact_runs(text_plan),
		authoring,
		flow: KernelFacadeText.Plan.flow(text_plan),
		furniture: KernelFacadeText.Plan.furniture(text_plan),
		page_size,
		pages: KernelFacadeText.Plan.pages(text_plan),
		placements: KernelFacadeText.Plan.placements(text_plan),
		rules: KernelFacadeText.Plan.rules(text_plan),
		styles: KernelFacadeText.Plan.styles(text_plan),
		text,
	}
	build_validated(KernelFacadeFragments.Plan.semantics(fragment_plan), prepared, intent, limits)
}

build_validated : KernelTextSemantics.Plan, InternalPrepared, KernelFacadeScenes.IntentProfile, KernelFacadeScenes.Limits -> Try(KernelFacadeScenes.Plan, KernelFacadeScenes.Error)
build_validated = |semantics, prepared, intent, limits| {
	text = prepared.text
	semantic_store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(semantics))
	arena_prepared = prepare_arena(prepared)
	figure_by_occurrence = if prepared.authoring.figures.is_empty() [] else index_figures(semantic_store, prepared.authoring.figures.len())?
	arena = build_arena_with_intent({ ..arena_prepared, figure_by_occurrence }, intent, limits)?
	colors = KernelColor.Plan.build(arena.colors, limits.color) ? Color
	scene = KernelScene.Plan.build(
		arena.scenes,
		KernelScene.Resources.with_text({ color_spaces: arena.colors.spaces.len(), images: arena.images.resources.len(), text_runs: text.runs.len() }),
		limits.scene,
	) ? Scene
	ownership = (if prepared.artifact_runs.is_empty() KernelTextOwnership.Plan.build(semantics, scene, text) else KernelTextOwnership.Plan.build_with_artifact_text(semantics, scene, text)) ? Ownership
	Ok(KernelFacadeScenes.Plan.{ colors, images: arena.images, ownership, scene, work: arena.work })
}

prepare_arena : InternalPrepared -> InternalArenaPrepared
prepare_arena = |prepared| {
	artifact_kinds: prepared.artifact_kinds,
	artifact_runs: prepared.artifact_runs,
	authoring: prepared.authoring,
	flow: prepared.flow,
	furniture: prepared.furniture,
	page_size: prepared.page_size,
	pages: prepared.pages,
	placements: prepared.placements,
	rules: prepared.rules,
	styles: prepared.styles,
	run_unicode: prepared.text.runs.map(|run| run.unicode),
	figure_by_occurrence: [],
}

build_arena : KernelFacadeScenes.ArenaPrepared, KernelFacadeScenes.Limits -> Try(KernelFacadeScenes.Arena, KernelFacadeScenes.Error)
build_arena = |prepared, limits| build_arena_with_intent(
	{
		artifact_kinds: RepeatedHeaders,
		artifact_runs: [],
		authoring: empty_authoring,
		figure_by_occurrence: [],
		flow: no_flow,
		furniture: NoFurniture,
		page_size: prepared.page_size,
		pages: prepared.pages,
		placements: prepared.placements,
		rules: [],
		run_unicode: List.repeat(OccurrenceText(Semantics.OccurrenceId.from_index(0)), prepared.text_runs),
		styles: prepared.styles,
	},
	NoIntentProfile,
	limits,
)

build_arena_with_intent : InternalArenaPrepared, KernelFacadeScenes.IntentProfile, KernelFacadeScenes.Limits -> Try(KernelFacadeScenes.Arena, KernelFacadeScenes.Error)
build_arena_with_intent = |prepared, intent, limits| {
	if prepared.page_size.width.raw() <= 0 or prepared.page_size.height.raw() <= 0 {
		return Err(InvalidPageSize)
	}
	run_count = prepared.run_unicode.len()
	rule_count = prepared.rules.len()

	## Page furniture drawings paint as page-artifact groups: one transform
	## to the item's bottom-left corner around the drawing's commands.
	furniture = furniture_facts(prepared.furniture)
	paint_count = furniture.paints.len()
	furniture_counts = drawing_counts(furniture)?

	## Figure and decoration drawings: figure `k` paints inside the group of
	## its anchor line's run, and each decoration is one page-artifact group.
	flow = flow_facts(prepared.authoring, prepared.flow)?
	decoration_count = prepared.flow.decorations.len()
	panel_count = prepared.flow.panels.len()
	command_count = checked_add(checked_add(checked_add(checked_times(run_count, 2)?, flow.commands)?, rule_count)?, furniture_counts.commands)?
	group_count = checked_add(checked_add(checked_add(checked_add(run_count, rule_count)?, paint_count)?, decoration_count)?, panel_count)?
	check_limit(command_count, limits.max_commands, Commands)?
	check_limit(group_count, limits.max_groups, Groups)?
	check_limit(group_count, limits.max_page_group_edges, PageGroupEdges)?
	check_limit(prepared.pages.len(), limits.max_pages, Pages)?
	if prepared.placements.len() != run_count {
		return Err(InvalidPlacement({ placement: prepared.placements.len() }))
	}
	if prepared.styles.len() != run_count {
		return Err(InvalidStyleCount({ runs: run_count, styles: prepared.styles.len() }))
	}
	page_box = {
		origin: { x: Layout.Unit.from_raw(0), y: Layout.Unit.from_raw(0) },
		size: prepared.page_size,
	}
	has_rgb_images = flow.images.any(|image| !source_is_gray(image)) or furniture.images.any(|image| !source_is_gray(image))
	has_gray_images = flow.images.any(|image| source_is_gray(image)) or furniture.images.any(|image| source_is_gray(image))
	use_srgb = match intent {
		NoIntentProfile => False
		PackagedSrgbIntent => has_nonblack_srgb(prepared.styles) or has_rgb_images or prepared.rules.any(|rule| nonblack(rule.color)) or furniture_counts.nonblack or flow.nonblack
	}

	## Every flow path's paint is proven convertible before any scene
	## accumulator grows, so painting never exits on an error.
	check_flow_colors(prepared.authoring, intent, use_srgb) ? |_| UnsupportedColor({ run: 0 })
	color_checks = match intent {
		NoIntentProfile => run_count
		PackagedSrgbIntent => checked_add(run_count, run_count)?
	}
	var $commands = List.with_capacity(command_count)
	var $groups = List.with_capacity(group_count)
	var $page_groups = List.with_capacity(group_count)
	path_count = checked_add(checked_add(rule_count, furniture_counts.paths)?, flow.paths)?
	var $paths = if path_count == 0 [] else List.with_capacity(path_count)
	var $path_segments = if path_count == 0 [] else List.with_capacity(checked_add(checked_add(rule_count, furniture_counts.segments)?, flow.segments)?)
	var $paint_cursor = 0
	var $decoration_cursor = 0
	var $panel_cursor = 0
	var $artifact_cursor = 0
	var $fragment = 0
	var $rule_cursor = 0
	var $pages = List.with_capacity(prepared.pages.len())
	var $painted_figures = if prepared.authoring.figures.is_empty() [] else List.repeat(False, prepared.authoring.figures.len())
	var $placement_cursor = 0
	var $page_index = 0
	while $page_index < prepared.pages.len() {
		page = list_at(prepared.pages, $page_index)
		if page.id.index() != $page_index or page.runs.start() != $placement_cursor or !range_fits(page.runs, run_count) {
			return Err(InvalidPage({ page: $page_index }))
		}
		paint_start = $page_groups.len()
		page_end = checked_add(page.runs.start(), page.runs.length())?

		## One loop per page paints the page's text placements and then its
		## table rules. Two consecutive inner loops over the same accumulators
		## copied `$commands`, `$groups`, and `$page_groups` once per page: the
		## first loop's exit state reached the second loop's entry through an
		## aggregate that still held them (docs/performance/emission-linearity.md).
		while ($panel_cursor < panel_count and list_at(prepared.flow.panels, $panel_cursor).page == $page_index) or $placement_cursor < page_end or ($rule_cursor < rule_count and list_at(prepared.rules, $rule_cursor).page == $page_index) or ($decoration_cursor < decoration_count and list_at(prepared.flow.decorations, $decoration_cursor).page == $page_index) or ($paint_cursor < paint_count and list_at(furniture.paints, $paint_cursor).page == $page_index) {
			## A template region's backdrops paint first on their page,
			## through the furniture branch below, behind everything else.
			backdrop_ready = $paint_cursor < paint_count and list_at(furniture.paints, $paint_cursor).page == $page_index and list_at(furniture.paints, $paint_cursor).behind
			if !backdrop_ready and $panel_cursor < panel_count and list_at(prepared.flow.panels, $panel_cursor).page == $page_index {
				## A custom block's panel paints first on its page, behind
				## the text it frames: one `Decoration` page-artifact group,
				## a transform to its measured box's bottom-left corner
				## around its paths.
				paint = list_at(prepared.flow.panels, $panel_cursor)
				panel = list_at(flow.panels, paint.custom)
				command_start = $commands.len()
				$commands = $commands.append(
					Transform({
						children: Semantics.Range.from_start_and_length(command_start + 1, panel.commands.len()),
						matrix: {
							a: Layout.Unit.from_raw(1000),
							b: Layout.Unit.from_raw(0),
							c: Layout.Unit.from_raw(0),
							d: Layout.Unit.from_raw(1000),
							e: paint.origin.x,
							f: paint.origin.y,
						},
					}),
				)
				for drawing_command in panel.commands {
					match drawing_command {
						FlowImage(_) => {}
						FlowText(_) => {}
						FlowPath({ fill, segments, stroke }) => {
							path = Scene.PathId.from_index($paths.len())
							$paths = $paths.append({ id: path, segments: Semantics.Range.from_start_and_length($path_segments.len(), segments.len()) })
							for segment in segments {
								$path_segments = $path_segments.append(segment)
							}
							$commands = $commands.append(DrawPath({ path, style: checked_flow_style(fill, stroke, intent, use_srgb) }))
						}
					}
				}
				group = Scene.GroupId.from_index($groups.len())
				$groups = $groups.append({ commands: Semantics.Range.from_start_and_length(command_start, 1), id: group, owner: PageArtifact(Decoration) })
				$page_groups = $page_groups.append(group)
				$panel_cursor = $panel_cursor + 1
			} else if !backdrop_ready and $placement_cursor < page_end and !($rule_cursor < rule_count and list_at(prepared.rules, $rule_cursor).page == $page_index and list_at(prepared.rules, $rule_cursor).layer == Behind) {
				## Table row and cell fills (`Behind` rules, first on their
				## page) paint through the rule branch below before any of the
				## page's text.
				placement = list_at(prepared.placements, $placement_cursor)
				if placement.page.index() != $page_index or placement.run.index() != $placement_cursor {
					return Err(InvalidPlacement({ placement: $placement_cursor }))
				}
				style = list_at(prepared.styles, $placement_cursor)
				paint = match style.color {
					Srgb(Rgb(channels)) => match intent {
						NoIntentProfile => if channels.red == 0 and channels.green == 0 and channels.blue == 0 {
							{
								fill: { channels: Gray(0), space: Color.SpaceId.from_index(0) },
								mode: Fill,
								opacity: 65535,
								stroke: NoStroke,
							}
						} else {
							return Err(UnsupportedColor({ run: $placement_cursor }))
						}
						PackagedSrgbIntent => if use_srgb {
							{
								fill: { channels: Rgb(channels), space: Color.SpaceId.from_index(0) },
								mode: Fill,
								opacity: 65535,
								stroke: NoStroke,
							}
						} else {
							{
								fill: { channels: Gray(0), space: Color.SpaceId.from_index(0) },
								mode: Fill,
								opacity: 65535,
								stroke: NoStroke,
							}
						}
					}
					_ => return Err(UnsupportedColor({ run: $placement_cursor }))
				}
				figure = match list_at(prepared.run_unicode, $placement_cursor) {
					OccurrenceText(occurrence) => if occurrence.index() < prepared.figure_by_occurrence.len() list_at(prepared.figure_by_occurrence, occurrence.index()) else NoFigure
					ArtifactText(_) => NoFigure
				}
				command_start = $commands.len()
				first_figure = match figure {
					NoFigure => NoFigure
					Figure(figure_index) => if list_at($painted_figures, figure_index) NoFigure else Figure(figure_index)
				}

				## A figure's anchor line group has two roots: the drawing,
				## scaled uniformly about its bottom-left corner on the line's
				## baseline, then the anchor text. Their children follow.
				drawing = match first_figure {
					NoFigure => NoDrawing
					Figure(figure_index) => FigureDrawing({ drawing: list_at(flow.figures, figure_index), figure: figure_index, scale: list_at(prepared.flow.figure_scales, figure_index) })
				}
				drawn = match drawing {
					NoDrawing => 0
					FigureDrawing(value) => value.drawing.commands.len()
				}
				roots = if drawn == 0 1 else 2
				group_length = roots
				text_command = command_start + roots + drawn
				match drawing {
					NoDrawing => {}
					FigureDrawing({ drawing: figure_drawing, figure: figure_index, scale }) => {
						$commands = $commands.append(
							Transform({
								children: Semantics.Range.from_start_and_length(command_start + 2, drawn),
								matrix: {
									a: Layout.Unit.from_raw(scale.to_i64_wrap()),
									b: Layout.Unit.from_raw(0),
									c: Layout.Unit.from_raw(0),
									d: Layout.Unit.from_raw(scale.to_i64_wrap()),
									e: placement.origin.x,
									f: placement.origin.y,
								},
							}),
						)
						$painted_figures = list_set($painted_figures, figure_index, True)
						$commands = $commands.append(
							Transform({
								children: Semantics.Range.from_start_and_length(text_command, 1),
								matrix: {
									a: Layout.Unit.from_raw(1000),
									b: Layout.Unit.from_raw(0),
									c: Layout.Unit.from_raw(0),
									d: Layout.Unit.from_raw(1000),
									e: placement.origin.x,
									f: placement.origin.y,
								},
							}),
						)
						for drawing_command in figure_drawing.commands {
							match drawing_command {
								FlowImage({ image, placement: image_placement }) => {
									$commands = $commands.append(DrawImage({ image: Image.Id.from_index(figure_drawing.image_base + image), placement: image_placement }))
								}
								FlowText(_) => {}
								FlowPath({ fill, segments, stroke }) => {
									path = Scene.PathId.from_index($paths.len())
									$paths = $paths.append({ id: path, segments: Semantics.Range.from_start_and_length($path_segments.len(), segments.len()) })
									for segment in segments {
										$path_segments = $path_segments.append(segment)
									}
									$commands = $commands.append(DrawPath({ path, style: checked_flow_style(fill, stroke, intent, use_srgb) }))
								}
							}
						}
					}
				}
				if drawn == 0 {
					$commands = $commands.append(
						Transform({
							children: Semantics.Range.from_start_and_length(text_command, 1),
							matrix: {
								a: Layout.Unit.from_raw(1000),
								b: Layout.Unit.from_raw(0),
								c: Layout.Unit.from_raw(0),
								d: Layout.Unit.from_raw(1000),
								e: placement.origin.x,
								f: placement.origin.y,
							},
						}),
					)
				}
				$commands = $commands.append(DrawText({ paint, run: placement.run }))
				group = Scene.GroupId.from_index($groups.len())
				artifact = $artifact_cursor < prepared.artifact_runs.len() and list_at(prepared.artifact_runs, $artifact_cursor) == $placement_cursor
				owner = if artifact {
					kind = match prepared.artifact_kinds {
						RepeatedHeaders => RepeatedHeader
						Kinds(kinds) => list_at(kinds, $artifact_cursor)
					}
					$artifact_cursor = $artifact_cursor + 1
					PageArtifact(kind)
				} else {
					fragment = $fragment
					$fragment = $fragment + 1
					Fragment(Semantics.FragmentId.from_index(fragment))
				}
				$groups = $groups.append({
					commands: Semantics.Range.from_start_and_length(command_start, group_length),
					id: group,
					owner,
				})
				$page_groups = $page_groups.append(group)
				$placement_cursor = $placement_cursor + 1
			} else if !backdrop_ready and $rule_cursor < rule_count and list_at(prepared.rules, $rule_cursor).page == $page_index {
				## Table fills paint before the page's text and table rules and
				## link underlines after it, each a filled rectangle owned by a
				## layout decoration artifact.
				rule = list_at(prepared.rules, $rule_cursor)
				fill = match paint_color(rule.color, intent, use_srgb) {
					Ok(value) => value
					Err(_) => return Err(UnsupportedColor({ run: $placement_cursor }))
				}
				path = Scene.PathId.from_index($paths.len())
				$paths = $paths.append({ id: path, segments: Semantics.Range.from_start_and_length($path_segments.len(), 1) })
				$path_segments = $path_segments.append(Rectangle(rule.rect))
				command = $commands.len()
				$commands = $commands.append(DrawPath({ path, style: { fill: SolidFill({ color: fill, rule: Nonzero }), stroke: NoStroke } }))
				group = Scene.GroupId.from_index($groups.len())
				$groups = $groups.append({ commands: Semantics.Range.from_start_and_length(command, 1), id: group, owner: PageArtifact(Decoration) })
				$page_groups = $page_groups.append(group)
				$rule_cursor = $rule_cursor + 1
			} else if !backdrop_ready and $decoration_cursor < decoration_count and list_at(prepared.flow.decorations, $decoration_cursor).page == $page_index {
				## In-flow decorations paint after the page's text and table
				## rules, each one `Decoration` page-artifact group: a
				## transform to its bottom-left corner around its commands.
				paint = list_at(prepared.flow.decorations, $decoration_cursor)
				decoration = list_at(flow.decorations, paint.decoration)
				command_start = $commands.len()
				$commands = $commands.append(
					Transform({
						children: Semantics.Range.from_start_and_length(command_start + 1, decoration.commands.len()),
						matrix: {
							a: Layout.Unit.from_raw(1000),
							b: Layout.Unit.from_raw(0),
							c: Layout.Unit.from_raw(0),
							d: Layout.Unit.from_raw(1000),
							e: paint.origin.x,
							f: paint.origin.y,
						},
					}),
				)
				for drawing_command in decoration.commands {
					match drawing_command {
						FlowImage({ image, placement: image_placement }) => {
							$commands = $commands.append(DrawImage({ image: Image.Id.from_index(decoration.image_base + image), placement: image_placement }))
						}
						FlowText(_) => {}
						FlowPath({ fill, segments, stroke }) => {
							path = Scene.PathId.from_index($paths.len())
							$paths = $paths.append({ id: path, segments: Semantics.Range.from_start_and_length($path_segments.len(), segments.len()) })
							for segment in segments {
								$path_segments = $path_segments.append(segment)
							}
							$commands = $commands.append(DrawPath({ path, style: checked_flow_style(fill, stroke, intent, use_srgb) }))
						}
					}
				}
				group = Scene.GroupId.from_index($groups.len())
				$groups = $groups.append({ commands: Semantics.Range.from_start_and_length(command_start, 1), id: group, owner: PageArtifact(Decoration) })
				$page_groups = $page_groups.append(group)
				$decoration_cursor = $decoration_cursor + 1
			} else {
				## Furniture drawings paint last (region backdrops first), each
				## one page-artifact group:
				## a transform to its bottom-left corner around its images and
				## paths in drawing-local geometry.
				paint = list_at(furniture.paints, $paint_cursor)
				drawing = list_at(furniture.drawings, paint.drawing)
				command_start = $commands.len()
				$commands = $commands.append(
					Transform({
						children: Semantics.Range.from_start_and_length(command_start + 1, drawing.commands.len()),
						matrix: {
							a: Layout.Unit.from_raw(1000),
							b: Layout.Unit.from_raw(0),
							c: Layout.Unit.from_raw(0),
							d: Layout.Unit.from_raw(1000),
							e: paint.origin.x,
							f: paint.origin.y,
						},
					}),
				)
				for drawing_command in drawing.commands {
					match drawing_command {
						DrawingImage({ image, placement }) => {
							$commands = $commands.append(DrawImage({ image: Image.Id.from_index(flow.images.len() + image), placement }))
						}
						DrawingPath({ fill, segments, stroke }) => {
							path = Scene.PathId.from_index($paths.len())
							$paths = $paths.append({ id: path, segments: Semantics.Range.from_start_and_length($path_segments.len(), segments.len()) })
							for segment in segments {
								$path_segments = $path_segments.append(segment)
							}
							style = furniture_path_style(fill, stroke, intent, use_srgb) ? |_| UnsupportedColor({ run: $placement_cursor })
							$commands = $commands.append(DrawPath({ path, style }))
						}
					}
				}
				group = Scene.GroupId.from_index($groups.len())
				$groups = $groups.append({ commands: Semantics.Range.from_start_and_length(command_start, 1), id: group, owner: PageArtifact(paint.kind) })
				$page_groups = $page_groups.append(group)
				$paint_cursor = $paint_cursor + 1
			}
		}
		$pages = $pages.append({
			boxes: { art: page_box, bleed: page_box, crop: page_box, media: page_box, trim: page_box },
			id: page.id,
			paint_order: Semantics.Range.from_start_and_length(paint_start, $page_groups.len() - paint_start),
			rotation: Rotate0,
		})
		$page_index = $page_index + 1
	}
	if $placement_cursor != run_count {
		return Err(InvalidPlacement({ placement: $placement_cursor }))
	}
	if $painted_figures.any(|painted| !painted) or $decoration_cursor != decoration_count or $panel_cursor != panel_count {
		return Err(InvalidPlacement({ placement: $placement_cursor }))
	}
	gray_space = {
		id: Color.SpaceId.from_index(if use_srgb 1 else 0),
		space: CalibratedGray({
			black_point: { x: 0, y: 0, z: 0 },
			white_point: { x: 950000, y: 1000000, z: 1089000 },
		}),
	}
	painting_spaces = [
		{
			id: Color.SpaceId.from_index(0),
			space: CalibratedGray({
				black_point: { x: 0, y: 0, z: 0 },
				white_point: { x: 950000, y: 1000000, z: 1089000 },
			}),
		},
	]
	colors = match intent {
		NoIntentProfile => {
			profiles: [],
			spaces: painting_spaces,
			tags: [],
		}
		PackagedSrgbIntent => {
			profiles: [KernelSrgbProfile.profile(0, 0)],
			spaces: if use_srgb {
				rgb_space = { id: Color.SpaceId.from_index(0), space: Srgb(Color.ProfileId.from_index(0)) }
				if has_gray_images [rgb_space, gray_space] else [rgb_space]
			} else painting_spaces,
			tags: KernelSrgbProfile.tags,
		}
	}
	Ok(
		KernelFacadeScenes.Arena.{
			colors,
			images: authoring_images(flow.images, furniture.images, Color.SpaceId.from_index(0), gray_space.id),
			scenes: {
				commands: $commands,
				dash_lengths: [],
				groups: $groups,
				page_groups: $page_groups,
				pages: $pages,
				path_segments: $path_segments,
				paths: $paths,
			},
			work: {
				color_checks,
				command_writes: command_count,
				group_writes: group_count,
				page_group_writes: group_count,
				page_writes: prepared.pages.len(),
				placement_visits: run_count,
			},
		},
	)
}

index_figures : Semantics.Store, U64 -> Try(List([Figure(U64), NoFigure]), KernelFacadeScenes.Error)
index_figures = |store, figure_count| {
	var $by_occurrence = List.repeat(NoFigure, store.occurrences.len())
	var $figure = 0
	var $node_index = 0
	while $node_index < store.nodes.len() {
		node = list_at(store.nodes, $node_index)
		if node.role.local_name == "Figure" {
			if $figure >= figure_count or node.content.length() != 1 or node.content.start() >= store.content_spine.len() {
				return Err(InvalidPlacement({ placement: $node_index }))
			}
			occurrence = match list_at(store.content_spine, node.content.start()) {
				ContentOccurrence(id) => id
				_ => return Err(InvalidPlacement({ placement: $node_index }))
			}
			if occurrence.index() >= $by_occurrence.len() or list_at($by_occurrence, occurrence.index()) != NoFigure {
				return Err(InvalidPlacement({ placement: occurrence.index() }))
			}
			$by_occurrence = list_set($by_occurrence, occurrence.index(), Figure($figure))
			$figure = $figure + 1
		}
		$node_index = $node_index + 1
	}
	if $figure != figure_count {
		return Err(InvalidPlacement({ placement: $figure }))
	}
	Ok($by_occurrence)
}

## Flow drawing images (figures in order, then decorations), then page
## furniture images: furniture image `k` is image `flow images + k`.
authoring_images : List(Image.Source), List(Image.Source), Color.SpaceId, Color.SpaceId -> Image.SourceStore
authoring_images = |flow_images, furniture_images, rgb_space, gray_space| {
	if flow_images.is_empty() and furniture_images.is_empty() {
		return { resources: [] }
	}
	var $resources = List.with_capacity(flow_images.len() + furniture_images.len())
	for image in flow_images {
		$resources = $resources.append(source_resource(image, Image.Id.from_index($resources.len()), rgb_space, gray_space))
	}
	for image in furniture_images {
		$resources = $resources.append(source_resource(image, Image.Id.from_index($resources.len()), rgb_space, gray_space))
	}
	{ resources: $resources }
}

## One flow drawing ready to paint: its commands and the image identity
## of its first image.
PaintedDrawing : { commands : List(Document.FlowCommand), image_base : U64 }

## Every figure's and decoration's drawing with its image base, their
## images in resource order, and the scene commands, paths, and path
## segments they add (a decoration once per placement).
## Custom block panels hold paths only, so they add no images.
FlowFacts : { commands : U64, decorations : List(PaintedDrawing), figures : List(PaintedDrawing), images : List(Image.Source), nonblack : Bool, panels : List(PaintedDrawing), paths : U64, segments : U64 }

flow_facts : Document.NormalizedAuthoring, KernelFacadePages.FlowPaints -> Try(FlowFacts, KernelFacadeScenes.Error)
flow_facts = |authoring, paints| {
	if authoring.figures.is_empty() and authoring.decorations.is_empty() and authoring.customs.is_empty() {
		return Ok({ commands: 0, decorations: [], figures: [], images: [], nonblack: False, panels: [], paths: 0, segments: 0 })
	}
	if paints.figure_scales.len() != authoring.figures.len() {
		return Err(InvalidPlacement({ placement: 0 }))
	}
	var $images = []
	var $figures = List.with_capacity(authoring.figures.len())
	var $decorations = List.with_capacity(authoring.decorations.len())
	var $commands = 0
	var $paths = 0
	var $segments = 0
	var $nonblack = False
	for figure in authoring.figures {
		drawing = without_labels(valid_flow_drawing(figure.drawing)?)
		$figures = $figures.append({ commands: drawing.commands, image_base: $images.len() })
		for image in drawing.images {
			$images = $images.append(image)
		}
		counted = count_flow(drawing.commands)?
		$commands = checked_add($commands, checked_add(counted.commands, 1)?)?
		$paths = checked_add($paths, counted.paths)?
		$segments = checked_add($segments, counted.segments)?
		$nonblack = $nonblack or counted.nonblack
	}
	for decoration in authoring.decorations {
		drawing = without_labels(valid_flow_drawing(decoration.drawing)?)
		$decorations = $decorations.append({ commands: drawing.commands, image_base: $images.len() })
		for image in drawing.images {
			$images = $images.append(image)
		}
		counted = count_flow(drawing.commands)?
		$commands = checked_add($commands, checked_add(counted.commands, 1)?)?
		$paths = checked_add($paths, counted.paths)?
		$segments = checked_add($segments, counted.segments)?
		$nonblack = $nonblack or counted.nonblack
	}
	var $panels = List.with_capacity(authoring.customs.len())
	for custom in authoring.customs {
		drawing = without_labels(valid_flow_drawing(custom.panel)?)
		if !drawing.images.is_empty() {
			return Err(InvalidPlacement({ placement: 0 }))
		}
		$panels = $panels.append({ commands: drawing.commands, image_base: 0 })
		counted = count_flow(drawing.commands)?
		$commands = checked_add($commands, checked_add(counted.commands, 1)?)?
		$paths = checked_add($paths, counted.paths)?
		$segments = checked_add($segments, counted.segments)?
		$nonblack = $nonblack or counted.nonblack
	}
	Ok({ commands: $commands, decorations: $decorations, figures: $figures, images: $images, nonblack: $nonblack, panels: $panels, paths: $paths, segments: $segments })
}

## A drawing's paths and images: its text labels are artifact text runs,
## shaped and placed by `KernelFacadeLabels` and painted with the page's
## text. A drawing without labels keeps its command list as is.
without_labels : Document.FlowDrawing -> Document.FlowDrawing
without_labels = |drawing| {
	labelled = drawing.commands.any(
		|command| match command {
			FlowText(_) => Bool.True
			_ => Bool.False
		},
	)
	if labelled {
		{
			..drawing,
			commands: drawing.commands.keep_if(
				|command| match command {
					FlowText(_) => Bool.False
					_ => Bool.True
				},
			),
		}
	} else {
		drawing
	}
}

valid_flow_drawing : Document.ValidatedDrawing -> Try(Document.FlowDrawing, KernelFacadeScenes.Error)
valid_flow_drawing = |drawing| match drawing {
	ValidDrawing(value) => Ok(value)
	InvalidDrawing(_) => Err(InvalidPlacement({ placement: 0 }))
}

count_flow : List(Document.FlowCommand) -> Try({ commands : U64, nonblack : Bool, paths : U64, segments : U64 }, KernelFacadeScenes.Error)
count_flow = |commands| {
	var $paths = 0
	var $segments = 0
	var $nonblack = False
	for command in commands {
		match command {
			FlowImage(_) => {}
			FlowText(_) => {}
			FlowPath({ fill, segments, stroke }) => {
				$paths = checked_add($paths, 1)?
				$segments = checked_add($segments, segments.len())?
				fill_nonblack = match fill {
					NoFill => False
					Fill(color) => nonblack(color)
				}
				stroke_nonblack = match stroke {
					NoStroke => False
					Stroke({ color, width: _ }) => nonblack(color)
				}
				$nonblack = $nonblack or fill_nonblack or stroke_nonblack
			}
		}
	}
	Ok({ commands: commands.len(), nonblack: $nonblack, paths: $paths, segments: $segments })
}

## Every figure and decoration path paint converts in the page's painting
## space.
check_flow_colors : Document.NormalizedAuthoring, KernelFacadeScenes.IntentProfile, Bool -> Try({}, [Unsupported])
check_flow_colors = |authoring, intent, use_srgb| {
	check = |drawing| match drawing {
		InvalidDrawing(_) => Ok({})
		ValidDrawing(value) => {
			for command in value.commands {
				match command {
					FlowImage(_) => {}
					FlowText(_) => {}
					FlowPath({ fill, segments: _, stroke }) => {
						_ = furniture_path_style(fill, stroke, intent, use_srgb)?
					}
				}
			}
			Ok({})
		}
	}
	for figure in authoring.figures {
		check(figure.drawing)?
	}
	for decoration in authoring.decorations {
		check(decoration.drawing)?
	}
	for custom in authoring.customs {
		check(custom.panel)?
	}
	Ok({})
}

## A flow path's paint after `check_flow_colors` proved it converts.
checked_flow_style : [Fill(Color.SourceValue), NoFill], [NoStroke, Stroke({ color : Color.SourceValue, width : Layout.Unit })], KernelFacadeScenes.IntentProfile, Bool -> Scene.PathStyle
checked_flow_style = |fill, stroke, intent, use_srgb| match furniture_path_style(fill, stroke, intent, use_srgb) {
	Ok(style) => style
	Err(_) => crash "validated flow path paint escaped"
}

FurnitureFacts : { drawings : List(KernelFacadeFurniture.Drawing), images : List(Image.Source), paints : List(KernelFacadeFurniture.DrawingPaint) }

furniture_facts : [NoFurniture, WithFurniture(KernelFacadeFurniture.Plan)] -> FurnitureFacts
furniture_facts = |furniture| match furniture {
	NoFurniture => { drawings: [], images: [], paints: [] }
	WithFurniture(plan) => { drawings: KernelFacadeFurniture.Plan.drawings(plan), images: KernelFacadeFurniture.Plan.images(plan), paints: KernelFacadeFurniture.Plan.drawing_paints(plan) }
}

## Commands, paths, and path segments of every painted furniture drawing,
## and whether any of their colors is not black.
drawing_counts : FurnitureFacts -> Try({ commands : U64, nonblack : Bool, paths : U64, segments : U64 }, KernelFacadeScenes.Error)
drawing_counts = |furniture| {
	var $commands = 0
	var $paths = 0
	var $segments = 0
	var $nonblack = False
	for paint in furniture.paints {
		drawing = list_at(furniture.drawings, paint.drawing)
		$commands = checked_add($commands, checked_add(drawing.commands.len(), 1)?)?
		for command in drawing.commands {
			match command {
				DrawingImage(_) => {}
				DrawingPath({ fill, segments, stroke }) => {
					$paths = checked_add($paths, 1)?
					$segments = checked_add($segments, segments.len())?
					fill_nonblack = match fill {
						NoFill => False
						Fill(color) => nonblack(color)
					}
					stroke_nonblack = match stroke {
						NoStroke => False
						Stroke({ color, width: _ }) => nonblack(color)
					}
					$nonblack = $nonblack or fill_nonblack or stroke_nonblack
				}
			}
		}
	}
	Ok({ commands: $commands, nonblack: $nonblack, paths: $paths, segments: $segments })
}

## A furniture path's fill and stroke in the page's painting space: solid,
## nonzero fill; butt caps, miter joins, and a miter limit of 10.
furniture_path_style : [Fill(Color.SourceValue), NoFill], [NoStroke, Stroke({ color : Color.SourceValue, width : Layout.Unit })], KernelFacadeScenes.IntentProfile, Bool -> Try(Scene.PathStyle, [Unsupported])
furniture_path_style = |fill, stroke, intent, use_srgb| {
	fill_style = match fill {
		NoFill => NoFill
		Fill(color) => SolidFill({ color: paint_color(color, intent, use_srgb)?, rule: Nonzero })
	}
	stroke_style = match stroke {
		NoStroke => NoStroke
		Stroke({ color, width }) => SolidStroke({ cap: ButtCap, color: paint_color(color, intent, use_srgb)?, dash: SolidLine, join: MiterJoin, miter_limit: Layout.Unit.from_raw(10000), width })
	}
	Ok({ fill: fill_style, stroke: stroke_style })
}

source_is_gray : Image.Source -> Bool
source_is_gray = |source| match source.inspect() {
	PackedGray8View(_) => True
	_ => False
}

source_resource : Image.Source, Image.Id, Color.SpaceId, Color.SpaceId -> Image.SourceResource
source_resource = |source, id, rgb_space, gray_space| {
	payload = match source.inspect() {
		JpegSrgbView({ bytes, orientation }) => EncodedJpeg({ bytes, color_space: rgb_space, orientation_policy: orientation })
		PackedGray8View({ alpha, dimensions, pixels, row_stride }) => PackedPixels({ alpha, color_space: gray_space, dimensions, format: Gray8, pixels, row_stride })
		PackedRgb8View({ alpha, dimensions, pixels, row_stride }) => PackedPixels({ alpha, color_space: rgb_space, dimensions, format: Rgb8, pixels, row_stride })
	}
	{ id, payload }
}

nonblack : Color.SourceValue -> Bool
nonblack = |color| match color {
	Srgb(Rgb({ blue, green, red })) => blue != 0 or green != 0 or red != 0
	_ => False
}

## The fill of a table rule in the page's painting space: black is the
## calibrated gray zero without an intent profile, and every color is sRGB
## when the page paints in sRGB.
paint_color : Color.SourceValue, KernelFacadeScenes.IntentProfile, Bool -> Try(Color.Value, [Unsupported])
paint_color = |color, intent, use_srgb| match color {
	Srgb(Rgb(channels)) => match intent {
		NoIntentProfile => if channels.red == 0 and channels.green == 0 and channels.blue == 0 Ok({ channels: Gray(0), space: Color.SpaceId.from_index(0) }) else Err(Unsupported)
		PackagedSrgbIntent => if use_srgb Ok({ channels: Rgb(channels), space: Color.SpaceId.from_index(0) }) else if channels.red == 0 and channels.green == 0 and channels.blue == 0 Ok({ channels: Gray(0), space: Color.SpaceId.from_index(0) }) else Err(Unsupported)
	}
	_ => Err(Unsupported)
}

has_nonblack_srgb : List(KernelFacadeShape.RunStyle) -> Bool
has_nonblack_srgb = |styles| {
	var $found = False
	var $index = 0
	while $index < styles.len() and $found == False {
		$found = match list_at(styles, $index).color {
			Srgb(Rgb({ blue, green, red })) => blue != 0 or green != 0 or red != 0
			_ => False
		}
		$index = $index + 1
	}
	$found
}

range_fits : Semantics.Range, U64 -> Bool
range_fits = |range, available| range.start() <= available and range.length() <= available - range.start()

check_limit : U64, U64, KernelFacadeScenes.Dimension -> Try({}, KernelFacadeScenes.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelFacadeScenes.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Ok(value) => Ok(value)
	Err(_) => Err(ArithmeticOverflow)
}

checked_times : U64, U64 -> Try(U64, KernelFacadeScenes.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Ok(value) => Ok(value)
	Err(_) => Err(ArithmeticOverflow)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated facade-scene index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(updated) => updated
	Err(OutOfBounds) => crash "validated facade-scene write escaped"
}
