import KernelFont
import KernelFontPlan
import KernelFontSubset
import "../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font : List(U8)
import "../tests/assets/CallerFont-Regular.ttf" as caller_font : List(U8)
import "../tests/assets/IBMPlexSansHebrew-Rtl-Fixture.ttf" as hebrew_font : List(U8)
import "../tests/assets/IBMPlexSerif-FiLigature-Fixture.ttf" as ligature_font : List(U8)
import "../tests/assets/NotoSansSC-CJK-Fixture.ttf" as cjk_font : List(U8)

Gate3FuzzTargets :: [].{
	inspect_mutation : List(U8) -> Bool
	inspect_mutation = |bytes| match KernelFont.inspect(bytes, inspection_limits) {
		Err(_) => True
		Ok(font) => inspection_invariants(font)
	}

	subset_roundtrip : { font : U8, glyphs : List(U8), retained_limit : U8 } -> Bool
	subset_roundtrip = |input| {
		font_bytes = fixture(input.font)
		font = match KernelFont.inspect(font_bytes, inspection_limits) {
			Err(_) => return False
			Ok(value) => value
		}
		usages = input.glyphs.map(|choice| {
			glyph: (choice.to_u64() % font.metrics.glyph_count).to_u32_wrap(),
		})
		limits = KernelFontPlan.Limits.make({ max_retained_glyphs: input.retained_limit.to_u64() })
		first_plan = KernelFontPlan.plan(font, usages, limits)
		second_plan = KernelFontPlan.plan(font, usages, limits)
		if first_plan != second_plan {
			return False
		}
		match (first_plan, second_plan) {
			(Err(_), Err(_)) => True
			(Ok(plan), Ok(repeated_plan)) => {
				if plan.prefix != repeated_plan.prefix or plan.entries != repeated_plan.entries {
					return False
				}
				first_subset = KernelFontSubset.build(font, plan)
				second_subset = KernelFontSubset.build(font, repeated_plan)
				match (first_subset, second_subset) {
					(Ok(subset), Ok(repeated_subset)) => {
						if subset.bytes != repeated_subset.bytes {
							return False
						}
						match KernelFont.inspect(subset.bytes, inspection_limits) {
							Err(_) => False
							Ok(reinspected) => plan_and_subset_invariants(font, plan, reinspected)
						}
					}
					_ => False
				}
			}
			_ => False
		}
	}
}

inspection_limits : KernelFont.Limits
inspection_limits = KernelFont.Limits.make({
	max_bytes: 524288,
	max_cmap_mappings: 20000,
	max_glyphs: 20000,
	max_tables: 64,
})

fixture : U8 -> List(U8)
fixture = |choice| match choice % 5 {
	0 => built_in_font
	1 => caller_font
	2 => cjk_font
	3 => hebrew_font
	_ => ligature_font
}

inspection_invariants : KernelFont.Inspection -> Bool
inspection_invariants = |font| {
	if font.metrics.glyph_count == 0 or
		font.loca_offsets.len() != font.metrics.glyph_count + 1 or
		font.work.directory_entries != font.tables.len() or
		font.work.glyph_visits != font.metrics.glyph_count or
		font.work.loca_entries != font.metrics.glyph_count + 1 or
		font.work.cmap_mapping_visits > 20000 {
		return False
	}
	var $previous_tag = 0
	var $table_index = 0
	while $table_index < font.tables.len() {
		table = list_at(font.tables, $table_index)
		if ($table_index > 0 and table.tag <= $previous_tag) or
			table.offset % 4 != 0 or
				table.offset + table.length > font.bytes.len() {
			return False
		}
		var $other_index = 0
		while $other_index < $table_index {
			other = list_at(font.tables, $other_index)
			if table.offset < other.offset + other.length and other.offset < table.offset + table.length return False
			$other_index = $other_index + 1
		}
		$previous_tag = table.tag
		$table_index = $table_index + 1
	}
	var $loca_index = 1
	while $loca_index < font.loca_offsets.len() {
		if list_at(font.loca_offsets, $loca_index) < list_at(font.loca_offsets, $loca_index - 1) {
			return False
		}
		$loca_index = $loca_index + 1
	}
	var $previous_last = 0
	var $span_index = 0
	while $span_index < font.coverage.len() {
		span = list_at(font.coverage, $span_index)
		if span.first > span.last or
			($span_index > 0 and span.first <= $previous_last) or
			(span.first <= 0xdfff and span.last >= 0xd800) or
			span.last > 0x10ffff {
			return False
		}
		var $scalar = span.first
		while $scalar <= span.last {
			match KernelFont.glyph_for_scalar(font, $scalar) {
				None => return False
				Some(glyph) => if glyph == 0 or glyph.to_u64() >= font.metrics.glyph_count return False
			}
			$scalar = $scalar + 1
		}
		$previous_last = span.last
		$span_index = $span_index + 1
	}
	var $edge_index = 0
	while $edge_index < font.components.len() {
		edge = list_at(font.components, $edge_index)
		if edge.child.to_u64() >= font.metrics.glyph_count or edge.parent.to_u64() >= font.metrics.glyph_count {
			return False
		}
		$edge_index = $edge_index + 1
	}
	True
}

plan_and_subset_invariants : KernelFont.Inspection, KernelFontPlan.Plan, KernelFont.Inspection -> Bool
plan_and_subset_invariants = |source, plan, subset| {
	if !inspection_invariants(subset) or subset.metrics.glyph_count != plan.entries.len() {
		return False
	}
	var $entry_index = 0
	while $entry_index < plan.entries.len() {
		entry = list_at(plan.entries, $entry_index)
		if entry.subset_glyph.to_u64() != $entry_index or
			entry.cid != entry.subset_glyph or
			list_at(plan.original_to_subset, entry.original_glyph.to_u64()) != entry.subset_glyph {
			return False
		}
		subset_metric = match KernelFont.horizontal_metric(subset, entry.subset_glyph) {
			Err(_) => return False
			Ok(value) => value
		}
		if subset_metric.advance_width != entry.width or subset_metric.left_side_bearing != entry.left_side_bearing {
			return False
		}
		$entry_index = $entry_index + 1
	}
	var $span_index = 0
	while $span_index < source.coverage.len() {
		span = list_at(source.coverage, $span_index)
		var $scalar = span.first
		while $scalar <= span.last {
			match KernelFont.glyph_for_scalar(source, $scalar) {
				None => {}
				Some(original) => {
					mapped = list_at(plan.original_to_subset, original.to_u64())
					expected = if mapped != 0xffffffff and list_at(plan.retained, original.to_u64()) == 2 Some(mapped) else None
					if KernelFont.glyph_for_scalar(subset, $scalar) != expected return False
				}
			}
			$scalar = $scalar + 1
		}
		$span_index = $span_index + 1
	}
	var $edge_index = 0
	while $edge_index < source.components.len() {
		edge = list_at(source.components, $edge_index)
		mapped_parent = list_at(plan.original_to_subset, edge.parent.to_u64())
		if mapped_parent != 0xffffffff {
			mapped_child = list_at(plan.original_to_subset, edge.child.to_u64())
			if mapped_child == 0xffffffff or !has_component(subset.components, mapped_parent, mapped_child) return False
		}
		$edge_index = $edge_index + 1
	}
	True
}

has_component : List(KernelFont.ComponentEdge), U32, U32 -> Bool
has_component = |edges, parent, child| {
	var $index = 0
	while $index < edges.len() {
		edge = list_at(edges, $index)
		if edge.parent == parent and edge.child == child return True
		$index = $index + 1
	}
	False
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "fuzz property escaped a validated dense index"
	Ok(value) => value
}
