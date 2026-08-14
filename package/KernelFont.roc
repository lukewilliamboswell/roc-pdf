import KernelSha256

KernelFont :: [].{
	Dimension : [CmapMappings, FontBytes, Glyphs, Tables]
	Error : [
		ArithmeticOverflow,
		ChecksumMismatch({ actual : U32, expected : U32, tag : U32 }),
		CmapLimitExceeded({ attempted : U64, limit : U64 }),
		CompositeCycle,
		CompositeDepthMismatch({ actual : U64, declared : U64 }),
		DuplicateOrUnorderedTable({ index : U64, tag : U32 }),
		FontChecksumMismatch({ actual : U32 }),
		InvalidCmap,
		InvalidDirectory,
		InvalidEmbeddingRights(U16),
		InvalidHead,
		InvalidHorizontalMetrics,
		InvalidGlyph({ glyph : U32, offset : U64 }),
		InvalidLoca,
		InvalidMaxp,
		InvalidName,
		InvalidOs2,
		InvalidTableRange({ length : U64, offset : U64, tag : U32 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		MissingTable(U32),
		OverlappingTables({ left : U32, right : U32 }),
		UnsupportedFontProgram(U32),
	]

	Limits :: { max_bytes : U64, max_cmap_mappings : U64, max_glyphs : U64, max_tables : U64 }.{
		make : { max_bytes : U64, max_cmap_mappings : U64, max_glyphs : U64, max_tables : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	Table : { checksum : U32, length : U64, offset : U64, tag : U32 }
	ComponentEdge : { child : U32, component_offset : U64, parent : U32 }
	HorizontalMetric : { advance_width : U16, left_side_bearing : I64 }
	CoverageSpan : { first : U32, last : U32 }
	CmapGroup : { end : U32, start : U32, start_glyph : U32 }
	CmapSegment : { delta : I64, end : U32, range_offset : U16, range_offset_location : U64, start : U32 }
	Cmap : [
		Format4({ length : U64, offset : U64, segments : List(CmapSegment) }),
		Format12({ groups : List(CmapGroup) }),
	]
	EmbeddingRights : [Editable, Installable, PreviewAndPrint]
	NameRange : { length : U64, offset : U64 }
	Names : {
		family_utf16be : NameRange,
		full_utf16be : NameRange,
		postscript_utf16be : NameRange,
	}
	Metrics : {
		ascent : I64,
		cap_height : I64,
		descent : I64,
		glyph_count : U64,
		index_to_loc_format : U8,
		line_gap : I64,
		number_of_h_metrics : U64,
		units_per_em : U16,
		x_max : I64,
		x_min : I64,
		y_max : I64,
		y_min : I64,
	}
	Work : {
		checksum_bytes : U64,
		cmap_mapping_visits : U64,
		component_edge_visits : U64,
		directory_entries : U64,
		glyph_visits : U64,
		loca_entries : U64,
		overlap_comparisons : U64,
	}
	Inspection : {
		bytes : List(U8),
		cmap : Cmap,
		components : List(ComponentEdge),
		coverage : List(CoverageSpan),
		digest : List(U8),
		embedding_rights : EmbeddingRights,
		loca_offsets : List(U64),
		metrics : Metrics,
		names : Names,
		tables : List(Table),
		work : Work,
	}

	inspect : List(U8), Limits -> Try(Inspection, Error)
	inspect = |bytes, limits| inspect_font(bytes, limits)

	glyph_for_scalar : Inspection, U32 -> [None, Some(U32)]
	glyph_for_scalar = |font, scalar| glyph_for_cmap(font.bytes, font.cmap, font.metrics.glyph_count, scalar)

	advance_width : Inspection, U32 -> Try(U16, Error)
	advance_width = |font, glyph| {
		metric = horizontal_metric_for(font, glyph)?
		Ok(metric.advance_width)
	}

	horizontal_metric : Inspection, U32 -> Try(HorizontalMetric, Error)
	horizontal_metric = |font, glyph| horizontal_metric_for(font, glyph)

	postscript_name : Inspection -> List(U8)
	postscript_name = |font| postscript_name_bytes(font)
}

horizontal_metric_for : KernelFont.Inspection, U32 -> Try(KernelFont.HorizontalMetric, KernelFont.Error)
horizontal_metric_for = |font, glyph| {
	if glyph.to_u64() >= font.metrics.glyph_count {
		return Err(InvalidHorizontalMetrics)
	}
	hmtx = required_table(font.tables, tag_hmtx)?
	metric_index = if glyph.to_u64() < font.metrics.number_of_h_metrics {
		glyph.to_u64()
	} else {
		font.metrics.number_of_h_metrics - 1
	}
	advance_width = read_u16(font.bytes, hmtx.offset + metric_index * 4)
	left_side_bearing_offset = if glyph.to_u64() < font.metrics.number_of_h_metrics {
		hmtx.offset + glyph.to_u64() * 4 + 2
	} else {
		hmtx.offset + font.metrics.number_of_h_metrics * 4 + (glyph.to_u64() - font.metrics.number_of_h_metrics) * 2
	}
	Ok({ advance_width, left_side_bearing: signed_i16(read_u16(font.bytes, left_side_bearing_offset)) })
}

inspect_font : List(U8), KernelFont.Limits -> Try(KernelFont.Inspection, KernelFont.Error)
inspect_font = |bytes, limits| {
	if bytes.len() > limits.max_bytes {
		return Err(LimitExceeded({ attempted: bytes.len(), dimension: FontBytes, limit: limits.max_bytes }))
	}
	if bytes.len() < 12 {
		return Err(InvalidDirectory)
	}
	signature = read_u32(bytes, 0)
	if signature != 0x00010000 {
		return Err(UnsupportedFontProgram(signature))
	}
	table_count = read_u16(bytes, 4).to_u64()
	if table_count == 0 {
		return Err(InvalidDirectory)
	}
	if table_count > limits.max_tables {
		return Err(LimitExceeded({ attempted: table_count, dimension: Tables, limit: limits.max_tables }))
	}
	directory_length = checked_add(12, checked_times(table_count, 16)?)?
	if directory_length > bytes.len() or !valid_search_header(bytes, table_count) {
		return Err(InvalidDirectory)
	}

	var $tables = []
	var $index = 0
	var $previous_tag = 0
	while $index < table_count {
		record = 12 + $index * 16
		tag = read_u32(bytes, record)
		checksum = read_u32(bytes, record + 4)
		offset = read_u32(bytes, record + 8).to_u64()
		length = read_u32(bytes, record + 12).to_u64()
		if $index > 0 and tag <= $previous_tag {
			return Err(DuplicateOrUnorderedTable({ index: $index, tag }))
		}
		if offset % 4 != 0 or offset < directory_length or offset > bytes.len() or length > bytes.len() - offset {
			return Err(InvalidTableRange({ length, offset, tag }))
		}
		actual_checksum = table_checksum(bytes, offset, length, tag == tag_head)
		if actual_checksum != checksum {
			return Err(ChecksumMismatch({ actual: actual_checksum, expected: checksum, tag }))
		}
		$tables = $tables.append({ checksum, length, offset, tag })
		$previous_tag = tag
		$index = $index + 1
	}

	overlap_work = validate_no_overlap($tables)?
	whole_checksum = checksum_range(bytes, 0, bytes.len(), False)
	if whole_checksum != sfnt_checksum {
		return Err(FontChecksumMismatch({ actual: whole_checksum }))
	}

	head = required_table($tables, tag_head)?
	maxp = required_table($tables, tag_maxp)?
	hhea = required_table($tables, tag_hhea)?
	hmtx = required_table($tables, tag_hmtx)?
	loca = required_table($tables, tag_loca)?
	_ = required_table($tables, tag_glyf)?
	name = required_table($tables, tag_name)?
	os2 = required_table($tables, tag_os2)?
	_ = required_table($tables, tag_post)?
	cmap_table = required_table($tables, tag_cmap)?

	head_metrics = inspect_head(bytes, head)?
	maxp_metrics = inspect_maxp(bytes, maxp, limits.max_glyphs)?
	glyph_count = maxp_metrics.glyph_count
	horizontal = inspect_hhea(bytes, hhea, glyph_count)?
	validate_hmtx(hmtx, glyph_count, horizontal.number_of_h_metrics)?
	glyf = required_table($tables, tag_glyf)?
	loca_offsets = inspect_loca(bytes, loca, glyf, glyph_count, head_metrics.index_to_loc_format)?
	glyph_result = inspect_glyphs(bytes, glyf, loca_offsets, glyph_count, maxp_metrics.max_component_depth)?
	os2_result = inspect_os2(bytes, os2)?
	names = inspect_names(bytes, name)?
	cmap_result = inspect_cmap(bytes, cmap_table, glyph_count, limits.max_cmap_mappings)?
	digest = KernelSha256.digest(bytes) ? |_| ArithmeticOverflow

	Ok({
		bytes,
		cmap: cmap_result.cmap,
		components: glyph_result.components,
		coverage: cmap_result.coverage,
		digest,
		embedding_rights: os2_result.embedding_rights,
		loca_offsets,
		metrics: {
			ascent: horizontal.ascent,
			cap_height: os2_result.cap_height,
			descent: horizontal.descent,
			glyph_count,
			index_to_loc_format: head_metrics.index_to_loc_format,
			line_gap: horizontal.line_gap,
			number_of_h_metrics: horizontal.number_of_h_metrics,
			units_per_em: head_metrics.units_per_em,
			x_max: head_metrics.x_max,
			x_min: head_metrics.x_min,
			y_max: head_metrics.y_max,
			y_min: head_metrics.y_min,
		},
		names,
		tables: $tables,
		work: {
			checksum_bytes: bytes.len() + $tables.fold(0, |total, table| total + padded_length(table.length)),
			cmap_mapping_visits: cmap_result.mapping_visits,
			component_edge_visits: glyph_result.component_edge_visits,
			directory_entries: table_count,
			glyph_visits: glyph_result.glyph_visits,
			loca_entries: loca_offsets.len(),
			overlap_comparisons: overlap_work,
		},
	})
}

valid_search_header : List(U8), U64 -> Bool
valid_search_header = |bytes, table_count| {
	var $power = 1
	var $entry_selector = 0
	while $power * 2 <= table_count {
		$power = $power * 2
		$entry_selector = $entry_selector + 1
	}
	search_range = $power * 16
	range_shift = table_count * 16 - search_range
	read_u16(bytes, 6).to_u64() == search_range and
		read_u16(bytes, 8).to_u64() == $entry_selector and
			read_u16(bytes, 10).to_u64() == range_shift
}

validate_no_overlap : List(KernelFont.Table) -> Try(U64, KernelFont.Error)
validate_no_overlap = |tables| {
	var $left_index = 0
	var $comparisons = 0
	while $left_index < tables.len() {
		left = list_at(tables, $left_index)
		var $right_index = $left_index + 1
		while $right_index < tables.len() {
			right = list_at(tables, $right_index)
			$comparisons = $comparisons + 1
			if ranges_overlap(left.offset, left.length, right.offset, right.length) {
				return Err(OverlappingTables({ left: left.tag, right: right.tag }))
			}
			$right_index = $right_index + 1
		}
		$left_index = $left_index + 1
	}
	Ok($comparisons)
}

ranges_overlap : U64, U64, U64, U64 -> Bool
ranges_overlap = |left_offset, left_length, right_offset, right_length| {
	if left_length == 0 or right_length == 0 {
		False
	} else {
		left_offset < right_offset + right_length and right_offset < left_offset + left_length
	}
}

required_table : List(KernelFont.Table), U32 -> Try(KernelFont.Table, KernelFont.Error)
required_table = |tables, wanted| {
	var $index = 0
	while $index < tables.len() {
		table = list_at(tables, $index)
		if table.tag == wanted {
			return Ok(table)
		}
		$index = $index + 1
	}
	Err(MissingTable(wanted))
}

inspect_head : List(U8), KernelFont.Table -> Try({ index_to_loc_format : U8, units_per_em : U16, x_max : I64, x_min : I64, y_max : I64, y_min : I64 }, KernelFont.Error)
inspect_head = |bytes, table| {
	if table.length < 54 or read_u32(bytes, table.offset) != 0x00010000 or read_u32(bytes, table.offset + 12) != 0x5f0f3cf5 {
		return Err(InvalidHead)
	}
	units_per_em = read_u16(bytes, table.offset + 18)
	loc_format = signed_i16(read_u16(bytes, table.offset + 50))
	if units_per_em < 16 or units_per_em > 16384 or (loc_format != 0 and loc_format != 1) or signed_i16(read_u16(bytes, table.offset + 52)) != 0 {
		return Err(InvalidHead)
	}
	Ok({
		index_to_loc_format: loc_format.to_u8_wrap(),
		units_per_em,
		x_min: signed_i16(read_u16(bytes, table.offset + 36)),
		y_min: signed_i16(read_u16(bytes, table.offset + 38)),
		x_max: signed_i16(read_u16(bytes, table.offset + 40)),
		y_max: signed_i16(read_u16(bytes, table.offset + 42)),
	})
}

inspect_maxp : List(U8), KernelFont.Table, U64 -> Try({ glyph_count : U64, max_component_depth : U64 }, KernelFont.Error)
inspect_maxp = |bytes, table, max_glyphs| {
	if table.length < 32 or read_u32(bytes, table.offset) != 0x00010000 {
		return Err(InvalidMaxp)
	}
	glyphs = read_u16(bytes, table.offset + 4).to_u64()
	if glyphs == 0 {
		Err(InvalidMaxp)
	} else if glyphs > max_glyphs {
		Err(LimitExceeded({ attempted: glyphs, dimension: Glyphs, limit: max_glyphs }))
	} else {
		Ok({ glyph_count: glyphs, max_component_depth: read_u16(bytes, table.offset + 30).to_u64() })
	}
}

inspect_hhea : List(U8), KernelFont.Table, U64 -> Try({ ascent : I64, descent : I64, line_gap : I64, number_of_h_metrics : U64 }, KernelFont.Error)
inspect_hhea = |bytes, table, glyph_count| {
	if table.length < 36 or read_u32(bytes, table.offset) != 0x00010000 or signed_i16(read_u16(bytes, table.offset + 32)) != 0 {
		return Err(InvalidHorizontalMetrics)
	}
	count = read_u16(bytes, table.offset + 34).to_u64()
	if count == 0 or count > glyph_count {
		Err(InvalidHorizontalMetrics)
	} else {
		Ok({
			ascent: signed_i16(read_u16(bytes, table.offset + 4)),
			descent: signed_i16(read_u16(bytes, table.offset + 6)),
			line_gap: signed_i16(read_u16(bytes, table.offset + 8)),
			number_of_h_metrics: count,
		})
	}
}

validate_hmtx : KernelFont.Table, U64, U64 -> Try({}, KernelFont.Error)
validate_hmtx = |table, glyph_count, metric_count| {
	expected = checked_add(checked_times(metric_count, 4)?, checked_times(glyph_count - metric_count, 2)?)?
	if table.length != expected {
		Err(InvalidHorizontalMetrics)
	} else {
		Ok({})
	}
}

inspect_loca : List(U8), KernelFont.Table, KernelFont.Table, U64, U8 -> Try(List(U64), KernelFont.Error)
inspect_loca = |bytes, loca, glyf, glyph_count, format| {
	entry_size = if format == 0 2 else 4
	entry_count = glyph_count + 1
	if loca.length != entry_count * entry_size {
		return Err(InvalidLoca)
	}
	var $index = 0
	var $previous = 0
	var $offsets = List.with_capacity(entry_count)
	while $index < entry_count {
		raw = if format == 0 {
			read_u16(bytes, loca.offset + $index * 2).to_u64() * 2
		} else {
			read_u32(bytes, loca.offset + $index * 4).to_u64()
		}
		if raw < $previous or raw > glyf.length {
			return Err(InvalidLoca)
		}
		$offsets = $offsets.append(raw)
		$previous = raw
		$index = $index + 1
	}
	Ok($offsets)
}

inspect_glyphs : List(U8), KernelFont.Table, List(U64), U64, U64 -> Try({ component_edge_visits : U64, components : List(KernelFont.ComponentEdge), glyph_visits : U64 }, KernelFont.Error)
inspect_glyphs = |bytes, glyf, loca_offsets, glyph_count, declared_depth| {
	var $components = []
	var $glyph = 0
	while $glyph < glyph_count {
		relative_start = list_at(loca_offsets, $glyph)
		relative_end = list_at(loca_offsets, $glyph + 1)
		if relative_start != relative_end {
			start = glyf.offset + relative_start
			end = glyf.offset + relative_end
			if end - start < 10 {
				return Err(InvalidGlyph({ glyph: $glyph.to_u32_wrap(), offset: relative_start }))
			}
			contours = signed_i16(read_u16(bytes, start))
			if signed_i16(read_u16(bytes, start + 2)) > signed_i16(read_u16(bytes, start + 6)) or signed_i16(read_u16(bytes, start + 4)) > signed_i16(read_u16(bytes, start + 8)) {
				return Err(InvalidGlyph({ glyph: $glyph.to_u32_wrap(), offset: relative_start }))
			}
			if contours >= 0 {
				validate_simple_glyph(bytes, start, end, contours.to_u64_wrap(), $glyph.to_u32_wrap(), relative_start)?
			} else {
				edges = inspect_composite_glyph(bytes, start, end, $glyph.to_u32_wrap(), glyph_count, relative_start)?
				$components = append_all($components, edges)
			}
		}
		$glyph = $glyph + 1
	}
	graph = validate_component_graph($components, glyph_count, declared_depth)?
	Ok({
		component_edge_visits: graph.edge_visits,
		components: $components,
		glyph_visits: glyph_count,
	})
}

validate_simple_glyph : List(U8), U64, U64, U64, U32, U64 -> Try({}, KernelFont.Error)
validate_simple_glyph = |bytes, start, end, contour_count, glyph, relative_offset| {
	var $cursor = start + 10
	if contour_count == 0 and $cursor == end {
		return Ok({})
	}
	if contour_count > (end - $cursor) / 2 {
		return Err(InvalidGlyph({ glyph, offset: relative_offset }))
	}
	var $contour = 0
	var $previous_end = NoPrevious
	var $point_count = 0
	while $contour < contour_count {
		point_end = read_u16(bytes, $cursor + $contour * 2).to_u64()
		match $previous_end {
			NoPrevious => {}
			Previous(value) => if point_end <= value return Err(InvalidGlyph({ glyph, offset: relative_offset }))
		}
		$previous_end = Previous(point_end)
		$point_count = point_end + 1
		$contour = $contour + 1
	}
	$cursor = $cursor + contour_count * 2
	if $cursor + 2 > end {
		return Err(InvalidGlyph({ glyph, offset: relative_offset }))
	}
	instruction_length = read_u16(bytes, $cursor).to_u64()
	$cursor = $cursor + 2
	if instruction_length > end - $cursor {
		return Err(InvalidGlyph({ glyph, offset: relative_offset }))
	}
	$cursor = $cursor + instruction_length
	var $logical_points = 0
	var $x_bytes = 0
	var $y_bytes = 0
	while $logical_points < $point_count {
		if $cursor >= end {
			return Err(InvalidGlyph({ glyph, offset: relative_offset }))
		}
		flag = list_at(bytes, $cursor)
		$cursor = $cursor + 1
		if flag.bitwise_and(0x80) != 0 {
			return Err(InvalidGlyph({ glyph, offset: relative_offset }))
		}
		repeat = if flag.bitwise_and(0x08) == 0 {
			1
		} else {
			if $cursor >= end return Err(InvalidGlyph({ glyph, offset: relative_offset }))
			count = list_at(bytes, $cursor).to_u64() + 1
			$cursor = $cursor + 1
			count
		}
		if repeat > $point_count - $logical_points {
			return Err(InvalidGlyph({ glyph, offset: relative_offset }))
		}
		x_size = if flag.bitwise_and(0x02) != 0 1 else if flag.bitwise_and(0x10) != 0 0 else 2
		y_size = if flag.bitwise_and(0x04) != 0 1 else if flag.bitwise_and(0x20) != 0 0 else 2
		$x_bytes = $x_bytes + repeat * x_size
		$y_bytes = $y_bytes + repeat * y_size
		$logical_points = $logical_points + repeat
	}
	if $x_bytes > end - $cursor or $y_bytes > end - $cursor - $x_bytes {
		Err(InvalidGlyph({ glyph, offset: relative_offset }))
	} else {
		Ok({})
	}
}

inspect_composite_glyph : List(U8), U64, U64, U32, U64, U64 -> Try(List(KernelFont.ComponentEdge), KernelFont.Error)
inspect_composite_glyph = |bytes, start, end, glyph, glyph_count, relative_offset| {
	var $cursor = start + 10
	var $edges = []
	var $more = True
	var $first = True
	var $has_instructions = False
	while $more {
		if $cursor + 4 > end {
			return Err(InvalidGlyph({ glyph, offset: relative_offset }))
		}
		flags = read_u16(bytes, $cursor)
		child = read_u16(bytes, $cursor + 2).to_u32()
		$cursor = $cursor + 4
		transform_count = (if flags.bitwise_and(0x0008) != 0 1 else 0) + (if flags.bitwise_and(0x0040) != 0 1 else 0) + (if flags.bitwise_and(0x0080) != 0 1 else 0)
		if flags.bitwise_and(0xe010) != 0 or transform_count > 1 or (flags.bitwise_and(0x1800) == 0x1800) or ($first and flags.bitwise_and(0x0002) == 0) or child.to_u64() >= glyph_count {
			return Err(InvalidGlyph({ glyph, offset: relative_offset }))
		}
		argument_bytes = if flags.bitwise_and(0x0001) != 0 4 else 2
		transform_bytes = if flags.bitwise_and(0x0008) != 0 2 else if flags.bitwise_and(0x0040) != 0 4 else if flags.bitwise_and(0x0080) != 0 8 else 0
		additional = argument_bytes + transform_bytes
		if additional > end - $cursor {
			return Err(InvalidGlyph({ glyph, offset: relative_offset }))
		}
		$cursor = $cursor + additional
		component_offset = relative_offset + ($cursor - start) - additional - 2
		$edges = $edges.append({ child, component_offset, parent: glyph })
		$has_instructions = $has_instructions or flags.bitwise_and(0x0100) != 0
		$more = flags.bitwise_and(0x0020) != 0
		$first = False
	}
	if $has_instructions {
		if $cursor + 2 > end {
			return Err(InvalidGlyph({ glyph, offset: relative_offset }))
		}
		instruction_length = read_u16(bytes, $cursor).to_u64()
		$cursor = $cursor + 2
		if instruction_length > end - $cursor {
			return Err(InvalidGlyph({ glyph, offset: relative_offset }))
		}
	}
	Ok($edges)
}

validate_component_graph : List(KernelFont.ComponentEdge), U64, U64 -> Try({ edge_visits : U64 }, KernelFont.Error)
validate_component_graph = |edges, glyph_count, declared_depth| {
	var $remaining_children = List.repeat(0, glyph_count)
	var $parent_counts = List.repeat(0, glyph_count)
	var $edge_index = 0
	while $edge_index < edges.len() {
		edge = list_at(edges, $edge_index)
		parent = edge.parent.to_u64()
		child = edge.child.to_u64()
		$remaining_children = list_set($remaining_children, parent, list_at($remaining_children, parent) + 1)
		$parent_counts = list_set($parent_counts, child, list_at($parent_counts, child) + 1)
		$edge_index = $edge_index + 1
	}
	var $starts = List.with_capacity(glyph_count + 1)
	var $total = 0
	var $glyph = 0
	while $glyph < glyph_count {
		$starts = $starts.append($total)
		$total = $total + list_at($parent_counts, $glyph)
		$glyph = $glyph + 1
	}
	$starts = $starts.append($total)
	var $write_positions = List.with_capacity(glyph_count)
	$glyph = 0
	while $glyph < glyph_count {
		$write_positions = $write_positions.append(list_at($starts, $glyph))
		$glyph = $glyph + 1
	}
	var $parents = List.repeat(0, edges.len())
	$edge_index = 0
	while $edge_index < edges.len() {
		edge = list_at(edges, $edge_index)
		child = edge.child.to_u64()
		position = list_at($write_positions, child)
		$parents = list_set($parents, position, edge.parent.to_u64())
		$write_positions = list_set($write_positions, child, position + 1)
		$edge_index = $edge_index + 1
	}
	var $depths = List.repeat(0, glyph_count)
	var $queue = List.with_capacity(glyph_count)
	$glyph = 0
	while $glyph < glyph_count {
		if list_at($remaining_children, $glyph) == 0 {
			$queue = $queue.append($glyph)
		}
		$glyph = $glyph + 1
	}
	var $queue_index = 0
	var $processed = 0
	var $edge_visits = 0
	var $actual_depth = 0
	while $queue_index < $queue.len() {
		child = list_at($queue, $queue_index)
		child_depth = list_at($depths, child)
		var $position = list_at($starts, child)
		end = list_at($starts, child + 1)
		while $position < end {
			parent = list_at($parents, $position)
			candidate_depth = child_depth + 1
			if candidate_depth > list_at($depths, parent) {
				$depths = list_set($depths, parent, candidate_depth)
			}
			remaining = list_at($remaining_children, parent) - 1
			$remaining_children = list_set($remaining_children, parent, remaining)
			if remaining == 0 {
				parent_depth = list_at($depths, parent)
				if parent_depth > $actual_depth {
					$actual_depth = parent_depth
				}
				$queue = $queue.append(parent)
			}
			$edge_visits = $edge_visits + 1
			$position = $position + 1
		}
		$processed = $processed + 1
		$queue_index = $queue_index + 1
	}
	if $processed != glyph_count {
		Err(CompositeCycle)
	} else if $actual_depth > declared_depth {
		Err(CompositeDepthMismatch({ actual: $actual_depth, declared: declared_depth }))
	} else {
		Ok({ edge_visits: $edge_visits })
	}
}

inspect_os2 : List(U8), KernelFont.Table -> Try({ cap_height : I64, embedding_rights : KernelFont.EmbeddingRights }, KernelFont.Error)
inspect_os2 = |bytes, table| {
	if table.length < 90 or read_u16(bytes, table.offset) < 2 {
		return Err(InvalidOs2)
	}
	fs_type = read_u16(bytes, table.offset + 8)
	embedding_rights = if fs_type.bitwise_and(0x0002) != 0 or fs_type.bitwise_and(0x0100) != 0 or fs_type.bitwise_and(0x0200) != 0 {
		problem : KernelFont.Error
		problem = InvalidEmbeddingRights(fs_type)
		return Err(problem)
	} else if fs_type.bitwise_and(0x0008) != 0 {
		Editable
	} else if fs_type.bitwise_and(0x0004) != 0 {
		PreviewAndPrint
	} else {
		Installable
	}
	cap_height = signed_i16(read_u16(bytes, table.offset + 88))
	if cap_height <= 0 {
		Err(InvalidOs2)
	} else {
		Ok({ cap_height, embedding_rights })
	}
}

inspect_names : List(U8), KernelFont.Table -> Try(KernelFont.Names, KernelFont.Error)
inspect_names = |bytes, table| {
	if table.length < 6 {
		return Err(InvalidName)
	}
	format = read_u16(bytes, table.offset)
	count = read_u16(bytes, table.offset + 2).to_u64()
	string_offset = read_u16(bytes, table.offset + 4).to_u64()
	record_end = checked_add(6, checked_times(count, 12)?)?
	if format > 1 or record_end > table.length or string_offset < record_end or string_offset > table.length {
		return Err(InvalidName)
	}
	empty : KernelFont.NameRange
	empty = { length: 0, offset: 0 }
	var $family = empty
	var $full = empty
	var $postscript = empty
	var $family_priority = 0
	var $full_priority = 0
	var $postscript_priority = 0
	var $index = 0
	while $index < count {
		record = table.offset + 6 + $index * 12
		platform_id = read_u16(bytes, record)
		encoding = read_u16(bytes, record + 2)
		language = read_u16(bytes, record + 4)
		name_id = read_u16(bytes, record + 6)
		length = read_u16(bytes, record + 8).to_u64()
		offset = read_u16(bytes, record + 10).to_u64()
		if length % 2 != 0 or offset > table.length - string_offset or length > table.length - string_offset - offset {
			return Err(InvalidName)
		}
		range : KernelFont.NameRange
		range = { length, offset: table.offset + string_offset + offset }
		priority = if platform_id == 3 and language == 0x0409 {
			if encoding == 10 2 else if encoding == 1 1 else 0
		} else {
			0
		}
		if priority > 0 and (name_id == 1 or name_id == 4 or name_id == 6) {
			if length == 0 or !valid_utf16be(bytes, range) {
				return Err(InvalidName)
			}
			if name_id == 1 and priority > $family_priority {
				$family = range
				$family_priority = priority
			} else if name_id == 4 and priority > $full_priority {
				$full = range
				$full_priority = priority
			} else if name_id == 6 and priority > $postscript_priority {
				if !valid_postscript_utf16be(bytes, range) {
					return Err(InvalidName)
				}
				$postscript = range
				$postscript_priority = priority
			}
		}
		$index = $index + 1
	}
	if $family_priority == 0 or $full_priority == 0 or $postscript_priority == 0 {
		Err(InvalidName)
	} else {
		Ok({ family_utf16be: $family, full_utf16be: $full, postscript_utf16be: $postscript })
	}
}

valid_utf16be : List(U8), KernelFont.NameRange -> Bool
valid_utf16be = |bytes, range| {
	var $index = 0
	while $index < range.length {
		unit = read_u16(bytes, range.offset + $index)
		if unit >= 0xd800 and unit <= 0xdbff {
			if $index + 4 > range.length {
				return False
			}
			low = read_u16(bytes, range.offset + $index + 2)
			if low < 0xdc00 or low > 0xdfff {
				return False
			}
			$index = $index + 4
		} else if unit >= 0xdc00 and unit <= 0xdfff {
			return False
		} else {
			$index = $index + 2
		}
	}
	True
}

valid_postscript_utf16be : List(U8), KernelFont.NameRange -> Bool
valid_postscript_utf16be = |bytes, range| {
	var $index = 0
	while $index < range.length {
		unit = read_u16(bytes, range.offset + $index)
		if unit > 0x7e or unit < 0x21 or postscript_delimiter(unit.to_u8_wrap()) {
			return False
		}
		$index = $index + 2
	}
	True
}

postscript_delimiter : U8 -> Bool
postscript_delimiter = |byte| byte == 0x28 or byte == 0x29 or byte == 0x3c or byte == 0x3e or byte == 0x5b or byte == 0x5d or byte == 0x7b or byte == 0x7d or byte == 0x2f or byte == 0x25

postscript_name_bytes : KernelFont.Inspection -> List(U8)
postscript_name_bytes = |font| {
	range = font.names.postscript_utf16be
	var $result = List.with_capacity(range.length / 2)
	var $index = 0
	while $index < range.length {
		$result = $result.append(list_at(font.bytes, range.offset + $index + 1))
		$index = $index + 2
	}
	$result
}

inspect_cmap : List(U8), KernelFont.Table, U64, U64 -> Try({ cmap : KernelFont.Cmap, coverage : List(KernelFont.CoverageSpan), mapping_visits : U64 }, KernelFont.Error)
inspect_cmap = |bytes, table, glyph_count, mapping_limit| {
	if table.length < 4 or read_u16(bytes, table.offset) != 0 {
		return Err(InvalidCmap)
	}
	encoding_count = read_u16(bytes, table.offset + 2).to_u64()
	if 4 + encoding_count * 8 > table.length {
		return Err(InvalidCmap)
	}
	var $best = NoCandidate
	var $index = 0
	while $index < encoding_count {
		record = table.offset + 4 + $index * 8
		platform_id = read_u16(bytes, record)
		encoding = read_u16(bytes, record + 2)
		subtable_offset = read_u32(bytes, record + 4).to_u64()
		if subtable_offset + 2 > table.length {
			return Err(InvalidCmap)
		}
		absolute = table.offset + subtable_offset
		format = read_u16(bytes, absolute)
		score = cmap_score(platform_id, encoding, format)
		if score > 0 {
			match $best {
				NoCandidate => {
					$best = Candidate({ format, offset: absolute, available: table.length - subtable_offset, score })
				}
				Candidate(current) => if score > current.score {
					$best = Candidate({ format, offset: absolute, available: table.length - subtable_offset, score })
				}
			}
		}
		$index = $index + 1
	}
	match $best {
		NoCandidate => Err(InvalidCmap)
		Candidate(candidate) => if candidate.format == 12 {
			inspect_cmap12(bytes, candidate.offset, candidate.available, glyph_count, mapping_limit)
		} else {
			inspect_cmap4(bytes, candidate.offset, candidate.available, glyph_count, mapping_limit)
		}
	}
}

cmap_score : U16, U16, U16 -> U8
cmap_score = |platform_id, encoding, format| {
	if format == 12 and platform_id == 3 and encoding == 10 {
		5
	} else if format == 12 and platform_id == 0 {
		4
	} else if format == 4 and platform_id == 3 and encoding == 1 {
		3
	} else if format == 4 and platform_id == 0 {
		2
	} else {
		0
	}
}

inspect_cmap12 : List(U8), U64, U64, U64, U64 -> Try({ cmap : KernelFont.Cmap, coverage : List(KernelFont.CoverageSpan), mapping_visits : U64 }, KernelFont.Error)
inspect_cmap12 = |bytes, offset, available, glyph_count, mapping_limit| {
	if available < 16 or read_u16(bytes, offset + 2) != 0 {
		return Err(InvalidCmap)
	}
	length = read_u32(bytes, offset + 4).to_u64()
	group_count = read_u32(bytes, offset + 12).to_u64()
	if length > available or length != 16 + group_count * 12 {
		return Err(InvalidCmap)
	}
	var $groups = []
	var $coverage = []
	var $current_span = NoSpan
	var $previous_end = NoPrevious
	var $mapping_visits = 0
	var $index = 0
	while $index < group_count {
		record = offset + 16 + $index * 12
		start = read_u32(bytes, record)
		end = read_u32(bytes, record + 4)
		start_glyph = read_u32(bytes, record + 8)
		if start > end or end > 0x10ffff or (start <= 0xdfff and end >= 0xd800) {
			return Err(InvalidCmap)
		}
		match $previous_end {
			NoPrevious => {}
			Previous(value) => if start <= value return Err(InvalidCmap)
		}
		count = end.to_u64() - start.to_u64() + 1
		if start_glyph.to_u64() + count > glyph_count {
			return Err(InvalidCmap)
		}
		$mapping_visits = $mapping_visits + count
		if $mapping_visits > mapping_limit {
			return Err(CmapLimitExceeded({ attempted: $mapping_visits, limit: mapping_limit }))
		}
		$groups = $groups.append({ start, end, start_glyph })
		first_covered = if start_glyph == 0 start + 1 else start
		if first_covered <= end {
			appended = coverage_append($coverage, $current_span, first_covered, end)
			$coverage = appended.complete
			$current_span = appended.current
		}
		$previous_end = Previous(end)
		$index = $index + 1
	}
	final_coverage = coverage_finish($coverage, $current_span)
	Ok({ cmap: Format12({ groups: $groups }), coverage: final_coverage, mapping_visits: $mapping_visits })
}

inspect_cmap4 : List(U8), U64, U64, U64, U64 -> Try({ cmap : KernelFont.Cmap, coverage : List(KernelFont.CoverageSpan), mapping_visits : U64 }, KernelFont.Error)
inspect_cmap4 = |bytes, offset, available, glyph_count, mapping_limit| {
	if available < 16 {
		return Err(InvalidCmap)
	}
	length = read_u16(bytes, offset + 2).to_u64()
	seg_count_x2 = read_u16(bytes, offset + 6).to_u64()
	if seg_count_x2 == 0 or seg_count_x2 % 2 != 0 {
		return Err(InvalidCmap)
	}
	seg_count = seg_count_x2 / 2
	minimum = 16 + seg_count * 8
	if length > available or length < minimum or read_u16(bytes, offset + 14 + seg_count * 2) != 0 or !valid_cmap4_search(bytes, offset, seg_count) {
		return Err(InvalidCmap)
	}
	end_codes = offset + 14
	start_codes = end_codes + seg_count * 2 + 2
	deltas = start_codes + seg_count * 2
	range_offsets = deltas + seg_count * 2
	var $segments = []
	var $coverage = []
	var $current_span = NoSpan
	var $previous_end = NoPrevious
	var $mapping_visits = 0
	var $index = 0
	while $index < seg_count {
		start = read_u16(bytes, start_codes + $index * 2).to_u32()
		end = read_u16(bytes, end_codes + $index * 2).to_u32()
		delta = signed_i16(read_u16(bytes, deltas + $index * 2))
		range_offset_location = range_offsets + $index * 2
		range_offset = read_u16(bytes, range_offset_location)
		if start > end {
			return Err(InvalidCmap)
		}
		match $previous_end {
			NoPrevious => {}
			Previous(value) => if start <= value return Err(InvalidCmap)
		}
		segment : KernelFont.CmapSegment
		segment = { start, end, delta, range_offset, range_offset_location }
		$segments = $segments.append(segment)
		var $scalar = start
		while $scalar <= end {
			$mapping_visits = $mapping_visits + 1
			if $mapping_visits > mapping_limit {
				return Err(CmapLimitExceeded({ attempted: $mapping_visits, limit: mapping_limit }))
			}
			match glyph_for_segment(bytes, segment, offset + length, $scalar) {
				InvalidGlyph => return Err(InvalidCmap)
				NoGlyph => {}
				Mapped(glyph) => {
					if glyph.to_u64() >= glyph_count {
						return Err(InvalidCmap)
					}
					if !is_surrogate($scalar) {
						appended = coverage_append($coverage, $current_span, $scalar, $scalar)
						$coverage = appended.complete
						$current_span = appended.current
					}
				}
			}
			if $scalar == 0xffff {
				break
			}
			$scalar = $scalar + 1
		}
		$previous_end = Previous(end)
		$index = $index + 1
	}
	last = list_at($segments, seg_count - 1)
	if last.start != 0xffff or last.end != 0xffff {
		return Err(InvalidCmap)
	}
	Ok({
		cmap: Format4({ length, offset, segments: $segments }),
		coverage: coverage_finish($coverage, $current_span),
		mapping_visits: $mapping_visits,
	})
}

valid_cmap4_search : List(U8), U64, U64 -> Bool
valid_cmap4_search = |bytes, offset, count| {
	var $power = 1
	var $selector = 0
	while $power * 2 <= count {
		$power = $power * 2
		$selector = $selector + 1
	}
	read_u16(bytes, offset + 8).to_u64() == $power * 2 and
		read_u16(bytes, offset + 10).to_u64() == $selector and
			read_u16(bytes, offset + 12).to_u64() == count * 2 - $power * 2
}

glyph_for_cmap : List(U8), KernelFont.Cmap, U64, U32 -> [None, Some(U32)]
glyph_for_cmap = |bytes, cmap, glyph_count, scalar| match cmap {
	Format12({ groups }) => {
		var $index = 0
		while $index < groups.len() {
			group = list_at(groups, $index)
			if scalar < group.start {
				return None
			}
			if scalar <= group.end {
				glyph = group.start_glyph + (scalar - group.start)
				return if glyph == 0 or glyph.to_u64() >= glyph_count None else Some(glyph)
			}
			$index = $index + 1
		}
		None
	}
	Format4({ length, offset, segments }) => {
		var $index = 0
		while $index < segments.len() {
			segment = list_at(segments, $index)
			if scalar < segment.start {
				return None
			}
			if scalar <= segment.end {
				return match glyph_for_segment(bytes, segment, offset + length, scalar) {
					Mapped(glyph) => if glyph.to_u64() < glyph_count Some(glyph) else None
					_ => None
				}
			}
			$index = $index + 1
		}
		None
	}
}

glyph_for_segment : List(U8), KernelFont.CmapSegment, U64, U32 -> [InvalidGlyph, Mapped(U32), NoGlyph]
glyph_for_segment = |bytes, segment, subtable_end, scalar| {
	if segment.range_offset == 0 {
		glyph = (scalar.to_i64() + segment.delta).to_u16_wrap().to_u32()
		if glyph == 0 NoGlyph else Mapped(glyph)
	} else {
		location = segment.range_offset_location + segment.range_offset.to_u64() + (scalar - segment.start).to_u64() * 2
		if location + 2 > subtable_end {
			InvalidGlyph
		} else {
			raw = read_u16(bytes, location)
			if raw == 0 {
				NoGlyph
			} else {
				Mapped((raw.to_i64() + segment.delta).to_u16_wrap().to_u32())
			}
		}
	}
}

coverage_append : List(KernelFont.CoverageSpan), [Current(KernelFont.CoverageSpan), NoSpan], U32, U32 -> { complete : List(KernelFont.CoverageSpan), current : [Current(KernelFont.CoverageSpan), NoSpan] }
coverage_append = |complete, current, first, last| match current {
	NoSpan => { complete, current: Current({ first, last }) }
	Current(span) => if first == span.last + 1 {
		{ complete, current: Current({ first: span.first, last }) }
	} else {
		{ complete: complete.append(span), current: Current({ first, last }) }
	}
}

coverage_finish : List(KernelFont.CoverageSpan), [Current(KernelFont.CoverageSpan), NoSpan] -> List(KernelFont.CoverageSpan)
coverage_finish = |complete, current| match current {
	NoSpan => complete
	Current(span) => complete.append(span)
}

table_checksum : List(U8), U64, U64, Bool -> U32
table_checksum = |bytes, offset, length, is_head| checksum_range(bytes, offset, length, is_head)

checksum_range : List(U8), U64, U64, Bool -> U32
checksum_range = |bytes, offset, length, zero_adjustment| {
	var $sum = 0
	var $index = 0
	while $index < padded_length(length) {
		var $word = 0
		var $byte_index = 0
		while $byte_index < 4 {
			position = $index + $byte_index
			byte = if position >= length or (zero_adjustment and position >= 8 and position < 12) {
				0
			} else {
				list_at(bytes, offset + position)
			}
			$word = $word.bitwise_or(byte.to_u32().shl_wrap((3 - $byte_index).to_u8_wrap() * 8))
			$byte_index = $byte_index + 1
		}
		$sum = U32.plus_wrap($sum, $word)
		$index = $index + 4
	}
	$sum
}

padded_length : U64 -> U64
padded_length = |length| if length % 4 == 0 length else length + (4 - length % 4)

read_u16 : List(U8), U64 -> U16
read_u16 = |bytes, index| list_at(bytes, index).to_u16().shl_wrap(8).bitwise_or(list_at(bytes, index + 1).to_u16())

read_u32 : List(U8), U64 -> U32
read_u32 = |bytes, index| {
	list_at(bytes, index).to_u32().shl_wrap(24)
		.bitwise_or(list_at(bytes, index + 1).to_u32().shl_wrap(16))
		.bitwise_or(list_at(bytes, index + 2).to_u32().shl_wrap(8))
		.bitwise_or(list_at(bytes, index + 3).to_u32())
}

signed_i16 : U16 -> I64
signed_i16 = |value| if value >= 0x8000 value.to_i64() - 0x10000 else value.to_i64()

is_surrogate : U32 -> Bool
is_surrogate = |value| value >= 0xd800 and value <= 0xdfff

checked_add : U64, U64 -> Try(U64, KernelFont.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_times : U64, U64 -> Try(U64, KernelFont.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated font index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated font list update escaped"
	}
	Ok(updated) => updated
}

append_all : List(a), List(a) -> List(a)
append_all = |left, right| {
	var $result = left
	var $index = 0
	while $index < right.len() {
		$result = $result.append(list_at(right, $index))
		$index = $index + 1
	}
	$result
}

tag_cmap : U32
tag_cmap = 0x636d6170

tag_glyf : U32
tag_glyf = 0x676c7966

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

sfnt_checksum : U32
sfnt_checksum = 0xb1b0afba

## Unsupported program signatures are rejected before table parsing.
expect match KernelFont.inspect(
	[0x4f, 0x54, 0x54, 0x4f, 0, 0, 0, 0, 0, 0, 0, 0],
	KernelFont.Limits.make({ max_bytes: 12, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 }),
) {
	Err(UnsupportedFontProgram(0x4f54544f)) => Bool.True
	_ => Bool.False
}

## The byte budget rejects before inspecting an attacker-controlled header.
expect match KernelFont.inspect(
	[0, 1, 0, 0],
	KernelFont.Limits.make({ max_bytes: 3, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 }),
) {
	Err(LimitExceeded({ attempted: 4, dimension: FontBytes, limit: 3 })) => Bool.True
	_ => Bool.False
}

## A one-point simple glyph whose packed flag omits both coordinates is valid.
expect validate_simple_glyph(
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x31],
	0,
	15,
	1,
	0,
	0,
) == Ok({})

## Reserved simple-glyph flag bits are rejected within the glyph span.
expect match validate_simple_glyph(
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x80],
	0,
	15,
	1,
	7,
	22,
) {
	Err(InvalidGlyph({ glyph: 7, offset: 22 })) => Bool.True
	_ => Bool.False
}

## Composite closure is acyclic and its actual depth fits maxp's declaration.
expect validate_component_graph(
	[{ child: 0, component_offset: 10, parent: 1 }, { child: 1, component_offset: 20, parent: 2 }],
	3,
	2,
) == Ok({ edge_visits: 2 })

expect match validate_component_graph(
	[{ child: 1, component_offset: 10, parent: 0 }, { child: 0, component_offset: 20, parent: 1 }],
	2,
	2,
) {
	Err(CompositeCycle) => Bool.True
	_ => Bool.False
}

## Name parsing rejects malformed surrogate structure and PostScript delimiters.
expect valid_utf16be([0xd8, 0x00, 0xdc, 0x00], { length: 4, offset: 0 })
expect !valid_utf16be([0xd8, 0x00, 0x00, 0x41], { length: 4, offset: 0 })
expect valid_postscript_utf16be([0x00, 0x46, 0x00, 0x6f, 0x00, 0x6e, 0x00, 0x74], { length: 8, offset: 0 })
expect !valid_postscript_utf16be([0x00, 0x46, 0x00, 0x2f, 0x00, 0x31], { length: 6, offset: 0 })

expect match validate_component_graph(
	[{ child: 0, component_offset: 10, parent: 1 }, { child: 1, component_offset: 20, parent: 2 }],
	3,
	1,
) {
	Err(CompositeDepthMismatch({ actual: 2, declared: 1 })) => Bool.True
	_ => Bool.False
}
