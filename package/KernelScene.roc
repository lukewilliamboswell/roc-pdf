import Color
import Image
import KernelGeometry
import Layout
import Scene
import Semantics
import Text

KernelScene :: [].{
	Dimension : [Commands, DashLengths, GraphicsDepth, Groups, Pages, PathSegments, Paths]
	IndexKind : [ColorSpaceIndex, CommandIndex, DashIndex, GroupIndex, ImageIndex, PageGroupEdgeIndex, PageIndex, PathIndex, SegmentIndex, TextRunIndex]
	TextPaintReason : [FillAndStrokeMissingStroke, FillHasStroke, OpacityNotOpaque, StrokeWidthNonPositive]
	Error : [
		ArithmeticOverflow,
		DashAllZero({ command : U64 }),
		DashLengthNegative({ command : U64, dash : U64 }),
		DashPhaseNegative({ command : U64 }),
		DuplicateOwnership({ index : U64, kind : IndexKind }),
		EmptyCommandRange({ group : U64 }),
		EmptyPath({ path : U64 }),
		Geometry(KernelGeometry.Error),
		IndexOutOfRange({ available : U64, index : U64, kind : IndexKind }),
		InvalidPathOrder({ path : U64, segment : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		MiterLimitTooSmall({ command : U64 }),
		NoPathPaint({ path : U64 }),
		NonDenseIdentity({ actual : U64, expected : U64, kind : IndexKind }),
		NonPositiveRect({ index : U64, kind : IndexKind }),
		Orphaned({ index : U64, kind : IndexKind }),
		SpanOutOfRange({ available : U64, kind : IndexKind, length : U64, owner : U64, start : U64 }),
		TextPaintInvalid({ command : U64, reason : TextPaintReason }),
		UnsupportedCommand({ command : U64 }),
		UnpaintedPath({ command : U64 }),
	]

	Limits :: {
		max_commands : U64,
		max_dash_lengths : U64,
		max_graphics_depth : U64,
		max_groups : U64,
		max_pages : U64,
		max_path_segments : U64,
		max_paths : U64,
	}.{
		make : {
			max_commands : U64,
			max_dash_lengths : U64,
			max_graphics_depth : U64,
			max_groups : U64,
			max_pages : U64,
			max_path_segments : U64,
			max_paths : U64,
		} -> Limits
		make = |limits| Limits.(limits)
	}

	Resources :: { color_spaces : U64, images : U64, text_runs : U64 }.{
		make : { color_spaces : U64, images : U64 } -> Resources
		make = |resources| Resources.({ color_spaces: resources.color_spaces, images: resources.images, text_runs: 0 })

		with_text : { color_spaces : U64, images : U64, text_runs : U64 } -> Resources
		with_text = |resources| Resources.(resources)

		color_space_count : Resources -> U64
		color_space_count = |resources| resources.color_spaces

		image_count : Resources -> U64
		image_count = |resources| resources.images

		text_run_count : Resources -> U64
		text_run_count = |resources| resources.text_runs
	}

	Work : {
		child_ranges : U64,
		color_references : U64,
		command_visits : U64,
		dash_values : U64,
		group_visits : U64,
		image_placements : U64,
		max_graphics_depth : U64,
		page_box_checks : U64,
		page_group_edges : U64,
		page_visits : U64,
		path_segments : U64,
		path_visits : U64,
		text_placements : U64,
	}

	Plan :: { resources : Resources, scenes : Scene.Store, work : Work }.{
		build : Scene.Store, Resources, Limits -> Try(Plan, Error)
		build = |scenes, resources, limits| build_plan(scenes, resources, limits)

		resources : Plan -> Resources
		resources = |plan| plan.resources

		scenes : Plan -> Scene.Store
		scenes = |plan| plan.scenes

		work : Plan -> Work
		work = |plan| plan.work
	}
}

Frame := { depth : U64, range : Semantics.Range }

CommandWork := {
	children : [Leaf, Nested(Semantics.Range)],
	color_references : U64,
	dash_values : U64,
	image_placements : U64,
	text_placements : U64,
}

scene_failure : KernelScene.Error -> Try(a, KernelScene.Error)
scene_failure = |error| Err(error)

build_plan : Scene.Store, KernelScene.Resources, KernelScene.Limits -> Try(KernelScene.Plan, KernelScene.Error)
build_plan = |scenes, resources, limits| {
	check_limit(scenes.commands.len(), limits.max_commands, Commands)?
	check_limit(scenes.dash_lengths.len(), limits.max_dash_lengths, DashLengths)?
	check_limit(scenes.groups.len(), limits.max_groups, Groups)?
	check_limit(scenes.pages.len(), limits.max_pages, Pages)?
	check_limit(scenes.path_segments.len(), limits.max_path_segments, PathSegments)?
	check_limit(scenes.paths.len(), limits.max_paths, Paths)?

	path_work = validate_paths(scenes)?
	page_work = validate_pages(scenes)?
	command_work = validate_groups(scenes, resources, limits.max_graphics_depth)?

	Ok(
		KernelScene.Plan.{
			resources,
			scenes,
			work: {
				child_ranges: command_work.child_ranges,
				color_references: command_work.color_references,
				command_visits: command_work.command_visits,
				dash_values: command_work.dash_values,
				group_visits: scenes.groups.len(),
				image_placements: command_work.image_placements,
				max_graphics_depth: command_work.max_graphics_depth,
				page_box_checks: page_work.page_box_checks,
				page_group_edges: page_work.page_group_edges,
				page_visits: scenes.pages.len(),
				path_segments: path_work.path_segments,
				path_visits: scenes.paths.len(),
				text_placements: command_work.text_placements,
			},
		},
	)
}

validate_paths : Scene.Store -> Try({ path_segments : U64 }, KernelScene.Error)
validate_paths = |scenes| {
	var $owners = List.repeat(0, scenes.path_segments.len())
	var $path_index = 0
	var $visits = 0
	var $error = NoError
	while $path_index < scenes.paths.len() and $error == NoError {
		path = list_at(scenes.paths, $path_index)
		if path.id.index() != $path_index {
			$error = Invalid(NonDenseIdentity({ actual: path.id.index(), expected: $path_index, kind: PathIndex }))
		} else if path.segments.length() == 0 {
			$error = Invalid(EmptyPath({ path: $path_index }))
		} else {
			match validate_span(path.segments, scenes.path_segments.len(), SegmentIndex, $path_index) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(span) => {
					var $segment_index = span.start
					var $subpath_open = False
					var $draws = 0
					while $segment_index < span.end and $error == NoError {
						match mark_once($owners, $segment_index, SegmentIndex) {
							Err(error) => {
								$error = Invalid(error)
							}
							Ok(next_owners) => {
								$owners = next_owners
								segment = list_at(scenes.path_segments, $segment_index)
								match segment {
									MoveTo(_) => {
										$subpath_open = True
									}
									LineTo(_) => if $subpath_open {
										$draws = $draws + 1
									} else {
										$error = Invalid(InvalidPathOrder({ path: $path_index, segment: $segment_index }))
									}
									CubicTo(_) => if $subpath_open {
										$draws = $draws + 1
									} else {
										$error = Invalid(InvalidPathOrder({ path: $path_index, segment: $segment_index }))
									}
									Close => if $subpath_open {
										$subpath_open = False
									} else {
										$error = Invalid(InvalidPathOrder({ path: $path_index, segment: $segment_index }))
									}
									Rectangle(rectangle) => if positive_rect(rectangle) {
										$draws = $draws + 1
										$subpath_open = False
									} else {
										$error = Invalid(NonPositiveRect({ index: $segment_index, kind: SegmentIndex }))
									}
								}
							}
						}
						$segment_index = $segment_index + 1
						$visits = $visits + 1
					}
					if $error == NoError and $draws == 0 {
						$error = Invalid(NoPathPaint({ path: $path_index }))
					}
				}
			}
		}
		$path_index = $path_index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => {
			ensure_all_owned($owners, SegmentIndex)?
			Ok({ path_segments: $visits })
		}
	}
}

validate_pages : Scene.Store -> Try({ page_box_checks : U64, page_group_edges : U64 }, KernelScene.Error)
validate_pages = |scenes| {
	var $edge_owners = List.repeat(0, scenes.page_groups.len())
	var $group_owners = List.repeat(0, scenes.groups.len())
	var $page_index = 0
	var $box_checks = 0
	var $edge_visits = 0
	var $error = NoError
	while $page_index < scenes.pages.len() and $error == NoError {
		page = list_at(scenes.pages, $page_index)
		if page.id.index() != $page_index {
			$error = Invalid(NonDenseIdentity({ actual: page.id.index(), expected: $page_index, kind: PageIndex }))
		} else {
			match KernelGeometry.validate_page(page) {
				Err(error) => {
					$error = Invalid(Geometry(error))
				}
				Ok(geometry_work) => {
					$box_checks = $box_checks + geometry_work.box_checks
					match validate_span(page.paint_order, scenes.page_groups.len(), GroupIndex, $page_index) {
						Err(error) => {
							$error = Invalid(error)
						}
						Ok(span) => {
							var $edge = span.start
							while $edge < span.end and $error == NoError {
								match mark_once($edge_owners, $edge, PageGroupEdgeIndex) {
									Err(error) => {
										$error = Invalid(error)
									}
									Ok(next_edge_owners) => {
										$edge_owners = next_edge_owners
										group_index = list_at(scenes.page_groups, $edge).index()
										if group_index >= scenes.groups.len() {
											$error = Invalid(IndexOutOfRange({ available: scenes.groups.len(), index: group_index, kind: GroupIndex }))
										} else {
											match mark_once($group_owners, group_index, GroupIndex) {
												Err(error) => {
													$error = Invalid(error)
												}
												Ok(next_group_owners) => {
													$group_owners = next_group_owners
												}
											}
										}
									}
								}
								$edge = $edge + 1
								$edge_visits = $edge_visits + 1
							}
						}
					}
				}
			}
		}
		$page_index = $page_index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => {
			ensure_all_owned($edge_owners, PageGroupEdgeIndex)?
			ensure_all_owned($group_owners, GroupIndex)?
			Ok({ page_box_checks: $box_checks, page_group_edges: $edge_visits })
		}
	}
}

validate_groups : Scene.Store, KernelScene.Resources, U64 -> Try({ child_ranges : U64, color_references : U64, command_visits : U64, dash_values : U64, image_placements : U64, max_graphics_depth : U64, text_placements : U64 }, KernelScene.Error)
validate_groups = |scenes, resources, max_depth| {
	var $group_index = 0
	var $expected_command = 0
	var $child_ranges = 0
	var $color_references = 0
	var $command_visits = 0
	var $dash_values = 0
	var $image_placements = 0
	var $text_placements = 0
	var $maximum_depth = 0
	var $error = NoError
	while $group_index < scenes.groups.len() and $error == NoError {
		group = list_at(scenes.groups, $group_index)
		if group.id.index() != $group_index {
			$error = Invalid(NonDenseIdentity({ actual: group.id.index(), expected: $group_index, kind: GroupIndex }))
		} else if group.commands.length() == 0 {
			$error = Invalid(EmptyCommandRange({ group: $group_index }))
		} else {
			var $frames = [Frame.{ depth: 1, range: group.commands }]
			var $frame_index = 0
			while $frame_index < $frames.len() and $error == NoError {
				frame = list_at($frames, $frame_index)
				if frame.depth > max_depth {
					$error = Invalid(LimitExceeded({ attempted: frame.depth, dimension: GraphicsDepth, limit: max_depth }))
				} else {
					$maximum_depth = U64.max($maximum_depth, frame.depth)
					match validate_span(frame.range, scenes.commands.len(), CommandIndex, $group_index) {
						Err(error) => {
							$error = Invalid(error)
						}
						Ok(span) => {
							var $command_index = span.start
							while $command_index < span.end and $error == NoError {
								if $command_index < $expected_command {
									$error = Invalid(DuplicateOwnership({ index: $command_index, kind: CommandIndex }))
								} else if $command_index > $expected_command {
									$error = Invalid(Orphaned({ index: $expected_command, kind: CommandIndex }))
								} else {
									$expected_command = $expected_command + 1
									match validate_command(list_at(scenes.commands, $command_index), $command_index, scenes, resources) {
										Err(error) => {
											$error = Invalid(error)
										}
										Ok(work) => {
											$color_references = $color_references + work.color_references
											$dash_values = $dash_values + work.dash_values
											$image_placements = $image_placements + work.image_placements
											$text_placements = $text_placements + work.text_placements
											match work.children {
												Leaf => {}
												Nested(children) => if children.length() == 0 {
													$error = Invalid(EmptyCommandRange({ group: $group_index }))
												} else {
													match U64.plus_try(frame.depth, 1) {
														Err(Overflow) => {
															$error = Invalid(ArithmeticOverflow)
														}
														Ok(depth) => {
															$frames = $frames.append(Frame.{ depth, range: children })
															$child_ranges = $child_ranges + 1
														}
													}
												}
											}
										}
									}
								}
								$command_index = $command_index + 1
								$command_visits = $command_visits + 1
							}
						}
					}
				}
				$frame_index = $frame_index + 1
			}
		}
		$group_index = $group_index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => if $expected_command < scenes.commands.len() {
			Err(Orphaned({ index: $expected_command, kind: CommandIndex }))
		} else {
			Ok({ child_ranges: $child_ranges, color_references: $color_references, command_visits: $command_visits, dash_values: $dash_values, image_placements: $image_placements, max_graphics_depth: $maximum_depth, text_placements: $text_placements })
		}
	}
}

validate_command : Scene.Command, U64, Scene.Store, KernelScene.Resources -> Try(CommandWork, KernelScene.Error)
validate_command = |command, index, scenes, resources| match command {
	Clip({ children, path }) => {
		validate_path_id(path, scenes.paths.len())?
		Ok({ children: Nested(children), color_references: 0, dash_values: 0, image_placements: 0, text_placements: 0 })
	}
	DrawImage({ image, placement }) => {
		if image.index() >= resources.images {
			Err(IndexOutOfRange({ available: resources.images, index: image.index(), kind: ImageIndex }))
		} else if !positive_rect(placement) {
			Err(NonPositiveRect({ index, kind: CommandIndex }))
		} else {
			Ok({ children: Leaf, color_references: 0, dash_values: 0, image_placements: 1, text_placements: 0 })
		}
	}
	DrawPath({ path, style }) => {
		validate_path_id(path, scenes.paths.len())?
		work = validate_style(style, index, scenes.dash_lengths, resources.color_spaces)?
		Ok({ children: Leaf, color_references: work.color_references, dash_values: work.dash_values, image_placements: 0, text_placements: 0 })
	}
	DrawText({ paint, run }) => {
		if run.index() >= resources.text_runs {
			return Err(IndexOutOfRange({ available: resources.text_runs, index: run.index(), kind: TextRunIndex }))
		}
		colors = validate_text_paint(paint, index, resources.color_spaces)?
		Ok({ children: Leaf, color_references: colors, dash_values: 0, image_placements: 0, text_placements: 1 })
	}
	Opacity(_) => Err(UnsupportedCommand({ command: index }))
	Transform({ children, matrix: _ }) => Ok({ children: Nested(children), color_references: 0, dash_values: 0, image_placements: 0, text_placements: 0 })
}

validate_text_paint : Scene.TextPaint, U64, U64 -> Try(U64, KernelScene.Error)
validate_text_paint = |paint, command, color_space_count| {
	if paint.opacity != 65535 {
		return Err(TextPaintInvalid({ command, reason: OpacityNotOpaque }))
	}
	validate_color(paint.fill, color_space_count)?
	match paint.mode {
		Fill => match paint.stroke {
			NoStroke => Ok(1)
			Stroke(_) => Err(TextPaintInvalid({ command, reason: FillHasStroke }))
		}
		FillAndStroke => match paint.stroke {
			NoStroke => Err(TextPaintInvalid({ command, reason: FillAndStrokeMissingStroke }))
			Stroke({ color, width }) => {
				validate_color(color, color_space_count)?
				if width.raw() <= 0 {
					Err(TextPaintInvalid({ command, reason: StrokeWidthNonPositive }))
				} else {
					Ok(2)
				}
			}
		}
	}
}

validate_style : Scene.PathStyle, U64, List(Layout.Unit), U64 -> Try({ color_references : U64, dash_values : U64 }, KernelScene.Error)
validate_style = |style, command, dash_lengths, color_space_count| {
	fill_colors = match style.fill {
		NoFill => 0
		SolidFill({ color, rule: _ }) => {
			validate_color(color, color_space_count)?
			1
		}
	}
	stroke_work = match style.stroke {
		NoStroke => Ok({ colors: 0, dash_values: 0 })
		SolidStroke(stroke) => validate_stroke(stroke, command, dash_lengths, color_space_count)
	}?
	if fill_colors == 0 and stroke_work.colors == 0 {
		scene_failure(
			UnpaintedPath({
				command: command,
			}),
		)
	} else {
		Ok({ color_references: fill_colors + stroke_work.colors, dash_values: stroke_work.dash_values })
	}
}

validate_stroke : Scene.StrokeStyle, U64, List(Layout.Unit), U64 -> Try({ colors : U64, dash_values : U64 }, KernelScene.Error)
validate_stroke = |stroke, command, dash_lengths, color_space_count| {
	validate_color(stroke.color, color_space_count)?
	if stroke.width.raw() <= 0 {
		scene_failure(NonPositiveRect({ index: command, kind: CommandIndex }))
	} else if stroke.miter_limit.raw() < 1000 {
		scene_failure(
			MiterLimitTooSmall({
				command: command,
			}),
		)
	} else {
		dash_values = match stroke.dash {
			SolidLine => Ok(0)
			Dashed({ lengths, phase }) => validate_dash(lengths, phase, command, dash_lengths)
		}?
		Ok({ colors: 1, dash_values })
	}
}

validate_dash : Semantics.Range, Layout.Unit, U64, List(Layout.Unit) -> Try(U64, KernelScene.Error)
validate_dash = |range, phase, command, values| {
	if phase.raw() < 0 {
		scene_failure(
			DashPhaseNegative({
				command: command,
			}),
		)
	} else {
		span = validate_span(range, values.len(), DashIndex, command)?
		var $index = span.start
		var $has_positive = False
		var $error = NoError
		while $index < span.end and $error == NoError {
			value = list_at(values, $index).raw()
			if value < 0 {
				$error = Invalid(DashLengthNegative({ command, dash: $index }))
			} else if value > 0 {
				$has_positive = True
			}
			$index = $index + 1
		}
		match $error {
			Invalid(error) => Err(error)
			NoError => if $has_positive Ok(span.end - span.start) else scene_failure(
				DashAllZero({
					command: command,
				}),
			)
		}
	}
}

validate_color : Color.Value, U64 -> Try({}, KernelScene.Error)
validate_color = |color, available| {
	index = color.space.index()
	if index >= available {
		Err(IndexOutOfRange({ available, index, kind: ColorSpaceIndex }))
	} else {
		Ok({})
	}
}

validate_path_id : Scene.PathId, U64 -> Try({}, KernelScene.Error)
validate_path_id = |path, available| {
	index = path.index()
	if index >= available {
		Err(IndexOutOfRange({ available, index, kind: PathIndex }))
	} else {
		Ok({})
	}
}

validate_span : Semantics.Range, U64, KernelScene.IndexKind, U64 -> Try({ end : U64, start : U64 }, KernelScene.Error)
validate_span = |range, available, kind, owner| {
	start = range.start()
	length = range.length()
	if start > available or length > available - start {
		Err(SpanOutOfRange({ available, kind, length, owner, start }))
	} else {
		Ok({ end: start + length, start })
	}
}

mark_once : List(U8), U64, KernelScene.IndexKind -> Try(List(U8), KernelScene.Error)
mark_once = |owners, index, kind| {
	if list_at(owners, index) != 0 {
		Err(DuplicateOwnership({ index, kind }))
	} else {
		Ok(list_set(owners, index, 1))
	}
}

ensure_all_owned : List(U8), KernelScene.IndexKind -> Try({}, KernelScene.Error)
ensure_all_owned = |owners, kind| {
	var $index = 0
	var $orphan = NoOrphan
	while $index < owners.len() and $orphan == NoOrphan {
		if list_at(owners, $index) == 0 {
			$orphan = Orphan($index)
		}
		$index = $index + 1
	}
	match $orphan {
		NoOrphan => Ok({})
		Orphan(index) => Err(Orphaned({ index, kind }))
	}
}

check_limit : U64, U64, KernelScene.Dimension -> Try({}, KernelScene.Error)
check_limit = |attempted, limit, dimension| {
	if attempted > limit {
		Err(LimitExceeded({ attempted, dimension, limit }))
	} else {
		Ok({})
	}
}

positive_rect : Layout.Rect -> Bool
positive_rect = |rect| {
	if rect.size.width.raw() <= 0 or rect.size.height.raw() <= 0 {
		False
	} else {
		match I64.plus_try(rect.origin.x.raw(), rect.size.width.raw()) {
			Err(Overflow) => False
			Ok(_) => match I64.plus_try(rect.origin.y.raw(), rect.size.height.raw()) {
				Err(Overflow) => False
				Ok(_) => True
			}
		}
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated scene index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated scene update escaped"
	}
}

unit : I64 -> Layout.Unit
unit = |raw| Layout.Unit.from_raw(raw)

rect : I64, I64, I64, I64 -> Layout.Rect
rect = |x, y, width, height| {
	origin: { x: unit(x), y: unit(y) },
	size: { height: unit(height), width: unit(width) },
}

test_color : Color.Value
test_color = { channels: Rgb({ blue: 1000, green: 2000, red: 3000 }), space: Color.SpaceId.from_index(0) }

test_style : Scene.PathStyle
test_style = {
	fill: SolidFill({ color: test_color, rule: Nonzero }),
	stroke: SolidStroke({
		cap: RoundCap,
		color: test_color,
		dash: Dashed({ lengths: Semantics.Range.from_start_and_length(0, 2), phase: unit(0) }),
		join: MiterJoin,
		miter_limit: unit(10000),
		width: unit(1000),
	}),
}

test_page : Scene.Page
test_page = {
	boxes: {
		art: rect(1000, 1000, 8000, 8000),
		bleed: rect(500, 500, 9000, 9000),
		crop: rect(0, 0, 10000, 10000),
		media: rect(0, 0, 10000, 10000),
		trim: rect(750, 750, 8500, 8500),
	},
	id: Semantics.PageId.from_index(0),
	paint_order: Semantics.Range.from_start_and_length(0, 1),
	rotation: Rotate0,
}

test_store : Scene.Store
test_store = {
	commands: [
		Transform({
			children: Semantics.Range.from_start_and_length(2, 1),
			matrix: { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(0), f: unit(0) },
		}),
		DrawPath({ path: Scene.PathId.from_index(0), style: test_style }),
		Clip({ children: Semantics.Range.from_start_and_length(3, 1), path: Scene.PathId.from_index(0) }),
		DrawImage({ image: Image.Id.from_index(0), placement: rect(0, 0, 1000, 1000) }),
	],
	dash_lengths: [unit(1000), unit(500)],
	groups: [{ commands: Semantics.Range.from_start_and_length(0, 2), id: Scene.GroupId.from_index(0), owner: PageArtifact(Background) }],
	page_groups: [Scene.GroupId.from_index(0)],
	pages: [test_page],
	path_segments: [
		MoveTo({ x: unit(0), y: unit(0) }),
		LineTo({ x: unit(1000), y: unit(0) }),
		CubicTo({ control_1: { x: unit(1000), y: unit(500) }, control_2: { x: unit(500), y: unit(1000) }, end: { x: unit(0), y: unit(1000) } }),
		Close,
		Rectangle(rect(100, 100, 200, 300)),
	],
	paths: [{ id: Scene.PathId.from_index(0), segments: Semantics.Range.from_start_and_length(0, 5) }],
}

test_limits : KernelScene.Limits
test_limits = KernelScene.Limits.make({ max_commands: 4, max_dash_lengths: 2, max_graphics_depth: 3, max_groups: 1, max_pages: 1, max_path_segments: 5, max_paths: 1 })

test_resources : KernelScene.Resources
test_resources = KernelScene.Resources.make({ color_spaces: 1, images: 1 })

test_text_paint : Scene.TextPaint
test_text_paint = {
	fill: test_color,
	mode: Fill,
	opacity: 65535,
	stroke: NoStroke,
}

text_store : Scene.Store
text_store = {
	..test_store,
	commands: [DrawText({ paint: test_text_paint, run: Text.RunId.from_index(0) })],
	groups: [{ commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) }],
}

