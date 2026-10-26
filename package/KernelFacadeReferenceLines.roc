import Document
import KernelFacadeLines
import KernelFacadePages
import KernelFacadeReferenceShape
import KernelFacadeSemantics
import KernelFacadeShape
import KernelFacadeSources
import KernelFacadeTables
import KernelLineLayout
import KernelReferenceLayout
import Layout
import Semantics
import Text
import Theme
import unicode.Scalar

## One source-free row arena is selected before pagination. Its items
## retain real literal-cluster identity or an unresolved fixed-width atom.
KernelFacadeReferenceLines :: [].{
	Error : [
		InvalidContext({ block : U64 }),
		LimitExceeded,
		Geometry(KernelFacadeLines.Error),
		Items({ block : U64, error : KernelReferenceLayout.Error }),
		Tables(KernelFacadeTables.Error),
		SourceOverflow({ source : U64, line : U64, width : Layout.Unit, available : Layout.Unit }),
	]
	Work : { atoms : U64, literal_clusters : U64, glyph_indices : U64, hold_scalars : U64, holds : U64, measured_items : U64, wrapped_items : U64, boundaries : U64, rows : U64, row_items : U64, alignment_items : U64 }
	View : {
		items : List(KernelReferenceLayout.Item),
		rows : List(KernelReferenceLayout.Line),
		item_offsets : List(Layout.Unit),
		input : KernelFacadePages.MeasuredInput,
		visible_advances : List(U64),
		work : Work,
	}
	Plan :: View.{
		build : KernelFacadeSemantics.SymbolicView, KernelFacadeReferenceShape.Plan, Layout.Size, Theme, KernelFacadeLines.Limits -> Try(Plan, Error)
		build = |symbolic, shape, page, theme, limits| build_plan(symbolic, shape, page, theme, limits)
		view : Plan -> View
		view = |Plan.(value)| value
	}
}

BlockItems : { body : Semantics.IndexRange, label : [NoLabel, Label(Semantics.IndexRange)], size : Layout.Unit }

Holds : { ranges : List(Semantics.IndexRange), contexts : List(Semantics.IndexRange), scalars : U64 }

