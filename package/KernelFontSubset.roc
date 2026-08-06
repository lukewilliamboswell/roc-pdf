import KernelFont
import KernelFontPlan

KernelFontSubset :: [].{
	Error : [
		ArithmeticOverflow,
		InvalidPlan,
		MissingSourceTable(U32),
		UnmappedComposite({ child : U32, parent : U32 }),
	]
	Work : {
		component_rewrites : U64,
		entry_visits : U64,
		source_glyph_bytes : U64,
	}
	GlyphTables : {
		glyf : List(U8),
		hmtx : List(U8),
		loca : List(U8),
		loca_offsets : List(U32),
		work : Work,
	}
	Subset : {
		bytes : List(U8),
		work : {
			cmap_mappings : U64,
			component_rewrites : U64,
			entry_visits : U64,
			glyf_bytes : U64,
			hmtx_bytes : U64,
			loca_bytes : U64,
			output_bytes : U64,
			source_glyph_bytes : U64,
			tables : U64,
		},
	}

	build_glyph_tables : KernelFont.Inspection, KernelFontPlan.Plan -> Try(GlyphTables, Error)
	build_glyph_tables = |font, plan| build_glyph_tables_from(font, plan)

	build : KernelFont.Inspection, KernelFontPlan.Plan -> Try(Subset, Error)
	build = |font, plan| build_subset(font, plan)
}

SourceTables : {
	cvt : List(U8),
	fpgm : List(U8),
	gasp : List(U8),
	head : List(U8),
	hhea : List(U8),
	maxp : List(U8),
	os2 : List(U8),
	prep : List(U8),
}

SfntTables : {
	cmap : List(U8),
	cvt : List(U8),
	fpgm : List(U8),
	gasp : List(U8),
	glyf : List(U8),
	head : List(U8),
	hhea : List(U8),
	hmtx : List(U8),
	loca : List(U8),
	maxp : List(U8),
	name : List(U8),
	os2 : List(U8),
	post : List(U8),
	prep : List(U8),
}

build_subset : KernelFont.Inspection, KernelFontPlan.Plan -> Try(KernelFontSubset.Subset, KernelFontSubset.Error)
build_subset = |font, plan| {
	glyph_tables = build_glyph_tables_from(font, plan)?
	cmap_result = build_cmap(font, plan)?
	source = collect_source_tables(font)?
	head = set_u16(set_u32(source.head, 8, 0), 50, 1)
	hhea = set_u16(source.hhea, 34, plan.entries.len().to_u16_wrap())
	maxp = set_u16(source.maxp, 4, plan.entries.len().to_u16_wrap())
	name = build_name(plan.prefix)
	post = build_post({})
	tables : SfntTables
	tables = {
		cmap: cmap_result.bytes,
		cvt: source.cvt,
		fpgm: source.fpgm,
		gasp: source.gasp,
		glyf: glyph_tables.glyf,
		head,
		hhea,
		hmtx: glyph_tables.hmtx,
		loca: glyph_tables.loca,
		maxp,
		name,
		os2: source.os2,
		post,
		prep: source.prep,
	}
	bytes = assemble_sfnt(tables)?
	Ok({
		bytes,
		work: {
			cmap_mappings: cmap_result.mappings,
			component_rewrites: glyph_tables.work.component_rewrites,
			entry_visits: glyph_tables.work.entry_visits,
			glyf_bytes: glyph_tables.glyf.len(),
			hmtx_bytes: glyph_tables.hmtx.len(),
			loca_bytes: glyph_tables.loca.len(),
			output_bytes: bytes.len(),
			source_glyph_bytes: glyph_tables.work.source_glyph_bytes,
			tables: subset_table_count,
		},
	})
}