text_limits : KernelScene.Limits
text_limits = KernelScene.Limits.make({ max_commands: 1, max_dash_lengths: 2, max_graphics_depth: 1, max_groups: 1, max_pages: 1, max_path_segments: 5, max_paths: 1 })

text_resources : KernelScene.Resources
text_resources = KernelScene.Resources.with_text({ color_spaces: 1, images: 0, text_runs: 1 })

## Visible text paint is a validated scene fact with an exact run reference.
expect {
	plan = KernelScene.Plan.build(text_store, text_resources, text_limits)?
	work = KernelScene.Plan.work(plan)
	work.text_placements == 1 and work.color_references == 1 and KernelScene.Resources.text_run_count(KernelScene.Plan.resources(plan)) == 1
}

## A text command cannot refer to a run absent from the prepared text store.
expect {
	command = list_at(text_store.commands, 0)
	bad_command = match command {
		DrawText({ paint, run: _ }) => DrawText({ paint, run: Text.RunId.from_index(1) })
		_ => command
	}
	bad = { ..text_store, commands: [bad_command] }
	match KernelScene.Plan.build(bad, text_resources, text_limits) {
		Err(IndexOutOfRange({ available: 1, index: 1, kind: TextRunIndex })) => True
		_ => False
	}
}

## Gate 3 text paint is opaque until an ExtGState capability is implemented.
expect {
	bad = { ..text_store, commands: [DrawText({ paint: { ..test_text_paint, opacity: 65534 }, run: Text.RunId.from_index(0) })] }
	match KernelScene.Plan.build(bad, text_resources, text_limits) {
		Err(TextPaintInvalid({ command: 0, reason: OpacityNotOpaque })) => True
		_ => False
	}
}

