import Color
import Document
import Image
import KernelColor
import KernelFacadeFragments
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
				authoring: empty_authoring,
				page_size: prepared.page_size,
				pages: prepared.pages,
				placements: prepared.placements,
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
	authoring : Document.NormalizedAuthoring,
	page_size : Layout.Size,
	pages : List(KernelFacadeText.Page),
	placements : List(KernelFacadeText.Placement),
	styles : List(KernelFacadeShape.RunStyle),
	text : Text.Store,
}

InternalArenaPrepared : {
	authoring : Document.NormalizedAuthoring,
	figure_by_occurrence : List([Figure(U64), NoFigure]),
	page_size : Layout.Size,
	pages : List(KernelFacadeText.Page),
	placements : List(KernelFacadeText.Placement),
	run_occurrences : List(Semantics.OccurrenceId),
	styles : List(KernelFacadeShape.RunStyle),
}

empty_authoring : Document.NormalizedAuthoring
empty_authoring = { blocks: [], figures: [], language: "", metadata_title: "", outline: [], page_labels: [] }

build_plan : KernelFacadeFragments.Plan, Layout.Size, Document.NormalizedAuthoring, KernelFacadeScenes.IntentProfile, KernelFacadeScenes.Limits -> Try(KernelFacadeScenes.Plan, KernelFacadeScenes.Error)
build_plan = |fragment_plan, page_size, authoring, intent, limits| {
	text_plan = KernelFacadeFragments.Plan.text(fragment_plan)
	text = KernelFacadeText.Plan.text(text_plan)
	prepared = {
		authoring,
		page_size,
		pages: KernelFacadeText.Plan.pages(text_plan),
		placements: KernelFacadeText.Plan.placements(text_plan),
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
	ownership = KernelTextOwnership.Plan.build(semantics, scene, text) ? Ownership
	Ok(KernelFacadeScenes.Plan.{ colors, images: arena.images, ownership, scene, work: arena.work })
}

prepare_arena : InternalPrepared -> InternalArenaPrepared
prepare_arena = |prepared| {
	authoring: prepared.authoring,
	page_size: prepared.page_size,
	pages: prepared.pages,
	placements: prepared.placements,
	styles: prepared.styles,
	run_occurrences: prepared.text.runs.map(|run| run.occurrence),
	figure_by_occurrence: [],
}

build_arena : KernelFacadeScenes.ArenaPrepared, KernelFacadeScenes.Limits -> Try(KernelFacadeScenes.Arena, KernelFacadeScenes.Error)
build_arena = |prepared, limits| build_arena_with_intent(
	{
		authoring: empty_authoring,
		figure_by_occurrence: [],
		page_size: prepared.page_size,
		pages: prepared.pages,
		placements: prepared.placements,
		run_occurrences: List.repeat(Semantics.OccurrenceId.from_index(0), prepared.text_runs),
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
	run_count = prepared.run_occurrences.len()
	command_count = checked_add(checked_times(run_count, 2)?, prepared.authoring.figures.len())?
	check_limit(command_count, limits.max_commands, Commands)?
	check_limit(run_count, limits.max_groups, Groups)?
	check_limit(run_count, limits.max_page_group_edges, PageGroupEdges)?
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
	has_rgb_images = prepared.authoring.figures.any(|figure| !source_is_gray(figure.image))
	has_gray_images = prepared.authoring.figures.any(|figure| source_is_gray(figure.image))
	use_srgb = match intent {
		NoIntentProfile => False
		PackagedSrgbIntent => has_nonblack_srgb(prepared.styles) or has_rgb_images
	}
	color_checks = match intent {
		NoIntentProfile => run_count
		PackagedSrgbIntent => checked_add(run_count, run_count)?
	}
	var $commands = List.with_capacity(command_count)
	var $groups = List.with_capacity(run_count)
	var $page_groups = List.with_capacity(run_count)
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
		while $placement_cursor < page_end {
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
			occurrence = list_at(prepared.run_occurrences, $placement_cursor)
			figure = if occurrence.index() < prepared.figure_by_occurrence.len() list_at(prepared.figure_by_occurrence, occurrence.index()) else NoFigure
			command_start = $commands.len()
			group_length = match figure {
				NoFigure => 1
				Figure(figure_index) => if list_at($painted_figures, figure_index) {
					1
				} else {
					authored = list_at(prepared.authoring.figures, figure_index)
					image_x = checked_i64_add(placement.origin.x.raw(), authored.placement.origin.x.raw())?
					image_top = checked_i64_minus(placement.origin.y.raw(), authored.placement.size.height.raw())?
					image_y = checked_i64_add(image_top, authored.placement.origin.y.raw())?
					$commands = $commands.append(DrawImage({ image: Image.Id.from_index(figure_index), placement: { origin: { x: Layout.Unit.from_raw(image_x), y: Layout.Unit.from_raw(image_y) }, size: authored.placement.size } }))
					$painted_figures = list_set($painted_figures, figure_index, True)
					2
				}
			}
			text_command = $commands.len() + 1
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
			).append(DrawText({ paint, run: placement.run }))
			group = Scene.GroupId.from_index($groups.len())
			$groups = $groups.append({
				commands: Semantics.Range.from_start_and_length(command_start, group_length),
				id: group,
				owner: Fragment(Semantics.FragmentId.from_index($placement_cursor)),
			})
			$page_groups = $page_groups.append(group)
			$placement_cursor = $placement_cursor + 1
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
	if $painted_figures.any(|painted| !painted) {
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
			images: authoring_images(prepared.authoring, Color.SpaceId.from_index(0), gray_space.id),
			scenes: {
				commands: $commands,
				dash_lengths: [],
				groups: $groups,
				page_groups: $page_groups,
				pages: $pages,
				path_segments: [],
				paths: [],
			},
			work: {
				color_checks,
				command_writes: command_count,
				group_writes: run_count,
				page_group_writes: run_count,
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

authoring_images : Document.NormalizedAuthoring, Color.SpaceId, Color.SpaceId -> Image.SourceStore
authoring_images = |authoring, rgb_space, gray_space| {
	if authoring.figures.is_empty() {
		return { resources: [] }
	}
	var $resources = List.with_capacity(authoring.figures.len())
	var $index = 0
	while $index < authoring.figures.len() {
		figure = list_at(authoring.figures, $index)
		$resources = $resources.append(source_resource(figure.image, Image.Id.from_index($index), rgb_space, gray_space))
		$index = $index + 1
	}
	{ resources: $resources }
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

checked_i64_add : I64, I64 -> Try(I64, KernelFacadeScenes.Error)
checked_i64_add = |left, right| match I64.plus_try(left, right) {
	Ok(value) => Ok(value)
	Err(_) => Err(ArithmeticOverflow)
}

checked_i64_minus : I64, I64 -> Try(I64, KernelFacadeScenes.Error)
checked_i64_minus = |left, right| match I64.minus_try(left, right) {
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