build_glyph_tables_from : KernelFont.Inspection, KernelFontPlan.Plan -> Try(KernelFontSubset.GlyphTables, KernelFontSubset.Error)
build_glyph_tables_from = |font, plan| {
	if plan.entries.len() == 0 or plan.original_to_subset.len() != font.metrics.glyph_count or plan.retained.len() != font.metrics.glyph_count or plan.prefix.len() != 6 {
		return Err(InvalidPlan)
	}
	var $source_bytes = 0
	var $entry_index = 0
	var $previous_original = NoPrevious
	while $entry_index < plan.entries.len() {
		entry = list_at(plan.entries, $entry_index)
		if entry.subset_glyph.to_u64() != $entry_index or entry.cid != entry.subset_glyph {
			return Err(InvalidPlan)
		}
		match $previous_original {
			NoPrevious => if entry.original_glyph != 0 return Err(InvalidPlan)
			Previous(value) => if entry.original_glyph <= value return Err(InvalidPlan)
		}
		original = entry.original_glyph.to_u64()
		if original >= font.metrics.glyph_count or list_at(plan.original_to_subset, original) != entry.subset_glyph {
			return Err(InvalidPlan)
		}
		start = list_at(font.loca_offsets, original)
		end = list_at(font.loca_offsets, original + 1)
		$source_bytes = checked_add($source_bytes, end - start)?
		$previous_original = Previous(entry.original_glyph)
		$entry_index = $entry_index + 1
	}
	if $source_bytes > u32_max {
		return Err(ArithmeticOverflow)
	}

	var $glyf = List.with_capacity($source_bytes)
	var $loca_offsets = List.with_capacity(plan.entries.len() + 1)
	var $hmtx = List.with_capacity(checked_times(plan.entries.len(), 4)?)
	var $component_index = 0
	var $component_rewrites = 0
	$entry_index = 0
	while $entry_index < plan.entries.len() {
		entry = list_at(plan.entries, $entry_index)
		original = entry.original_glyph.to_u64()
		old_start = list_at(font.loca_offsets, original)
		old_end = list_at(font.loca_offsets, original + 1)
		new_start = $glyf.len()
		$loca_offsets = $loca_offsets.append(new_start.to_u32_wrap())
		$glyf = append_range($glyf, font.bytes, glyf_table_offset(font) + old_start, old_end - old_start)

		while $component_index < font.components.len() and list_at(font.components, $component_index).parent < entry.original_glyph {
			$component_index = $component_index + 1
		}
		while $component_index < font.components.len() and list_at(font.components, $component_index).parent == entry.original_glyph {
			edge = list_at(font.components, $component_index)
			if edge.component_offset < old_start or edge.component_offset + 2 > old_end {
				return Err(InvalidPlan)
			}
			mapped = list_at(plan.original_to_subset, edge.child.to_u64())
			if mapped == unmapped_glyph {
				return Err(UnmappedComposite({ child: edge.child, parent: edge.parent }))
			}
			destination = new_start + edge.component_offset - old_start
			$glyf = set_u16($glyf, destination, mapped.to_u16_wrap())
			$component_rewrites = $component_rewrites + 1
			$component_index = $component_index + 1
		}

		$hmtx = append_u16($hmtx, entry.width)
		$hmtx = append_u16($hmtx, entry.left_side_bearing.to_u16_wrap())
		$entry_index = $entry_index + 1
	}
	$loca_offsets = $loca_offsets.append($glyf.len().to_u32_wrap())
	loca = encode_loca($loca_offsets)
	Ok({
		glyf: $glyf,
		hmtx: $hmtx,
		loca,
		loca_offsets: $loca_offsets,
		work: {
			component_rewrites: $component_rewrites,
			entry_visits: plan.entries.len() * 2,
			source_glyph_bytes: $source_bytes,
		},
	})
}