## Fill-only and fill-and-stroke modes require matching typed stroke policy.
expect {
	stroke = Stroke({ color: test_color, width: unit(500) })
	fill_with_stroke = { ..text_store, commands: [DrawText({ paint: { ..test_text_paint, stroke }, run: Text.RunId.from_index(0) })] }
	fill_and_stroke_without = { ..text_store, commands: [DrawText({ paint: { ..test_text_paint, mode: FillAndStroke }, run: Text.RunId.from_index(0) })] }
	bad_width = { ..text_store, commands: [DrawText({ paint: { ..test_text_paint, mode: FillAndStroke, stroke: Stroke({ color: test_color, width: unit(0) }) }, run: Text.RunId.from_index(0) })] }
	fill_rejected = match KernelScene.Plan.build(fill_with_stroke, text_resources, text_limits) {
		Err(TextPaintInvalid({ command: 0, reason: FillHasStroke })) => True
		_ => False
	}
	missing_rejected = match KernelScene.Plan.build(fill_and_stroke_without, text_resources, text_limits) {
		Err(TextPaintInvalid({ command: 0, reason: FillAndStrokeMissingStroke })) => True
		_ => False
	}
	width_rejected = match KernelScene.Plan.build(bad_width, text_resources, text_limits) {
		Err(TextPaintInvalid({ command: 0, reason: StrokeWidthNonPositive })) => True
		_ => False
	}
	fill_rejected and missing_rejected and width_rejected
}