build_plan : KernelFacadeSemantics.SymbolicView, KernelFacadeReferenceShape.Plan, Layout.Size, Theme, KernelFacadeLines.Limits -> Try(KernelFacadeReferenceLines.Plan, KernelFacadeReferenceLines.Error)
build_plan = |symbolic, shape, page, theme, line_limits| {
	authoring = symbolic.authoring
	owners = symbolic.block_ownership
	limits = KernelFacadeLines.Limits.values(line_limits)
	item_limits = { max_items: KernelLineLayout.BatchLimits.max_items(limits.line), max_lines: KernelLineLayout.BatchLimits.max_lines(limits.line) }
	if owners.len() != authoring.blocks.len() or owners.len() > limits.max_blocks {
		return Err(LimitExceeded)
	}
	shaped = KernelFacadeReferenceShape.Plan.view(shape)
	sources = KernelFacadeSources.Plan.sources(symbolic.sources)
	holds = build_holds(authoring, shaped.literals, item_limits.max_items)?
	var $builder = KernelReferenceLayout.Builder.start(item_limits)
	var $blocks = List.with_capacity(owners.len())
	var $literal = 0
	var $pending = 0
	var $block = 0
	while $block < owners.len() {
		label_start = KernelReferenceLayout.Builder.position($builder) ? |error| Items({ block: $block, error })
		var $label = NoLabel
		if $literal < shaped.literals.len() {
			context = list_at(shaped.literals, $literal)
			if context.block == $block and context.role == GeneratedLabel {
				$builder = append_literal($builder, shaped, $literal, holds, sources)
				$builder = KernelReferenceLayout.Builder.segment_end($builder)
				label_end = KernelReferenceLayout.Builder.position($builder) ? |error| Items({ block: $block, error })
				$label = Label(Semantics.IndexRange.from_start_and_length(label_start, label_end - label_start))
				$literal = $literal + 1
			}
		}
		start = KernelReferenceLayout.Builder.position($builder) ? |error| Items({ block: $block, error })
		var $segment = NoSegment
		var $size = 0.I64
		while ($literal < shaped.literals.len() and list_at(shaped.literals, $literal).block == $block) or ($pending < symbolic.pending.len() and list_at(symbolic.pending, $pending).block == $block) {
			literal_first = $literal < shaped.literals.len() and list_at(shaped.literals, $literal).block == $block and ($pending >= symbolic.pending.len() or list_at(symbolic.pending, $pending).block != $block or list_at(shaped.literals, $literal).occurrence.id.index() < list_at(symbolic.pending, $pending).occurrence.index())
			next_segment = if (literal_first) list_at(shaped.literals, $literal).segment else list_at(symbolic.pending, $pending).segment
			match $segment {
				Segment(previous) if previous != next_segment => {
					$builder = KernelReferenceLayout.Builder.segment_end($builder)
				}
				_ => {}
			}
			$segment = Segment(next_segment)
			if literal_first {
				if list_at(shaped.literals, $literal).role != Body {
					return Err(InvalidContext({ block: $block }))
				}
				physical = list_at(shaped.literal_runs, $literal).runs
				if physical.length() == 0 {
					return Err(InvalidContext({ block: $block }))
				}
				# Every physical segment of this authored leaf shares its size.
				$size = I64.max($size, list_at(shaped.store.runs, physical.start()).size.raw())
				$builder = append_literal($builder, shaped, $literal, holds, sources)
				$literal = $literal + 1
			} else {
				context = list_at(symbolic.pending, $pending)
				if context.reference >= authoring.page_references.len() {
					return Err(InvalidContext({ block: $block }))
				}
				style = KernelFacadeShape.leaf_style(authoring, $block, AtInline(context.inline), Body, theme)
				$size = I64.max($size, style.size.raw())
				$builder = KernelReferenceLayout.Builder.reference($builder, context.reference, list_at(authoring.page_references, context.reference).spec.width)
				$pending = $pending + 1
			}
		}
		end = KernelReferenceLayout.Builder.position($builder) ? |error| Items({ block: $block, error })
		if end > start {
			$builder = KernelReferenceLayout.Builder.segment_end($builder)
		}
		$blocks = $blocks.append({ body: Semantics.IndexRange.from_start_and_length(start, end - start), label: $label, size: Layout.Unit.from_raw($size) })
		$block = $block + 1
	}
	if $literal != shaped.literals.len() or $pending != symbolic.pending.len() {
		return Err(InvalidContext({ block: $block }))
	}
	built = KernelReferenceLayout.Builder.finish($builder) ? |error| Items({ block: 0, error })
	items = built.items
	block_ranges = $blocks
	var $labels = List.with_capacity(owners.len())
	var $measured_items = 0
	for block in block_ranges {
		label = match block.label {
			NoLabel => NoLabel
			Label(range) => {
				width = KernelReferenceLayout.measure(items.sublist({ start: range.start(), len: range.length() }), item_limits) ? |error| Items({ block: $labels.len(), error })
				$measured_items = $measured_items + width.work.item_visits
				Label({ size: positive(Theme.body_style(theme).size), width: positive(width.max_content) })
			}
		}
		$labels = $labels.append(label)
	}
	geometry = KernelFacadeLines.geometry_measured(authoring, $labels, page, theme) ? Geometry
	content_width = positive(page.width) - positive(theme.page_margin.left) - positive(theme.page_margin.right)
	var $group_frames = List.with_capacity(authoring.groups.len())
	var $table_frames = List.with_capacity(authoring.tables.len())
	var $source_frames = []
	var $figure_frames = []
	var $group = 0
	while $group < authoring.groups.len() {
		offset = list_at(geometry.offsets, $group)
		end = if (geometry.ends.is_empty()) content_width else list_at(geometry.ends, $group)
		$group_frames = $group_frames.append({ offset, width: end - offset })
		record = list_at(authoring.groups, $group)
		match record.kind {
			Table(_) => {
				frame = list_at(geometry.blocks, record.first_block)
				$table_frames = $table_frames.append({ offset: frame.body_offset, width: frame.body_width })
			}
			_ => {}
		}
		$group = $group + 1
	}
	for source in authoring.sources {
		frame = list_at(geometry.blocks, list_at(authoring.groups, source.group).first_block)
		$source_frames = $source_frames.append({ offset: Layout.Unit.from_raw(frame.body_offset.to_i64_wrap()), width: Layout.Unit.from_raw(frame.body_width.to_i64_wrap()) })
	}
	$block = 0
	while $block < authoring.blocks.len() {
		record = list_at(authoring.blocks, $block)
		match record.kind {
			Figure(_) => {
				frame = list_at(geometry.blocks, $block)
				var $parent = record.parent
				var $padding = 0
				while $parent != 0 {
					group = list_at(authoring.groups, $parent - 1)
					match group.kind {
						Callout(index) => {
							$padding = $padding + positive(list_at(authoring.callouts, index.to_u64()).padding) * 2
						}
						_ => {}
					}
					$parent = group.parent
				}
				$figure_frames = $figure_frames.append({ width: frame.body_width, padding: $padding })
			}
			_ => {}
		}
		$block = $block + 1
	}

	var $cell_measures = List.with_capacity(authoring.cells.len())
	for cell in authoring.cells {
		range = list_at(block_ranges, cell.block).body
		measure = if (range.length() == 0) { max_content: 0, min_content: 0, token: Items(range) } else {
			measured = KernelReferenceLayout.measure(items.sublist({ start: range.start(), len: range.length() }), item_limits) ? |error| Items({ block: cell.block, error })
			$measured_items = $measured_items + measured.work.item_visits
			{ max_content: positive(measured.max_content), min_content: positive(measured.min_content), token: Items(Semantics.IndexRange.from_start_and_length(range.start() + measured.widest.start(), measured.widest.length())) }
		}
		$cell_measures = $cell_measures.append(measure)
	}
	tables = KernelFacadeTables.Plan.build_measured(authoring, sources, $cell_measures, content_width, $table_frames, theme) ? Tables
	var $cell_widths = List.repeat(0, owners.len())
	for cell in KernelFacadeTables.Plan.cells(tables) {
		$cell_widths = list_set($cell_widths, cell.block, cell.width)
	}
	var $rows = []
	var $visible = []
	var $page_blocks = List.with_capacity(owners.len())
	var $wrapped_items = 0
	var $boundaries = 0
	var $alignment_items = 0
	$block = 0
	while $block < owners.len() {
		block_items = list_at(block_ranges, $block)
		frame = list_at(geometry.blocks, $block)
		start = $rows.len()
		var $label = NoLabel
		match block_items.label {
			NoLabel => {}
			Label(range) => {
				wrapped = KernelReferenceLayout.wrap(items.sublist({ start: range.start(), len: range.length() }), Layout.Unit.from_raw(frame.column.to_i64_wrap()), item_limits) ? |error| Items({ block: $block, error })
				for line in wrapped.lines {
					$rows = $rows.append({ advance: line.advance, items: Semantics.IndexRange.from_start_and_length(range.start() + line.items.start(), line.items.length()) })
					$visible = $visible.append(positive(line.advance))
				}
				$wrapped_items = $wrapped_items + wrapped.work.item_visits
				$boundaries = $boundaries + wrapped.work.boundary_visits
				$label = Label({ rows: Semantics.IndexRange.from_start_and_length(start, $rows.len() - start), offset: Layout.Unit.from_raw(frame.label_offset.to_i64_wrap()) })
			}
		}
		body_start = $rows.len()
		width = if (list_at($cell_widths, $block) > 0) list_at($cell_widths, $block) else frame.body_width
		if block_items.body.length() > 0 {
			body = items.sublist({ start: block_items.body.start(), len: block_items.body.length() })
			match list_at(authoring.blocks, $block).kind {
				SourceLine({ source, line }) if list_at(authoring.sources, source).wrap == RejectLongToken => {
					measured = KernelReferenceLayout.measure(body, item_limits) ? |error| Items({ block: $block, error })
					$measured_items = $measured_items + measured.work.item_visits
					if positive(measured.max_content) > width {
						return Err(SourceOverflow({ source, line, width: measured.max_content, available: Layout.Unit.from_raw(width.to_i64_wrap()) }))
					}
				}
				_ => {}
			}
			wrapped = KernelReferenceLayout.wrap(body, Layout.Unit.from_raw(width.to_i64_wrap()), item_limits) ? |error| Items({ block: $block, error })
			for line in wrapped.lines {
				if $rows.len() >= item_limits.max_lines {
					return Err(LimitExceeded)
				}
				row = { advance: line.advance, items: Semantics.IndexRange.from_start_and_length(block_items.body.start() + line.items.start(), line.items.length()) }
				visible = if (list_at($cell_widths, $block) > 0) literal_visible_advance(items, row, shaped, sources) else { advance: positive(line.advance), visits: 0 }
				$alignment_items = $alignment_items + visible.visits
				$rows = $rows.append(row)
				$visible = $visible.append(visible.advance)
			}
			$wrapped_items = $wrapped_items + wrapped.work.item_visits
			$boundaries = $boundaries + wrapped.work.boundary_visits
		}
		page_block = match list_at(owners, $block) {
			ContentlessCell => ContentlessCell
			EmptySourceLine => match list_at(authoring.blocks, $block).kind {
				EmptySourceLine(value) => EmptySourceLine(value)
				_ => return Err(InvalidContext({ block: $block }))
			}
			TextBlock({ body, level, .. }) => {
				style = KernelFacadeShape.leaf_style(authoring, $block, NoInline, Body, theme)
				MeasuredText({ rows: Semantics.IndexRange.from_start_and_length(body_start, $rows.len() - body_start), size: style.size, leading: style.leading, owner: body, level, body_offset: Layout.Unit.from_raw(frame.body_offset.to_i64_wrap()), label: $label })
			}
			RichTextBlock({ occurrences, level, .. }) => {
				style = Theme.body_style(theme)
				MeasuredText({ rows: Semantics.IndexRange.from_start_and_length(body_start, $rows.len() - body_start), size: block_items.size, leading: style.leading, owner: Semantics.OccurrenceId.from_index(occurrences.start()), level, body_offset: Layout.Unit.from_raw(frame.body_offset.to_i64_wrap()), label: $label })
			}
		}
		$page_blocks = $page_blocks.append(page_block)
		$block = $block + 1
	}
	var $offsets = List.repeat(Layout.Unit.from_raw(0), items.len())
	var $row_items = 0
	for row in $rows {
		var $advance = 0.I64
		var $item = row.items.start()
		while $item < row.items.start() + row.items.length() {
			$offsets = list_set($offsets, $item, Layout.Unit.from_raw($advance))
			$advance = $advance + list_at(items, $item).advance.raw()
			$row_items = $row_items + 1
			$item = $item + 1
		}
		if $advance != row.advance.raw() {
			return Err(InvalidContext({ block: 0 }))
		}
	}
	if $row_items != items.len() {
		return Err(InvalidContext({ block: 0 }))
	}
	Ok(KernelFacadeReferenceLines.Plan.{ items, rows: $rows, item_offsets: $offsets, visible_advances: $visible, input: { blocks: $page_blocks, group_frames: $group_frames, source_frames: $source_frames, figure_frames: $figure_frames, tables: KernelFacadeTables.Plan.tables(tables), cells: KernelFacadeTables.Plan.cells(tables) }, work: { atoms: built.work.atom_writes, literal_clusters: built.work.cluster_visits, glyph_indices: built.work.glyph_index_visits, hold_scalars: holds.scalars, holds: holds.ranges.len(), measured_items: $measured_items, wrapped_items: $wrapped_items, boundaries: $boundaries, rows: $rows.len(), row_items: $row_items, alignment_items: $alignment_items } })
}