build_cmap : KernelFont.Inspection, KernelFontPlan.Plan -> Try({ bytes : List(U8), mappings : U64 }, KernelFontSubset.Error)
build_cmap = |font, plan| {
	var $groups = List.with_capacity(checked_times(font.work.cmap_mapping_visits, 12)?)
	var $mapping_count = 0
	var $group_count = zero_u64
	var $has_group = false_bool
	var $group_start = zero_u32
	var $group_end = zero_u32
	var $group_glyph = zero_u32
	var $span_index = 0
	while $span_index < font.coverage.len() {
		span = list_at(font.coverage, $span_index)
		var $scalar = span.first
		while $scalar <= span.last {
			match KernelFont.glyph_for_scalar(font, $scalar) {
				None => {}
				Some(original) => {
					mapped = list_at(plan.original_to_subset, original.to_u64())
					if mapped != unmapped_glyph and list_at(plan.retained, original.to_u64()) == content_marker {
						if !$has_group {
							$group_start = $scalar
							$group_end = $scalar
							$group_glyph = mapped
							$has_group = True
						} else {
							expected_glyph = $group_glyph + ($group_end - $group_start) + 1
							if $scalar == $group_end + 1 and mapped == expected_glyph {
								$group_end = $scalar
							} else {
								$groups = append_u32($groups, $group_start)
								$groups = append_u32($groups, $group_end)
								$groups = append_u32($groups, $group_glyph)
								$group_count = $group_count + 1
								$group_start = $scalar
								$group_end = $scalar
								$group_glyph = mapped
							}
						}
						$mapping_count = $mapping_count + 1
					}
				}
			}
			if $scalar == 0x10ffff {
				break
			}
			$scalar = $scalar + 1
		}
		$span_index = $span_index + 1
	}
	if $has_group {
		$groups = append_u32($groups, $group_start)
		$groups = append_u32($groups, $group_end)
		$groups = append_u32($groups, $group_glyph)
		$group_count = $group_count + 1
	}
	if $groups.len() > u32_max - 16 {
		return Err(ArithmeticOverflow)
	}
	var $bytes = List.with_capacity(28 + $groups.len())
	$bytes = append_u16($bytes, 0)
	$bytes = append_u16($bytes, 1)
	$bytes = append_u16($bytes, 3)
	$bytes = append_u16($bytes, 10)
	$bytes = append_u32($bytes, 12)
	$bytes = append_u16($bytes, 12)
	$bytes = append_u16($bytes, 0)
	$bytes = append_u32($bytes, (16 + $groups.len()).to_u32_wrap())
	$bytes = append_u32($bytes, 0)
	$bytes = append_u32($bytes, $group_count.to_u32_wrap())
	Ok({ bytes: concat_bytes($bytes, $groups), mappings: $mapping_count })
}

build_name : List(U8) -> List(U8)
build_name = |prefix| {
	family = concat_bytes(concat_bytes(prefix, [0x2b]), Str.to_utf8("Roc PDF Sans"))
	full = concat_bytes(concat_bytes(prefix, [0x2b]), Str.to_utf8("Roc PDF Sans Regular"))
	postscript = concat_bytes(concat_bytes(prefix, [0x2b]), Str.to_utf8("RocPdfSans-Regular"))
	family_utf16 = ascii_utf16be(family)
	full_utf16 = ascii_utf16be(full)
	postscript_utf16 = ascii_utf16be(postscript)
	string_offset = 42
	var $bytes = List.with_capacity(string_offset + family_utf16.len() + full_utf16.len() + postscript_utf16.len())
	$bytes = append_u16($bytes, 0)
	$bytes = append_u16($bytes, 3)
	$bytes = append_u16($bytes, string_offset.to_u16_wrap())
	$bytes = append_name_record($bytes, 1, family_utf16.len(), 0)
	$bytes = append_name_record($bytes, 4, full_utf16.len(), family_utf16.len())
	$bytes = append_name_record($bytes, 6, postscript_utf16.len(), family_utf16.len() + full_utf16.len())
	$bytes = concat_bytes($bytes, family_utf16)
	$bytes = concat_bytes($bytes, full_utf16)
	concat_bytes($bytes, postscript_utf16)
}