## Flat scene validation visits every stored relationship exactly once.
expect {
	plan = KernelScene.Plan.build(test_store, test_resources, test_limits)?
	work = KernelScene.Plan.work(plan)
	actual =
		\\pages: ${Str.inspect(work.page_visits)}
		\\box checks: ${Str.inspect(work.page_box_checks)}
		\\paths: ${Str.inspect(work.path_visits)}
		\\segments: ${Str.inspect(work.path_segments)}
		\\groups: ${Str.inspect(work.group_visits)}
		\\page edges: ${Str.inspect(work.page_group_edges)}
		\\commands: ${Str.inspect(work.command_visits)}
		\\child ranges: ${Str.inspect(work.child_ranges)}
		\\max depth: ${Str.inspect(work.max_graphics_depth)}
		\\colors: ${Str.inspect(work.color_references)}
		\\dash values: ${Str.inspect(work.dash_values)}
		\\images: ${Str.inspect(work.image_placements)}
	expected =
		\\pages: 1
		\\box checks: 5
		\\paths: 1
		\\segments: 5
		\\groups: 1
		\\page edges: 1
		\\commands: 4
		\\child ranges: 2
		\\max depth: 3
		\\colors: 2
		\\dash values: 2
		\\images: 1

	actual == expected
}

## Overlapping command ranges are rejected instead of painting twice.
expect {
	commands = list_set(
		test_store.commands,
		0,
		Transform({
			children: Semantics.Range.from_start_and_length(1, 1),
			matrix: { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(0), f: unit(0) },
		}),
	)
	bad = { ..test_store, commands }

	match KernelScene.Plan.build(bad, test_resources, test_limits) {
		Err(DuplicateOwnership({ index: 1, kind: CommandIndex })) => True
		_ => False
	}
}