append_literal : KernelReferenceLayout.Builder, KernelFacadeReferenceShape.View, U64, Holds, List(KernelFacadeSources.Source) -> KernelReferenceLayout.Builder
append_literal = |builder, shaped, context, holds, sources| {
	var $builder = builder
	runs = list_at(shaped.literal_runs, context).runs
	held = list_at(holds.contexts, context)
	var $hold = held.start()
	var $run = runs.start()
	while $run < runs.start() + runs.length() {
		record = list_at(shaped.store.runs, $run)
		first = list_at(shaped.store.clusters, record.clusters.start()).source.scalars.start()
		last = list_at(shaped.store.clusters, record.clusters.start() + record.clusters.length() - 1).source.scalars
		end = last.start() + last.length()
		while $hold < held.start() + held.length() and range_end(list_at(holds.ranges, $hold)) <= first {
			$hold = $hold + 1
		}
		var $stop = $hold
		while $stop < held.start() + held.length() and list_at(holds.ranges, $stop).start() < end {
			$stop = $stop + 1
		}
		analysis = list_at(sources, list_at(shaped.requests, $run).source.index()).analysis
		$builder = KernelReferenceLayout.Builder.run($builder, shaped.store, Text.RunId.from_index($run), analysis, { ranges: holds.ranges, span: Semantics.IndexRange.from_start_and_length($hold, $stop - $hold) })
		$run = $run + 1
	}
	$builder
}

