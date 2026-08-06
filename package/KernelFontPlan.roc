import KernelFont
import KernelSha256

KernelFontPlan :: [].{
	Error : [
		ArithmeticOverflow,
		FontFailure(KernelFont.Error),
		GlyphOutOfRange({ glyph : U32, glyph_count : U64, usage_index : U64 }),
		GlyphZeroUsed({ usage_index : U64 }),
		RetainedGlyphLimitExceeded({ attempted : U64, limit : U64 }),
	]

	Limits :: { max_retained_glyphs : U64 }.{
		make : { max_retained_glyphs : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	Usage : { glyph : U32 }
	Entry : {
		cid : U32,
		content : Bool,
		original_glyph : U32,
		left_side_bearing : I64,
		subset_glyph : U32,
		width : U16,
	}
	Work : {
		component_edge_visits : U64,
		component_index_visits : U64,
		glyph_scans : U64,
		retained_glyphs : U64,
		usage_visits : U64,
	}
	Plan : {
		entries : List(Entry),
		original_to_subset : List(U32),
		prefix : List(U8),
		retained : List(U8),
		work : Work,
	}

	plan : KernelFont.Inspection, List(Usage), Limits -> Try(Plan, Error)
	plan = |font, usages, limits| plan_font(font, usages, limits)
}

plan_font : KernelFont.Inspection, List(KernelFontPlan.Usage), KernelFontPlan.Limits -> Try(KernelFontPlan.Plan, KernelFontPlan.Error)
plan_font = |font, usages, limits| {
	closure = mark_closure(font.metrics.glyph_count, font.components, usages, limits.max_retained_glyphs)?
	var $entries = List.with_capacity(closure.retained_glyphs)
	empty_mapping : U32
	empty_mapping = 0xffffffff
	var $original_to_subset = List.repeat(empty_mapping, font.metrics.glyph_count)
	var $original = 0
	var $subset = zero_u64
	while $original < font.metrics.glyph_count {
		marker = list_at(closure.markers, $original)
		if marker != 0 {
			original_glyph = $original.to_u32_wrap()
			subset_glyph = $subset.to_u32_wrap()
			metric = KernelFont.horizontal_metric(font, original_glyph) ? |problem| FontFailure(problem)
			$entries = $entries.append({
				cid: subset_glyph,
				content: marker == content_marker,
				left_side_bearing: metric.left_side_bearing,
				original_glyph,
				subset_glyph,
				width: metric.advance_width,
			})
			$original_to_subset = list_set($original_to_subset, $original, subset_glyph)
			$subset = $subset + 1
		}
		$original = $original + 1
	}
	prefix = subset_prefix(font.digest, $entries)?
	Ok({
		entries: $entries,
		original_to_subset: $original_to_subset,
		prefix,
		retained: closure.markers,
		work: {
			component_edge_visits: closure.component_edge_visits,
			component_index_visits: closure.component_index_visits,
			glyph_scans: font.metrics.glyph_count,
			retained_glyphs: closure.retained_glyphs,
			usage_visits: usages.len(),
		},
	})
}

mark_closure : U64, List(KernelFont.ComponentEdge), List(KernelFontPlan.Usage), U64 -> Try({ component_edge_visits : U64, component_index_visits : U64, markers : List(U8), retained_glyphs : U64 }, KernelFontPlan.Error)
mark_closure = |glyph_count, components, usages, retained_limit| {
	if glyph_count == 0 {
		return Err(GlyphOutOfRange({ glyph: 0, glyph_count, usage_index: 0 }))
	}
	empty_marker : U8
	empty_marker = 0
	var $markers = List.repeat(empty_marker, glyph_count)
	$markers = list_set($markers, 0, dependency_marker)
	var $queue = List.with_capacity(glyph_count)
	$queue = $queue.append(0)
	var $retained = 1
	if $retained > retained_limit {
		return Err(RetainedGlyphLimitExceeded({ attempted: $retained, limit: retained_limit }))
	}
	var $usage_index = 0
	while $usage_index < usages.len() {
		usage = list_at(usages, $usage_index)
		glyph = usage.glyph.to_u64()
		if glyph == 0 {
			return Err(GlyphZeroUsed({ usage_index: $usage_index }))
		}
		if glyph >= glyph_count {
			return Err(GlyphOutOfRange({ glyph: usage.glyph, glyph_count, usage_index: $usage_index }))
		}
		if list_at($markers, glyph) == empty_marker {
			$retained = $retained + 1
			if $retained > retained_limit {
				return Err(RetainedGlyphLimitExceeded({ attempted: $retained, limit: retained_limit }))
			}
			$queue = $queue.append(glyph)
		}
		$markers = list_set($markers, glyph, content_marker)
		$usage_index = $usage_index + 1
	}

	var $starts = List.with_capacity(glyph_count + 1)
	var $component_index = 0
	var $glyph = 0
	while $glyph < glyph_count {
		$starts = $starts.append($component_index)
		while $component_index < components.len() and list_at(components, $component_index).parent.to_u64() == $glyph {
			$component_index = $component_index + 1
		}
		$glyph = $glyph + 1
	}
	$starts = $starts.append($component_index)

	var $queue_index = 0
	var $edge_visits = 0
	while $queue_index < $queue.len() {
		parent = list_at($queue, $queue_index)
		var $position = list_at($starts, parent)
		end = list_at($starts, parent + 1)
		while $position < end {
			child = list_at(components, $position).child.to_u64()
			if list_at($markers, child) == empty_marker {
				$retained = $retained + 1
				if $retained > retained_limit {
					return Err(RetainedGlyphLimitExceeded({ attempted: $retained, limit: retained_limit }))
				}
				$markers = list_set($markers, child, dependency_marker)
				$queue = $queue.append(child)
			}
			$edge_visits = $edge_visits + 1
			$position = $position + 1
		}
		$queue_index = $queue_index + 1
	}
	Ok({
		component_edge_visits: $edge_visits,
		component_index_visits: components.len(),
		markers: $markers,
		retained_glyphs: $retained,
	})
}

subset_prefix : List(U8), List(KernelFontPlan.Entry) -> Try(List(U8), KernelFontPlan.Error)
subset_prefix = |font_digest, entries| {
	glyph_bytes = checked_times(entries.len(), 4)?
	capacity = checked_add(font_digest.len(), glyph_bytes)?
	var $identity = List.with_capacity(capacity)
	var $byte_index = 0
	while $byte_index < font_digest.len() {
		$identity = $identity.append(list_at(font_digest, $byte_index))
		$byte_index = $byte_index + 1
	}
	var $entry_index = 0
	while $entry_index < entries.len() {
		glyph = list_at(entries, $entry_index).original_glyph
		$identity = $identity.append(glyph.shr_wrap(24).to_u8_wrap())
		$identity = $identity.append(glyph.shr_wrap(16).to_u8_wrap())
		$identity = $identity.append(glyph.shr_wrap(8).to_u8_wrap())
		$identity = $identity.append(glyph.to_u8_wrap())
		$entry_index = $entry_index + 1
	}
	digest = KernelSha256.digest($identity) ? |_| ArithmeticOverflow
	var $prefix = List.with_capacity(6)
	var $index = 0
	while $index < 6 {
		$prefix = $prefix.append(0x41 + list_at(digest, $index) % 26)
		$index = $index + 1
	}
	Ok($prefix)
}

checked_add : U64, U64 -> Try(U64, KernelFontPlan.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_times : U64, U64 -> Try(U64, KernelFontPlan.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated font-plan index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated font-plan update escaped"
	}
	Ok(updated) => updated
}

content_marker : U8
content_marker = 2

dependency_marker : U8
dependency_marker = 1

zero_u64 : U64
zero_u64 = 0

expect {
	result = mark_closure(
		5,
		[
			{ child: 1, component_offset: 20, parent: 2 },
			{ child: 2, component_offset: 40, parent: 3 },
		],
		[{ glyph: 3 }, { glyph: 3 }, { glyph: 4 }],
		5,
	)?
	result.retained_glyphs == 5 and
		result.component_index_visits == 2 and
			result.component_edge_visits == 2 and
				result.markers == [1, 1, 1, 2, 2]
}

expect match mark_closure(2, [], [{ glyph: 0 }], 2) {
	Err(GlyphZeroUsed({ usage_index: 0 })) => Bool.True
	_ => Bool.False
}

expect match mark_closure(2, [], [{ glyph: 2 }], 2) {
	Err(GlyphOutOfRange({ glyph: 2, glyph_count: 2, usage_index: 0 })) => Bool.True
	_ => Bool.False
}

expect match mark_closure(3, [{ child: 1, component_offset: 20, parent: 2 }], [{ glyph: 2 }], 2) {
	Err(RetainedGlyphLimitExceeded({ attempted: 3, limit: 2 })) => Bool.True
	_ => Bool.False
}

expect {
	entries : List(KernelFontPlan.Entry)
	entries = [
		{ cid: 0, content: False, left_side_bearing: 0, original_glyph: 0, subset_glyph: 0, width: 500 },
		{ cid: 1, content: True, left_side_bearing: 10, original_glyph: 4, subset_glyph: 1, width: 600 },
	]
	first = subset_prefix(List.repeat(7, 32), entries)?
	second = subset_prefix(List.repeat(7, 32), entries)?
	first == second and first.len() == 6 and first.all(|byte| byte >= 0x41 and byte <= 0x5a)
}