## A drawable path cannot begin with a line lacking a current point.
expect {
	bad = { ..test_store, path_segments: [LineTo({ x: unit(1), y: unit(1) }), Rectangle(rect(0, 0, 1, 1)), Rectangle(rect(0, 0, 1, 1)), Rectangle(rect(0, 0, 1, 1)), Rectangle(rect(0, 0, 1, 1))] }

	match KernelScene.Plan.build(bad, test_resources, test_limits) {
		Err(InvalidPathOrder({ path: 0, segment: 0 })) => True
		_ => False
	}
}

## Dash arrays reject negative entries before a scene plan escapes.
expect {
	bad = { ..test_store, dash_lengths: [unit(1000), unit(-1)] }

	match KernelScene.Plan.build(bad, test_resources, test_limits) {
		Err(DashLengthNegative({ command: 1, dash: 1 })) => True
		_ => False
	}
}

## Gate 4 opacity remains explicitly unavailable in a Gate 2 scene.
expect {
	commands = list_set(test_store.commands, 3, Opacity({ children: Semantics.Range.from_start_and_length(0, 1), opacity: 32768 }))
	bad = { ..test_store, commands }

	match KernelScene.Plan.build(bad, test_resources, test_limits) {
		Err(UnsupportedCommand({ command: 3 })) => True
		_ => False
	}
}