build_post : {} -> List(U8)
build_post = |_| {
	var $bytes = List.with_capacity(32)
	$bytes = append_u32($bytes, 0x00030000)
	$bytes = append_u32($bytes, 0)
	$bytes = append_u16($bytes, 0)
	$bytes = append_u16($bytes, 0)
	$bytes = append_u32($bytes, 0)
	$bytes = append_u32($bytes, 0)
	$bytes = append_u32($bytes, 0)
	$bytes = append_u32($bytes, 0)
	append_u32($bytes, 0)
}

append_name_record : List(U8), U16, U64, U64 -> List(U8)
append_name_record = |bytes, name_id, length, offset| {
	var $result = append_u16(bytes, 3)
	$result = append_u16($result, 1)
	$result = append_u16($result, 0x0409)
	$result = append_u16($result, name_id)
	$result = append_u16($result, length.to_u16_wrap())
	append_u16($result, offset.to_u16_wrap())
}

ascii_utf16be : List(U8) -> List(U8)
ascii_utf16be = |ascii| {
	var $result = List.with_capacity(ascii.len() * 2)
	var $index = 0
	while $index < ascii.len() {
		$result = $result.append(0)
		$result = $result.append(list_at(ascii, $index))
		$index = $index + 1
	}
	$result
}

collect_source_tables : KernelFont.Inspection -> Try(SourceTables, KernelFontSubset.Error)
collect_source_tables = |font| {
	var $cvt = []
	var $fpgm = []
	var $gasp = []
	var $head = []
	var $hhea = []
	var $maxp = []
	var $os2 = []
	var $prep = []
	var $found = 0
	var $index = 0
	while $index < font.tables.len() {
		table = list_at(font.tables, $index)
		if table.tag == tag_cvt {
			$cvt = append_range(List.with_capacity(table.length), font.bytes, table.offset, table.length)
			$found = $found.bitwise_or(1)
		} else if table.tag == tag_fpgm {
			$fpgm = append_range(List.with_capacity(table.length), font.bytes, table.offset, table.length)
			$found = $found.bitwise_or(2)
		} else if table.tag == tag_gasp {
			$gasp = append_range(List.with_capacity(table.length), font.bytes, table.offset, table.length)
			$found = $found.bitwise_or(4)
		} else if table.tag == tag_head {
			$head = append_range(List.with_capacity(table.length), font.bytes, table.offset, table.length)
			$found = $found.bitwise_or(8)
		} else if table.tag == tag_hhea {
			$hhea = append_range(List.with_capacity(table.length), font.bytes, table.offset, table.length)
			$found = $found.bitwise_or(16)
		} else if table.tag == tag_maxp {
			$maxp = append_range(List.with_capacity(table.length), font.bytes, table.offset, table.length)
			$found = $found.bitwise_or(32)
		} else if table.tag == tag_os2 {
			$os2 = append_range(List.with_capacity(table.length), font.bytes, table.offset, table.length)
			$found = $found.bitwise_or(64)
		} else if table.tag == tag_prep {
			$prep = append_range(List.with_capacity(table.length), font.bytes, table.offset, table.length)
			$found = $found.bitwise_or(128)
		}
		$index = $index + 1
	}
	if $found != 255 {
		missing = if $found.bitwise_and(1) == 0 tag_cvt else if $found.bitwise_and(2) == 0 tag_fpgm else if $found.bitwise_and(4) == 0 tag_gasp else if $found.bitwise_and(8) == 0 tag_head else if $found.bitwise_and(16) == 0 tag_hhea else if $found.bitwise_and(32) == 0 tag_maxp else if $found.bitwise_and(64) == 0 tag_os2 else tag_prep
		return Err(MissingSourceTable(missing))
	}
	Ok({ cvt: $cvt, fpgm: $fpgm, gasp: $gasp, head: $head, hhea: $hhea, maxp: $maxp, os2: $os2, prep: $prep })
}