build_holds : Document.NormalizedAuthoring, List(KernelFacadeReferenceShape.LiteralContext), U64 -> Try(Holds, KernelFacadeReferenceLines.Error)
build_holds = |authoring, literals, limit| {
	var $ranges = []
	var $contexts = List.with_capacity(literals.len())
	var $scalars = 0
	for context in literals {
		start = $ranges.len()
		if KernelFacadeShape.leaf_is_code(authoring, context.inline) {
			inline = match context.inline {
				AtInline(index) => index
				NoInline => crash "code leaf lost inline"
			}
			text = match list_at(authoring.inlines, inline).kind {
				Text(value) => value.text
				_ => crash "code literal lost text"
			}
			origin = match context.occurrence.source {
				Text(_, UnicodeRange(range)) => range.scalars.start()
				_ => crash "code literal lost source"
			}
			var $word = NoWord
			var $end = 0
			for located in Scalar.iter(text) {
				$scalars = $scalars + 1
				$end = located.scalar_index + 1
				if Scalar.to_u32(located.scalar) == 32 {
					match $word {
						Word(first) => {
							if $ranges.len() >= limit {
								return Err(LimitExceeded)
							}
							$ranges = $ranges.append(Semantics.IndexRange.from_start_and_length(origin + first, located.scalar_index - first))
						}
						NoWord => {}
					}
					$word = NoWord
				} else if $word == NoWord {
					$word = Word(located.scalar_index)
				}
			}
			match $word {
				Word(first) => {
					if $ranges.len() >= limit {
						return Err(LimitExceeded)
					}
					$ranges = $ranges.append(Semantics.IndexRange.from_start_and_length(origin + first, $end - first))
				}
				NoWord => {}
			}
		}
		$contexts = $contexts.append(Semantics.IndexRange.from_start_and_length(start, $ranges.len() - start))
	}
	Ok({ ranges: $ranges, contexts: $contexts, scalars: $scalars })
}

