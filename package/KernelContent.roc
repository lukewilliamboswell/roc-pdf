import Color
import Image
import KernelGate2Fixture
import KernelGate2ResourceName
import KernelLex
import KernelTagged
import Layout
import Scene
import Semantics

KernelContent :: [].{
	Dimension : [ContentBytes, ContentStreams]
	Error : [
		ArithmeticOverflow,
		ContentStreamCountMismatch({ pages : U64, streams : U64 }),
		FragmentStreamMismatch({ fragment : U64, page : U64, stream : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		MissingMarkedFragment({ fragment : U64 }),
		TextRunInvalid({ prepared : U64, run : U64 }),
		UnsupportedValidatedCommand({ command : U64 }),
	]

	Limits :: { max_content_bytes : U64, max_content_streams : U64 }.{
		make : { max_content_bytes : U64, max_content_streams : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	Stream : { bytes : List(U8), page : Semantics.PageId, stream : Semantics.ContentStreamId }
	Work : {
		bytes_emitted : U64,
		command_visits : U64,
		graphics_state_pairs : U64,
		group_visits : U64,
		image_placements : U64,
		marked_artifact_groups : U64,
		marked_fragment_groups : U64,
		max_frame_depth : U64,
		path_segments : U64,
		text_placements : U64,
	}

	TextRun : { actual_text_begin : List(U8), body : List(U8), close_actual_text : Bool }

	TextPlan :: { runs : List(TextRun) }.{
		make : List(TextRun) -> TextPlan
		make = |runs| TextPlan.{ runs }

		run : TextPlan, U64 -> TextRun
		run = |plan, run| list_at(plan.runs, run)

		run_count : TextPlan -> U64
		run_count = |plan| plan.runs.len()
	}

	Plan :: { streams : List(Stream), work : Work }.{
		build : KernelTagged.Plan, Limits -> Try(Plan, Error)
		build = |tagged, limits| build_plan(tagged, NoText, limits)

		build_with_text : KernelTagged.Plan, TextPlan, Limits -> Try(Plan, Error)
		build_with_text = |tagged, text, limits| build_plan(tagged, WithText(text), limits)

		stream : Plan, Semantics.ContentStreamId -> Stream
		stream = |plan, stream| list_at(plan.streams, stream.index())

		stream_count : Plan -> U64
		stream_count = |plan| plan.streams.len()

		work : Plan -> Work
		work = |plan| plan.work
	}
}

MarkedSlot := [HasMarked(KernelTagged.MarkedContentReference), MissingMarked]

TextLowering := [NoText, WithText(KernelContent.TextPlan)]

Frame := { close_graphics : Bool, end : U64, next : U64 }

EmitWork := { bytes : List(U8), command_visits : U64, graphics_state_pairs : U64, image_placements : U64, max_frame_depth : U64, path_segments : U64, text_placements : U64 }

build_plan : KernelTagged.Plan, TextLowering, KernelContent.Limits -> Try(KernelContent.Plan, KernelContent.Error)
build_plan = |tagged, text, limits| {
	scenes = KernelTagged.Plan.scenes(tagged)
	semantics = KernelTagged.Plan.semantics(tagged)
	stream_count = KernelTagged.Plan.parent_rows(tagged).len()
	if stream_count > limits.max_content_streams {
		Err(LimitExceeded({ attempted: stream_count, dimension: ContentStreams, limit: limits.max_content_streams }))
	} else if stream_count != scenes.pages.len() {
		Err(ContentStreamCountMismatch({ pages: scenes.pages.len(), streams: stream_count }))
	} else {
		marked = index_marked(KernelTagged.Plan.marked_fragments(tagged), semantics.fragments.len())?
		var $streams = List.with_capacity(stream_count)
		var $page_index = 0
		var $total_bytes = 0
		var $command_visits = 0
		var $graphics_pairs = 0
		var $group_visits = 0
		var $image_placements = 0
		var $max_frame_depth = 0
		var $artifact_groups = 0
		var $fragment_groups = 0
		var $path_segments = 0
		var $text_placements = 0
		var $error = NoError
		while $page_index < scenes.pages.len() and $error == NoError {
			page = list_at(scenes.pages, $page_index)
			page_limit = limits.max_content_bytes - $total_bytes
			var $bytes = List.with_capacity(U64.min(page_limit, initial_content_capacity))
			var $edge = page.paint_order.start()
			end = $edge + page.paint_order.length()
			while $edge < end and $error == NoError {
				group = list_at(scenes.groups, list_at(scenes.page_groups, $edge).index())
				match open_group($bytes, group.owner, marked, $page_index, page_limit) {
					Err(error) => {
						$error = Invalid(error)
					}
					Ok(opened) => {
						$bytes = opened.bytes
						$artifact_groups = $artifact_groups + opened.artifacts
						$fragment_groups = $fragment_groups + opened.fragments
						match emit_commands($bytes, group.commands, scenes, text, page_limit) {
							Err(error) => {
								$error = Invalid(error)
							}
							Ok(emitted) => match append_literal(emitted.bytes, "EMC\n", page_limit) {
								Err(error) => {
									$error = Invalid(error)
								}
								Ok(closed) => {
									$bytes = closed
									$command_visits = $command_visits + emitted.command_visits
									$graphics_pairs = $graphics_pairs + emitted.graphics_state_pairs
									$image_placements = $image_placements + emitted.image_placements
									$max_frame_depth = U64.max($max_frame_depth, emitted.max_frame_depth)
									$path_segments = $path_segments + emitted.path_segments
									$text_placements = $text_placements + emitted.text_placements
								}
							}
						}
					}
				}
				$edge = $edge + 1
				$group_visits = $group_visits + 1
			}
			if $error == NoError {
				match checked_add($total_bytes, $bytes.len()) {
					Err(error) => {
						$error = Invalid(error)
					}
					Ok(total) => if total > limits.max_content_bytes {
						$error = Invalid(LimitExceeded({ attempted: total, dimension: ContentBytes, limit: limits.max_content_bytes }))
					} else {
						$total_bytes = total
						$streams = $streams.append({ bytes: $bytes, page: page.id, stream: Semantics.ContentStreamId.from_index($page_index) })
					}
				}
			}
			$page_index = $page_index + 1
		}
		match $error {
			Invalid(error) => Err(error)
			NoError => Ok(
				KernelContent.Plan.{
					streams: $streams,
					work: {
						bytes_emitted: $total_bytes,
						command_visits: $command_visits,
						graphics_state_pairs: $graphics_pairs,
						group_visits: $group_visits,
						image_placements: $image_placements,
						marked_artifact_groups: $artifact_groups,
						marked_fragment_groups: $fragment_groups,
						max_frame_depth: $max_frame_depth,
						path_segments: $path_segments,
						text_placements: $text_placements,
					},
				},
			)
		}
	}
}

index_marked : List(KernelTagged.MarkedContentReference), U64 -> Try(List(MarkedSlot), KernelContent.Error)
index_marked = |references, fragment_count| {
	var $slots = List.repeat(MissingMarked, fragment_count)
	var $index = 0
	while $index < references.len() {
		reference = list_at(references, $index)
		$slots = list_set($slots, reference.fragment.index(), HasMarked(reference))
		$index = $index + 1
	}
	Ok($slots)
}

open_group : List(U8), Scene.GroupOwner, List(MarkedSlot), U64, U64 -> Try({ artifacts : U64, bytes : List(U8), fragments : U64 }, KernelContent.Error)
open_group = |bytes, owner, marked, page, limit| match owner {
	Fragment(fragment) => match list_at(marked, fragment.index()) {
		MissingMarked => Err(MissingMarkedFragment({ fragment: fragment.index() }))
		HasMarked(reference) => {
			stream = reference.content_stream.index()
			if stream != page {
				Err(FragmentStreamMismatch({ fragment: fragment.index(), page, stream }))
			} else {
				with_tag = append_literal(bytes, "/P <</MCID ", limit)?
				with_mcid = append_unsigned(with_tag, reference.mcid, limit)?
				opened = append_literal(with_mcid, ">> BDC\n", limit)?
				Ok({ artifacts: 0, bytes: opened, fragments: 1 })
			}
		}
	}
	PageArtifact(kind) => {
		prefix = match kind {
			Background => "/Artifact <</Type /Background>> BDC\n"
			Decoration => "/Artifact <</Type /Layout>> BDC\n"
			Footer => "/Artifact <</Type /Pagination /Subtype /Footer>> BDC\n"
			Header => "/Artifact <</Type /Pagination /Subtype /Header>> BDC\n"
			PageNumber => "/Artifact <</Type /Pagination /Subtype /PageNum>> BDC\n"
			Watermark => "/Artifact <</Type /Pagination /Subtype /Watermark>> BDC\n"
		}
		Ok({ artifacts: 1, bytes: append_literal(bytes, prefix, limit)?, fragments: 0 })
	}
}

emit_commands : List(U8), Semantics.Range, Scene.Store, TextLowering, U64 -> Try(EmitWork, KernelContent.Error)
emit_commands = |initial, root, scenes, text, limit| {
	var $bytes = initial
	var $frames = []
	var $current = Frame.{ close_graphics: False, end: root.start() + root.length(), next: root.start() }
	var $active = 0
	var $done = False
	var $command_visits = 0
	var $graphics_pairs = 0
	var $image_placements = 0
	var $max_frame_depth = 1
	var $path_segments = 0
	var $text_placements = 0
	var $error = NoError
	while $done == False and $error == NoError {
		if $current.next >= $current.end {
			if $current.close_graphics {
				match append_literal($bytes, "Q\n", limit) {
					Err(error) => {
						$error = Invalid(error)
					}
					Ok(bytes) => {
						$bytes = bytes
					}
				}
			}
			if $active == 0 {
				$done = True
			} else {
				$active = $active - 1
				$current = list_at($frames, $active)
			}
		} else {
			command_index = $current.next
			$current = { ..$current, next: $current.next + 1 }
			command = list_at(scenes.commands, command_index)
			match command {
				Clip({ children, path }) => match emit_clip_open($bytes, path, scenes, limit) {
					Err(error) => {
						$error = Invalid(error)
					}
					Ok(opened) => {
						$bytes = opened.bytes
						$path_segments = $path_segments + opened.path_segments
						$frames = push_frame($frames, $active, $current)
						$active = $active + 1
						$current = Frame.{ close_graphics: True, end: children.start() + children.length(), next: children.start() }
						$max_frame_depth = U64.max($max_frame_depth, $active + 1)
						$graphics_pairs = $graphics_pairs + 1
					}
				}
				DrawImage({ image, placement }) => {
					required = image_length(image, placement)
					if $bytes.len() > limit or required > limit - $bytes.len() {
						attempted = match U64.plus_try($bytes.len(), required) {
							Err(Overflow) => U64.highest
							Ok(total) => total
						}
						$error = Invalid(LimitExceeded({ attempted, dimension: ContentBytes, limit }))
					} else {
						$bytes = emit_image_unchecked($bytes, image, placement)
						$graphics_pairs = $graphics_pairs + 1
						$image_placements = $image_placements + 1
					}
				}
				DrawPath({ path, style }) => match emit_draw_path($bytes, path, style, scenes, limit) {
					Err(error) => {
						$error = Invalid(error)
					}
					Ok(emitted) => {
						$bytes = emitted.bytes
						$path_segments = $path_segments + emitted.path_segments
					}
				}
				DrawText({ paint, run }) => match text {
					NoText => {
						$error = Invalid(UnsupportedValidatedCommand({ command: command_index }))
					}
					WithText(plan) => if run.index() >= KernelContent.TextPlan.run_count(plan) {
						$error = Invalid(TextRunInvalid({ prepared: KernelContent.TextPlan.run_count(plan), run: run.index() }))
					} else {
						match emit_text($bytes, paint, KernelContent.TextPlan.run(plan, run.index()), limit) {
							Err(error) => {
								$error = Invalid(error)
							}
							Ok(bytes) => {
								$bytes = bytes
								$text_placements = $text_placements + 1
							}
						}
					}
				}
				Opacity(_) => {
					$error = Invalid(UnsupportedValidatedCommand({ command: command_index }))
				}
				Transform({ children, matrix }) => match emit_transform_open($bytes, matrix, limit) {
					Err(error) => {
						$error = Invalid(error)
					}
					Ok(bytes) => {
						$bytes = bytes
						$frames = push_frame($frames, $active, $current)
						$active = $active + 1
						$current = Frame.{ close_graphics: True, end: children.start() + children.length(), next: children.start() }
						$max_frame_depth = U64.max($max_frame_depth, $active + 1)
						$graphics_pairs = $graphics_pairs + 1
					}
				}
			}
			$command_visits = $command_visits + 1
		}
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ bytes: $bytes, command_visits: $command_visits, graphics_state_pairs: $graphics_pairs, image_placements: $image_placements, max_frame_depth: $max_frame_depth, path_segments: $path_segments, text_placements: $text_placements })
	}
}

emit_text : List(U8), Scene.TextPaint, KernelContent.TextRun, U64 -> Try(List(U8), KernelContent.Error)
emit_text = |bytes, paint, run, limit| {
	var $out = append_bytes(bytes, run.actual_text_begin, limit)?
	$out = emit_color($out, paint.fill, False, limit)?
	$out = match paint.mode {
		Fill => append_literal($out, "BT\n0 Tr\n", limit)?
		FillAndStroke => match paint.stroke {
			NoStroke => {
				crash "validated fill-and-stroke text lost its stroke"
			}
			Stroke({ color, width }) => {
				var $stroked = emit_color($out, color, True, limit)?
				$stroked = append_layout($stroked, width, limit)?
				$stroked = append_literal($stroked, " w\nBT\n2 Tr\n", limit)?
				$stroked
			}
		}
	}
	$out = append_bytes($out, run.body, limit)?
	$out = append_literal($out, "ET\n", limit)?
	if run.close_actual_text append_literal($out, "EMC\n", limit) else Ok($out)
}

push_frame : List(Frame), U64, Frame -> List(Frame)
push_frame = |frames, index, frame| if index < frames.len() list_set(frames, index, frame) else frames.append(frame)

emit_transform_open : List(U8), Scene.Matrix, U64 -> Try(List(U8), KernelContent.Error)
emit_transform_open = |bytes, matrix, limit| {
	var $out = append_literal(bytes, "q\n", limit)?
	$out = append_layout($out, matrix.a, limit)?
	$out = append_literal($out, " ", limit)?
	$out = append_layout($out, matrix.b, limit)?
	$out = append_literal($out, " ", limit)?
	$out = append_layout($out, matrix.c, limit)?
	$out = append_literal($out, " ", limit)?
	$out = append_layout($out, matrix.d, limit)?
	$out = append_literal($out, " ", limit)?
	$out = append_layout($out, matrix.e, limit)?
	$out = append_literal($out, " ", limit)?
	$out = append_layout($out, matrix.f, limit)?
	append_literal($out, " cm\n", limit)
}

emit_clip_open : List(U8), Scene.PathId, Scene.Store, U64 -> Try({ bytes : List(U8), path_segments : U64 }, KernelContent.Error)
emit_clip_open = |bytes, path, scenes, limit| {
	opened = append_literal(bytes, "q\n", limit)?
	emitted = emit_path(opened, path, scenes, limit)?
	Ok({ bytes: append_literal(emitted.bytes, "W n\n", limit)?, path_segments: emitted.path_segments })
}

emit_image_unchecked : List(U8), Image.Id, Layout.Rect -> List(U8)
emit_image_unchecked = |bytes, image, placement| {
	var $out = append_all_unchecked(bytes, image_open_bytes)
	$out = append_thousandths_unchecked($out, placement.size.width.raw())
	$out = append_all_unchecked($out, image_matrix_middle_bytes)
	$out = append_thousandths_unchecked($out, placement.size.height.raw())
	$out = append_all_unchecked($out, space_bytes)
	$out = append_thousandths_unchecked($out, placement.origin.x.raw())
	$out = append_all_unchecked($out, space_bytes)
	$out = append_thousandths_unchecked($out, placement.origin.y.raw())
	$out = append_all_unchecked($out, image_name_prefix_bytes)
	$out = KernelGate2ResourceName.append($out, image.index())
	append_all_unchecked($out, image_close_bytes)
}

image_length : Image.Id, Layout.Rect -> U64
image_length = |image, placement| {
	image_open_bytes.len() +
		decimal_length(placement.size.width.raw(), 3) +
		image_matrix_middle_bytes.len() +
		decimal_length(placement.size.height.raw(), 3) +
		space_bytes.len() +
		decimal_length(placement.origin.x.raw(), 3) +
		space_bytes.len() +
		decimal_length(placement.origin.y.raw(), 3) +
		image_name_prefix_bytes.len() +
		KernelGate2ResourceName.suffix_length(image.index()) +
		image_close_bytes.len()
}

image_open_bytes : List(U8)
image_open_bytes = [113, 10]

image_matrix_middle_bytes : List(U8)
image_matrix_middle_bytes = [32, 48, 32, 48, 32]

space_bytes : List(U8)
space_bytes = [32]

image_name_prefix_bytes : List(U8)
image_name_prefix_bytes = [32, 99, 109, 10, 47, 73, 109]

image_close_bytes : List(U8)
image_close_bytes = [32, 68, 111, 10, 81, 10]

append_all_unchecked : List(U8), List(U8) -> List(U8)
append_all_unchecked = |target, source| {
	var $out = target
	var $index = 0
	while $index < source.len() {
		$out = $out.append(list_at(source, $index))
		$index = $index + 1
	}
	$out
}

append_thousandths_unchecked : List(U8), I64 -> List(U8)
append_thousandths_unchecked = |output, coefficient| {
	if coefficient == 0 {
		output.append(48)
	} else {
		magnitude = if coefficient < 0 U64.minus_wrap(0, coefficient.to_u64_wrap()) else coefficient.to_u64_wrap()
		var $normalized = magnitude
		var $scale = 3
		while $scale > 0 and U64.mod_by($normalized, 10) == 0 {
			$normalized = U64.div_by($normalized, 10)
			$scale = $scale - 1
		}
		var $out = if coefficient < 0 output.append(45) else output
		if $scale == 0 {
			var $remaining = $normalized
			var $divisor = 1
			while $remaining >= 10 {
				$remaining = U64.div_by($remaining, 10)
				$divisor = $divisor * 10
			}
			while $divisor > 0 {
				digit = U64.mod_by(U64.div_by($normalized, $divisor), 10)
				$out = $out.append((48 + digit).to_u8_wrap())
				$divisor = U64.div_by($divisor, 10)
			}
			$out
		} else {
			power = match $scale {
				1 => 10
				2 => 100
				_ => 1000
			}
			whole = U64.div_by($normalized, power)
			fraction = U64.mod_by($normalized, power)
			var $whole_remaining = whole
			var $whole_divisor = 1
			while $whole_remaining >= 10 {
				$whole_remaining = U64.div_by($whole_remaining, 10)
				$whole_divisor = $whole_divisor * 10
			}
			while $whole_divisor > 0 {
				digit = U64.mod_by(U64.div_by(whole, $whole_divisor), 10)
				$out = $out.append((48 + digit).to_u8_wrap())
				$whole_divisor = U64.div_by($whole_divisor, 10)
			}
			$out = $out.append(46)
			var $fraction_divisor = U64.div_by(power, 10)
			while $fraction_divisor > 0 {
				digit = U64.mod_by(U64.div_by(fraction, $fraction_divisor), 10)
				$out = $out.append((48 + digit).to_u8_wrap())
				$fraction_divisor = U64.div_by($fraction_divisor, 10)
			}
			$out
		}
	}
}

## The hot layout writer is byte-identical to the general lexical boundary.
expect {
	values = [I64.lowest, -25, 0, 1, 1200, I64.highest]
	var $index = 0
	var $same = True
	while $index < values.len() and $same {
		value = list_at(values, $index)
		$same = append_thousandths_unchecked([], value) == KernelLex.append_thousandths([], value)
		$index = $index + 1
	}
	$same
}

emit_draw_path : List(U8), Scene.PathId, Scene.PathStyle, Scene.Store, U64 -> Try({ bytes : List(U8), path_segments : U64 }, KernelContent.Error)
emit_draw_path = |bytes, path, style, scenes, limit| {
	styled = emit_style(bytes, style, scenes.dash_lengths, limit)?
	emitted = emit_path(styled, path, scenes, limit)?
	operator = match style.fill {
		NoFill => "S\n"
		SolidFill({ color: _, rule }) => match style.stroke {
			NoStroke => match rule {
				EvenOdd => "f*\n"
				Nonzero => "f\n"
			}
			SolidStroke(_) => match rule {
				EvenOdd => "B*\n"
				Nonzero => "B\n"
			}
		}
	}
	Ok({ bytes: append_literal(emitted.bytes, operator, limit)?, path_segments: emitted.path_segments })
}

emit_style : List(U8), Scene.PathStyle, List(Layout.Unit), U64 -> Try(List(U8), KernelContent.Error)
emit_style = |bytes, style, dash_lengths, limit| {
	with_fill = match style.fill {
		NoFill => Ok(bytes)
		SolidFill({ color, rule: _ }) => emit_color(bytes, color, False, limit)
	}?
	match style.stroke {
		NoStroke => Ok(with_fill)
		SolidStroke(stroke) => emit_stroke(with_fill, stroke, dash_lengths, limit)
	}
}

emit_stroke : List(U8), Scene.StrokeStyle, List(Layout.Unit), U64 -> Try(List(U8), KernelContent.Error)
emit_stroke = |bytes, stroke, dash_lengths, limit| {
	var $out = emit_color(bytes, stroke.color, True, limit)?
	$out = append_layout($out, stroke.width, limit)?
	$out = append_literal($out, " w\n", limit)?
	cap = match stroke.cap {
		ButtCap => 0
		ProjectingSquareCap => 2
		RoundCap => 1
	}
	$out = append_unsigned($out, cap, limit)?
	$out = append_literal($out, " J\n", limit)?
	join = match stroke.join {
		BevelJoin => 2
		MiterJoin => 0
		RoundJoin => 1
	}
	$out = append_unsigned($out, join, limit)?
	$out = append_literal($out, " j\n", limit)?
	$out = append_layout($out, stroke.miter_limit, limit)?
	$out = append_literal($out, " M\n", limit)?
	match stroke.dash {
		SolidLine => Ok(append_literal($out, "[] 0 d\n", limit)?)
		Dashed({ lengths, phase }) => {
			$out = append_literal($out, "[", limit)?
			var $index = lengths.start()
			end = $index + lengths.length()
			while $index < end {
				if $index > lengths.start() {
					$out = append_literal($out, " ", limit)?
				}
				$out = append_layout($out, list_at(dash_lengths, $index), limit)?
				$index = $index + 1
			}
			$out = append_literal($out, "] ", limit)?
			$out = append_layout($out, phase, limit)?
			Ok(append_literal($out, " d\n", limit)?)
		}
	}
}

emit_color : List(U8), Color.Value, Bool, U64 -> Try(List(U8), KernelContent.Error)
emit_color = |bytes, color, stroking, limit| {
	var $out = append_literal(bytes, "/CS", limit)?
	$out = append_resource_index($out, color.space.index(), limit)?
	$out = append_literal($out, if stroking " CS\n" else " cs\n", limit)?
	match color.channels {
		Gray(gray) => {
			$out = append_channel($out, gray, limit)?
			append_literal($out, if stroking " SCN\n" else " scn\n", limit)
		}
		Rgb({ blue, green, red }) => {
			$out = append_channel($out, red, limit)?
			$out = append_literal($out, " ", limit)?
			$out = append_channel($out, green, limit)?
			$out = append_literal($out, " ", limit)?
			$out = append_channel($out, blue, limit)?
			append_literal($out, if stroking " SCN\n" else " scn\n", limit)
		}
	}
}

emit_path : List(U8), Scene.PathId, Scene.Store, U64 -> Try({ bytes : List(U8), path_segments : U64 }, KernelContent.Error)
emit_path = |bytes, path_id, scenes, limit| {
	path = list_at(scenes.paths, path_id.index())
	var $out = bytes
	var $index = path.segments.start()
	end = $index + path.segments.length()
	while $index < end {
		match list_at(scenes.path_segments, $index) {
			Close => {
				$out = append_literal($out, "h\n", limit)?
			}
			CubicTo({ control_1, control_2, end: endpoint }) => {
				$out = append_point($out, control_1, limit)?
				$out = append_literal($out, " ", limit)?
				$out = append_point($out, control_2, limit)?
				$out = append_literal($out, " ", limit)?
				$out = append_point($out, endpoint, limit)?
				$out = append_literal($out, " c\n", limit)?
			}
			LineTo(point) => {
				$out = append_point($out, point, limit)?
				$out = append_literal($out, " l\n", limit)?
			}
			MoveTo(point) => {
				$out = append_point($out, point, limit)?
				$out = append_literal($out, " m\n", limit)?
			}
			Rectangle(rectangle) => {
				$out = append_point($out, rectangle.origin, limit)?
				$out = append_literal($out, " ", limit)?
				$out = append_layout($out, rectangle.size.width, limit)?
				$out = append_literal($out, " ", limit)?
				$out = append_layout($out, rectangle.size.height, limit)?
				$out = append_literal($out, " re\n", limit)?
			}
		}
		$index = $index + 1
	}
	Ok({ bytes: $out, path_segments: path.segments.length() })
}

append_point : List(U8), Layout.Point, U64 -> Try(List(U8), KernelContent.Error)
append_point = |bytes, point, limit| {
	with_x = append_layout(bytes, point.x, limit)?
	with_space = append_literal(with_x, " ", limit)?
	append_layout(with_space, point.y, limit)
}

append_layout : List(U8), Layout.Unit, U64 -> Try(List(U8), KernelContent.Error)
append_layout = |bytes, value, limit| {
	coefficient = value.raw()
	reserved = reserve_exact(bytes, decimal_length(coefficient, 3), limit)?
	Ok(KernelLex.append_thousandths(reserved, coefficient))
}

append_channel : List(U8), U16, U64 -> Try(List(U8), KernelContent.Error)
append_channel = |bytes, value, limit| {
	numerator = value.to_u64() * 1000000000
	coefficient = round_half_even(numerator, 65535)
	coefficient_i64 = coefficient.to_i64_wrap()
	reserved = reserve_exact(bytes, decimal_length(coefficient_i64, 9), limit)?
	Ok(KernelLex.append_billionths(reserved, coefficient_i64))
}

round_half_even : U64, U64 -> U64
round_half_even = |numerator, denominator| {
	quotient = U64.div_by(numerator, denominator)
	remainder = U64.mod_by(numerator, denominator)
	twice = remainder * 2
	if twice > denominator or (twice == denominator and U64.mod_by(quotient, 2) == 1) quotient + 1 else quotient
}

append_unsigned : List(U8), U64, U64 -> Try(List(U8), KernelContent.Error)
append_unsigned = |bytes, value, limit| {
	reserved = reserve_exact(bytes, unsigned_length(value), limit)?
	Ok(KernelLex.append_unsigned(reserved, value))
}

append_resource_index : List(U8), U64, U64 -> Try(List(U8), KernelContent.Error)
append_resource_index = |bytes, value, limit| {
	reserved = reserve_exact(bytes, KernelGate2ResourceName.suffix_length(value), limit)?
	Ok(KernelGate2ResourceName.append(reserved, value))
}

append_literal : List(U8), Str, U64 -> Try(List(U8), KernelContent.Error)
append_literal = |bytes, value, limit| append_bytes(bytes, Str.to_utf8(value), limit)

append_bytes : List(U8), List(U8), U64 -> Try(List(U8), KernelContent.Error)
append_bytes = |bytes, addition, limit| {
	match reserve_exact(bytes, addition.len(), limit) {
		Err(error) => Err(error)
		Ok(reserved) => {
			var $out = reserved
			var $index = 0
			while $index < addition.len() {
				$out = $out.append(list_at(addition, $index))
				$index = $index + 1
			}
			Ok($out)
		}
	}
}

reserve_exact : List(U8), U64, U64 -> Try(List(U8), KernelContent.Error)
reserve_exact = |bytes, additional, limit| {
	attempted = checked_add(bytes.len(), additional)?
	if attempted > limit {
		Err(LimitExceeded({ attempted, dimension: ContentBytes, limit }))
	} else {
		remaining = limit - bytes.len()
		geometric_spare = U64.max(additional, attempted)
		Ok(List.reserve(bytes, U64.min(remaining, geometric_spare)))
	}
}

initial_content_capacity : U64
initial_content_capacity = 4096

unsigned_length : U64 -> U64
unsigned_length = |value| {
	var $remaining = value
	var $digits = 1
	while $remaining >= 10 {
		$remaining = U64.div_by($remaining, 10)
		$digits = $digits + 1
	}
	$digits
}

decimal_length : I64, U8 -> U64
decimal_length = |coefficient, original_scale| {
	if coefficient == 0 {
		1
	} else {
		var $magnitude = if coefficient < 0 U64.minus_wrap(0, coefficient.to_u64_wrap()) else coefficient.to_u64_wrap()
		var $scale = original_scale.to_u64()
		while $scale > 0 and U64.mod_by($magnitude, 10) == 0 {
			$magnitude = U64.div_by($magnitude, 10)
			$scale = $scale - 1
		}
		sign = if coefficient < 0 1 else 0
		if $scale == 0 {
			sign + unsigned_length($magnitude)
		} else {
			power = power_of_ten($scale)
			whole = U64.div_by($magnitude, power)
			sign + unsigned_length(whole) + 1 + $scale
		}
	}
}

power_of_ten : U64 -> U64
power_of_ten = |exponent| {
	var $value = 1
	var $index = 0
	while $index < exponent {
		$value = $value * 10
		$index = $index + 1
	}
	$value
}

checked_add : U64, U64 -> Try(U64, KernelContent.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated content index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated content update escaped"
	}
}

## Content lowering preserves paint order, nesting, marked ownership, and exact fixed-point numbers.
expect {
	tagged = KernelGate2Fixture.tagged_plan(1)?
	plan = KernelContent.Plan.build(tagged, KernelContent.Limits.make({ max_content_bytes: 512, max_content_streams: 1 }))?
	stream = KernelContent.Plan.stream(plan, Semantics.ContentStreamId.from_index(0))
	expected =
		\\/P <</MCID 0>> BDC
		\\/CS1_0 cs
		\\0.50000763 scn
		\\0 0 1 1 re
		\\f
		\\EMC
		\\/Artifact <</Type /Background>> BDC
		\\q
		\\1 0 0 1 2 3 cm
		\\q
		\\2 0 0 1 4 5 cm
		\\/Im1_0 Do
		\\Q
		\\Q
		\\EMC
	stream.bytes == Str.to_utf8("${expected}\n")
}

## Content work counts each arena command and balanced graphics pair once.
expect {
	tagged = KernelGate2Fixture.tagged_plan(1)?
	plan = KernelContent.Plan.build(tagged, KernelContent.Limits.make({ max_content_bytes: 512, max_content_streams: 1 }))?
	work = KernelContent.Plan.work(plan)
	work.command_visits == 3 and work.group_visits == 2 and work.graphics_state_pairs == 2 and work.image_placements == 1 and work.max_frame_depth == 2 and work.path_segments == 1 and work.marked_fragment_groups == 1 and work.marked_artifact_groups == 1 and work.bytes_emitted == KernelContent.Plan.stream(plan, Semantics.ContentStreamId.from_index(0)).bytes.len()
}

## Clip, stroke, cap, join, miter, and dash operators lower from typed values.
expect {
	stroke : Scene.StrokeStyle
	stroke = {
		cap: ProjectingSquareCap,
		color: { channels: Gray(65535), space: Color.SpaceId.from_index(0) },
		dash: Dashed({ lengths: Semantics.Range.from_start_and_length(0, 2), phase: KernelGate2Fixture.unit(250) }),
		join: BevelJoin,
		miter_limit: KernelGate2Fixture.unit(10000),
		width: KernelGate2Fixture.unit(500),
	}
	scenes = {
		..KernelGate2Fixture.scene,
		commands: [
			Clip({ children: Semantics.Range.from_start_and_length(1, 1), path: Scene.PathId.from_index(0) }),
			DrawPath({ path: Scene.PathId.from_index(0), style: { fill: NoFill, stroke: SolidStroke(stroke) } }),
		],
		dash_lengths: [KernelGate2Fixture.unit(1000), KernelGate2Fixture.unit(500)],
	}
	emitted = emit_commands([], Semantics.Range.from_start_and_length(0, 1), scenes, NoText, 512)?
	expected =
		\\q
		\\0 0 1 1 re
		\\W n
		\\/CS1_0 CS
		\\1 SCN
		\\0.5 w
		\\2 J
		\\2 j
		\\10 M
		\\[1 0.5] 0.25 d
		\\0 0 1 1 re
		\\S
		\\Q
	emitted.bytes == Str.to_utf8("${expected}\n") and emitted.command_visits == 2 and emitted.graphics_state_pairs == 1 and emitted.path_segments == 2
}

## RGB channel order and every Gate 2 path segment have canonical operators.
expect {
	segments = [
		MoveTo({ x: KernelGate2Fixture.unit(0), y: KernelGate2Fixture.unit(0) }),
		LineTo({ x: KernelGate2Fixture.unit(1000), y: KernelGate2Fixture.unit(0) }),
		CubicTo({ control_1: { x: KernelGate2Fixture.unit(1000), y: KernelGate2Fixture.unit(500) }, control_2: { x: KernelGate2Fixture.unit(500), y: KernelGate2Fixture.unit(1000) }, end: { x: KernelGate2Fixture.unit(0), y: KernelGate2Fixture.unit(1000) } }),
		Close,
	]
	scenes = {
		..KernelGate2Fixture.scene,
		commands: [DrawPath({ path: Scene.PathId.from_index(0), style: { fill: SolidFill({ color: { channels: Rgb({ blue: 0, green: 32768, red: 65535 }), space: Color.SpaceId.from_index(0) }, rule: EvenOdd }), stroke: NoStroke } })],
		path_segments: segments,
		paths: [{ id: Scene.PathId.from_index(0), segments: Semantics.Range.from_start_and_length(0, segments.len()) }],
	}
	emitted = emit_commands([], Semantics.Range.from_start_and_length(0, 1), scenes, NoText, 512)?
	expected =
		\\/CS1_0 cs
		\\1 0.50000763 0 scn
		\\0 0 m
		\\1 0 l
		\\1 0.5 0.5 1 0 1 c
		\\h
		\\f*
	emitted.bytes == Str.to_utf8("${expected}\n") and emitted.command_visits == 1 and emitted.path_segments == 4
}

## Gate 2 currently requires one deterministic content stream per page.
expect {
	tagged = KernelGate2Fixture.tagged_plan(2)?
	match KernelContent.Plan.build(tagged, KernelContent.Limits.make({ max_content_bytes: 512, max_content_streams: 2 })) {
		Err(ContentStreamCountMismatch({ pages: 1, streams: 2 })) => True
		_ => False
	}
}

## A content limit rejects the plan instead of returning a partial stream.
expect {
	tagged = KernelGate2Fixture.tagged_plan(1)?
	match KernelContent.Plan.build(tagged, KernelContent.Limits.make({ max_content_bytes: 32, max_content_streams: 1 })) {
		Err(LimitExceeded({ attempted: _, dimension: ContentBytes, limit: 32 })) => True
		_ => False
	}
}
