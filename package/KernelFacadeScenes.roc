import Color
import KernelColor
import KernelFacadeFragments
import KernelFacadeShape
import KernelFacadeText
import KernelScene
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
	Arena :: { colors : Color.Store, scenes : Scene.Store, work : Work }.{
		build_prepared : ArenaPrepared, Limits -> Try(Arena, Error)
		build_prepared = |prepared, limits| build_arena(prepared, limits)

		colors : Arena -> Color.Store
		colors = |arena| arena.colors

		scenes : Arena -> Scene.Store
		scenes = |arena| arena.scenes

		work : Arena -> Work
		work = |arena| arena.work
	}
	Plan :: { colors : KernelColor.Plan, ownership : KernelTextOwnership.Plan, scene : KernelScene.Plan, work : Work }.{
		build : KernelFacadeFragments.Plan, Layout.Size, Limits -> Try(Plan, Error)
		build = |fragments, page_size, limits| build_plan(fragments, page_size, NoIntentProfile, limits)

		build_with_intent : KernelFacadeFragments.Plan, Layout.Size, IntentProfile, Limits -> Try(Plan, Error)
		build_with_intent = |fragments, page_size, intent, limits| build_plan(fragments, page_size, intent, limits)

		build_prepared : KernelTextSemantics.Plan, Prepared, Limits -> Try(Plan, Error)
		build_prepared = |semantics, prepared, limits| build_validated(semantics, prepared, NoIntentProfile, limits)

		colors : Plan -> KernelColor.Plan
		colors = |plan| plan.colors

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

build_plan : KernelFacadeFragments.Plan, Layout.Size, KernelFacadeScenes.IntentProfile, KernelFacadeScenes.Limits -> Try(KernelFacadeScenes.Plan, KernelFacadeScenes.Error)
build_plan = |fragment_plan, page_size, intent, limits| {
	text_plan = KernelFacadeFragments.Plan.text(fragment_plan)
	text = KernelFacadeText.Plan.text(text_plan)
	prepared = {
		page_size,
		pages: KernelFacadeText.Plan.pages(text_plan),
		placements: KernelFacadeText.Plan.placements(text_plan),
		styles: KernelFacadeText.Plan.styles(text_plan),
		text,
	}
	build_validated(KernelFacadeFragments.Plan.semantics(fragment_plan), prepared, intent, limits)
}

build_validated : KernelTextSemantics.Plan, KernelFacadeScenes.Prepared, KernelFacadeScenes.IntentProfile, KernelFacadeScenes.Limits -> Try(KernelFacadeScenes.Plan, KernelFacadeScenes.Error)
build_validated = |semantics, prepared, intent, limits| {
	text = prepared.text
	arena = build_arena_with_intent(prepare_arena(prepared), intent, limits)?
	colors = KernelColor.Plan.build(arena.colors, limits.color) ? Color
	scene = KernelScene.Plan.build(
		arena.scenes,
		KernelScene.Resources.with_text({ color_spaces: arena.colors.spaces.len(), images: 0, text_runs: text.runs.len() }),
		limits.scene,
	) ? Scene
	ownership = KernelTextOwnership.Plan.build(semantics, scene, text) ? Ownership
	Ok(KernelFacadeScenes.Plan.{ colors, ownership, scene, work: arena.work })
}

prepare_arena : KernelFacadeScenes.Prepared -> KernelFacadeScenes.ArenaPrepared
prepare_arena = |prepared| {
	page_size: prepared.page_size,
	pages: prepared.pages,
	placements: prepared.placements,
	styles: prepared.styles,
	text_runs: prepared.text.runs.len(),
}

build_arena : KernelFacadeScenes.ArenaPrepared, KernelFacadeScenes.Limits -> Try(KernelFacadeScenes.Arena, KernelFacadeScenes.Error)
build_arena = |prepared, limits| build_arena_with_intent(prepared, NoIntentProfile, limits)

build_arena_with_intent : KernelFacadeScenes.ArenaPrepared, KernelFacadeScenes.IntentProfile, KernelFacadeScenes.Limits -> Try(KernelFacadeScenes.Arena, KernelFacadeScenes.Error)
build_arena_with_intent = |prepared, intent, limits| {
	if prepared.page_size.width.raw() <= 0 or prepared.page_size.height.raw() <= 0 {
		return Err(InvalidPageSize)
	}
	run_count = prepared.text_runs
	command_count = checked_times(run_count, 2)?
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
	paint = {
		fill: { channels: Gray(0), space: Color.SpaceId.from_index(0) },
		mode: Fill,
		opacity: 65535,
		stroke: NoStroke,
	}
	var $commands = List.with_capacity(command_count)
	var $groups = List.with_capacity(run_count)
	var $page_groups = List.with_capacity(run_count)
	var $pages = List.with_capacity(prepared.pages.len())
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
			match style.color {
				Srgb(Rgb({ blue, green, red })) => if blue != 0 or green != 0 or red != 0 {
					return Err(UnsupportedColor({ run: $placement_cursor }))
				}
				_ => return Err(UnsupportedColor({ run: $placement_cursor }))
			}
			command_start = $commands.len()
			$commands = $commands.append(
				Transform({
					children: Semantics.Range.from_start_and_length(command_start + 1, 1),
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
				commands: Semantics.Range.from_start_and_length(command_start, 1),
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
			spaces: painting_spaces,
			tags: KernelSrgbProfile.tags,
		}
	}
	Ok(
		KernelFacadeScenes.Arena.{
			colors,
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
				color_checks: run_count,
				command_writes: command_count,
				group_writes: run_count,
				page_group_writes: run_count,
				page_writes: prepared.pages.len(),
				placement_visits: run_count,
			},
		},
	)
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
