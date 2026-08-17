import Color
import Image
import KernelGeometry
import Layout
import Scene
import Semantics
import Text

KernelScene :: [].{
	Dimension : [Commands, DashLengths, FormCommands, Forms, GraphicsDepth, Groups, Pages, PathSegments, Paths, PatternCommands, Patterns, ShadingStops, Shadings]
	IndexKind : [ColorSpaceIndex, CommandIndex, DashIndex, FormCommandIndex, FormIndex, GroupIndex, ImageIndex, PageGroupEdgeIndex, PageIndex, PathIndex, PatternCommandIndex, PatternIndex, SegmentIndex, ShadingIndex, ShadingStopIndex, TextRunIndex]
	TextPaintReason : [FillAndStrokeMissingStroke, FillHasStroke, OpacityNotOpaque, StrokeWidthNonPositive]
	Error : [
		ArithmeticOverflow,
		DashAllZero({ command : U64 }),
		DashLengthNegative({ command : U64, dash : U64 }),
		DashPhaseNegative({ command : U64 }),
		DuplicateOwnership({ index : U64, kind : IndexKind }),
		EmptyCommandRange({ group : U64 }),
		EmptyForm({ form : U64 }),
		EmptyPath({ path : U64 }),
		FormTransformSingular({ command : U64 }),
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

		## Linear geometry whose start equals its end, or radial geometry
		## whose circles coincide or whose radii are both zero, has no
		## deterministic paint direction and is rejected.
		DegenerateShadingGeometry({ shading : U64 }),
		EmptyPatternCell({ pattern : U64 }),
		NegativeShadingRadius({ shading : U64 }),

		## Nested pattern invocation is outside the supported subset: a
		## pattern cell may not fill with another pattern.
		PatternInPatternCell({ command : U64 }),
		PatternMatrixSingular({ pattern : U64 }),
		PatternStepInvalid({ pattern : U64 }),

		## The supported stop model requires the first stop exactly at the
		## domain start and the last exactly at the domain end.
		ShadingStopEndpointInvalid({ shading : U64 }),
		ShadingStopsNotIncreasing({ shading : U64, stop : U64 }),

		## Semantic text inside a reusable, ownership-neutral pattern cell
		## would lose or duplicate its semantics, so it is rejected.
		TextInPatternCell({ command : U64 }),
		TooFewShadingStops({ shading : U64, stops : U64 }),

		## Pattern content is fully opaque in the initial subset: opacity
		## groups and soft masks inside a cell are rejected.
		TransparencyInPatternCell({ command : U64 }),
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

	Resources :: { allow_opacity : Bool, allow_paints : Bool, color_spaces : U64, forms : U64, images : U64, patterns : U64, shadings : U64, text_runs : U64 }.{
		make : { color_spaces : U64, images : U64 } -> Resources
		make = |resources| Resources.({ allow_opacity: Bool.False, allow_paints: Bool.False, color_spaces: resources.color_spaces, forms: 0, images: resources.images, patterns: 0, shadings: 0, text_runs: 0 })

		with_text : { color_spaces : U64, images : U64, text_runs : U64 } -> Resources
		with_text = |resources| Resources.({ allow_opacity: Bool.False, allow_paints: Bool.False, color_spaces: resources.color_spaces, forms: 0, images: resources.images, patterns: 0, shadings: 0, text_runs: resources.text_runs })

		## Gate 4 scenes additionally declare their dense form count and gain
		## the constant-opacity capability; the older constructors keep
		## declaring zero forms and rejecting opacity, so a Gate 2 or Gate 3
		## scene still rejects any form placement or opacity group.
		with_forms : { color_spaces : U64, forms : U64, images : U64, text_runs : U64 } -> Resources
		with_forms = |resources| Resources.({ allow_opacity: Bool.True, allow_paints: Bool.False, color_spaces: resources.color_spaces, forms: resources.forms, images: resources.images, patterns: 0, shadings: 0, text_runs: resources.text_runs })

		## Paint-aware scenes additionally declare their dense shading and
		## pattern counts and gain the shading-paint and pattern-fill
		## capabilities; every earlier constructor keeps declaring zero and
		## rejecting the paint commands.
		with_paints : { color_spaces : U64, forms : U64, images : U64, patterns : U64, shadings : U64, text_runs : U64 } -> Resources
		with_paints = |resources| Resources.({ allow_opacity: Bool.True, allow_paints: Bool.True, color_spaces: resources.color_spaces, forms: resources.forms, images: resources.images, patterns: resources.patterns, shadings: resources.shadings, text_runs: resources.text_runs })

		color_space_count : Resources -> U64
		color_space_count = |resources| resources.color_spaces

		form_count : Resources -> U64
		form_count = |resources| resources.forms

		image_count : Resources -> U64
		image_count = |resources| resources.images

		pattern_count : Resources -> U64
		pattern_count = |resources| resources.patterns

		shading_count : Resources -> U64
		shading_count = |resources| resources.shadings

		text_run_count : Resources -> U64
		text_run_count = |resources| resources.text_runs
	}

	Work : {
		child_ranges : U64,
		color_references : U64,
		command_visits : U64,
		dash_values : U64,
		form_placements : U64,
		group_visits : U64,
		image_placements : U64,
		max_graphics_depth : U64,
		opacity_commands : U64,
		page_box_checks : U64,
		pattern_fills : U64,
		shading_paints : U64,
		soft_mask_commands : U64,
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

	FormLimits :: { max_form_commands : U64, max_forms : U64 }.{
		make : { max_form_commands : U64, max_forms : U64 } -> FormLimits
		make = |limits| FormLimits.(limits)
	}

	FormWork : {
		form_child_ranges : U64,
		form_command_visits : U64,
		form_opacity_commands : U64,
		form_pattern_fills : U64,
		form_shading_paints : U64,
		form_soft_mask_commands : U64,
		form_visits : U64,
		max_form_depth : U64,
		nested_form_placements : U64,
	}

	## A Gate 4 scene plan validates the flat form-command arena with exactly
	## the same command rules as page content: dense form identities, positive
	## bounding boxes, once-each command ownership, balanced nesting inside the
	## declared depth budget, and typed per-command validation over the shared
	## path, dash, image, text, and form stores.
	FormPlan :: { forms : Scene.FormStore, page : Plan, work : FormWork }.{
		build : Scene.Store, Scene.FormStore, Resources, Limits, FormLimits -> Try(FormPlan, Error)
		build = |scenes, form_store, resources, limits, form_limits| build_form_plan(scenes, form_store, resources, limits, form_limits)

		forms : FormPlan -> Scene.FormStore
		forms = |plan| plan.forms

		page : FormPlan -> Plan
		page = |plan| plan.page

		work : FormPlan -> FormWork
		work = |plan| plan.work
	}

	PaintLimits :: { max_pattern_commands : U64, max_patterns : U64, max_shading_stops : U64, max_shadings : U64 }.{
		make : { max_pattern_commands : U64, max_patterns : U64, max_shading_stops : U64, max_shadings : U64 } -> PaintLimits
		make = |limits| PaintLimits.(limits)
	}

	PaintWork : {
		cell_child_ranges : U64,
		cell_command_visits : U64,
		cell_form_placements : U64,
		cell_image_placements : U64,
		cell_shading_paints : U64,
		cell_visits : U64,
		max_cell_depth : U64,
		shading_stop_visits : U64,
		shading_visits : U64,
	}

	## A paint-aware scene plan validates the shading store, the pattern
	## store, and the flat pattern-command arena on top of the form-aware
	## plan. Shadings are validated structurally (dense identities, exact
	## once-each stop ownership, strictly increasing offsets with exact
	## domain endpoints, non-degenerate geometry); pattern cells are
	## validated with the same command rules as page and form content under
	## an explicit cell whitelist, so text, transparency, and nested pattern
	## invocation are rejected at this boundary.
	PaintPlan :: { forms : FormPlan, patterns : Scene.PatternStore, shadings : Scene.ShadingStore, work : PaintWork }.{
		build : Scene.Store, Scene.FormStore, Scene.ShadingStore, Scene.PatternStore, Resources, Limits, FormLimits, PaintLimits -> Try(PaintPlan, Error)
		build = |scenes, form_store, shading_store, pattern_store, resources, limits, form_limits, paint_limits| build_paint_plan(scenes, form_store, shading_store, pattern_store, resources, limits, form_limits, paint_limits)

		forms : PaintPlan -> FormPlan
		forms = |plan| plan.forms

		patterns : PaintPlan -> Scene.PatternStore
		patterns = |plan| plan.patterns

		shadings : PaintPlan -> Scene.ShadingStore
		shadings = |plan| plan.shadings

		work : PaintPlan -> PaintWork
		work = |plan| plan.work
	}
}

Frame := { depth : U64, range : Semantics.Range }

CommandWork := {
	children : [Leaf, Nested(Semantics.Range)],
	color_references : U64,
	dash_values : U64,
	form_placements : U64,
	image_placements : U64,
	opacity_commands : U64,
	pattern_fills : U64,
	shading_paints : U64,
	soft_mask_commands : U64,
	text_placements : U64,
}

leaf_work : CommandWork
leaf_work = { children: Leaf, color_references: 0, dash_values: 0, form_placements: 0, image_placements: 0, opacity_commands: 0, pattern_fills: 0, shading_paints: 0, soft_mask_commands: 0, text_placements: 0 }

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
				form_placements: command_work.form_placements,
				group_visits: scenes.groups.len(),
				image_placements: command_work.image_placements,
				max_graphics_depth: command_work.max_graphics_depth,
				opacity_commands: command_work.opacity_commands,
				page_box_checks: page_work.page_box_checks,
				pattern_fills: command_work.pattern_fills,
				shading_paints: command_work.shading_paints,
				soft_mask_commands: command_work.soft_mask_commands,
				page_group_edges: page_work.page_group_edges,
				page_visits: scenes.pages.len(),
				path_segments: path_work.path_segments,
				path_visits: scenes.paths.len(),
				text_placements: command_work.text_placements,
			},
		},
	)
}