## Dense path identities cannot be detached from their arena index.
expect {
	paths = [{ id: Scene.PathId.from_index(1), segments: Semantics.Range.from_start_and_length(0, 5) }]
	bad = { ..test_store, paths }

	match KernelScene.Plan.build(bad, test_resources, test_limits) {
		Err(NonDenseIdentity({ actual: 1, expected: 0, kind: PathIndex })) => True
		_ => False
	}
}

## Every page-group edge is owned by exactly one page range.
expect {
	bad = { ..test_store, page_groups: test_store.page_groups.append(Scene.GroupId.from_index(0)) }

	match KernelScene.Plan.build(bad, test_resources, test_limits) {
		Err(Orphaned({ index: 1, kind: PageGroupEdgeIndex })) => True
		_ => False
	}
}

## Every command is reached exactly once from one group root.
expect {
	group = list_at(test_store.groups, 0)
	groups = [{ ..group, commands: Semantics.Range.from_start_and_length(0, 1) }]
	bad = { ..test_store, groups }

	match KernelScene.Plan.build(bad, test_resources, test_limits) {
		Err(Orphaned({ index: 1, kind: CommandIndex })) => True
		_ => False
	}
}

## Command ranges are checked before any arena access.
expect {
	group = list_at(test_store.groups, 0)
	groups = [{ ..group, commands: Semantics.Range.from_start_and_length(4, 1) }]
	bad = { ..test_store, groups }

	match KernelScene.Plan.build(bad, test_resources, test_limits) {
		Err(SpanOutOfRange({ available: 4, kind: CommandIndex, length: 1, owner: 0, start: 4 })) => True
		_ => False
	}
}