positive : Layout.Unit -> U64
positive = |value| if (value.raw() > 0) value.raw().to_u64_wrap() else 0

range_end : Semantics.IndexRange -> U64
range_end = |range| range.start() + range.length()

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(_) => crash "validated reference-line index escaped"
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(updated) => updated
	Err(_) => crash "validated reference-line write escaped"
}

expect {
	authoring = Document.normalize(Document.from_blocks({ title: "Code holds", language: "en", contents: [Document.rich_paragraph([Document.code("pré-2 x")])] }))
	empty = Semantics.IndexRange.from_start_and_length(0, 0)
	context = { block: 0, inline: AtInline(1), segment: 0, role: Body, occurrence: { id: Semantics.OccurrenceId.from_index(0), fragments: empty, language: Language("en"), text_properties: empty, source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange({ scalars: Semantics.IndexRange.from_start_and_length(0, 7), utf8_bytes: Semantics.IndexRange.from_start_and_length(0, 8) })) } }
	plan = build_holds(authoring, [context], 10)?
	plan.scalars == 7 and plan.ranges == [Semantics.IndexRange.from_start_and_length(0, 5), Semantics.IndexRange.from_start_and_length(6, 1)] and plan.contexts == [Semantics.IndexRange.from_start_and_length(0, 2)]
}

literal_visible_advance : List(KernelReferenceLayout.Item), KernelReferenceLayout.Line, KernelFacadeReferenceShape.View, List(KernelFacadeSources.Source) -> { advance : U64, visits : U64 }
literal_visible_advance = |items, line, shaped, sources| {
	var $advance = positive(line.advance)
	var $item = range_end(line.items)
	var $visits = 0
	var $source = U64.highest
	var $bytes = []
	while $item > line.items.start() {
		item = list_at(items, $item - 1)
		$visits = $visits + 1
		match item.source {
			ReferenceAtom(_) => break
			LiteralCluster(literal) => {
				range = list_at(shaped.store.clusters, literal.cluster).source.utf8_bytes
				if range.length() != 1 {
					break
				}
				id = list_at(shaped.requests, literal.run).source.index()
				unicode = list_at(sources, id).unicode
				# A final non-space answers without constructing a byte view.
				if range.start() + 1 == unicode.count_utf8_bytes() and !unicode.ends_with(" ") {
					break
				}
				if id != $source {
					$bytes = unicode.to_utf8()
					$source = id
				}
				if $bytes.get(range.start()) != Ok(32) {
					break
				}
				width = positive(item.advance)
				$advance = if (width > $advance) 0 else $advance - width
				$item = $item - 1
			}
		}
	}
	{ advance: $advance, visits: $visits }
}