assemble_sfnt : SfntTables -> Try(List(U8), KernelFontSubset.Error)
assemble_sfnt = |tables| {
	ordered = [
		{ bytes: tables.os2, tag: tag_os2 },
		{ bytes: tables.cmap, tag: tag_cmap },
		{ bytes: tables.cvt, tag: tag_cvt },
		{ bytes: tables.fpgm, tag: tag_fpgm },
		{ bytes: tables.gasp, tag: tag_gasp },
		{ bytes: tables.glyf, tag: tag_glyf },
		{ bytes: tables.head, tag: tag_head },
		{ bytes: tables.hhea, tag: tag_hhea },
		{ bytes: tables.hmtx, tag: tag_hmtx },
		{ bytes: tables.loca, tag: tag_loca },
		{ bytes: tables.maxp, tag: tag_maxp },
		{ bytes: tables.name, tag: tag_name },
		{ bytes: tables.post, tag: tag_post },
		{ bytes: tables.prep, tag: tag_prep },
	]
	var $output_length = sfnt_directory_length
	var $index = 0
	while $index < ordered.len() {
		table = list_at(ordered, $index)
		$output_length = checked_add($output_length, padded_length(table.bytes.len()))?
		$index = $index + 1
	}
	if $output_length > u32_max {
		return Err(ArithmeticOverflow)
	}
	var $output = List.with_capacity($output_length)
	$output = append_u32($output, 0x00010000)
	$output = append_u16($output, subset_table_count.to_u16_wrap())
	$output = append_u16($output, 128)
	$output = append_u16($output, 3)
	$output = append_u16($output, 96)
	var $table_offset = sfnt_directory_length
	var $head_offset = 0
	$index = 0
	while $index < ordered.len() {
		table = list_at(ordered, $index)
		$output = append_directory($output, table.tag, table.bytes, $table_offset)
		if table.tag == tag_head {
			$head_offset = $table_offset
		}
		$table_offset = $table_offset + padded_length(table.bytes.len())
		$index = $index + 1
	}
	$index = 0
	while $index < ordered.len() {
		table = list_at(ordered, $index)
		$output = append_padded($output, table.bytes)
		$index = $index + 1
	}
	adjustment = U32.minus_wrap(sfnt_checksum, checksum_bytes($output))
	Ok(set_u32($output, $head_offset + 8, adjustment))
}

append_directory : List(U8), U32, List(U8), U64 -> List(U8)
append_directory = |output, tag, bytes, offset| {
	var $result = append_u32(output, tag)
	$result = append_u32($result, checksum_bytes(bytes))
	$result = append_u32($result, offset.to_u32_wrap())
	append_u32($result, bytes.len().to_u32_wrap())
}

append_padded : List(U8), List(U8) -> List(U8)
append_padded = |output, table| {
	var $result = concat_bytes(output, table)
	while $result.len() % 4 != 0 {
		$result = $result.append(0)
	}
	$result
}

checksum_bytes : List(U8) -> U32
checksum_bytes = |bytes| {
	var $sum = 0
	var $index = 0
	while $index < padded_length(bytes.len()) {
		var $word = 0
		var $byte_index = 0
		while $byte_index < 4 {
			position = $index + $byte_index
			byte = if position < bytes.len() list_at(bytes, position) else 0
			$word = $word.bitwise_or(byte.to_u32().shl_wrap((3 - $byte_index).to_u8_wrap() * 8))
			$byte_index = $byte_index + 1
		}
		$sum = U32.plus_wrap($sum, $word)
		$index = $index + 4
	}
	$sum
}

padded_length : U64 -> U64
padded_length = |length| if length % 4 == 0 length else length + 4 - length % 4

concat_bytes : List(U8), List(U8) -> List(U8)
concat_bytes = |left, right| append_range(left, right, 0, right.len())

glyf_table_offset : KernelFont.Inspection -> U64
glyf_table_offset = |font| {
	var $index = 0
	while $index < font.tables.len() {
		table = list_at(font.tables, $index)
		if table.tag == tag_glyf {
			return table.offset
		}
		$index = $index + 1
	}
	crash "inspected font lost required glyf table"
}