## Graphics-state depth is bounded without depending on the host stack.
expect {
	shallow_limits = KernelScene.Limits.make({ max_commands: 4, max_dash_lengths: 2, max_graphics_depth: 2, max_groups: 1, max_pages: 1, max_path_segments: 5, max_paths: 1 })

	match KernelScene.Plan.build(test_store, test_resources, shallow_limits) {
		Err(LimitExceeded({ attempted: 3, dimension: GraphicsDepth, limit: 2 })) => True
		_ => False
	}
}

## Scene dimensions are rejected before traversal exceeds their budget.
expect {
	small_limits = KernelScene.Limits.make({ max_commands: 3, max_dash_lengths: 2, max_graphics_depth: 3, max_groups: 1, max_pages: 1, max_path_segments: 5, max_paths: 1 })

	match KernelScene.Plan.build(test_store, test_resources, small_limits) {
		Err(LimitExceeded({ attempted: 4, dimension: Commands, limit: 3 })) => True
		_ => False
	}
}

## Resource indices are checked at every image placement.
expect {
	commands = list_set(test_store.commands, 3, DrawImage({ image: Image.Id.from_index(1), placement: rect(0, 0, 1000, 1000) }))
	bad = { ..test_store, commands }

	match KernelScene.Plan.build(bad, test_resources, test_limits) {
		Err(IndexOutOfRange({ available: 1, index: 1, kind: ImageIndex })) => True
		_ => False
	}
}

## A dash pattern must contain a positive painted length.
expect {
	bad = { ..test_store, dash_lengths: [unit(0), unit(0)] }

	match KernelScene.Plan.build(bad, test_resources, test_limits) {
		Err(DashAllZero({ command: 1 })) => True
		_ => False
	}
}