build_form_plan : Scene.Store, Scene.FormStore, KernelScene.Resources, KernelScene.Limits, KernelScene.FormLimits -> Try(KernelScene.FormPlan, KernelScene.Error)
build_form_plan = |scenes, form_store, resources, limits, form_limits| {
	check_limit(form_store.forms.len(), form_limits.max_forms, Forms)?
	check_limit(form_store.commands.len(), form_limits.max_form_commands, FormCommands)?
	if form_store.forms.len() != resources.forms {
		return Err(IndexOutOfRange({ available: form_store.forms.len(), index: resources.forms, kind: FormIndex }))
	}
	page = build_plan(scenes, resources, limits)?
	form_work = validate_forms(form_store, scenes, resources, limits.max_graphics_depth)?
	Ok(KernelScene.FormPlan.{ forms: form_store, page, work: form_work })
}

build_paint_plan : Scene.Store, Scene.FormStore, Scene.ShadingStore, Scene.PatternStore, KernelScene.Resources, KernelScene.Limits, KernelScene.FormLimits, KernelScene.PaintLimits -> Try(KernelScene.PaintPlan, KernelScene.Error)
build_paint_plan = |scenes, form_store, shading_store, pattern_store, resources, limits, form_limits, paint_limits| {
	check_limit(shading_store.shadings.len(), paint_limits.max_shadings, Shadings)?
	check_limit(pattern_store.cells.len(), paint_limits.max_patterns, Patterns)?
	check_limit(pattern_store.commands.len(), paint_limits.max_pattern_commands, PatternCommands)?
	if shading_store.shadings.len() != resources.shadings {
		return Err(IndexOutOfRange({ available: shading_store.shadings.len(), index: resources.shadings, kind: ShadingIndex }))
	}
	if pattern_store.cells.len() != resources.patterns {
		return Err(IndexOutOfRange({ available: pattern_store.cells.len(), index: resources.patterns, kind: PatternIndex }))
	}
	shading_work = validate_shadings(shading_store, resources, paint_limits.max_shading_stops)?
	forms = build_form_plan(scenes, form_store, resources, limits, form_limits)?
	cell_work = validate_cells(pattern_store, scenes, resources, limits.max_graphics_depth)?
	Ok(
		KernelScene.PaintPlan.{
			forms,
			patterns: pattern_store,
			shadings: shading_store,
			work: {
				cell_child_ranges: cell_work.cell_child_ranges,
				cell_command_visits: cell_work.cell_command_visits,
				cell_form_placements: cell_work.cell_form_placements,
				cell_image_placements: cell_work.cell_image_placements,
				cell_shading_paints: cell_work.cell_shading_paints,
				cell_visits: pattern_store.cells.len(),
				max_cell_depth: cell_work.max_cell_depth,
				shading_stop_visits: shading_work.stop_visits,
				shading_visits: shading_store.shadings.len(),
			},
		},
	)
}