encode_loca : List(U32) -> List(U8)
encode_loca = |offsets| {
	var $bytes = List.with_capacity(offsets.len() * 4)
	var $index = 0
	while $index < offsets.len() {
		value = list_at(offsets, $index)
		$bytes = $bytes.append(value.shr_wrap(24).to_u8_wrap())
		$bytes = $bytes.append(value.shr_wrap(16).to_u8_wrap())
		$bytes = $bytes.append(value.shr_wrap(8).to_u8_wrap())
		$bytes = $bytes.append(value.to_u8_wrap())
		$index = $index + 1
	}
	$bytes
}

append_range : List(U8), List(U8), U64, U64 -> List(U8)
append_range = |target, source, offset, length| {
	var $result = target
	var $index = 0
	while $index < length {
		$result = $result.append(list_at(source, offset + $index))
		$index = $index + 1
	}
	$result
}

append_u16 : List(U8), U16 -> List(U8)
append_u16 = |bytes, value| bytes.append(value.shr_wrap(8).to_u8_wrap()).append(value.to_u8_wrap())

append_u32 : List(U8), U32 -> List(U8)
append_u32 = |bytes, value| bytes
	.append(value.shr_wrap(24).to_u8_wrap())
	.append(value.shr_wrap(16).to_u8_wrap())
	.append(value.shr_wrap(8).to_u8_wrap())
	.append(value.to_u8_wrap())

set_u16 : List(U8), U64, U16 -> List(U8)
set_u16 = |bytes, index, value| {
	first = list_set(bytes, index, value.shr_wrap(8).to_u8_wrap())
	list_set(first, index + 1, value.to_u8_wrap())
}

set_u32 : List(U8), U64, U32 -> List(U8)
set_u32 = |bytes, index, value| {
	first = list_set(bytes, index, value.shr_wrap(24).to_u8_wrap())
	second = list_set(first, index + 1, value.shr_wrap(16).to_u8_wrap())
	third = list_set(second, index + 2, value.shr_wrap(8).to_u8_wrap())
	list_set(third, index + 3, value.to_u8_wrap())
}

checked_add : U64, U64 -> Try(U64, KernelFontSubset.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_times : U64, U64 -> Try(U64, KernelFontSubset.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated font-subset index escaped"
	}
	Ok(value) => value
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated font-subset update escaped"
	}
	Ok(updated) => updated
}

tag_glyf : U32
tag_glyf = 0x676c7966

tag_cmap : U32
tag_cmap = 0x636d6170

tag_cvt : U32
tag_cvt = 0x63767420

tag_fpgm : U32
tag_fpgm = 0x6670676d

tag_gasp : U32
tag_gasp = 0x67617370

tag_head : U32
tag_head = 0x68656164

tag_hhea : U32
tag_hhea = 0x68686561

tag_hmtx : U32
tag_hmtx = 0x686d7478

tag_loca : U32
tag_loca = 0x6c6f6361

tag_maxp : U32
tag_maxp = 0x6d617870

tag_name : U32
tag_name = 0x6e616d65

tag_os2 : U32
tag_os2 = 0x4f532f32

tag_post : U32
tag_post = 0x706f7374

tag_prep : U32
tag_prep = 0x70726570

unmapped_glyph : U32
unmapped_glyph = 0xffffffff

u32_max : U64
u32_max = 0xffffffff

zero_u32 : U32
zero_u32 = 0

zero_u64 : U64
zero_u64 = 0

false_bool : Bool
false_bool = False

content_marker : U8
content_marker = 2

sfnt_checksum : U32
sfnt_checksum = 0xb1b0afba

subset_table_count : U64
subset_table_count = 14

sfnt_directory_length : U64
sfnt_directory_length = 236

expect encode_loca([0, 1, 0x01020304]) == [0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 3, 4]

expect set_u16([0, 0, 0], 1, 0x1234) == [0, 0x12, 0x34]