## The shading store is validated structurally: dense identities, exact
## once-each stop ownership, at least two strictly increasing stops with
## exact `0`/`65535` domain endpoints, a declared color space in range, and
## non-degenerate geometry with non-negative radii.
validate_shadings : Scene.ShadingStore, KernelScene.Resources, U64 -> Try({ stop_visits : U64 }, KernelScene.Error)
validate_shadings = |store, resources, max_stops| {
	var $owners = List.repeat(0, store.stops.len())
	var $shading_index = 0
	var $visits = 0
	var $error = NoError
	while $shading_index < store.shadings.len() and $error == NoError {
		shading = list_at(store.shadings, $shading_index)
		if shading.id.index() != $shading_index {
			$error = Invalid(NonDenseIdentity({ actual: shading.id.index(), expected: $shading_index, kind: ShadingIndex }))
		} else if shading.space.index() >= resources.color_spaces {
			$error = Invalid(IndexOutOfRange({ available: resources.color_spaces, index: shading.space.index(), kind: ColorSpaceIndex }))
		} else if shading.stops.length() < 2 {
			$error = Invalid(TooFewShadingStops({ shading: $shading_index, stops: shading.stops.length() }))
		} else if shading.stops.length() > max_stops {
			$error = Invalid(LimitExceeded({ attempted: shading.stops.length(), dimension: ShadingStops, limit: max_stops }))
		} else {
			match validate_span(shading.stops, store.stops.len(), ShadingStopIndex, $shading_index) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(span) => {
					var $stop_index = span.start
					var $previous = 0
					while $stop_index < span.end and $error == NoError {
						match mark_once($owners, $stop_index, ShadingStopIndex) {
							Err(error) => {
								$error = Invalid(error)
							}
							Ok(next_owners) => {
								$owners = next_owners
								offset = list_at(store.stops, $stop_index).offset.to_u64()
								if $stop_index == span.start {
									if offset != 0 {
										$error = Invalid(ShadingStopEndpointInvalid({ shading: $shading_index }))
									}
								} else if offset <= $previous {
									$error = Invalid(ShadingStopsNotIncreasing({ shading: $shading_index, stop: $stop_index }))
								} else if $stop_index == span.end - 1 and offset != 65535 {
									$error = Invalid(ShadingStopEndpointInvalid({ shading: $shading_index }))
								} else {
									{}
								}
								$previous = offset
							}
						}
						$stop_index = $stop_index + 1
						$visits = $visits + 1
					}
					if $error == NoError {
						match validate_shading_geometry(shading.geometry, $shading_index) {
							Err(error) => {
								$error = Invalid(error)
							}
							Ok({}) => {}
						}
					}
				}
			}
		}
		$shading_index = $shading_index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => {
			ensure_all_owned($owners, ShadingStopIndex)?
			Ok({ stop_visits: $visits })
		}
	}
}

validate_shading_geometry : Scene.ShadingGeometry, U64 -> Try({}, KernelScene.Error)
validate_shading_geometry = |geometry, shading| match geometry {
	Axial({ end, start }) => {
		if start.x.raw() == end.x.raw() and start.y.raw() == end.y.raw() {
			Err(DegenerateShadingGeometry({ shading: shading }))
		} else {
			Ok({})
		}
	}
	Radial({ end_center, end_radius, start_center, start_radius }) => {
		if start_radius.raw() < 0 or end_radius.raw() < 0 {
			Err(NegativeShadingRadius({ shading: shading }))
		} else if start_radius.raw() == 0 and end_radius.raw() == 0 {
			Err(DegenerateShadingGeometry({ shading: shading }))
		} else if start_center.x.raw() == end_center.x.raw() and start_center.y.raw() == end_center.y.raw() and start_radius.raw() == end_radius.raw() {
			Err(DegenerateShadingGeometry({ shading: shading }))
		} else {
			Ok({})
		}
	}
}

## Walks the flat pattern-command arena with the same dense once-each
## ownership cursor as form content, under the explicit cell whitelist:
## text (`TextInPatternCell`), opacity and soft masks
## (`TransparencyInPatternCell`), and nested pattern fills
## (`PatternInPatternCell`) are rejected before any commonly shared
## validation runs.
validate_cells : Scene.PatternStore, Scene.Store, KernelScene.Resources, U64 -> Try({ cell_child_ranges : U64, cell_command_visits : U64, cell_form_placements : U64, cell_image_placements : U64, cell_shading_paints : U64, max_cell_depth : U64 }, KernelScene.Error)
validate_cells = |store, scenes, resources, max_depth| {
	var $cell_index = 0
	var $expected_command = 0
	var $child_ranges = 0
	var $command_visits = 0
	var $form_placements = 0
	var $image_placements = 0
	var $shading_paints = 0
	var $maximum_depth = 0
	var $error = NoError
	while $cell_index < store.cells.len() and $error == NoError {
		cell = list_at(store.cells, $cell_index)
		if cell.id.index() != $cell_index {
			$error = Invalid(NonDenseIdentity({ actual: cell.id.index(), expected: $cell_index, kind: PatternIndex }))
		} else if !positive_rect(cell.bbox) {
			$error = Invalid(NonPositiveRect({ index: $cell_index, kind: PatternIndex }))
		} else if cell.x_step.raw() <= 0 or cell.y_step.raw() <= 0 {
			$error = Invalid(PatternStepInvalid({ pattern: $cell_index }))
		} else if cell.commands.length() == 0 {
			$error = Invalid(EmptyPatternCell({ pattern: $cell_index }))
		} else {
			match validate_pattern_matrix(cell.matrix, $cell_index) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok({}) => {
					var $frames = [Frame.{ depth: 1, range: cell.commands }]
					var $frame_index = 0
					while $frame_index < $frames.len() and $error == NoError {
						frame = list_at($frames, $frame_index)
						if frame.depth > max_depth {
							$error = Invalid(LimitExceeded({ attempted: frame.depth, dimension: GraphicsDepth, limit: max_depth }))
						} else {
							$maximum_depth = U64.max($maximum_depth, frame.depth)
							match validate_span(frame.range, store.commands.len(), PatternCommandIndex, $cell_index) {
								Err(error) => {
									$error = Invalid(error)
								}
								Ok(span) => {
									var $command_index = span.start
									while $command_index < span.end and $error == NoError {
										if $command_index < $expected_command {
											$error = Invalid(DuplicateOwnership({ index: $command_index, kind: PatternCommandIndex }))
										} else if $command_index > $expected_command {
											$error = Invalid(Orphaned({ index: $expected_command, kind: PatternCommandIndex }))
										} else {
											$expected_command = $expected_command + 1
											match validate_cell_command(list_at(store.commands, $command_index), $command_index, scenes, resources) {
												Err(error) => {
													$error = Invalid(error)
												}
												Ok(work) => {
													$form_placements = $form_placements + work.form_placements
													$image_placements = $image_placements + work.image_placements
													$shading_paints = $shading_paints + work.shading_paints
													match work.children {
														Leaf => {}
														Nested(children) => if children.length() == 0 {
															$error = Invalid(EmptyPatternCell({ pattern: $cell_index }))
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
			}
		}
		$cell_index = $cell_index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => if $expected_command < store.commands.len() {
			Err(Orphaned({ index: $expected_command, kind: PatternCommandIndex }))
		} else {
			Ok({
				cell_child_ranges: $child_ranges,
				cell_command_visits: $command_visits,
				cell_form_placements: $form_placements,
				cell_image_placements: $image_placements,
				cell_shading_paints: $shading_paints,
				max_cell_depth: $maximum_depth,
			})
		}
	}
}

validate_cell_command : Scene.Command, U64, Scene.Store, KernelScene.Resources -> Try(CommandWork, KernelScene.Error)
validate_cell_command = |command, index, scenes, resources| match command {
	DrawText(_) => Err(TextInPatternCell({ command: index }))
	Opacity(_) | SoftMask(_) => Err(TransparencyInPatternCell({ command: index }))
	DrawPath({ path: _, style }) => match style.fill {
		PatternFill(_) => Err(PatternInPatternCell({ command: index }))
		NoFill | SolidFill(_) => validate_command(command, index, scenes, resources)
	}
	_ => validate_command(command, index, scenes, resources)
}

## A pattern matrix must stay invertible; a zero or overflowing determinant
## has no deterministic tiling geometry.
validate_pattern_matrix : Scene.Matrix, U64 -> Try({}, KernelScene.Error)
validate_pattern_matrix = |matrix, pattern| {
	ad = I64.times_try(matrix.a.raw(), matrix.d.raw()) ? |_| ArithmeticOverflow
	bc = I64.times_try(matrix.b.raw(), matrix.c.raw()) ? |_| ArithmeticOverflow
	determinant = I64.minus_try(ad, bc) ? |_| ArithmeticOverflow
	if determinant == 0 {
		Err(PatternMatrixSingular({ pattern: pattern }))
	} else {
		Ok({})
	}
}

## Walks the flat form-command arena with the same dense once-each ownership
## cursor as page groups: every command belongs to exactly one form, child
## ranges stay inside the arena, and each command passes the identical typed
## validation as page content.
validate_forms : Scene.FormStore, Scene.Store, KernelScene.Resources, U64 -> Try(KernelScene.FormWork, KernelScene.Error)
validate_forms = |form_store, scenes, resources, max_depth| {
	var $form_index = 0
	var $expected_command = 0
	var $child_ranges = 0
	var $command_visits = 0
	var $nested_placements = 0
	var $opacity_commands = 0
	var $pattern_fills = 0
	var $shading_paints = 0
	var $soft_mask_commands = 0
	var $maximum_depth = 0
	var $error = NoError
	while $form_index < form_store.forms.len() and $error == NoError {
		form = list_at(form_store.forms, $form_index)
		if form.id.index() != $form_index {
			$error = Invalid(NonDenseIdentity({ actual: form.id.index(), expected: $form_index, kind: FormIndex }))
		} else if !positive_rect(form.bbox) {
			$error = Invalid(NonPositiveRect({ index: $form_index, kind: FormIndex }))
		} else if form.commands.length() == 0 {
			$error = Invalid(EmptyForm({ form: $form_index }))
		} else {
			var $frames = [Frame.{ depth: 1, range: form.commands }]
			var $frame_index = 0
			while $frame_index < $frames.len() and $error == NoError {
				frame = list_at($frames, $frame_index)
				if frame.depth > max_depth {
					$error = Invalid(LimitExceeded({ attempted: frame.depth, dimension: GraphicsDepth, limit: max_depth }))
				} else {
					$maximum_depth = U64.max($maximum_depth, frame.depth)
					match validate_span(frame.range, form_store.commands.len(), FormCommandIndex, $form_index) {
						Err(error) => {
							$error = Invalid(error)
						}
						Ok(span) => {
							var $command_index = span.start
							while $command_index < span.end and $error == NoError {
								if $command_index < $expected_command {
									$error = Invalid(DuplicateOwnership({ index: $command_index, kind: FormCommandIndex }))
								} else if $command_index > $expected_command {
									$error = Invalid(Orphaned({ index: $expected_command, kind: FormCommandIndex }))
								} else {
									$expected_command = $expected_command + 1
									match validate_command(list_at(form_store.commands, $command_index), $command_index, scenes, resources) {
										Err(error) => {
											$error = Invalid(error)
										}
										Ok(work) => {
											$nested_placements = $nested_placements + work.form_placements
											$opacity_commands = $opacity_commands + work.opacity_commands
											$pattern_fills = $pattern_fills + work.pattern_fills
											$shading_paints = $shading_paints + work.shading_paints
											$soft_mask_commands = $soft_mask_commands + work.soft_mask_commands
											match work.children {
												Leaf => {}
												Nested(children) => if children.length() == 0 {
													$error = Invalid(EmptyForm({ form: $form_index }))
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
		$form_index = $form_index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => if $expected_command < form_store.commands.len() {
			Err(Orphaned({ index: $expected_command, kind: FormCommandIndex }))
		} else {
			Ok({
				form_child_ranges: $child_ranges,
				form_command_visits: $command_visits,
				form_opacity_commands: $opacity_commands,
				form_pattern_fills: $pattern_fills,
				form_shading_paints: $shading_paints,
				form_soft_mask_commands: $soft_mask_commands,
				form_visits: form_store.forms.len(),
				max_form_depth: $maximum_depth,
				nested_form_placements: $nested_placements,
			})
		}
	}
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

validate_groups : Scene.Store, KernelScene.Resources, U64 -> Try({ child_ranges : U64, color_references : U64, command_visits : U64, dash_values : U64, form_placements : U64, image_placements : U64, max_graphics_depth : U64, opacity_commands : U64, pattern_fills : U64, shading_paints : U64, soft_mask_commands : U64, text_placements : U64 }, KernelScene.Error)
validate_groups = |scenes, resources, max_depth| {
	var $group_index = 0
	var $expected_command = 0
	var $child_ranges = 0
	var $color_references = 0
	var $command_visits = 0
	var $dash_values = 0
	var $form_placements = 0
	var $image_placements = 0
	var $opacity_commands = 0
	var $pattern_fills = 0
	var $shading_paints = 0
	var $soft_mask_commands = 0
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
											$form_placements = $form_placements + work.form_placements
											$image_placements = $image_placements + work.image_placements
											$opacity_commands = $opacity_commands + work.opacity_commands
											$pattern_fills = $pattern_fills + work.pattern_fills
											$shading_paints = $shading_paints + work.shading_paints
											$soft_mask_commands = $soft_mask_commands + work.soft_mask_commands
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
			Ok({ child_ranges: $child_ranges, color_references: $color_references, command_visits: $command_visits, dash_values: $dash_values, form_placements: $form_placements, image_placements: $image_placements, max_graphics_depth: $maximum_depth, opacity_commands: $opacity_commands, pattern_fills: $pattern_fills, shading_paints: $shading_paints, soft_mask_commands: $soft_mask_commands, text_placements: $text_placements })
		}
	}
}

validate_command : Scene.Command, U64, Scene.Store, KernelScene.Resources -> Try(CommandWork, KernelScene.Error)
validate_command = |command, index, scenes, resources| match command {
	Clip({ children, path }) => {
		validate_path_id(path, scenes.paths.len())?
		Ok({ ..leaf_work, children: Nested(children) })
	}
	DrawImage({ image, placement }) => {
		if image.index() >= resources.images {
			Err(IndexOutOfRange({ available: resources.images, index: image.index(), kind: ImageIndex }))
		} else if !positive_rect(placement) {
			Err(NonPositiveRect({ index, kind: CommandIndex }))
		} else {
			Ok({ ..leaf_work, image_placements: 1 })
		}
	}
	DrawPath({ path, style }) => {
		validate_path_id(path, scenes.paths.len())?
		work = validate_style(style, index, scenes.dash_lengths, resources)?
		Ok({ ..leaf_work, color_references: work.color_references, dash_values: work.dash_values, pattern_fills: work.pattern_fills })
	}
	DrawText({ paint, run }) => {
		if run.index() >= resources.text_runs {
			return Err(IndexOutOfRange({ available: resources.text_runs, index: run.index(), kind: TextRunIndex }))
		}
		colors = validate_text_paint(paint, index, resources.color_spaces)?
		Ok({ ..leaf_work, color_references: colors, text_placements: 1 })
	}

	## Constant opacity is a Gate 4 capability: form-aware scenes validate the
	## group's children like any nested range, while Gate 2/3 scenes keep the
	## explicit rejection. The `U16` value itself has no invalid state — zero
	## and fully opaque are both meaningful.
	Opacity({ children, opacity: _ }) => if resources.allow_opacity {
		Ok({ ..leaf_work, children: Nested(children), opacity_commands: 1 })
	} else {
		Err(UnsupportedCommand({ command: index }))
	}

	## Shading paints share the paint gate: the shading must name a declared
	## entry of the validated shading store; every earlier resource
	## constructor declares zero shadings and rejects the command outright.
	PaintShading({ shading }) => if !resources.allow_paints {
		Err(UnsupportedCommand({ command: index }))
	} else if shading.index() >= resources.shadings {
		Err(IndexOutOfRange({ available: resources.shadings, index: shading.index(), kind: ShadingIndex }))
	} else {
		Ok({ ..leaf_work, shading_paints: 1 })
	}

	## Alpha soft masks share the Gate 4 gate: the mask must name a declared
	## form (its isolated-group requirement is a normalization fact checked
	## with the form store), and the group's children validate like any
	## nested range.
	SoftMask({ children, mask }) => if !resources.allow_opacity {
		Err(UnsupportedCommand({ command: index }))
	} else if mask.index() >= resources.forms {
		Err(IndexOutOfRange({ available: resources.forms, index: mask.index(), kind: FormIndex }))
	} else {
		Ok({ ..leaf_work, children: Nested(children), soft_mask_commands: 1 })
	}
	PlaceForm({ form, transform }) => {
		if form.index() >= resources.forms {
			return Err(IndexOutOfRange({ available: resources.forms, index: form.index(), kind: FormIndex }))
		}
		validate_placement_transform(transform, index)?
		Ok({ ..leaf_work, form_placements: 1 })
	}
	Transform({ children, matrix: _ }) => Ok({ ..leaf_work, children: Nested(children) })
}

## A placement transform must stay invertible: a zero determinant collapses
## the placed form and an overflowing determinant cannot be reasoned about, so
## both are rejected before any content lowering.
validate_placement_transform : Scene.Matrix, U64 -> Try({}, KernelScene.Error)
validate_placement_transform = |matrix, command| {
	ad = I64.times_try(matrix.a.raw(), matrix.d.raw()) ? |_| ArithmeticOverflow
	bc = I64.times_try(matrix.b.raw(), matrix.c.raw()) ? |_| ArithmeticOverflow
	determinant = I64.minus_try(ad, bc) ? |_| ArithmeticOverflow
	if determinant == 0 {
		Err(FormTransformSingular({ command: command }))
	} else {
		Ok({})
	}
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

validate_style : Scene.PathStyle, U64, List(Layout.Unit), KernelScene.Resources -> Try({ color_references : U64, dash_values : U64, pattern_fills : U64 }, KernelScene.Error)
validate_style = |style, command, dash_lengths, resources| {
	fill = match style.fill {
		NoFill => Ok({ colors: 0, patterns: 0 })
		PatternFill({ pattern, rule: _ }) => if !resources.allow_paints {
			Err(UnsupportedCommand({ command: command }))
		} else if pattern.index() >= resources.patterns {
			Err(IndexOutOfRange({ available: resources.patterns, index: pattern.index(), kind: PatternIndex }))
		} else {
			Ok({ colors: 0, patterns: 1 })
		}
		SolidFill({ color, rule: _ }) => {
			validate_color(color, resources.color_spaces)?
			Ok({ colors: 1, patterns: 0 })
		}
	}?
	stroke_work = match style.stroke {
		NoStroke => Ok({ colors: 0, dash_values: 0 })
		SolidStroke(stroke) => validate_stroke(stroke, command, dash_lengths, resources.color_spaces)
	}?
	if fill.colors == 0 and fill.patterns == 0 and stroke_work.colors == 0 {
		scene_failure(
			UnpaintedPath({
				command: command,
			}),
		)
	} else {
		Ok({ color_references: fill.colors + stroke_work.colors, dash_values: stroke_work.dash_values, pattern_fills: fill.patterns })
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

test_form_store : Scene.FormStore
test_form_store = {
	commands: [
		Transform({
			children: Semantics.Range.from_start_and_length(1, 1),
			matrix: { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(0), f: unit(0) },
		}),
		DrawPath({ path: Scene.PathId.from_index(0), style: test_style }),
	],
	forms: [{ bbox: rect(0, 0, 1000, 1000), commands: Semantics.Range.from_start_and_length(0, 1), group: NoGroup, id: Scene.FormId.from_index(0) }],
}

form_placing_store : Scene.Store
form_placing_store = {
	..test_store,
	commands: [
		Transform({
			children: Semantics.Range.from_start_and_length(2, 1),
			matrix: { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(0), f: unit(0) },
		}),
		PlaceForm({ form: Scene.FormId.from_index(0), transform: { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(2000), f: unit(3000) } }),
		DrawImage({ image: Image.Id.from_index(0), placement: rect(0, 0, 1000, 1000) }),
	],
	groups: [{ commands: Semantics.Range.from_start_and_length(0, 2), id: Scene.GroupId.from_index(0), owner: PageArtifact(Background) }],
}

form_test_resources : KernelScene.Resources
form_test_resources = KernelScene.Resources.with_forms({ color_spaces: 1, forms: 1, images: 1, text_runs: 0 })

## Form content is validated with the same command rules as page content, with
## dense once-each arena ownership and the declared depth budget.
expect {
	plan = KernelScene.FormPlan.build(form_placing_store, test_form_store, form_test_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 }))?
	work = KernelScene.FormPlan.work(plan)
	page_work = KernelScene.Plan.work(KernelScene.FormPlan.page(plan))
	work.form_visits == 1 and work.form_command_visits == 2 and work.form_child_ranges == 1 and work.max_form_depth == 2 and work.nested_form_placements == 0 and page_work.form_placements == 1
}

## A Gate 2 or Gate 3 scene still rejects any form placement: the older
## resource constructors declare zero forms.
expect {
	match KernelScene.Plan.build(form_placing_store, test_resources, test_limits) {
		Err(IndexOutOfRange({ available: 0, index: 0, kind: FormIndex })) => True
		_ => False
	}
}

## A singular placement transform is rejected before any lowering.
expect {
	bad = {
		..form_placing_store,
		commands: list_set(
			form_placing_store.commands,
			1,
			PlaceForm({ form: Scene.FormId.from_index(0), transform: { a: unit(0), b: unit(0), c: unit(0), d: unit(1000), e: unit(0), f: unit(0) } }),
		),
	}
	match KernelScene.FormPlan.build(bad, test_form_store, form_test_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 })) {
		Err(FormTransformSingular({ command: 1 })) => True
		_ => False
	}
}

## Form identities stay dense and bounding boxes stay positive.
expect {
	sparse = { ..test_form_store, forms: [{ ..list_at(test_form_store.forms, 0), id: Scene.FormId.from_index(1) }] }
	flat = { ..test_form_store, forms: [{ ..list_at(test_form_store.forms, 0), bbox: rect(0, 0, 0, 1000) }] }
	limits = KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 })
	sparse_rejected = match KernelScene.FormPlan.build(form_placing_store, sparse, form_test_resources, test_limits, limits) {
		Err(NonDenseIdentity({ actual: 1, expected: 0, kind: FormIndex })) => True
		_ => False
	}
	flat_rejected = match KernelScene.FormPlan.build(form_placing_store, flat, form_test_resources, test_limits, limits) {
		Err(NonPositiveRect({ index: 0, kind: FormIndex })) => True
		_ => False
	}
	sparse_rejected and flat_rejected
}

opacity_store : Scene.Store
opacity_store = {
	..test_store,
	commands: [
		Opacity({ children: Semantics.Range.from_start_and_length(1, 2), opacity: 32768 }),
		DrawPath({ path: Scene.PathId.from_index(0), style: test_style }),
		Opacity({ children: Semantics.Range.from_start_and_length(3, 1), opacity: 65535 }),
		DrawImage({ image: Image.Id.from_index(0), placement: rect(0, 0, 1000, 1000) }),
	],
	groups: [{ commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.GroupId.from_index(0), owner: PageArtifact(Background) }],
}

## A form-aware scene validates constant-opacity groups like any nested range:
## the children stay once-each owned, depth is bounded, and every opacity
## command (opaque or not) is counted as validation work.
expect {
	plan = KernelScene.Plan.build(opacity_store, form_test_resources, test_limits)?
	work = KernelScene.Plan.work(plan)
	work.opacity_commands == 2 and work.command_visits == 4 and work.child_ranges == 2 and work.max_graphics_depth == 3 and work.image_placements == 1
}

## The same opacity scene stays rejected under the Gate 2 and Gate 3 resource
## constructors: constant opacity is a Gate 4 capability.
expect {
	made = match KernelScene.Plan.build(opacity_store, test_resources, test_limits) {
		Err(UnsupportedCommand({ command: 0 })) => True
		_ => False
	}
	with_text = match KernelScene.Plan.build(opacity_store, KernelScene.Resources.with_text({ color_spaces: 1, images: 1, text_runs: 0 }), test_limits) {
		Err(UnsupportedCommand({ command: 0 })) => True
		_ => False
	}
	made and with_text
}

## An empty opacity group cannot own zero commands.
expect {
	bad = {
		..opacity_store,
		commands: [
			Opacity({ children: Semantics.Range.from_start_and_length(1, 2), opacity: 32768 }),
			DrawPath({ path: Scene.PathId.from_index(0), style: test_style }),
			Opacity({ children: Semantics.Range.from_start_and_length(0, 0), opacity: 32768 }),
			DrawImage({ image: Image.Id.from_index(0), placement: rect(0, 0, 1000, 1000) }),
		],
	}
	match KernelScene.Plan.build(bad, form_test_resources, test_limits) {
		Err(EmptyCommandRange({ group: 0 })) => True
		_ => False
	}
}

## Soft-mask groups validate in form-aware scenes with nested children, a
## bounded mask reference, and counted work — and stay rejected under the
## Gate 2/3 resource constructors like every Gate 4 transparency command.
expect {
	masked = {
		..opacity_store,
		commands: [
			SoftMask({ children: span_of(1, 2), mask: Scene.FormId.from_index(0) }),
			DrawPath({ path: Scene.PathId.from_index(0), style: test_style }),
			Opacity({ children: span_of(3, 1), opacity: 32768 }),
			DrawImage({ image: Image.Id.from_index(0), placement: rect(0, 0, 1000, 1000) }),
		],
	}
	plan = KernelScene.Plan.build(masked, form_test_resources, test_limits)?
	work = KernelScene.Plan.work(plan)
	out_of_range = {
		..masked,
		commands: [
			SoftMask({ children: span_of(1, 2), mask: Scene.FormId.from_index(7) }),
			DrawPath({ path: Scene.PathId.from_index(0), style: test_style }),
			Opacity({ children: span_of(3, 1), opacity: 32768 }),
			DrawImage({ image: Image.Id.from_index(0), placement: rect(0, 0, 1000, 1000) }),
		],
	}
	bounds_rejected = match KernelScene.Plan.build(out_of_range, form_test_resources, test_limits) {
		Err(IndexOutOfRange({ available: 1, index: 7, kind: FormIndex })) => True
		_ => False
	}
	gate2_rejected = match KernelScene.Plan.build(masked, test_resources, test_limits) {
		Err(UnsupportedCommand({ command: 0 })) => True
		_ => False
	}
	work.soft_mask_commands == 1 and work.opacity_commands == 1 and work.command_visits == 4 and bounds_rejected and gate2_rejected
}

span_of : U64, U64 -> Semantics.Range
span_of = |start, length| Semantics.Range.from_start_and_length(start, length)

## Opacity groups inside form content validate with the identical command
## rules and are counted as form validation work.
expect {
	form_commands = [
		Opacity({ children: Semantics.Range.from_start_and_length(1, 1), opacity: 16384 }),
		DrawPath({ path: Scene.PathId.from_index(0), style: test_style }),
	]
	forms = { commands: form_commands, forms: [{ bbox: rect(0, 0, 1000, 1000), commands: Semantics.Range.from_start_and_length(0, 1), group: IsolatedGroup, id: Scene.FormId.from_index(0) }] }
	plan = KernelScene.FormPlan.build(form_placing_store, forms, form_test_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 }))?
	work = KernelScene.FormPlan.work(plan)
	work.form_opacity_commands == 1 and work.form_command_visits == 2 and work.max_form_depth == 2
}

paint_resources : KernelScene.Resources
paint_resources = KernelScene.Resources.with_paints({ color_spaces: 1, forms: 1, images: 1, patterns: 1, shadings: 1, text_runs: 0 })

paint_limits : KernelScene.PaintLimits
paint_limits = KernelScene.PaintLimits.make({ max_pattern_commands: 8, max_patterns: 2, max_shading_stops: 4, max_shadings: 2 })

test_shading : Scene.Shading
test_shading = {
	extend_end: Bool.False,
	extend_start: Bool.False,
	geometry: Axial({ end: { x: unit(9000), y: unit(0) }, start: { x: unit(1000), y: unit(0) } }),
	id: Scene.ShadingId.from_index(0),
	space: Color.SpaceId.from_index(0),
	stops: Semantics.Range.from_start_and_length(0, 2),
}

test_shading_store : Scene.ShadingStore
test_shading_store = {
	shadings: [test_shading],
	stops: [
		{ channels: Rgb({ blue: 0, green: 0, red: 65535 }), offset: 0 },
		{ channels: Rgb({ blue: 65535, green: 0, red: 0 }), offset: 65535 },
	],
}

test_pattern_store : Scene.PatternStore
test_pattern_store = {
	cells: [
		{
			bbox: rect(0, 0, 1000, 1000),
			commands: Semantics.Range.from_start_and_length(0, 1),
			id: Scene.PatternId.from_index(0),
			matrix: { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(0), f: unit(0) },
			x_step: unit(1000),
			y_step: unit(1000),
		},
	],
	commands: [DrawPath({ path: Scene.PathId.from_index(0), style: test_style })],
}

paint_scene : Scene.Store
paint_scene = {
	..test_store,
	commands: [
		Clip({ children: span_of(3, 1), path: Scene.PathId.from_index(0) }),
		DrawPath({ path: Scene.PathId.from_index(0), style: { fill: PatternFill({ pattern: Scene.PatternId.from_index(0), rule: Nonzero }), stroke: NoStroke } }),
		DrawImage({ image: Image.Id.from_index(0), placement: rect(0, 0, 1000, 1000) }),
		PaintShading({ shading: Scene.ShadingId.from_index(0) }),
	],
	groups: [{ commands: span_of(0, 3), id: Scene.GroupId.from_index(0), owner: PageArtifact(Background) }],
}

## A paint-aware plan validates shading stops, cell content, and paint
## commands with exact per-relationship work, counting shading paints and
## pattern fills across the page arena.
expect {
	plan = KernelScene.PaintPlan.build(paint_scene, test_form_store, test_shading_store, test_pattern_store, paint_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 }), paint_limits)?
	work = KernelScene.PaintPlan.work(plan)
	page_work = KernelScene.Plan.work(KernelScene.FormPlan.page(KernelScene.PaintPlan.forms(plan)))
	work.shading_visits == 1 and work.shading_stop_visits == 2 and work.cell_visits == 1 and work.cell_command_visits == 1 and page_work.shading_paints == 1 and page_work.pattern_fills == 1
}

## Paint commands stay rejected under every earlier resource constructor.
expect {
	gate2 = match KernelScene.Plan.build(paint_scene, test_resources, test_limits) {
		Err(UnsupportedCommand({ command })) => command == 1
		_ => False
	}
	forms_only = match KernelScene.Plan.build(paint_scene, form_test_resources, test_limits) {
		Err(UnsupportedCommand({ command })) => command == 1
		_ => False
	}
	gate2 and forms_only
}

## The stop model rejects too-few, misplaced-endpoint, and non-increasing
## stops with distinct structured diagnostics.
expect {
	single = { ..test_shading_store, shadings: [{ ..test_shading, stops: span_of(0, 1) }] }
	too_few = match KernelScene.PaintPlan.build(paint_scene, test_form_store, single, test_pattern_store, paint_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 }), paint_limits) {
		Err(TooFewShadingStops({ shading: 0, stops: 1 })) => True
		_ => False
	}
	late_start = {
		..test_shading_store,
		stops: [
			{ channels: Rgb({ blue: 0, green: 0, red: 65535 }), offset: 1 },
			{ channels: Rgb({ blue: 65535, green: 0, red: 0 }), offset: 65535 },
		],
	}
	endpoint = match KernelScene.PaintPlan.build(paint_scene, test_form_store, late_start, test_pattern_store, paint_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 }), paint_limits) {
		Err(ShadingStopEndpointInvalid({ shading: 0 })) => True
		_ => False
	}
	flat = {
		shadings: [{ ..test_shading, stops: span_of(0, 3) }],
		stops: [
			{ channels: Rgb({ blue: 0, green: 0, red: 65535 }), offset: 0 },
			{ channels: Rgb({ blue: 0, green: 65535, red: 0 }), offset: 0 },
			{ channels: Rgb({ blue: 65535, green: 0, red: 0 }), offset: 65535 },
		],
	}
	not_increasing = match KernelScene.PaintPlan.build(paint_scene, test_form_store, flat, test_pattern_store, paint_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 }), paint_limits) {
		Err(ShadingStopsNotIncreasing({ shading: 0, stop: 1 })) => True
		_ => False
	}
	too_few and endpoint and not_increasing
}

## Degenerate axial and radial geometry and negative radii are rejected; a
## single zero radius is a supported cone endpoint.
expect {
	flat_axis = { ..test_shading_store, shadings: [{ ..test_shading, geometry: Axial({ end: { x: unit(1000), y: unit(0) }, start: { x: unit(1000), y: unit(0) } }) }] }
	axial_rejected = match KernelScene.PaintPlan.build(paint_scene, test_form_store, flat_axis, test_pattern_store, paint_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 }), paint_limits) {
		Err(DegenerateShadingGeometry({ shading: 0 })) => True
		_ => False
	}
	negative = { ..test_shading_store, shadings: [{ ..test_shading, geometry: Radial({ end_center: { x: unit(5000), y: unit(0) }, end_radius: unit(1000), start_center: { x: unit(1000), y: unit(0) }, start_radius: unit(-1) }) }] }
	negative_rejected = match KernelScene.PaintPlan.build(paint_scene, test_form_store, negative, test_pattern_store, paint_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 }), paint_limits) {
		Err(NegativeShadingRadius({ shading: 0 })) => True
		_ => False
	}
	cone = { ..test_shading_store, shadings: [{ ..test_shading, geometry: Radial({ end_center: { x: unit(5000), y: unit(0) }, end_radius: unit(1000), start_center: { x: unit(1000), y: unit(0) }, start_radius: unit(0) }) }] }
	cone_accepted = match KernelScene.PaintPlan.build(paint_scene, test_form_store, cone, test_pattern_store, paint_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 }), paint_limits) {
		Ok(_) => True
		_ => False
	}
	axial_rejected and negative_rejected and cone_accepted
}

## Pattern cells reject text, transparency, and nested pattern fills, and
## keep positive steps and an invertible matrix.
expect {
	text_cell = { ..test_pattern_store, commands: [DrawText({ paint: test_text_paint, run: Text.RunId.from_index(0) })] }
	text_rejected = match KernelScene.PaintPlan.build(paint_scene, test_form_store, test_shading_store, text_cell, paint_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 }), paint_limits) {
		Err(TextInPatternCell({ command: 0 })) => True
		_ => False
	}
	opacity_cell = {
		..test_pattern_store,
		cells: [{ ..list_at(test_pattern_store.cells, 0), commands: span_of(0, 1) }],
		commands: [
			Opacity({ children: span_of(1, 1), opacity: 32768 }),
			DrawPath({ path: Scene.PathId.from_index(0), style: test_style }),
		],
	}
	opacity_rejected = match KernelScene.PaintPlan.build(paint_scene, test_form_store, test_shading_store, opacity_cell, paint_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 }), paint_limits) {
		Err(TransparencyInPatternCell({ command: 0 })) => True
		_ => False
	}
	nested_cell = { ..test_pattern_store, commands: [DrawPath({ path: Scene.PathId.from_index(0), style: { fill: PatternFill({ pattern: Scene.PatternId.from_index(0), rule: Nonzero }), stroke: NoStroke } })] }
	nested_rejected = match KernelScene.PaintPlan.build(paint_scene, test_form_store, test_shading_store, nested_cell, paint_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 }), paint_limits) {
		Err(PatternInPatternCell({ command: 0 })) => True
		_ => False
	}
	flat_step = { ..test_pattern_store, cells: [{ ..list_at(test_pattern_store.cells, 0), x_step: unit(0) }] }
	step_rejected = match KernelScene.PaintPlan.build(paint_scene, test_form_store, test_shading_store, flat_step, paint_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 }), paint_limits) {
		Err(PatternStepInvalid({ pattern: 0 })) => True
		_ => False
	}
	singular = { ..test_pattern_store, cells: [{ ..list_at(test_pattern_store.cells, 0), matrix: { a: unit(1000), b: unit(0), c: unit(0), d: unit(0), e: unit(0), f: unit(0) } }] }
	matrix_rejected = match KernelScene.PaintPlan.build(paint_scene, test_form_store, test_shading_store, singular, paint_resources, test_limits, KernelScene.FormLimits.make({ max_form_commands: 2, max_forms: 1 }), paint_limits) {
		Err(PatternMatrixSingular({ pattern: 0 })) => True
		_ => False
	}
	text_rejected and opacity_rejected and nested_rejected and step_rejected and matrix_rejected
}
