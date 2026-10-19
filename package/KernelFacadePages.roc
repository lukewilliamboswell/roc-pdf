import Color
import Document
import KernelFacadeLines
import KernelFacadeShape
import KernelFacadeSources
import KernelFacadeTables
import KernelLineLayout
import KernelPageLayout
import Layout
import Scene
import Semantics
import KernelShape
import Text
import Theme

KernelFacadePages :: [].{
	Dimension : [Blocks, Rows]
	Error : [
		ArithmeticOverflow,

		## A custom block whose laid-out content (its paragraphs' lines and
		## the spacing between them) is taller than its measured box less
		## twice its inset: the extension under-measured it.
		CustomMeasureShort({ available : U64, content : U64, custom : U64 }),

		## A custom block (with any decoration above it) taller than the
		## largest page flow region.
		CustomOversize({ custom : U64, frame_height : U64, height : U64 }),

		## A decoration wider than the flow region or taller than the
		## largest page flow region.
		DecorationOversize({ decoration : U64, frame_height : U64, frame_width : U64, height : U64, width : U64 }),

		## A figure (with its caption and any decoration above it) that
		## does not fit the flow region at its authored size, or whose
		## drawing cannot be scaled to fit at all.
		FigureOversize({ block : U64, frame_height : U64, frame_width : U64, height : U64, width : U64 }),

		## A `ScaleToFit` figure that fits only below its floor: `scale` is
		## the largest fitting factor in thousandths.
		FigureScaleFloor({ block : U64, floor : U64, scale : U64 }),
		InvalidBlock({ block : U64 }),
		InvalidLine({ block : U64, line : U64 }),
		InvalidRun({ block : U64, run : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		PageBreakPosition({ page_break : U64 }),
		PageLayout(KernelPageLayout.Error),

		## A page-layout rejection of a document with tables: its block
		## indexes name `units`, which are leaf blocks or table rows.
		TableLayout({ error : KernelPageLayout.Error, groups : List(KeepSource), units : List(Unit) }),

		## A table rule wider than the row gap it is drawn in.
		## `gap` is the space the rule must fit: the row gap for header,
		## footer, and body rules, twice the cell padding for a column rule,
		## and the smaller of the padding and half the row gap for a frame.
		TableRuleWidth({ gap : U64, rule : [BodyRule, ColumnRule, FrameRule, HeaderFooterRule], width : U64 }),
	]
	Limits :: { max_blocks : U64, max_rows : U64, page : KernelPageLayout.Limits }.{
		make : { max_blocks : U64, max_rows : U64, page : KernelPageLayout.Limits } -> Limits
		make = |limits| Limits.(limits)
	}

	## One painted row: a body line at `body_offset` from the flow edge, the
	## logical run it belongs to (its explicit-line-break segment when the
	## body has several), and an optional generated label at `offset`.
	Row : {
		kind : [ContentRow, EmptySourceRow({ source : U64, line : U64 })],
		body_line : U64,
		body_offset : Layout.Unit,
		body_runs : KernelFacadeShape.LogicalRun,
		label : [Label({ line : U64, offset : Layout.Unit, runs : KernelFacadeShape.LogicalRun }), NoLabel],
	}

	## A page-layout unit of a document with tables: one leaf block, or one
	## table row (its row group), whose cells stand side by side.
	Unit : [LeafUnit(U64), RowUnit(U64), SourceUnit(U64)]

	## The source of one required page-layout group of a document with
	## tables: the `k`-th authored `keep_together` in preorder, or a table's
	## footer rows (their first and last row groups).
	KeepSource : [AuthoredKeep(U64), FooterRows({ first : U64, last : U64 })]

	## Page-template flow geometry: the first page's and every later page's
	## flow frame, and the first page's lead region receiving the first
	## `leaves` normalized leaf blocks (the lead region's group).
	FlowTemplate : { continuation : KernelPageLayout.Frame, first : KernelPageLayout.Frame, lead : [Lead({ frame : KernelPageLayout.Frame, leaves : U64 }), NoLead] }

	FlowScope : { leaves : Semantics.Range, opening : KernelPageLayout.Frame, continuation : KernelPageLayout.Frame }

	FlowSelection : [NoFlowTemplate, WithFlowTemplate(FlowTemplate), WithScopedFlow({ template : FlowTemplate, scopes : List(FlowScope) })]
	MeasuredBlock : [
		ContentlessCell,
		EmptySourceLine({ source : U64, line : U64 }),
		MeasuredText({ rows : Semantics.Range, size : Layout.Unit, leading : Layout.Unit, owner : Semantics.OccurrenceId, level : U64, body_offset : Layout.Unit, label : [NoLabel, Label({ rows : Semantics.Range, offset : Layout.Unit })] }),
	]
	MeasuredInput : {
		blocks : List(MeasuredBlock),
		group_frames : List({ offset : U64, width : U64 }),
		source_frames : List(KernelFacadeLines.SourceFrame),
		figure_frames : List({ width : U64, padding : U64 }),
		tables : List(KernelFacadeTables.TableGeometry),
		cells : List(KernelFacadeTables.CellGeometry),
	}
	MeasuredGridRow : [NoTextRow({ source : U64, line : U64 }), BodyRow({ block : U64, row : U64, offset : Layout.Unit, label : [NoLabel, Label({ row : U64, offset : Layout.Unit })] }), TableGrid]
	MeasuredView : {
		choice : KernelPageLayout.Choice,

		## Declared continuation-frame offset when no scoped page arena exists.
		continuation_top : Layout.Unit,
		blocks : List(KernelPageLayout.Block),
		units : List(Unit),
		unit_of_block : List(U64),
		grid_rows : List(MeasuredGridRow),
		row_info : List(RowInfo),
		table_info : List(TableInfo),
		flow : FlowFacts,
	}
	PositionedRow : { row : U64, block : U64, origin : Layout.Point, page : U64, artifact : Bool }
	MeasuredPaint : { rows : List(PositionedRow), rules : List(Rule), flow : FlowPaints, repeats : List(Repeat), splits : List(RowContinuation), source_fragments : List(SourceFragment), callout_fragments : List(KernelPageLayout.ContainerFragment), work : { blank_rows : U64, repeated_header_paints : U64 } }

	Measured :: MeasuredView.{
		build : Document.NormalizedAuthoring, MeasuredInput, Layout.Size, Theme, FlowSelection, Limits -> Try(Measured, Error)
		build = |authoring, input, page, theme, flow, limits| build_measured(authoring, input, page, theme, flow, limits)
		paint : Measured, Document.NormalizedAuthoring, MeasuredInput, List(U64), Layout.Size, Theme, Limits -> Try(MeasuredPaint, Error)
		paint = |Measured.(plan), authoring, input, advances, page, theme, limits| paint_measured(plan, authoring, input, advances, page, theme, limits)

		view : Measured -> MeasuredView
		view = |Measured.(plan)| plan
	}

	## A filled rectangle owned by a layout decoration artifact: a table
	## rule or link underline painted after its page's text (`Front`), or
	## a table row or cell fill painted before it (`Behind`). On each page
	## the `Behind` rectangles come first.
	Rule : { color : Color.SourceValue, layer : [Behind, Front], page : U64, rect : Layout.Rect }

	## One placed in-flow decoration: its index in the normalized
	## decorations, its page, its drawing's bottom-left corner, and whether
	## it paints behind the page's text. On each page the decorations that
	## paint behind come first.
	DecorationPaint : { behind : Bool, decoration : U64, origin : Layout.Point, page : U64 }

	## A continued table's header rows repainted at the top of `page`:
	## `group` is the table's normalized group and `rows` the header row
	## count, for the preparation report.
	Repeat : { group : U64, page : U64, rows : U64 }

	## A `SplitRows` body row continued on `page`: `group` is its row group.
	RowContinuation : { group : U64, page : U64 }

	## The flow drawings' layout facts: each figure's uniform scale in
	## thousandths (1000 unless `ScaleToFit` reduced it), every placed
	## decoration in document order, and every placed custom block panel.
	FlowPaints : { decorations : List(DecorationPaint), figure_scales : List(U64), panels : List(PanelPaint) }

	## One placed custom block: its index in the normalized customs, its
	## page, and its measured box's bottom-left corner, where its panel's
	## origin lies.
	PanelPaint : { custom : U64, origin : Layout.Point, page : U64 }

	Work : {
		block_planning_visits : U64,
		block_writes : U64,
		label_rows : U64,
		blank_rows : U64,
		page : KernelPageLayout.Work,
		repeated_header_paints : U64,
		row_writes : U64,
	}

	## `placed` is `FromLayout` when every row is one page-layout line and
	## the page layout's own pages and placements apply; a document with
	## tables rebuilds them, one placement per painted cell line, and names
	## its repeated-header rows (ascending row indexes) in `artifact_rows`.
	SourceFragment : { source : U64, page : U64, lines : Semantics.Range, rect : Layout.Rect, part : [Whole, First, Middle, Last] }

	Plan :: {
		callout_fragments : List(KernelPageLayout.ContainerFragment),
		source_fragments : List(SourceFragment),
		artifact_rows : List(U64),
		flow : FlowPaints,
		page : KernelPageLayout.Plan,
		placed : [FromLayout, Rebuilt({ pages : List(KernelPageLayout.Page), placements : List(KernelPageLayout.PlacedLine) })],
		repeats : List(Repeat),
		rows : List(Row),
		rules : List(Rule),
		splits : List(RowContinuation),
		units : List(Unit),
		work : Work,
	}.{
		callout_fragments : Plan -> List(KernelPageLayout.ContainerFragment)
		callout_fragments = |plan| plan.callout_fragments

		source_fragments : Plan -> List(SourceFragment)
		source_fragments = |plan| plan.source_fragments

		build : Document.NormalizedAuthoring, KernelFacadeShape.Plan, KernelFacadeLines.Plan, Layout.Size, Theme, Limits -> Try(Plan, Error)
		build = |authoring, shape, lines, page, theme, limits| build_plan(authoring, shape, lines, page, theme, NoFlowTemplate, limits)

		## Pagination under page templates: per-page flow frames and the
		## first page's lead region. The frames come from the templates'
		## fixed region heights alone, never from painted furniture.
		build_with_template : Document.NormalizedAuthoring, KernelFacadeShape.Plan, KernelFacadeLines.Plan, Layout.Size, Theme, FlowTemplate, Limits -> Try(Plan, Error)
		build_with_template = |authoring, shape, lines, page, theme, template, limits| build_plan(authoring, shape, lines, page, theme, WithFlowTemplate(template), limits)

		build_with_scopes : Document.NormalizedAuthoring, KernelFacadeShape.Plan, KernelFacadeLines.Plan, Layout.Size, Theme, FlowTemplate, List(FlowScope), Limits -> Try(Plan, Error)
		build_with_scopes = |authoring, shape, lines, page, theme, template, scopes, limits| build_plan(authoring, shape, lines, page, theme, WithScopedFlow({ template, scopes }), limits)

		page : Plan -> KernelPageLayout.Plan
		page = |plan| plan.page

		## The preferences the accepted pagination relaxed, with the
		## declaring block and page, for the preparation report.
		relaxations : Plan -> List(KernelPageLayout.Relaxation)
		relaxations = |plan| KernelPageLayout.Plan.relaxations(plan.page)

		rows : Plan -> List(Row)
		rows = |plan| plan.rows

		## The final pages, one per laid-out page, whose placement ranges
		## index `placements`.
		pages : Plan -> List(KernelPageLayout.Page)
		pages = |plan| match plan.placed {
			FromLayout => KernelPageLayout.Plan.pages(plan.page)
			Rebuilt(rebuilt) => rebuilt.pages
		}

		## One placement per row, in row order.
		placements : Plan -> List(KernelPageLayout.PlacedLine)
		placements = |plan| match plan.placed {
			FromLayout => KernelPageLayout.Plan.placements(plan.page)
			Rebuilt(rebuilt) => rebuilt.placements
		}

		## The rows that repaint a continued table's header rows: page
		## artifacts, never new semantic content.
		artifact_rows : Plan -> List(U64)
		artifact_rows = |plan| plan.artifact_rows

		rules : Plan -> List(Rule)
		rules = |plan| plan.rules

		## Figure scales and placed decorations.
		flow : Plan -> FlowPaints
		flow = |plan| plan.flow

		## Each page on which a continued table repaints its header rows.
		repeats : Plan -> List(Repeat)
		repeats = |plan| plan.repeats

		## Each page on which a split body row continues.
		splits : Plan -> List(RowContinuation)
		splits = |plan| plan.splits

		## The page-layout units of a document with tables (empty otherwise,
		## where page-layout block indexes are leaf blocks).
		units : Plan -> List(Unit)
		units = |plan| plan.units

		work : Plan -> Work
		work = |plan| plan.work
	}
}

## Layout policy per block, from the authored flow: headings and titles keep
## with the next block (R1, theme) and are unsplittable with figures;
## `keep_with_next` groups bind their last leaf (`Required`, else R2 unless
## the theme's R1 already applies); a page break sets the next leaf's
## mandatory `break_before`; spacers add to the preceding leaf's spacing;
## `keep_together` groups become required atomic groups. Documents without
## these constructs allocate nothing for them.

is_splittable_callout : Document.NormalizedAuthoring, Document.NormalizedGroupKind -> Bool
is_splittable_callout = |authoring, kind| match kind {
	Callout(index) => list_at(authoring.callouts, index.to_u64()).fragmentation == Lines
	_ => False
}

callout_containers : Document.NormalizedAuthoring, (U64 -> { offset : U64, width : U64 }), List(U64), Theme -> Try(List(KernelPageLayout.Container), KernelFacadePages.Error)
callout_containers = |authoring, group_frame, units, theme| {
	has_outer_paint = theme.table.row_gap > 0 and (table_theme_outer_paint(theme) or authoring.cells.any(|cell| cell.fill != 0))
	if authoring.callouts.is_empty() and !has_outer_paint {
		return Ok([])
	}
	var $containers = []
	var $group = 0
	var $cell = 0
	for group in authoring.groups {
		policy = match group.kind {
			Callout(index) => {
				callout_value = list_at(authoring.callouts, index.to_u64())
				padding = nonnegative_raw(callout_value.padding)?
				frame = group_frame($group)
				ContainerFacts({ padding, offset: frame.offset - padding, width: checked_add(frame.width, checked_mul(padding, 2)?)?, paint: Paint(index.to_u64()), skip_caption: False })
			}
			Table(index) => {
				## Tables and cells are in leaf order. Advance this cursor once
				## across the cell arena, never search all cells for each table.
				var $filled = False
				while $cell < authoring.cells.len() and list_at(authoring.cells, $cell).block < group.block_end {
					$filled = $filled or list_at(authoring.cells, $cell).fill != 0
					$cell = $cell + 1
				}
				in_callout = has_callout_ancestor(authoring, group.parent)
				outer_paint = theme.table.row_gap > 0 and ($filled or table_outer_paint(authoring, $group, list_at(authoring.tables, index.to_u64()), theme))
				if in_callout or outer_paint {
					frame = group_frame($group)

					## Outer fills, column rules and frames occupy the half gaps.
					## Reserve their footprint in every accepted fragment.
					ContainerFacts({ padding: (nonnegative_raw(theme.table.row_gap)? + 1) // 2, offset: frame.offset, width: frame.width, paint: NoPaint, skip_caption: !in_callout and list_at(authoring.tables, index.to_u64()).caption })
				} else NoContainerFacts
			}
			_ => NoContainerFacts
		}
		match policy {
			NoContainerFacts => {}
			ContainerFacts(facts) => {
				first_block = group.first_block + if (facts.skip_caption) 1 else 0
				first = if (units.is_empty()) first_block else list_at(units, first_block)
				last = if (units.is_empty()) group.block_end else list_at(units, group.block_end - 1) + 1
				$containers = $containers.append({ paint: facts.paint, blocks: Semantics.Range.from_start_and_length(first, last - first), padding: Layout.Unit.from_raw(facts.padding.to_i64_wrap()), offset: Layout.Unit.from_raw(facts.offset.to_i64_wrap()), width: Layout.Unit.from_raw(facts.width.to_i64_wrap()) })
			}
		}
		$group = $group + 1
	}
	Ok($containers)
}

## Internal horizontal rules stay inside row gaps. Only these paints reach
## above/below the first/last row, and then only when the section exists.
table_theme_outer_paint : Theme -> Bool
table_theme_outer_paint = |theme| theme.table.header_fill != NoFill or theme.table.body_fills.odd != NoFill or theme.table.body_fills.even != NoFill or theme.table.footer_fill != NoFill or positive_table_rule(theme.table.column_rule) or positive_table_rule(theme.table.frame)

positive_table_rule : Theme.TableRule -> Bool
positive_table_rule = |rule| match rule {
	NoRule => False
	Rule({ width, .. }) => width > 0
}

table_outer_paint : Document.NormalizedAuthoring, U64, Document.NormalizedTable, Theme -> Bool
table_outer_paint = |authoring, group_index, table, theme| {
	if positive_table_rule(theme.table.frame) or (table.header_rows > 0 and theme.table.header_fill != NoFill) or (table.footer_rows > 0 and theme.table.footer_fill != NoFill) or (table.body_rows > 0 and theme.table.body_fills.odd != NoFill) or (table.body_rows > 1 and theme.table.body_fills.even != NoFill) {
		return True
	}
	if !positive_table_rule(theme.table.column_rule) {
		return False
	}
	group = list_at(authoring.groups, group_index)
	var $row = group_index + 1
	while $row < group.group_end {
		row = list_at(authoring.groups, $row)
		if row.block_end - row.first_block > 1 {
			return True
		}
		$row = $row + 1
	}
	False
}

## A cell fill belongs only to its own table. The cursor must not carry it
## forward to the next unpainted table or lose it after a preceding table.
expect {
	make = |filled| Document.table({ caption: NoCaption, columns: [{ width: Share(1), align: Start }], header_rows: [], footer_rows: [], body_rows: [Document.row([if (filled) Document.cell([Document.plain_text("Cell")]).shaded(Theme.black) else Document.cell([Document.plain_text("Cell")])])], row_split: KeepRows })
	authoring = Document.normalize(Document.from_blocks({ title: "Paint", language: "en", contents: [make(False), make(True), make(False)] }))
	match callout_containers(authoring, |_| { offset: 0, width: 100000 }, [], Theme.{}) {
		Ok(spans) => spans.len() == 1 and list_at(spans, 0).blocks.start() == 1 and list_at(spans, 0).blocks.length() == 1 and list_at(spans, 0).paint == NoPaint and list_at(spans, 0).padding == 2
		Err(_) => False
	}
}

## Theme declarations that paint no outer box add no layout span: absent
## sections, one even-only body stripe, zero-width rules, and a column rule
## where every row consists of a single spanning cell.
expect {
	authoring = Document.normalize(Document.from_blocks({ title: "Paint", language: "en", contents: [Document.table({ caption: NoCaption, columns: [{ width: Share(1), align: Start }, { width: Share(1), align: Start }], header_rows: [], footer_rows: [], body_rows: [Document.row([Document.cell([Document.plain_text("Spanning")]).spanning(2)])], row_split: KeepRows })] }))
	theme : Theme
	theme = { table: { header_fill: Fill(Theme.black), footer_fill: Fill(Theme.black), body_fills: { even: Fill(Theme.black) }, column_rule: Rule({ color: Theme.black, width: 0.5 }), frame: Rule({ color: Theme.black, width: 0 }), body_rule: Rule({ color: Theme.black, width: 0.5 }) } }
	callout_containers(authoring, |_| { offset: 0, width: 100000 }, [], theme) == Ok([])
}

has_callout_ancestor : Document.NormalizedAuthoring, U64 -> Bool
has_callout_ancestor = |authoring, parent| {
	var $code = parent
	while $code != 0 {
		group = list_at(authoring.groups, $code - 1)
		match group.kind {
			Callout(_) => return True
			_ => {}
		}
		$code = group.parent
	}
	False
}

enclosing_callout_padding : Document.NormalizedAuthoring, U64 -> U64
enclosing_callout_padding = |authoring, parent| {
	var $padding = 0
	var $code = parent
	while $code != 0 {
		group = list_at(authoring.groups, $code - 1)
		match group.kind {
			Callout(index) => {
				$padding = $padding + list_at(authoring.callouts, index.to_u64()).padding.raw().to_u64_wrap()
			}
			_ => {}
		}
		$code = group.parent
	}
	$padding
}

## Merge independently ordered, page-keyed paint buffers without sorting.
merge_callout_rules : List(KernelFacadePages.Rule), List(KernelFacadePages.Rule) -> List(KernelFacadePages.Rule)
merge_callout_rules = |callouts, rules| {
	if callouts.is_empty() {
		return rules
	}
	var $out = List.with_capacity(callouts.len() + rules.len())
	var $callout = 0
	var $rule = 0
	while $callout < callouts.len() or $rule < rules.len() {
		if $callout < callouts.len() and ($rule >= rules.len() or list_at(callouts, $callout).page <= list_at(rules, $rule).page) {
			$out = $out.append(list_at(callouts, $callout))
			$callout = $callout + 1
		} else {
			$out = $out.append(list_at(rules, $rule))
			$rule = $rule + 1
		}
	}
	$out
}

callout_rules : Document.NormalizedAuthoring, List(KernelPageLayout.ContainerFragment) -> List(KernelFacadePages.Rule)
callout_rules = |authoring, fragments| {
	var $rules = []
	for fragment in fragments {
		panel = list_at(authoring.callouts, fragment.container).panel
		match panel.fill {
			NoFill => {}
			Fill(color) => {
				$rules = $rules.append({ color, page: fragment.page, layer: Behind, rect: fragment.rect })
			}
		}
		match panel.border {
			NoBorder => {}
			Border({ color, width }) => {
				x = fragment.rect.origin.x.raw()
				y = fragment.rect.origin.y.raw()
				w = fragment.rect.size.width.raw()
				h = fragment.rect.size.height.raw()
				t = width.raw()
				rect = |left, bottom, wide, high| { origin: { x: Layout.Unit.from_raw(left), y: Layout.Unit.from_raw(bottom) }, size: { width: Layout.Unit.from_raw(wide), height: Layout.Unit.from_raw(high) } }
				for side in [rect(x, y, w, t), rect(x, y + h - t, w, t), rect(x, y, t, h), rect(x + w - t, y, t, h)] {
					$rules = $rules.append({ color, page: fragment.page, layer: Behind, rect: side })
				}
			}
		}
	}
	$rules
}

build_plan : Document.NormalizedAuthoring, KernelFacadeShape.Plan, KernelFacadeLines.Plan, Layout.Size, Theme, FlowSelection, KernelFacadePages.Limits -> Try(KernelFacadePages.Plan, KernelFacadePages.Error)
build_plan = |authoring, shape, line_plan, page_size, theme, flow, limits| {
	match KernelFacadeLines.Plan.geometry(line_plan) {
		WithTables(tables) => return build_table_plan(authoring, shape, line_plan, page_size, theme, flow, limits, tables)
		NoTables => {}
	}
	block_lines = KernelFacadeLines.Plan.blocks(line_plan)
	block_runs = KernelFacadeShape.Plan.block_runs(shape)
	styles = KernelFacadeShape.Plan.styles(shape)
	shape_batch = KernelFacadeShape.Plan.shape(shape)
	line_batch = KernelFacadeLines.Plan.line(line_plan)
	lines = KernelLineLayout.BatchPlan.lines(line_batch)
	if authoring.blocks.len() == 0 or authoring.blocks.len() != block_lines.len() or block_lines.len() != block_runs.len() or styles.len() != shape_batch.store.runs.len() {
		return Err(InvalidBlock({ block: 0 }))
	}
	check_limit(authoring.blocks.len(), limits.max_blocks, Blocks)?
	check_page_breaks(authoring.page_breaks, authoring.blocks.len(), lead_leaves(flow))?
	author_keeps = authored_keeps(authoring.groups, authoring.blocks.len())
	flow_facts = plan_flow(authoring, block_lines, concrete_row_count, figure_widths(authoring, line_plan), page_size, theme, flow)?
	var $row_count = 0
	var $block_index = 0
	while $block_index < block_lines.len() {
		match list_at(block_lines, $block_index) {
			TextBlock({ body, body_offset: _, label }) => {
				body_end = range_end(body.lines)?
				if body.lines.length() == 0 or body_end > lines.len() {
					return Err(InvalidBlock({ block: $block_index }))
				}
				match label {
					NoLabel => {}
					Label(label_lines) => if label_lines.lines.length() != 1 or range_end(label_lines.lines)? > lines.len() {
						return Err(InvalidBlock({ block: $block_index }))
					}
				}
				$row_count = checked_add($row_count, body.lines.length())?
				check_limit($row_count, limits.max_rows, Rows)?
			}

			## Contentless cells exist only in tables, which take
			## `build_table_plan`.
			ContentlessCell | EmptySourceLine(_) => return Err(InvalidBlock({ block: $block_index }))
		}
		$block_index = $block_index + 1
	}
	var $visual_lines = List.with_capacity($row_count)
	var $rows = List.with_capacity($row_count)
	var $page_blocks = List.with_capacity(authoring.blocks.len())
	var $label_rows = 0
	var $break_cursor = 0
	var $spacer_cursor = 0
	$block_index = 0
	while $block_index < block_lines.len() {
		author_block = list_at(authoring.blocks, $block_index)
		line_block = list_at(block_lines, $block_index)
		run_block = list_at(block_runs, $block_index)
		match (line_block, run_block) {
			(TextBlock({ body: body_lines, body_offset, label: label_lines }), TextBlock({ body: body_run, label: label_run, level })) => {
				body_index = logical_run_first(body_run, $block_index, shape_batch.store.runs.len())?
				line_size = assert_logical_identity(shape_batch.store.runs, styles, body_run, $block_index)?
				body_record = list_at(shape_batch.store.runs, body_index)
				body_style = list_at(styles, body_index)
				segmented = list_at(styles, body_index).segment != list_at(styles, body_index + body_run.physical.length() - 1).segment
				visual_start = $visual_lines.len()
				var $segment_start = body_index
				var $segment_length = if (segmented) segment_length(styles, body_index, body_index + body_run.physical.length()) else body_run.physical.length()
				var $local = 0
				while $local < body_lines.lines.length() {
					body_line_index = body_lines.lines.start() + $local
					label = if $local == 0 {
						match (label_lines, label_run) {
							(NoLabel, NoLabel) => NoLabel
							(Label(label_range), Label(label_id)) => {
								_label_index = logical_run_first(label_id, $block_index, shape_batch.store.runs.len())?
								_label_size = assert_logical_identity(shape_batch.store.runs, styles, label_id, $block_index)?
								$label_rows = checked_add($label_rows, 1)?
								Label({ line: label_range.lines.start(), offset: label_range.offset, runs: label_id })
							}
							_ => return Err(InvalidBlock({ block: $block_index }))
						}
					} else {
						NoLabel
					}
					if body_line_index >= lines.len() {
						return Err(InvalidLine({ block: $block_index, line: body_line_index }))
					}
					line = list_at(lines, body_line_index)

					# A line belongs to the explicit-line-break segment whose
					# physical runs hold its first cluster.
					if segmented {
						while $segment_start + $segment_length < body_index + body_run.physical.length() and line.clusters.start() >= segment_cluster_end(shape_batch.store.runs, $segment_start, $segment_length)? {
							$segment_start = $segment_start + $segment_length
							$segment_length = segment_length(styles, $segment_start, body_index + body_run.physical.length())
						}
					}
					runs = if (segmented) { physical: Semantics.Range.from_start_and_length($segment_start, $segment_length) } else body_run
					$visual_lines = $visual_lines.append(line)
					$rows = $rows.append({ kind: ContentRow, body_line: body_line_index, body_offset, body_runs: runs, label })
					$local = $local + 1
				}
				minimum = U64.min(2, body_lines.lines.length())
				theme_keep = keeps_with_next(author_block.kind) and $block_index + 1 < block_lines.len()
				authored = if (author_keeps.is_empty()) NoKeep else list_at(author_keeps, $block_index)
				keep_with_next = match authored {
					Required => Required
					_ => if (theme_keep) Preferred(HeadingKeep) else authored
				}
				spacing = if (continues_list(authoring, block_runs, $block_index, level)) 0 else nonnegative_raw(theme.paragraph_spacing)?
				spaced = spacer_total(authoring.spacers, $spacer_cursor, $block_index + 1)
				$spacer_cursor = spaced.cursor
				break_before = $break_cursor < authoring.page_breaks.len() and list_at(authoring.page_breaks, $break_cursor).block == $block_index
				if break_before {
					$break_cursor = $break_cursor + 1
				}
				$page_blocks = $page_blocks.append(
					flow_block(
						authoring,
						flow_facts,
						$block_index,
						{
							baseline_offset: line_size,
							decoration: Layout.Unit.from_raw(0),
							lead: Layout.Unit.from_raw(0),
							leading: body_style.leading,
							lines: Semantics.Range.from_start_and_length(visual_start, body_lines.lines.length()),
							owner: Content(semantic_occurrence(body_record, $block_index, body_index)?),
							policy: {
								break_before,
								keep_together: keeps_together(author_block.kind),
								keep_with_next,
								minimum_first_lines: minimum,
								minimum_last_lines: minimum,
							},
							space_after: Layout.Unit.from_raw(checked_add(spacing, spaced.amount)?.to_i64_wrap()),
							trailing: Layout.Unit.from_raw(0),
						},
					),
				)
			}
			_ => return Err(InvalidBlock({ block: $block_index }))
		}
		$block_index = $block_index + 1
	}
	if $visual_lines.len() != $row_count or $rows.len() != $row_count {
		return Err(InvalidBlock({ block: block_lines.len() }))
	}
	$page_blocks = apply_customs(authoring, $page_blocks, [])?
	keep_groups = together_groups(authoring)
	constraints = { margins: theme.page_margin, page: page_size }
	containers = callout_containers(authoring, |group| KernelFacadeLines.Plan.group_frame(line_plan, group), [], theme)?
	page = if !containers.is_empty() {
		selection = match flow {
			NoFlowTemplate => NoTemplate
			WithFlowTemplate(template) | WithScopedFlow({ template, scopes: _ }) => WithTemplate(layout_template(template, lead_leaves(flow)))
		}
		KernelPageLayout.Plan.build_with_contexts(scope_policies(lead_policies($page_blocks, lead_leaves(flow)), flow, []), flow_groups(keep_groups, lead_leaves(flow)), $visual_lines, constraints, selection, layout_scopes(flow, []), containers, limits.page) ? PageLayout
	} else match flow {
		NoFlowTemplate => (
			if keep_groups.is_empty() {
				KernelPageLayout.Plan.build($page_blocks, $visual_lines, constraints, limits.page)
			} else {
				KernelPageLayout.Plan.build_with_groups($page_blocks, keep_groups, $visual_lines, constraints, limits.page)
			}
		) ? PageLayout
		WithFlowTemplate(template) | WithScopedFlow({ template, scopes: _ }) => {
			leaves = lead_leaves(flow)
			KernelPageLayout.Plan.build_with_scopes(scope_policies(lead_policies($page_blocks, leaves), flow, []), flow_groups(keep_groups, leaves), $visual_lines, constraints, layout_template(template, leaves), layout_scopes(flow, []), limits.page) ? PageLayout
		}
	}
	decorations = decoration_paints(authoring, KernelPageLayout.Plan.bands(page), [], nonnegative_raw(theme.page_margin.left)?)?
	panels = panel_paints(authoring, KernelPageLayout.Plan.fragments(page), block_runs, shape_batch.store.runs)?
	Ok(
		KernelFacadePages.Plan.{
			callout_fragments: KernelPageLayout.Plan.container_fragments(page),
			source_fragments: [],
			artifact_rows: [],
			flow: { decorations, figure_scales: flow_facts.scales, panels },
			page,
			placed: FromLayout,
			repeats: [],
			rows: $rows,
			rules: callout_rules(authoring, KernelPageLayout.Plan.container_fragments(page)),
			splits: [],
			units: [],
			work: {
				block_planning_visits: block_lines.len(),
				block_writes: $page_blocks.len(),
				label_rows: $label_rows,
				blank_rows: 0,
				page: KernelPageLayout.Plan.work(page),
				repeated_header_paints: 0,
				row_writes: $rows.len(),
			},
		},
	)
}

## One page-layout unit's table facts: a row unit's cell ordinals, its
## table, grid line count, and whether a rule follows its last line (the
## last header row) or precedes its first (the first footer row).
##
## `fill` is the row's theme fill and `body_rule` whether the theme's body
## rule separates it from the body row before it.
RowInfo : { body_rule : Bool, cells : Semantics.Range, fill : Theme.TableFill, grid : U64, rule_above : Bool, rule_below : Bool, table : U64 }

## One table's repeat facts: its header row units, the height they and the
## gap after them reserve on a continuation page, and its width.
TableInfo : { offset : U64, header_height : U64, header_units : Semantics.Range, width : U64 }

TableRuleStyle : [NoTableRule, TableRule({ color : Color.SourceValue, width : U64 })]

## Pagination of a document with tables. Every leaf block outside a table
## is one page-layout unit, exactly as without tables. A table becomes its
## caption unit (unsplittable, requiring its next unit) and one unit per
## row: `grid` synthetic lines of the cell leading, where `grid` is the most
## lines any of its cells holds, so a line boundary of the grid is a line
## boundary of every cell. Header rows are unsplittable and require their
## next unit, so the table start (caption, header rows, and the first body
## row's first placement unit) is placed together. Body rows are
## unsplittable under `KeepRows`; under `SplitRows` they break at a grid
## line with the orphan and widow minimums applied to the row's grid.
## Footer rows are unsplittable and form one required group, and the last
## body row prefers to keep with them (R3). Every body and footer row
## reserves the table's header height as its `lead`, so a page that starts
## inside a table has room for the repainted header rows. After pagination,
## the page placements are rebuilt: each cell line gets its own placement at
## its grid line's baseline and its cell's aligned offset, and a page that
## starts inside a table first repaints its header rows as artifact rows.
build_table_plan : Document.NormalizedAuthoring, KernelFacadeShape.Plan, KernelFacadeLines.Plan, Layout.Size, Theme, FlowSelection, KernelFacadePages.Limits, KernelFacadeTables.Plan -> Try(KernelFacadePages.Plan, KernelFacadePages.Error)
build_table_plan = |authoring, shape, line_plan, page_size, theme, flow, limits, tables| {
	block_lines = KernelFacadeLines.Plan.blocks(line_plan)
	block_runs = KernelFacadeShape.Plan.block_runs(shape)
	styles = KernelFacadeShape.Plan.styles(shape)
	shape_requests = KernelFacadeShape.Plan.requests(shape)
	shape_batch = KernelFacadeShape.Plan.shape(shape)
	lines = KernelLineLayout.BatchPlan.lines(KernelFacadeLines.Plan.line(line_plan))
	blocks = authoring.blocks
	if blocks.len() == 0 or blocks.len() != block_lines.len() or block_lines.len() != block_runs.len() or styles.len() != shape_batch.store.runs.len() {
		return Err(InvalidBlock({ block: 0 }))
	}
	check_limit(blocks.len(), limits.max_blocks, Blocks)?
	check_page_breaks(authoring.page_breaks, blocks.len(), lead_leaves(flow))?
	author_keeps = authored_keeps(authoring.groups, blocks.len())
	table_style = theme.table
	gap = nonnegative_raw(table_style.row_gap)?
	rule = match table_style.rule {
		NoRule => NoTableRule
		Rule({ color, width }) => {
			thickness = nonnegative_raw(width)?
			if thickness > gap {
				return Err(TableRuleWidth({ gap, rule: HeaderFooterRule, width: thickness }))
			}
			if (thickness == 0) NoTableRule else TableRule({ color, width: thickness })
		}
	}
	body_rule = match table_style.body_rule {
		NoRule => NoTableRule
		Rule({ color, width }) => {
			thickness = nonnegative_raw(width)?
			if thickness > gap {
				return Err(TableRuleWidth({ gap, rule: BodyRule, width: thickness }))
			}
			if (thickness == 0) NoTableRule else TableRule({ color, width: thickness })
		}
	}
	padding = nonnegative_raw(table_style.cell_padding)?
	column_rule = match table_style.column_rule {
		NoRule => NoTableRule
		Rule({ color, width }) => {
			thickness = nonnegative_raw(width)?
			if thickness > 2 * padding {
				return Err(TableRuleWidth({ gap: 2 * padding, rule: ColumnRule, width: thickness }))
			}
			if (thickness == 0) NoTableRule else TableRule({ color, width: thickness })
		}
	}
	frame = match table_style.frame {
		NoRule => NoTableRule
		Rule({ color, width }) => {
			thickness = nonnegative_raw(width)?
			room = U64.min(padding, gap / 2)
			if thickness > room {
				return Err(TableRuleWidth({ gap: room, rule: FrameRule, width: thickness }))
			}
			if (thickness == 0) NoTableRule else TableRule({ color, width: thickness })
		}
	}
	paragraph_spacing = nonnegative_raw(theme.paragraph_spacing)?
	flow_facts = plan_flow(authoring, block_lines, concrete_row_count, figure_widths(authoring, line_plan), page_size, theme, flow)?
	cell_geometry = KernelFacadeTables.Plan.cells(tables)
	table_geometry = KernelFacadeTables.Plan.tables(tables)
	table_sources = KernelFacadeTables.Plan.sources(tables)
	synthetic = { advance: Layout.Unit.from_raw(0), clusters: Semantics.Range.from_start_and_length(0, 0), source: { scalars: Semantics.Range.from_start_and_length(0, 0), utf8_bytes: Semantics.Range.from_start_and_length(0, 0) } }
	dummy_row = { kind: ContentRow, body_line: 0, body_offset: Layout.Unit.from_raw(0), body_runs: { physical: Semantics.Range.from_start_and_length(0, 0) }, label: NoLabel }
	no_row = { body_rule: False, cells: Semantics.Range.from_start_and_length(0, 0), fill: NoFill, grid: 0, rule_above: False, rule_below: False, table: 0 }
	var $visual_lines = []
	var $line_rows = []
	var $cell_rows = []
	var $cell_starts = List.with_capacity(cell_geometry.len())
	var $page_blocks = []
	var $units = []
	var $row_info = []
	var $table_info = List.with_capacity(table_geometry.len())
	var $unit_of_block = List.repeat(0, blocks.len())
	var $footer_groups = []
	var $footer_sources = []
	var $source_cursor = 0
	var $label_rows = 0
	var $break_cursor = 0
	var $spacer_cursor = 0
	var $table_cursor = 0
	var $cell_cursor = 0
	var $block_index = 0
	while $block_index < blocks.len() {
		table_start = if ($table_cursor < table_geometry.len()) list_at(authoring.groups, list_at(table_geometry, $table_cursor).group).first_block == $block_index else False
		source_start = if ($source_cursor < authoring.sources.len()) list_at(authoring.groups, list_at(authoring.sources, $source_cursor).group).first_block == $block_index else False
		if source_start {
			source = list_at(authoring.sources, $source_cursor)
			group = list_at(authoring.groups, source.group)
			source_frame = list_at(KernelFacadeLines.Plan.source_frames(line_plan), $source_cursor)
			visual_start = $visual_lines.len()
			var $leaf = group.first_block
			while $leaf < group.block_end {
				$unit_of_block = list_set($unit_of_block, $leaf, $units.len())
				match list_at(block_lines, $leaf) {
					EmptySourceLine({ source: source_id, line: logical }) => {
						if source_id != $source_cursor {
							return Err(InvalidBlock({ block: $leaf }))
						}
						check_limit(checked_add($visual_lines.len(), 1)?, limits.max_rows, Rows)?
						range = list_at(authoring.source_lines, source.lines.start() + logical)
						$visual_lines = $visual_lines.append({ advance: Layout.Unit.from_raw(0), clusters: Semantics.Range.from_start_and_length(0, 0), source: range })
						$line_rows = $line_rows.append({ kind: EmptySourceRow({ source: source_id, line: logical }), body_line: 0, body_offset: source_frame.offset, body_runs: { physical: Semantics.Range.from_start_and_length(0, 0) }, label: NoLabel })
					}
					TextBlock({ body, body_offset, label: NoLabel }) => {
						check_limit(checked_add($visual_lines.len(), body.lines.length())?, limits.max_rows, Rows)?
						var $line = 0
						while $line < body.lines.length() {
							index = body.lines.start() + $line
							$visual_lines = $visual_lines.append(list_at(lines, index))
							$line_rows = $line_rows.append({ kind: ContentRow, body_line: index, body_offset, body_runs: body.runs, label: NoLabel })
							$line = $line + 1
						}
					}
					_ => return Err(InvalidBlock({ block: $leaf }))
				}
				$leaf = $leaf + 1
			}
			spaced = spacer_total(authoring.spacers, $spacer_cursor, group.block_end)
			$spacer_cursor = spaced.cursor
			break_before = $break_cursor < authoring.page_breaks.len() and list_at(authoring.page_breaks, $break_cursor).block == $block_index
			if break_before {
				$break_cursor = $break_cursor + 1
			}
			authored = if (author_keeps.is_empty()) NoKeep else list_at(author_keeps, group.block_end - 1)
			$page_blocks = $page_blocks.append({
				baseline_offset: source.size,
				decoration: leaf_decoration(flow_facts, group.first_block),
				lead: Layout.Unit.from_raw(0),
				leading: source.leading,
				lines: Semantics.Range.from_start_and_length(visual_start, $visual_lines.len() - visual_start),
				owner: SourceBlock({ source: $source_cursor, padding: source.padding }),
				policy: { break_before, keep_together: source.fragmentation == Unsplittable, keep_with_next: authored, minimum_first_lines: 1, minimum_last_lines: 1 },
				space_after: Layout.Unit.from_raw(checked_add(paragraph_spacing, spaced.amount)?.to_i64_wrap()),
				trailing: Layout.Unit.from_raw(0),
			})
			$units = $units.append(SourceUnit($source_cursor))
			$row_info = $row_info.append(no_row)
			$block_index = group.block_end
			$source_cursor = $source_cursor + 1
		} else if table_start {
			table_group_index = list_at(table_geometry, $table_cursor).group
			group = list_at(authoring.groups, table_group_index)
			table = match group.kind {
				Table(index) => list_at(authoring.tables, index.to_u64())
				_ => return Err(InvalidBlock({ block: $block_index }))
			}
			break_before = $break_cursor < authoring.page_breaks.len() and list_at(authoring.page_breaks, $break_cursor).block == $block_index
			if break_before {
				$break_cursor = $break_cursor + 1
			}
			var $pending_break = break_before
			if table.caption {
				caption_block = group.first_block
				placed = table_leaf_unit(
					{ block_lines, block_runs, lines, shape_batch, styles },
					caption_block,
					{ lines: $visual_lines, rows: $line_rows },
				)?
				$visual_lines = placed.lines
				$line_rows = placed.rows
				$unit_of_block = list_set($unit_of_block, caption_block, $units.len())
				$units = $units.append(LeafUnit(caption_block))
				$row_info = $row_info.append(no_row)
				$page_blocks = $page_blocks.append({
					..placed.block,
					decoration: leaf_decoration(flow_facts, caption_block),
					policy: { break_before: $pending_break, keep_together: True, keep_with_next: Required, minimum_first_lines: placed.minimum, minimum_last_lines: placed.minimum },
					space_after: Layout.Unit.from_raw(gap.to_i64_wrap()),
				})
				$pending_break = False
			}
			header_first = $units.len()
			var $header_height = 0
			var $body_ordinal = 0
			var $row_group = table_group_index + 1
			while $row_group < group.group_end {
				row = list_at(authoring.groups, $row_group)
				section = match row.kind {
					TableRow(value) => value
					_ => return Err(InvalidBlock({ block: row.first_block }))
				}
				first_cell = $cell_cursor
				var $grid = 0
				var $leading = 0
				var $size = 0
				var $occurrence = Semantics.OccurrenceId.from_index(0)
				var $content_seen = False
				var $block = row.first_block
				while $block < row.block_end {
					geometry = list_at(cell_geometry, $cell_cursor)
					match (list_at(block_lines, $block), list_at(block_runs, $block)) {
						(TextBlock({ body: body_lines, body_offset: _, label: _ }), TextBlock({ body: body_run, label: _, level: _ })) => {
							body_index = logical_run_first(body_run, $block, shape_batch.store.runs.len())?
							cell_size = assert_logical_identity(shape_batch.store.runs, styles, body_run, $block)?
							record = list_at(shape_batch.store.runs, body_index)
							style = list_at(styles, body_index)

							# The cells of a row share one leading; the row's
							# baseline offset is its largest cell line size.
							if !$content_seen {
								$leading = positive_raw(style.leading)?
								$size = positive_raw(cell_size)?
								$occurrence = semantic_occurrence(record, $block, body_index)?
								$content_seen = True
							} else if positive_raw(style.leading)? != $leading {
								return Err(InvalidRun({ block: $block, run: body_index }))
							} else {
								$size = U64.max($size, positive_raw(cell_size)?)
							}
							$cell_starts = $cell_starts.append($cell_rows.len())
							$cell_rows = append_cell_rows($cell_rows, { body_lines: body_lines.lines, body_run, geometry, lines, requests: shape_requests, styles, sources: table_sources, store: shape_batch.store }, $block)?
							$grid = U64.max($grid, body_lines.lines.length())
						}

						## A contentless cell paints no line: it keeps its
						## grid position and adds nothing to the row height.
						(ContentlessCell, ContentlessCell) => {
							$cell_starts = $cell_starts.append($cell_rows.len())
						}
						_ => return Err(InvalidBlock({ block: $block }))
					}
					$unit_of_block = list_set($unit_of_block, $block, $units.len())
					$cell_cursor = $cell_cursor + 1
					$block = $block + 1
				}

				# A row of only contentless cells is one line of the body
				# style tall. Its unit's occurrence is never read: the
				# placements of a table row are rebuilt from its cells'
				# lines, and it has none.
				if !$content_seen {
					$grid = 1
					$leading = positive_raw(Theme.body_style(theme).leading)?
					$size = positive_raw(Theme.body_style(theme).size)?
				} else if $grid == 0 {
					return Err(InvalidBlock({ block: row.first_block }))
				}
				visual_start = $visual_lines.len()
				var $synthetic = 0
				while $synthetic < $grid {
					$visual_lines = $visual_lines.append(synthetic)
					$line_rows = $line_rows.append(dummy_row)
					$synthetic = $synthetic + 1
				}
				last_row = $row_group + 1 == group.group_end
				last_body = section == Body and (
					$row_group + 1 == group.group_end or (
						match list_at(authoring.groups, $row_group + 1).kind {
							TableRow(Footer) => True
							_ => False
						}
					)
				)
				first_footer = section == Footer and (
					match list_at(authoring.groups, $row_group - 1).kind {
						TableRow(Footer) => False
						_ => True
					}
				)
				last_header = section == Header and (
					match list_at(authoring.groups, $row_group + 1).kind {
						TableRow(Header) => False
						_ => True
					}
				)
				authored = if (author_keeps.is_empty()) NoKeep else list_at(author_keeps, row.block_end - 1)
				keep_with_next = if section == Header {
					Required
				} else if last_body and table.footer_rows > 0 {
					Preferred(FooterCarry)
				} else if last_row {
					authored
				} else {
					NoKeep
				}
				spacing = if last_row {
					spaced = spacer_total(authoring.spacers, $spacer_cursor, row.block_end)
					$spacer_cursor = spaced.cursor
					checked_add(paragraph_spacing, spaced.amount)?
				} else {
					gap
				}
				lead = if (section != Header and table.header_rows > 0) $header_height else 0
				minimum = U64.min(2, $grid)
				$units = $units.append(RowUnit($row_group))
				fill = match section {
					Header => table_style.header_fill
					Footer => table_style.footer_fill
					Body => if ($body_ordinal % 2 == 0) table_style.body_fills.odd else table_style.body_fills.even
				}
				$row_info = $row_info.append({ body_rule: section == Body and $body_ordinal > 0, cells: Semantics.Range.from_start_and_length(first_cell, $cell_cursor - first_cell), fill, grid: $grid, rule_above: first_footer, rule_below: last_header, table: $table_cursor })
				if section == Body {
					$body_ordinal = $body_ordinal + 1
				}
				$page_blocks = $page_blocks.append({
					baseline_offset: Layout.Unit.from_raw($size.to_i64_wrap()),
					decoration: leaf_decoration(flow_facts, row.first_block),
					lead: Layout.Unit.from_raw(lead.to_i64_wrap()),
					leading: Layout.Unit.from_raw($leading.to_i64_wrap()),
					lines: Semantics.Range.from_start_and_length(visual_start, $grid),
					owner: Content($occurrence),
					policy: {
						break_before: $pending_break,
						keep_together: section != Body or table.row_split == KeepRows,
						keep_with_next,
						minimum_first_lines: minimum,
						minimum_last_lines: minimum,
					},
					space_after: Layout.Unit.from_raw(spacing.to_i64_wrap()),
					trailing: Layout.Unit.from_raw(0),
				})
				$pending_break = False
				if section == Header {
					$header_height = checked_add($header_height, checked_add(checked_mul($grid, $leading)?, gap)?)?
				}
				$row_group = $row_group + 1
			}
			if table.footer_rows > 1 {
				$footer_groups = $footer_groups.append({ blocks: Semantics.Range.from_start_and_length($units.len() - table.footer_rows, table.footer_rows) })
				$footer_sources = $footer_sources.append(FooterRows({ first: group.group_end - table.footer_rows, last: group.group_end - 1 }))
			}
			$table_info = $table_info.append({ offset: list_at(table_geometry, $table_cursor).offset, header_height: $header_height, header_units: Semantics.Range.from_start_and_length(header_first, table.header_rows), width: list_at(table_geometry, $table_cursor).width })
			$table_cursor = $table_cursor + 1
			$block_index = group.block_end
		} else {
			author_block = list_at(blocks, $block_index)
			placed = table_leaf_unit(
				{ block_lines, block_runs, lines, shape_batch, styles },
				$block_index,
				{ lines: $visual_lines, rows: $line_rows },
			)?
			$visual_lines = placed.lines
			$line_rows = placed.rows
			$label_rows = $label_rows + placed.labels
			theme_keep = keeps_with_next(author_block.kind) and $block_index + 1 < blocks.len()
			authored = if (author_keeps.is_empty()) NoKeep else list_at(author_keeps, $block_index)
			keep_with_next = match authored {
				Required => Required
				_ => if (theme_keep) Preferred(HeadingKeep) else authored
			}
			level = match list_at(block_runs, $block_index) {
				TextBlock({ body: _, label: _, level: value }) => value
				ContentlessCell | EmptySourceLine(_) => return Err(InvalidBlock({ block: $block_index }))
			}
			spacing = if (continues_list(authoring, block_runs, $block_index, level)) 0 else paragraph_spacing
			spaced = spacer_total(authoring.spacers, $spacer_cursor, $block_index + 1)
			$spacer_cursor = spaced.cursor
			break_before = $break_cursor < authoring.page_breaks.len() and list_at(authoring.page_breaks, $break_cursor).block == $block_index
			if break_before {
				$break_cursor = $break_cursor + 1
			}
			$unit_of_block = list_set($unit_of_block, $block_index, $units.len())
			$units = $units.append(LeafUnit($block_index))
			$row_info = $row_info.append(no_row)
			$page_blocks = $page_blocks.append(
				flow_block(
					authoring,
					flow_facts,
					$block_index,
					{
						..placed.block,
						policy: {
							break_before,
							keep_together: keeps_together(author_block.kind),
							keep_with_next,
							minimum_first_lines: placed.minimum,
							minimum_last_lines: placed.minimum,
						},
						space_after: Layout.Unit.from_raw(checked_add(spacing, spaced.amount)?.to_i64_wrap()),
					},
				),
			)
			$block_index = $block_index + 1
		}
	}
	check_limit($visual_lines.len(), limits.max_rows, Rows)?

	## Authored keep-together groups over leaf ranges become unit ranges;
	## footer groups join them in preorder.
	$page_blocks = apply_customs(authoring, $page_blocks, $unit_of_block)?
	merged = merge_groups(unit_groups(authoring, $unit_of_block), $footer_groups, $footer_sources)
	constraints = { margins: theme.page_margin, page: page_size }
	containers = callout_containers(authoring, |group| KernelFacadeLines.Plan.group_frame(line_plan, group), $unit_of_block, theme)?
	page = if !containers.is_empty() {
		selection = match flow {
			NoFlowTemplate => NoTemplate
			WithFlowTemplate(template) | WithScopedFlow({ template, scopes: _ }) => {
				leaves = lead_leaves(flow)
				units = if (leaves == 0) 0 else list_at($unit_of_block, leaves - 1) + 1
				WithTemplate(layout_template(template, units))
			}
		}
		KernelPageLayout.Plan.build_with_contexts(scope_policies(lead_policies($page_blocks, mapped_lead_count(flow, $unit_of_block)), flow, $unit_of_block), flow_groups(merged.groups, mapped_lead_count(flow, $unit_of_block)), $visual_lines, constraints, selection, layout_scopes(flow, $unit_of_block), containers, limits.page) ? |error| TableLayout({ error, groups: merged.sources, units: $units })
	} else match flow {
		NoFlowTemplate => (
			if merged.groups.is_empty() {
				KernelPageLayout.Plan.build($page_blocks, $visual_lines, constraints, limits.page)
			} else {
				KernelPageLayout.Plan.build_with_groups($page_blocks, merged.groups, $visual_lines, constraints, limits.page)
			}
		) ? |error| TableLayout({ error, groups: merged.sources, units: $units })
		WithFlowTemplate(template) | WithScopedFlow({ template, scopes: _ }) => {
			leaves = lead_leaves(flow)
			units = if (leaves == 0) 0 else list_at($unit_of_block, leaves - 1) + 1
			KernelPageLayout.Plan.build_with_scopes(scope_policies(lead_policies($page_blocks, units), flow, $unit_of_block), flow_groups(merged.groups, units), $visual_lines, constraints, layout_template(template, units), layout_scopes(flow, $unit_of_block), limits.page) ? |error| TableLayout({ error, groups: merged.sources, units: $units })
		}
	}

	## Rebuild the placements: one per painted cell line and leaf line, with
	## each continued table's header rows repainted first as artifacts.
	margins = theme.page_margin
	frame_top = checked_sub(positive_raw(page_size.height)?, nonnegative_raw(margins.top)?)?

	## A continued table repaints its header rows at the top of a later
	## page's flow region, which a continuation template may move down.
	default_page_top = match flow {
		NoFlowTemplate => frame_top
		WithFlowTemplate(template) | WithScopedFlow({ template, scopes: _ }) => checked_sub(frame_top, nonnegative_raw(template.continuation.top)?)?
	}
	margin_left = nonnegative_raw(margins.left)?
	layout_pages = KernelPageLayout.Plan.pages(page)
	layout_fragments = KernelPageLayout.Plan.fragments(page)
	layout_placements = KernelPageLayout.Plan.placements(page)
	var $source_fragments = []
	var $blank_rows = 0
	var $rows = List.with_capacity($cell_rows.len() + $line_rows.len())
	var $placements = List.with_capacity($cell_rows.len() + $line_rows.len())
	var $pages = List.with_capacity(layout_pages.len())
	var $artifact_rows = []
	var $rules = []
	var $fills = []
	var $repeats = []
	var $splits = []
	var $repeated = 0
	var $unit = 0
	var $placement_cursor = 0
	var $segment = NoSegment
	lead_bands = KernelPageLayout.Plan.lead_bands(page)
	var $lead_cursor = 0
	for layout_page in layout_pages {
		page_index = layout_page.id.index()
		page_frames = KernelPageLayout.Plan.page_frames(page)
		selected_page_top = if (page_frames.is_empty()) default_page_top else checked_sub(frame_top, nonnegative_raw(list_at(page_frames, page_index).top)?)?
		placement_start = $placements.len()
		first_fragment = layout_page.fragments.start()
		fragment_end = first_fragment + layout_page.fragments.length()
		first = list_at(layout_fragments, first_fragment)
		while range_end(list_at($page_blocks, $unit).lines)? <= first.lines.start() {
			$unit = $unit + 1
		}
		lead_unit = list_at($page_blocks, $unit)
		if nonnegative_raw(lead_unit.lead)? > 0 {
			while $lead_cursor < lead_bands.len() and list_at(lead_bands, $lead_cursor).page < page_index {
				$lead_cursor = $lead_cursor + 1
			}
			page_top = if ($lead_cursor < lead_bands.len() and list_at(lead_bands, $lead_cursor).page == page_index) list_at(lead_bands, $lead_cursor).top else selected_page_top
			info = list_at($table_info, list_at($row_info, $unit).table)
			var $used = 0
			var $header = info.header_units.start()
			while $header < info.header_units.start() + info.header_units.length() {
				header_block = list_at($page_blocks, $header)
				header_row = list_at($row_info, $header)
				leading = positive_raw(header_block.leading)?
				baseline_offset = positive_raw(header_block.baseline_offset)?
				var $cell = header_row.cells.start()
				while $cell < header_row.cells.start() + header_row.cells.length() {
					start = list_at($cell_starts, $cell)
					count = cell_line_count($cell_starts, $cell_rows.len(), $cell)
					var $line = 0
					while $line < count {
						baseline = checked_sub(page_top, checked_add($used, checked_add(baseline_offset, checked_mul($line, leading)?)?)?)?
						$artifact_rows = $artifact_rows.append($rows.len())
						$placements = $placements.append({ baseline: { x: Layout.Unit.from_raw(margin_left.to_i64_wrap()), y: Layout.Unit.from_raw(baseline.to_i64_wrap()) }, fragment: Semantics.FragmentId.from_index(first_fragment), line: $rows.len() })
						$rows = $rows.append(list_at($cell_rows, start + $line))
						$line = $line + 1
					}
					$cell = $cell + 1
				}
				row_top = checked_sub(page_top, $used)?
				row_bottom = checked_sub(row_top, checked_mul(header_row.grid, leading)?)?
				$fills = append_fill($fills, header_row.fill, page_index, { bottom: row_bottom, gap, top: row_top, width: info.width, x: margin_left + info.offset })
				$fills = append_cell_fills($fills, authoring, cell_geometry, header_row.cells, { bottom: row_bottom, gap, padding, page: page_index, top: row_top, x: margin_left + info.offset })
				$rules = append_column_rules($rules, column_rule, cell_geometry, header_row.cells, { bottom: row_bottom, gap, padding, page: page_index, top: row_top, x: margin_left + info.offset })
				$segment = extend_segment($segment, header_row.table, row_top, row_bottom, gap)
				$used = checked_add($used, checked_add(checked_mul(header_row.grid, leading)?, gap)?)?
				$header = $header + 1
			}
			$repeated = $repeated + info.header_units.length()
			$repeats = $repeats.append({ group: list_at(table_geometry, list_at($row_info, $unit).table).group, page: page_index, rows: info.header_units.length() })
			$rules = append_rule($rules, rule, page_index, margin_left + info.offset, info.width, checked_sub(page_top, checked_sub($used, gap / 2)?)?)
		}
		var $fragment = first_fragment
		while $fragment < fragment_end {
			fragment = list_at(layout_fragments, $fragment)
			while range_end(list_at($page_blocks, $unit).lines)? <= fragment.lines.start() {
				$unit = $unit + 1
			}
			unit_block = list_at($page_blocks, $unit)
			taken = fragment.lines.length()
			match list_at($units, $unit) {
				LeafUnit(_) => {
					$rules = close_segment($rules, frame, $segment, page_index, margin_left, $table_info)
					$segment = NoSegment
					var $local = 0
					while $local < taken {
						placed = list_at(layout_placements, $placement_cursor + $local)
						$placements = $placements.append({ ..placed, line: $rows.len() })
						$rows = $rows.append(list_at($line_rows, fragment.lines.start() + $local))
						$local = $local + 1
					}
				}
				SourceUnit(source_id) => {
					$rules = close_segment($rules, frame, $segment, page_index, margin_left, $table_info)
					$segment = NoSegment
					source = list_at(authoring.sources, source_id)
					source_frame = list_at(KernelFacadeLines.Plan.source_frames(line_plan), source_id)
					source_padding = nonnegative_raw(source.padding)?
					x = checked_sub(checked_add(margin_left, nonnegative_raw(source_frame.offset)?)?, source_padding)?
					y = checked_sub(nonnegative_raw(fragment.geometry.origin.y)?, source_padding)?
					rect = { origin: { x: Layout.Unit.from_raw(x.to_i64_wrap()), y: Layout.Unit.from_raw(y.to_i64_wrap()) }, size: { width: Layout.Unit.from_raw(checked_add(nonnegative_raw(source_frame.width)?, checked_mul(source_padding, 2)?)?.to_i64_wrap()), height: Layout.Unit.from_raw(checked_add(nonnegative_raw(fragment.geometry.size.height)?, checked_mul(source_padding, 2)?)?.to_i64_wrap()) } }
					is_first = fragment.lines.start() == unit_block.lines.start()
					is_last = range_end(fragment.lines)? == range_end(unit_block.lines)?
					part = if (is_first and is_last) Whole else if (is_first) First else if (is_last) Last else Middle
					$source_fragments = $source_fragments.append({ source: source_id, page: page_index, lines: Semantics.Range.from_start_and_length(fragment.lines.start() - unit_block.lines.start(), taken), rect, part })
					match source.background {
						NoBackground => {}
						Background(color) => {
							$fills = $fills.append({ color, layer: Behind, page: page_index, rect })
						}
					}
					var $local = 0
					while $local < taken {
						placed = list_at(layout_placements, $placement_cursor + $local)
						row = list_at($line_rows, fragment.lines.start() + $local)
						match row.kind {
							ContentRow => {}
							EmptySourceRow(_) => {
								$blank_rows = $blank_rows + 1
							}
						}
						$placements = $placements.append({ ..placed, line: $rows.len() })
						$rows = $rows.append(row)
						$local = $local + 1
					}
				}
				RowUnit(row_group) => {
					info = list_at($row_info, $unit)
					first_grid = fragment.lines.start() - unit_block.lines.start()
					if first_grid > 0 {
						$splits = $splits.append({ group: row_group, page: page_index })
					}
					var $cell = info.cells.start()
					while $cell < info.cells.start() + info.cells.length() {
						start = list_at($cell_starts, $cell)
						count = cell_line_count($cell_starts, $cell_rows.len(), $cell)
						var $grid_line = first_grid
						while $grid_line < first_grid + taken and $grid_line < count {
							placed = list_at(layout_placements, $placement_cursor + $grid_line - first_grid)
							$placements = $placements.append({ ..placed, line: $rows.len() })
							$rows = $rows.append(list_at($cell_rows, start + $grid_line))
							$grid_line = $grid_line + 1
						}
						$cell = $cell + 1
					}
					table_width = list_at($table_info, info.table).width
					table_x = margin_left + list_at($table_info, info.table).offset
					bottom = fragment.geometry.origin.y.raw().to_u64_wrap()
					top = checked_add(bottom, fragment.geometry.size.height.raw().to_u64_wrap())?
					$fills = append_fill($fills, info.fill, page_index, { bottom, gap, top, width: table_width, x: table_x })
					$fills = append_cell_fills($fills, authoring, cell_geometry, info.cells, { bottom, gap, padding, page: page_index, top, x: table_x })
					$rules = append_column_rules($rules, column_rule, cell_geometry, info.cells, { bottom, gap, padding, page: page_index, top, x: table_x })
					$rules = close_other_segment($rules, frame, $segment, info.table, { page: page_index, tables: $table_info, x: margin_left })
					$segment = extend_segment($segment, info.table, top, bottom, gap)
					if info.body_rule and first_grid == 0 and $fragment > first_fragment {
						$rules = append_rule($rules, body_rule, page_index, table_x, table_width, checked_add(top, gap / 2)?)
					}
					if info.rule_below and first_grid + taken == info.grid {
						$rules = append_rule($rules, rule, page_index, table_x, table_width, checked_sub(bottom, gap / 2)?)
					}
					if info.rule_above and first_grid == 0 and $fragment > first_fragment {
						$rules = append_rule($rules, rule, page_index, table_x, table_width, checked_add(top, gap / 2)?)
					}
				}
			}
			$placement_cursor = $placement_cursor + taken
			$fragment = $fragment + 1
		}
		$rules = close_segment($rules, frame, $segment, page_index, margin_left, $table_info)
		$segment = NoSegment
		$pages = $pages.append({ ..layout_page, placements: Semantics.Range.from_start_and_length(placement_start, $placements.len() - placement_start) })
	}
	check_limit($rows.len(), limits.max_rows, Rows)?
	decorations = decoration_paints(authoring, KernelPageLayout.Plan.bands(page), $unit_of_block, margin_left)?
	panels = panel_paints(authoring, KernelPageLayout.Plan.fragments(page), block_runs, shape_batch.store.runs)?
	Ok(
		KernelFacadePages.Plan.{
			callout_fragments: KernelPageLayout.Plan.container_fragments(page),
			source_fragments: $source_fragments,
			artifact_rows: $artifact_rows,
			flow: { decorations, figure_scales: flow_facts.scales, panels },
			page,
			placed: Rebuilt({ pages: $pages, placements: $placements }),
			repeats: $repeats,
			rows: $rows,
			rules: merge_callout_rules(callout_rules(authoring, KernelPageLayout.Plan.container_fragments(page)), behind_first($fills, $rules)),
			splits: $splits,
			units: $units,
			work: {
				block_planning_visits: block_lines.len(),
				block_writes: $page_blocks.len(),
				label_rows: $label_rows,
				blank_rows: $blank_rows,
				page: KernelPageLayout.Plan.work(page),
				repeated_header_paints: $repeated,
				row_writes: $rows.len(),
			},
		},
	)
}

## The painted rows of one leaf block, appended to the visual line and row
## lists exactly as the table-free path builds them, and its page block
## before its policy is set.
table_leaf_unit : { block_lines : List(KernelFacadeLines.BlockLines), block_runs : List(KernelFacadeShape.BlockRuns), lines : List(KernelLineLayout.Line), shape_batch : KernelShape.Batch, styles : List(KernelFacadeShape.RunStyle) }, U64, { lines : List(KernelLineLayout.Line), rows : List(KernelFacadePages.Row) } -> Try({ block : KernelPageLayout.Block, labels : U64, lines : List(KernelLineLayout.Line), minimum : U64, rows : List(KernelFacadePages.Row) }, KernelFacadePages.Error)
table_leaf_unit = |at, block_index, buffers| {
	lines = at.lines
	shape_batch = at.shape_batch
	match (list_at(at.block_lines, block_index), list_at(at.block_runs, block_index)) {
		(TextBlock({ body: body_lines, body_offset, label: label_lines }), TextBlock({ body: body_run, label: label_run, level: _ })) => {
			body_end = range_end(body_lines.lines)?
			if body_lines.lines.length() == 0 or body_end > lines.len() {
				return Err(InvalidBlock({ block: block_index }))
			}
			body_index = logical_run_first(body_run, block_index, shape_batch.store.runs.len())?
			line_size = assert_logical_identity(shape_batch.store.runs, at.styles, body_run, block_index)?
			body_record = list_at(shape_batch.store.runs, body_index)
			body_style = list_at(at.styles, body_index)
			segmented = list_at(at.styles, body_index).segment != list_at(at.styles, body_index + body_run.physical.length() - 1).segment
			visual_start = buffers.lines.len()
			var $visual_lines = buffers.lines
			var $rows = buffers.rows
			var $labels = 0
			var $segment_start = body_index
			var $segment_length = if (segmented) segment_length(at.styles, body_index, body_index + body_run.physical.length()) else body_run.physical.length()
			var $local = 0
			while $local < body_lines.lines.length() {
				body_line_index = body_lines.lines.start() + $local
				label = if $local == 0 {
					match (label_lines, label_run) {
						(NoLabel, NoLabel) => NoLabel
						(Label(label_range), Label(label_id)) => {
							$labels = $labels + 1
							Label({ line: label_range.lines.start(), offset: label_range.offset, runs: label_id })
						}
						_ => return Err(InvalidBlock({ block: block_index }))
					}
				} else {
					NoLabel
				}
				line = list_at(lines, body_line_index)
				if segmented {
					while $segment_start + $segment_length < body_index + body_run.physical.length() and line.clusters.start() >= segment_cluster_end(shape_batch.store.runs, $segment_start, $segment_length)? {
						$segment_start = $segment_start + $segment_length
						$segment_length = segment_length(at.styles, $segment_start, body_index + body_run.physical.length())
					}
				}
				runs = if (segmented) { physical: Semantics.Range.from_start_and_length($segment_start, $segment_length) } else body_run
				$visual_lines = $visual_lines.append(line)
				$rows = $rows.append({ kind: ContentRow, body_line: body_line_index, body_offset, body_runs: runs, label })
				$local = $local + 1
			}
			Ok({
				block: {
					baseline_offset: line_size,
					decoration: Layout.Unit.from_raw(0),
					lead: Layout.Unit.from_raw(0),
					leading: body_style.leading,
					lines: Semantics.Range.from_start_and_length(visual_start, body_lines.lines.length()),
					owner: Content(semantic_occurrence(body_record, block_index, body_index)?),
					policy: { break_before: False, keep_together: False, keep_with_next: NoKeep, minimum_first_lines: 1, minimum_last_lines: 1 },
					space_after: Layout.Unit.from_raw(0),
					trailing: Layout.Unit.from_raw(0),
				},
				labels: $labels,
				lines: $visual_lines,
				minimum: U64.min(2, body_lines.lines.length()),
				rows: $rows,
			})
		}

		## Only a table row places a contentless cell.
		_ => Err(InvalidBlock({ block: block_index }))
	}
}

## One row per line of a cell: its body line, its explicit-line-break
## segment's runs, and its offset from the flow edge, which aligns the
## line's visible advance inside the cell's text box. A line that ends at a
## soft break carries the spaces before it in its advance; end and center
## alignment measure the line without them.
append_cell_rows : List(KernelFacadePages.Row), { body_lines : Semantics.Range, body_run : KernelFacadeShape.LogicalRun, geometry : KernelFacadeTables.CellGeometry, lines : List(KernelLineLayout.Line), requests : List(KernelShape.SimpleRequest), styles : List(KernelFacadeShape.RunStyle), sources : List(KernelFacadeSources.Source), store : Text.Store }, U64 -> Try(List(KernelFacadePages.Row), KernelFacadePages.Error)
append_cell_rows = |rows, at, block| {
	body_run = at.body_run
	body_index = body_run.physical.start()
	body_end = body_index + body_run.physical.length()
	segmented = list_at(at.styles, body_index).segment != list_at(at.styles, body_end - 1).segment
	var $rows = rows
	var $segment_start = body_index
	var $segment_length = if (segmented) segment_length(at.styles, body_index, body_end) else body_run.physical.length()
	var $local = 0
	while $local < at.body_lines.length() {
		line_index = at.body_lines.start() + $local
		if line_index >= at.lines.len() {
			return Err(InvalidLine({ block, line: line_index }))
		}
		line = list_at(at.lines, line_index)
		if segmented {
			while $segment_start + $segment_length < body_end and line.clusters.start() >= segment_cluster_end(at.store.runs, $segment_start, $segment_length)? {
				$segment_start = $segment_start + $segment_length
				$segment_length = segment_length(at.styles, $segment_start, body_end)
			}
		}
		runs = if (segmented) { physical: Semantics.Range.from_start_and_length($segment_start, $segment_length) } else body_run
		offset = match at.geometry.align {
			Start => at.geometry.x
			alignment => {
				source = list_at(at.sources, list_at(at.requests, $segment_start).source.index()).unicode
				advance = visible_advance(at.store, line, source)?
				slack = if (advance < at.geometry.width) at.geometry.width - advance else 0
				if (alignment == End) at.geometry.x + slack else at.geometry.x + slack // 2
			}
		}
		$rows = $rows.append({ kind: ContentRow, body_line: line_index, body_offset: Layout.Unit.from_raw((at.geometry.offset + offset).to_i64_wrap()), body_runs: runs, label: NoLabel })
		$local = $local + 1
	}
	Ok($rows)
}

## A line's advance without the spaces (U+0020) it ends with.
visible_advance : Text.Store, KernelLineLayout.Line, Str -> Try(U64, KernelFacadePages.Error)
visible_advance = |store, line, source| {
	var $advance = nonnegative_raw(line.advance)?
	last = store.clusters.get(line.clusters.start() + line.clusters.length() - 1)

	## Only a line that ends in a space pays for the byte view; a line that
	## ends its source answers from the source itself.
	trailing = match last {
		Ok(cluster) => if cluster.source.utf8_bytes.length() != 1 {
			False
		} else if cluster.source.utf8_bytes.start() + 1 == source.count_utf8_bytes() {
			source.ends_with(" ")
		} else {
			source.to_utf8().get(cluster.source.utf8_bytes.start()) == Ok(32)
		}
		Err(OutOfBounds) => False
	}
	if !trailing {
		return Ok($advance)
	}
	bytes = source.to_utf8()
	var $cluster = line.clusters.start() + line.clusters.length()
	var $trimming = True
	while $trimming and $cluster > line.clusters.start() {
		cluster = list_at(store.clusters, $cluster - 1)
		if cluster.source.utf8_bytes.length() == 1 and bytes.get(cluster.source.utf8_bytes.start()) == Ok(32) {
			var $reference = cluster.glyphs.start()
			while $reference < cluster.glyphs.start() + cluster.glyphs.length() {
				glyph = list_at(store.glyphs, list_at(store.glyph_indices, $reference))
				width = nonnegative_raw(glyph.advance_x)?
				$advance = if (width > $advance) 0 else $advance - width
				$reference = $reference + 1
			}
			$cluster = $cluster - 1
		} else {
			$trimming = False
		}
	}
	Ok($advance)
}

## The number of rows of cell ordinal `cell`: up to the next cell's first
## row, or the end of the cell rows.
cell_line_count : List(U64), U64, U64 -> U64
cell_line_count = |starts, total, cell| {
	start = list_at(starts, cell)
	end = if (cell + 1 < starts.len()) list_at(starts, cell + 1) else total
	end - start
}

## A rule rectangle centered on `center` (a y coordinate) across the table.
append_rule : List(KernelFacadePages.Rule), TableRuleStyle, U64, U64, U64, U64 -> List(KernelFacadePages.Rule)
append_rule = |rules, rule, page, x, width, center| match rule {
	NoTableRule => rules
	TableRule({ color, width: thickness }) => {
		bottom = if (center > thickness / 2) center - thickness / 2 else 0
		rules.append({
			color,
			layer: Front,
			page,
			rect: {
				origin: { x: Layout.Unit.from_raw(x.to_i64_wrap()), y: Layout.Unit.from_raw(bottom.to_i64_wrap()) },
				size: { height: Layout.Unit.from_raw(thickness.to_i64_wrap()), width: Layout.Unit.from_raw(width.to_i64_wrap()) },
			},
		})
	}
}

## The column rules of one row: one centered on each boundary between
## adjacent cells (a cell box is its text box widened by the padding on
## both sides), from half the row gap below the row to half above it.
append_column_rules : List(KernelFacadePages.Rule), TableRuleStyle, List(KernelFacadeTables.CellGeometry), Semantics.Range, { bottom : U64, gap : U64, padding : U64, page : U64, top : U64, x : U64 } -> List(KernelFacadePages.Rule)
append_column_rules = |rules, rule, geometry, range, box| match rule {
	NoTableRule => rules
	TableRule({ color, width: thickness }) => {
		below = box.gap / 2
		bottom = if (box.bottom > below) box.bottom - below else 0
		height = box.top + (box.gap - below) - bottom
		var $rules = rules
		var $cell = range.start() + 1
		while $cell < range.start() + range.length() {
			edge = box.x + list_at(geometry, $cell).x - box.padding
			left = if (edge > thickness / 2) edge - thickness / 2 else 0
			$rules = $rules.append({
				color,
				layer: Front,
				page: box.page,
				rect: {
					origin: { x: Layout.Unit.from_raw(left.to_i64_wrap()), y: Layout.Unit.from_raw(bottom.to_i64_wrap()) },
					size: { height: Layout.Unit.from_raw(height.to_i64_wrap()), width: Layout.Unit.from_raw(thickness.to_i64_wrap()) },
				},
			})
			$cell = $cell + 1
		}
		$rules
	}
}

## One page's contiguous run of a table's rows, for its frame: the table
## and the top and bottom of the rows' outer boxes (half the row gap
## outside the first and last row).
Segment : [NoSegment, Segment({ bottom : U64, table : U64, top : U64 })]

## Close the open segment unless it belongs to `table`.
close_other_segment : List(KernelFacadePages.Rule), TableRuleStyle, Segment, U64, { page : U64, tables : List(TableInfo), x : U64 } -> List(KernelFacadePages.Rule)
close_other_segment = |rules, frame, segment, table, at| match segment {
	Segment(open) => if (open.table == table) rules else close_segment(rules, frame, segment, at.page, at.x, at.tables)
	NoSegment => rules
}

## Add a row (its box from `bottom` to `top`) of table `table` to the open
## segment, or start one.
extend_segment : Segment, U64, U64, U64, U64 -> Segment
extend_segment = |segment, table, top, bottom, gap| {
	below = gap / 2
	outer_bottom = if (bottom > below) bottom - below else 0
	match segment {
		Segment(open) => if (open.table == table) Segment({ ..open, bottom: outer_bottom }) else Segment({ bottom: outer_bottom, table, top: top + (gap - below) })
		NoSegment => Segment({ bottom: outer_bottom, table, top: top + (gap - below) })
	}
}

## Close an open segment: its frame is four rectangles inside the rows'
## outer boxes, across the table's width.
close_segment : List(KernelFacadePages.Rule), TableRuleStyle, Segment, U64, U64, List(TableInfo) -> List(KernelFacadePages.Rule)
close_segment = |rules, frame, segment, page, margin_x, tables| match (frame, segment) {
	(TableRule({ color, width: thickness }), Segment({ bottom, table, top })) => {
		width = list_at(tables, table).width
		x = margin_x + list_at(tables, table).offset
		height = if (top > bottom) top - bottom else 0
		rect = |left, low, w, h| {
			color,
			layer: Front,
			page,
			rect: {
				origin: { x: Layout.Unit.from_raw(left.to_i64_wrap()), y: Layout.Unit.from_raw(low.to_i64_wrap()) },
				size: { height: Layout.Unit.from_raw(h.to_i64_wrap()), width: Layout.Unit.from_raw(w.to_i64_wrap()) },
			},
		}
		rules
			.append(rect(x, top - thickness, width, thickness))
			.append(rect(x, bottom, width, thickness))
			.append(rect(x, bottom, thickness, height))
			.append(rect(x + width - thickness, bottom, thickness, height))
	}
	_ => rules
}

## A row fill: the row's box from `bottom` to `top` across the table,
## extended by half the row gap above and below so filled neighbours meet.
append_fill : List(KernelFacadePages.Rule), Theme.TableFill, U64, { bottom : U64, gap : U64, top : U64, width : U64, x : U64 } -> List(KernelFacadePages.Rule)
append_fill = |fills, fill, page, box| match fill {
	NoFill => fills
	Fill(color) => fills.append(fill_rect(color, page, box))
}

## The fills of a row's own shaded cells, each across its cell box: its
## text box widened by the cell padding on both sides.
append_cell_fills : List(KernelFacadePages.Rule), Document.NormalizedAuthoring, List(KernelFacadeTables.CellGeometry), Semantics.Range, { bottom : U64, gap : U64, padding : U64, page : U64, top : U64, x : U64 } -> List(KernelFacadePages.Rule)
append_cell_fills = |fills, authoring, geometry, range, box| {
	cells = authoring.cells
	var $fills = fills
	var $cell = range.start()
	while $cell < range.start() + range.length() {
		match Document.cell_fill(list_at(cells, $cell)) {
			NoCellFill => {}
			CellFill(color) => {
				cell = list_at(geometry, $cell)
				left = if (cell.x > box.padding) cell.x - box.padding else 0
				$fills = $fills.append(fill_rect(color, box.page, { bottom: box.bottom, gap: box.gap, top: box.top, width: cell.width + 2 * box.padding, x: box.x + left }))
			}
		}
		$cell = $cell + 1
	}
	$fills
}

fill_rect : Color.SourceValue, U64, { bottom : U64, gap : U64, top : U64, width : U64, x : U64 } -> KernelFacadePages.Rule
fill_rect = |color, page, box| {
	below = box.gap / 2
	bottom = if (box.bottom > below) box.bottom - below else 0
	height = box.top + (box.gap - below) - bottom
	{
		color,
		layer: Behind,
		page,
		rect: {
			origin: { x: Layout.Unit.from_raw(box.x.to_i64_wrap()), y: Layout.Unit.from_raw(bottom.to_i64_wrap()) },
			size: { height: Layout.Unit.from_raw(height.to_i64_wrap()), width: Layout.Unit.from_raw(box.width.to_i64_wrap()) },
		},
	}
}

## Page-ordered fills and rules as one list: on each page the fills come
## first, so they paint behind the page's text and the rules after it.
behind_first : List(KernelFacadePages.Rule), List(KernelFacadePages.Rule) -> List(KernelFacadePages.Rule)
behind_first = |fills, rules| {
	if fills.is_empty() {
		return rules
	}
	var $merged = List.with_capacity(fills.len() + rules.len())
	var $left = 0
	var $right = 0
	while $left < fills.len() or $right < rules.len() {
		take_left = $right >= rules.len() or ($left < fills.len() and list_at(fills, $left).page <= list_at(rules, $right).page)
		if take_left {
			$merged = $merged.append(list_at(fills, $left))
			$left = $left + 1
		} else {
			$merged = $merged.append(list_at(rules, $right))
			$right = $right + 1
		}
	}
	$merged
}

## Authored keep-together groups, from leaf ranges to unit ranges.
unit_groups : Document.NormalizedAuthoring, List(U64) -> List(KernelPageLayout.KeepGroup)
unit_groups = |authoring, unit_of_block| {
	groups = authoring.groups
	var $together = []
	for group in groups {
		match group.kind {
			KeepTogether | Custom(_) | Callout(_) => {
				if !is_splittable_callout(authoring, group.kind) {
					first = list_at(unit_of_block, group.first_block)
					last = list_at(unit_of_block, group.block_end - 1)
					$together = $together.append({ blocks: Semantics.Range.from_start_and_length(first, last + 1 - first) })
				}
			}
			_ => {}
		}
	}
	$together
}

## Two preorder group lists merged in preorder (by start, and an enclosing
## group before a group it contains), with each group's source.
merge_groups : List(KernelPageLayout.KeepGroup), List(KernelPageLayout.KeepGroup), List(KernelFacadePages.KeepSource) -> { groups : List(KernelPageLayout.KeepGroup), sources : List(KernelFacadePages.KeepSource) }
merge_groups = |authored, footers, footer_sources| {
	var $merged = List.with_capacity(authored.len() + footers.len())
	var $sources = List.with_capacity(authored.len() + footers.len())
	var $left = 0
	var $right = 0
	while $left < authored.len() or $right < footers.len() {
		take_left = if $left >= authored.len() {
			False
		} else if $right >= footers.len() {
			True
		} else {
			a = list_at(authored, $left).blocks
			b = list_at(footers, $right).blocks
			a.start() < b.start() or (a.start() == b.start() and a.length() >= b.length())
		}
		if take_left {
			$merged = $merged.append(list_at(authored, $left))
			$sources = $sources.append(AuthoredKeep($left))
			$left = $left + 1
		} else {
			$merged = $merged.append(list_at(footers, $right))
			$sources = $sources.append(list_at(footer_sources, $right))
			$right = $right + 1
		}
	}
	{ groups: $merged, sources: $sources }
}

positive_raw : Layout.Unit -> Try(U64, KernelFacadePages.Error)
positive_raw = |value| {
	raw = value.raw()
	if (raw <= 0) Err(InvalidBlock({ block: 0 })) else Ok(raw.to_u64_wrap())
}

checked_sub : U64, U64 -> Try(U64, KernelFacadePages.Error)
checked_sub = |left, right| if (right > left) Err(ArithmeticOverflow) else Ok(left - right)

checked_mul : U64, U64 -> Try(U64, KernelFacadePages.Error)
checked_mul = |left, right| match U64.times_try(left, right) {
	Err(_) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

## An explicit page break separates two flow blocks: one before the first
## leaf, after the last, or directly after another break would ask for an
## empty page, which is rejected rather than collapsed.
## `flow_start` is the first leaf of the body flow: zero, or the leaf count
## of the first page's lead region, which is one unit and takes no break.
check_page_breaks : List(Document.NormalizedPageBreak), U64, U64 -> Try({}, KernelFacadePages.Error)
check_page_breaks = |page_breaks, block_count, flow_start| {
	var $index = 0
	while $index < page_breaks.len() {
		block = list_at(page_breaks, $index).block
		repeated = $index > 0 and list_at(page_breaks, $index - 1).block == block
		if block <= flow_start or block >= block_count or repeated {
			return Err(PageBreakPosition({ page_break: $index }))
		}
		$index = $index + 1
	}
	Ok({})
}

## The authored keep-with-next of each leaf: a `keep_with_next` group binds
## its last leaf; `Required` outranks `Preferred` when groups share it. Empty
## (and unallocated) when the document has no such group.
authored_keeps : List(Document.NormalizedGroup), U64 -> List(KernelPageLayout.Keep)
authored_keeps = |groups, block_count| {
	var $keeps = []
	for group in groups {
		match group.kind {
			KeepWithNext(keep) => {
				if $keeps.is_empty() {
					$keeps = List.repeat(NoKeep, block_count)
				}
				last = group.block_end - 1
				current = list_at($keeps, last)
				updated = match (keep, current) {
					(Required, _) => Required
					(Preferred, Required) => Required
					(Preferred, _) => Preferred(AuthorKeep)
				}
				$keeps = list_set($keeps, last, updated)
			}
			_ => {}
		}
	}
	$keeps
}

## Required keep-together groups in preorder, for page layout. A custom
## block is one: it is unsplittable.
together_groups : Document.NormalizedAuthoring -> List(KernelPageLayout.KeepGroup)
together_groups = |authoring| {
	groups = authoring.groups
	var $together = []
	for group in groups {
		match group.kind {
			KeepTogether | Custom(_) | Callout(_) => {
				if !is_splittable_callout(authoring, group.kind) {
					$together = $together.append({ blocks: Semantics.Range.from_start_and_length(group.first_block, group.block_end - group.first_block) })
				}
			}
			_ => {}
		}
	}
	$together
}

## The authored spacing after leaf `next - 1`: every spacer recorded before
## leaf `next`, from a forward cursor over the block-ordered spacers.
## Spacers before the first leaf fall at the top of the first page and are
## suppressed.
spacer_total : List(Document.NormalizedSpacer), U64, U64 -> { amount : U64, cursor : U64 }
spacer_total = |spacers, cursor, next| {
	var $cursor = cursor
	var $amount = 0
	while $cursor < spacers.len() and list_at(spacers, $cursor).block <= next {
		spacer = list_at(spacers, $cursor)
		raw = spacer.amount.raw()
		if spacer.block == next and raw > 0 {
			$amount = $amount + raw.to_u64_wrap()
		}
		$cursor = $cursor + 1
	}
	{ amount: $amount, cursor: $cursor }
}

## The number of physical runs from `start` (before `end`) sharing its
## explicit segment occurrence, independently of interned source identity.
segment_length : List(KernelFacadeShape.RunStyle), U64, U64 -> U64
segment_length = |requests, start, end| {
	segment = list_at(requests, start).segment
	var $index = start + 1
	while $index < end and list_at(requests, $index).segment == segment {
		$index = $index + 1
	}
	$index - start
}

segment_cluster_end : List(Text.Run), U64, U64 -> Try(U64, KernelFacadePages.Error)
segment_cluster_end = |runs, start, length| range_end(list_at(runs, start + length - 1).clusters)

nonnegative_raw : Layout.Unit -> Try(U64, KernelFacadePages.Error)
nonnegative_raw = |value| {
	raw = value.raw()
	if (raw < 0) Err(InvalidBlock({ block: 0 })) else Ok(raw.to_u64_wrap())
}

## A logical run's physical range must be non-empty and inside the shaped
## store; pagination consumes only its first run's identity facts after the
## whole range is proven identical.
logical_run_first : KernelFacadeShape.LogicalRun, U64, U64 -> Try(U64, KernelFacadePages.Error)
logical_run_first = |logical, block, run_count| {
	physical = logical.physical
	start = physical.start()
	length = physical.length()
	if length == 0 or start >= run_count or length > run_count - start {
		Err(InvalidRun({ block, run: start }))
	} else {
		Ok(start)
	}
}

## Every physical run of one logical run must carry the identical leading:
## pagination treats the logical run as one row source regardless of its
## face or occurrence split. Sizes may differ, since an inline role may
## scale its text below the paragraph size (the theme's `inline.<role>.scale`); the
## logical run's line size, its baseline offset, is its largest run size.
## Fill colors may differ between the occurrences of a rich paragraph; they
## are paint facts, not row geometry.
assert_logical_identity : List(Text.Run), List(KernelFacadeShape.RunStyle), KernelFacadeShape.LogicalRun, U64 -> Try(Layout.Unit, KernelFacadePages.Error)
assert_logical_identity = |runs, styles, logical, block| {
	start = logical.physical.start()
	length = logical.physical.length()
	if start >= runs.len() or length > runs.len() - start or start >= styles.len() or length > styles.len() - start {
		return Err(InvalidRun({ block, run: start }))
	}
	first = list_at(runs, start)
	first_style = list_at(styles, start)
	var $size = first.size.raw()
	var $index = start + 1
	while $index < start + length {
		run = list_at(runs, $index)
		if list_at(styles, $index).leading != first_style.leading {
			return Err(InvalidRun({ block, run: $index }))
		}
		$size = I64.max($size, run.size.raw())
		$index = $index + 1
	}
	Ok(Layout.Unit.from_raw($size))
}

keeps_together : Document.NormalizedBlockKind -> Bool
keeps_together = |kind| match kind {
	DestinationHeading(_) | Figure(_) | FigureCaption(_) | Heading(_) | Title => True
	_ => False
}

## Headings (with or without a destination) and titles keep with the next
## block's first placement unit (R1).
keeps_with_next : Document.NormalizedBlockKind -> Bool
keeps_with_next = |kind| match kind {
	DestinationHeading(_) | Heading(_) | Title => True
	_ => False
}

## Consecutive blocks of one list, at any nesting depth, stack without
## paragraph spacing: the legacy flat bullets, or two leaves inside the same
## outermost list.
continues_list : Document.NormalizedAuthoring, List(KernelFacadeShape.BlockRuns), U64, U64 -> Bool
continues_list = |authoring, block_runs, index, level| {
	blocks = authoring.blocks
	if index + 1 >= blocks.len() {
		return False
	}
	match (list_at(blocks, index).kind, list_at(blocks, index + 1).kind) {
		(Bullet({ list: left, item: _ }), Bullet({ list: right, item: _ })) => left == right
		_ => {
			next_level = match list_at(block_runs, index + 1) {
				TextBlock({ body: _, label: _, level: value }) => value
				ContentlessCell | EmptySourceLine(_) => 0
			}
			if level == 0 or next_level == 0 {
				False
			} else {
				list = outermost_list(authoring.groups, list_at(blocks, index).parent)
				list != 0 and list == outermost_list(authoring.groups, list_at(blocks, index + 1).parent)
			}
		}
	}
}

## The outermost list group above group code `code`.
outermost_list : List(Document.NormalizedGroup), U64 -> U64
outermost_list = |groups, code| {
	var $code = code
	var $found = 0
	while $code != 0 {
		group = list_at(groups, $code - 1)
		match group.kind {
			ItemList(_) => {
				$found = $code
			}
			_ => {}
		}
		$code = group.parent
	}
	$found
}

range_end : Semantics.Range -> Try(U64, KernelFacadePages.Error)
range_end = |range| checked_add(range.start(), range.length())

## The flow drawings' layout facts before pagination: `decorations[b]` is
## the total decoration height above leaf `b` (empty without
## decorations), and each figure's scale (thousandths) and anchor-line
## height. A figure's unit is the decoration above it, its drawing, and,
## when captioned, the paragraph spacing and its caption's lines.
FlowFacts : { decorations : List(U64), heights : List(U64), scales : List(U64) }

## Figure fit and decoration containment, proven before pagination
## against the flow width and the page flow heights (the smallest and the
## largest page frame; they differ only under page templates).
##
## - An `Exact` figure must be no wider than the flow region and its unit
##   no taller than the largest page frame; otherwise
##   `FigureOversize`. Its scale is 1000.
## - A `ScaleToFit` figure takes the largest scale `s` (thousandths, at
##   most 1000) with `w·s/1000` within the flow width and
##   `⌈h·s/1000⌉` within the smallest page frame less the rest of its
##   unit, so it fits on any fresh page. No positive scale is
##   `FigureOversize`; a scale below the floor is `FigureScaleFloor`.
## - A decoration must be no wider than the flow region and no taller
##   than the largest page frame (`DecorationOversize`).
##
## Nothing else is scaled, and nothing is clipped.
figure_widths : Document.NormalizedAuthoring, KernelFacadeLines.Plan -> List({ width : U64, padding : U64 })
figure_widths = |authoring, line_plan| select_figure_widths(authoring, KernelFacadeLines.Plan.work(line_plan).content_width, |block| KernelFacadeLines.Plan.frame(line_plan, block).width)

## Empty means the already-selected full content width with no enclosing
## padding. Keep the dense figure-indexed arena only when an earlier frame
## differs; one narrowed figure retains the default entries around it too.
select_figure_widths : Document.NormalizedAuthoring, U64, (U64 -> U64) -> List({ width : U64, padding : U64 })
select_figure_widths = |authoring, content_width, width_at| {
	if authoring.figures.is_empty() {
		return []
	}
	var $required = False
	var $block = 0
	while $block < authoring.blocks.len() {
		record = list_at(authoring.blocks, $block)
		match record.kind {
			Figure(_) => {
				if width_at($block) != content_width or enclosing_callout_padding(authoring, record.parent) != 0 {
					$required = True
					break
				}
			}
			_ => {}
		}
		$block = $block + 1
	}
	if !$required {
		return []
	}
	var $widths = List.with_capacity(authoring.figures.len())
	$block = 0
	while $block < authoring.blocks.len() {
		match list_at(authoring.blocks, $block).kind {
			Figure(_) => {
				$widths = $widths.append({ width: width_at($block), padding: enclosing_callout_padding(authoring, list_at(authoring.blocks, $block).parent) * 2 })
			}
			_ => {}
		}
		$block = $block + 1
	}
	$widths
}

expect {
	drawing = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 10, 10), Color.srgb8({ blue: 0, green: 0, red: 0 }))
	figure = Document.fitted_figure(drawing, "A plan", NoCaption, Exact)
	authoring = Document.normalize(Document.from_blocks({ contents: [figure, figure, figure], language: "en", title: "Figure frame facts" }))
	select_figure_widths(authoring, 100, |_| 100).is_empty() and
		select_figure_widths(authoring, 100, |block| if (block == 1) 80 else 100) == [{ width: 100, padding: 0 }, { width: 80, padding: 0 }, { width: 100, padding: 0 }]
}

expect {
	drawing = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 10, 10), Color.srgb8({ blue: 0, green: 0, red: 0 }))
	figure = Document.fitted_figure(drawing, "A plan", NoCaption, Exact)
	container = Document.callout({ contents: [figure], fragmentation: Lines, padding: Layout.Unit.from_raw(5), name: "Panel", panel: { fill: NoFill, border: NoBorder } })
	authoring = Document.normalize(Document.from_blocks({ contents: [figure, container, figure], language: "en", title: "Padded figure facts" }))
	select_figure_widths(authoring, 100, |_| 100) == [{ width: 100, padding: 0 }, { width: 100, padding: 10 }, { width: 100, padding: 0 }]
}

plan_flow : Document.NormalizedAuthoring, List(a), (a -> [Rows(U64), NoRows]), List({ width : U64, padding : U64 }), Layout.Size, Theme, FlowSelection -> Try(FlowFacts, KernelFacadePages.Error)
plan_flow = |authoring, block_lines, count_rows, widths, page_size, theme, flow| {
	if authoring.figures.is_empty() and authoring.decorations.is_empty() and authoring.customs.is_empty() {
		return Ok({ decorations: [], heights: [], scales: [] })
	}
	margins = theme.page_margin
	flow_width = checked_sub(nonnegative_raw(page_size.width)?, checked_add(nonnegative_raw(margins.left)?, nonnegative_raw(margins.right)?)?)?
	body_height = checked_sub(nonnegative_raw(page_size.height)?, checked_add(nonnegative_raw(margins.top)?, nonnegative_raw(margins.bottom)?)?)?

	var $decorations = if (authoring.decorations.is_empty()) [] else List.repeat(0, authoring.blocks.len())
	var $index = 0
	while $index < authoring.decorations.len() {
		decoration = list_at(authoring.decorations, $index)
		drawing = valid_drawing(decoration.drawing, decoration.block)?
		frames = scope_frame_bounds(flow, body_height, decoration.block)?
		if drawing.width > flow_width or drawing.height > frames.largest {
			return Err(DecorationOversize({ decoration: $index, frame_height: frames.largest, frame_width: flow_width, height: drawing.height, width: drawing.width }))
		}
		if decoration.block >= authoring.blocks.len() {
			return Err(InvalidBlock({ block: decoration.block }))
		}
		$decorations = list_set($decorations, decoration.block, checked_add(list_at($decorations, decoration.block), drawing.height)?)
		$index = $index + 1
	}

	# A custom block with the decorations above it fits a fresh page of
	# the largest kind, or preparation fails naming both heights.
	var $custom = 0
	while $custom < authoring.customs.len() {
		custom = list_at(authoring.customs, $custom)
		first = list_at(authoring.groups, custom.group).first_block
		frames = scope_frame_bounds(flow, body_height, first)?
		above = if ($decorations.is_empty()) 0 else list_at($decorations, first)
		height = checked_add(nonnegative_raw(custom.height)?, above)?
		if height > frames.largest {
			return Err(CustomOversize({ custom: $custom, frame_height: frames.largest, height }))
		}
		$custom = $custom + 1
	}
	if authoring.figures.is_empty() {
		return Ok({ decorations: $decorations, heights: [], scales: [] })
	}
	leading = nonnegative_raw(Theme.body_style(theme).leading)?
	spacing = nonnegative_raw(theme.paragraph_spacing)?
	var $heights = List.with_capacity(authoring.figures.len())
	var $scales = List.with_capacity(authoring.figures.len())
	var $block = 0
	while $block < authoring.blocks.len() {
		match list_at(authoring.blocks, $block).kind {
			Figure(figure_index) => {
				frames = scope_frame_bounds(flow, body_height, $block)?
				if figure_index != $scales.len() {
					return Err(InvalidBlock({ block: $block }))
				}
				figure = list_at(authoring.figures, figure_index)
				drawing = valid_drawing(figure.drawing, $block)?
				width = if (widths.is_empty()) flow_width else list_at(widths, figure_index).width
				padding = if (widths.is_empty()) 0 else list_at(widths, figure_index).padding
				largest = if (frames.largest > padding) frames.largest - padding else 0
				smallest = if (frames.smallest > padding) frames.smallest - padding else 0
				above = if ($decorations.is_empty()) 0 else list_at($decorations, $block)
				caption = if figure.captioned {
					if $block + 1 >= block_lines.len() {
						return Err(InvalidBlock({ block: $block }))
					}
					caption_lines = match count_rows(list_at(block_lines, $block + 1)) {
						Rows(count) => count
						NoRows => return Err(InvalidBlock({ block: $block + 1 }))
					}
					checked_add(spacing, checked_mul(caption_lines, leading)?)?
				} else {
					0
				}
				rest = checked_add(above, caption)?
				fitted = match figure.fit {
					ExactFit => {
						if drawing.width > width or checked_add(rest, drawing.height)? > largest {
							return Err(FigureOversize({ block: $block, frame_height: largest, frame_width: width, height: drawing.height, width: drawing.width }))
						}
						{ height: drawing.height, scale: 1000 }
					}
					ScaleFit(floor) => {
						oversize = FigureOversize({ block: $block, frame_height: smallest, frame_width: width, height: drawing.height, width: drawing.width })
						if rest >= smallest {
							return Err(oversize)
						}
						by_width = checked_mul(width, 1000)? // drawing.width
						by_height = checked_mul(smallest - rest, 1000)? // drawing.height
						scale = U64.min(1000, U64.min(by_width, by_height))
						if scale == 0 {
							return Err(oversize)
						}
						if scale < checked_mul(floor, 10)? {
							return Err(FigureScaleFloor({ block: $block, floor, scale }))
						}
						{ height: (checked_mul(drawing.height, scale)? + 999) // 1000, scale }
					}
				}
				$heights = $heights.append(fitted.height)
				$scales = $scales.append(fitted.scale)
			}
			_ => {}
		}
		$block = $block + 1
	}
	if $scales.len() != authoring.figures.len() {
		return Err(InvalidBlock({ block: authoring.blocks.len() }))
	}
	Ok({ decorations: $decorations, heights: $heights, scales: $scales })
}

## Binary lookup of the owning scope, independent of paint/current y.
## Unrelated chapters cannot constrain a figure's accepted scale.
scope_frame_bounds : FlowSelection, U64, U64 -> Try({ largest : U64, smallest : U64 }, KernelFacadePages.Error)
scope_frame_bounds = |flow, body_height, block| {
	default_template = match flow {
		NoFlowTemplate => return Ok({ largest: body_height, smallest: body_height })
		WithFlowTemplate(value) => value
		WithScopedFlow({ template, scopes }) => {
			var $low = 0
			var $high = scopes.len()
			while $low < $high {
				middle = $low + ($high - $low) // 2
				if list_at(scopes, middle).leaves.start() <= block {
					$low = middle + 1
				} else {
					$high = middle
				}
			}
			if $low > 0 {
				scope = list_at(scopes, $low - 1)
				if block < scope.leaves.start() + scope.leaves.length() {
					first = nonnegative_raw(scope.opening.height)?
					continuation = nonnegative_raw(scope.continuation.height)?
					return Ok({ largest: U64.max(first, continuation), smallest: U64.min(first, continuation) })
				}
			}
			template
		}
	}
	first = nonnegative_raw(default_template.first.height)?
	continuation = nonnegative_raw(default_template.continuation.height)?
	Ok({ largest: U64.max(first, continuation), smallest: U64.min(first, continuation) })
}

## A figure or decoration drawing that semantic planning already accepted.
valid_drawing : Document.ValidatedDrawing, U64 -> Try(Document.FlowDrawing, KernelFacadePages.Error)
valid_drawing = |drawing, block| match drawing {
	ValidDrawing(value) => Ok(value)
	InvalidDrawing(_) => Err(InvalidBlock({ block: block }))
}

## The decoration band above leaf `block`.
leaf_decoration : FlowFacts, U64 -> Layout.Unit
leaf_decoration = |facts, block| Layout.Unit.from_raw((if (facts.decorations.is_empty()) 0 else list_at(facts.decorations, block)).to_i64_wrap())

## A leaf's page block with its decoration band and, for a figure, its
## anchor line: one line whose leading is the (scaled) drawing height,
## with the baseline on the drawing's bottom edge, required to keep with
## its caption when it has one.
flow_block : Document.NormalizedAuthoring, FlowFacts, U64, KernelPageLayout.Block -> KernelPageLayout.Block
flow_block = |authoring, facts, block, page_block| {
	decorated = { ..page_block, decoration: leaf_decoration(facts, block) }
	match list_at(authoring.blocks, block).kind {
		Figure(figure_index) => {
			height = Layout.Unit.from_raw(list_at(facts.heights, figure_index).to_i64_wrap())
			captioned = list_at(authoring.figures, figure_index).captioned
			policy = decorated.policy
			{ ..decorated, baseline_offset: height, leading: height, policy: { ..policy, keep_with_next: if (captioned) Required else policy.keep_with_next } }
		}
		_ => decorated
	}
}

## Place every decoration from the bands pagination recorded: a band's
## decorations stack from its top in authored order. `units` maps a leaf
## to its page-layout unit (empty when they coincide).
decoration_paints : Document.NormalizedAuthoring, List(KernelPageLayout.Band), List(U64), U64 -> Try(List(KernelFacadePages.DecorationPaint), KernelFacadePages.Error)
decoration_paints = |authoring, bands, units, margin_left| {
	if authoring.decorations.is_empty() {
		return Ok([])
	}
	var $paints = List.with_capacity(authoring.decorations.len())
	var $band = 0
	var $offset = 0
	var $previous = U64.highest
	var $index = 0
	while $index < authoring.decorations.len() {
		decoration = list_at(authoring.decorations, $index)
		drawing = valid_drawing(decoration.drawing, decoration.block)?
		unit = if (units.is_empty()) decoration.block else list_at(units, decoration.block)
		if unit != $previous {
			$offset = 0
			$previous = unit
		}
		while $band < bands.len() and list_at(bands, $band).block < unit {
			$band = $band + 1
		}
		if $band >= bands.len() or list_at(bands, $band).block != unit {
			return Err(InvalidBlock({ block: decoration.block }))
		}
		band = list_at(bands, $band)
		bottom = checked_sub(band.top, checked_add($offset, drawing.height)?)?
		$paints = $paints.append({ behind: decoration.behind, decoration: $index, origin: { x: Layout.Unit.from_raw(margin_left.to_i64_wrap()), y: Layout.Unit.from_raw(bottom.to_i64_wrap()) }, page: band.page })
		$offset = checked_add($offset, drawing.height)?
		$index = $index + 1
	}
	Ok(behind_decorations_first($paints))
}

## Page-ordered decoration paints with each page's behind-text decorations
## moved before its others, keeping both orders; a list without them is
## returned as is.
behind_decorations_first : List(KernelFacadePages.DecorationPaint) -> List(KernelFacadePages.DecorationPaint)
behind_decorations_first = |paints| {
	if !paints.any(|paint| paint.behind) {
		return paints
	}
	var $ordered = List.with_capacity(paints.len())
	var $start = 0
	while $start < paints.len() {
		page = list_at(paints, $start).page
		var $end = $start
		while $end < paints.len() and list_at(paints, $end).page == page {
			$end = $end + 1
		}
		var $index = $start
		while $index < $end {
			paint = list_at(paints, $index)
			if paint.behind {
				$ordered = $ordered.append(paint)
			}
			$index = $index + 1
		}
		$index = $start
		while $index < $end {
			paint = list_at(paints, $index)
			if !paint.behind {
				$ordered = $ordered.append(paint)
			}
			$index = $index + 1
		}
		$start = $end
	}
	$ordered
}

check_limit : U64, U64, KernelFacadePages.Dimension -> Try({}, KernelFacadePages.Error)
check_limit = |attempted, limit, dimension| if (attempted > limit) Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelFacadePages.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(_) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated facade page index escaped"
	}
	Ok(value) => value
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated facade page write escaped"
	}
	Ok(updated) => updated
}

expect keeps_together(Title) and keeps_with_next(Heading(2)) and !keeps_together(Paragraph)

expect {
	authoring = Document.normalize(Document.from_blocks({ contents: [Document.bullets(["One", "Two"]), Document.paragraph("Three")], language: "en-AU", title: "Lists" }))
	runs = List.repeat(TextBlock({ body: { physical: Semantics.Range.from_start_and_length(0, 1) }, label: NoLabel, level: 1 }), 3)
	continues_list(authoring, runs, 0, 1) and !continues_list(authoring, runs, 1, 1)
}

# Leaves of one nested list stack without spacing; the paragraph after the
# outermost list does not.
expect {
	item = |text| Document.list_item([Document.paragraph(text)])
	nested = Document.bullet_list([Document.list_item([Document.paragraph("One"), Document.bullet_list([item("Two")])]), item("Three")])
	authoring = Document.normalize(Document.from_blocks({ contents: [nested, Document.paragraph("After")], language: "en-AU", title: "Lists" }))
	runs = [1, 2, 1, 0].map(|level| TextBlock({ body: { physical: Semantics.Range.from_start_and_length(0, 1) }, label: NoLabel, level }))
	continues_list(authoring, runs, 0, 1) and continues_list(authoring, runs, 1, 2) and !continues_list(authoring, runs, 2, 1)
}

## The content occurrence a shaped body run paints. Body runs come from the
## semantic shaping batch, so an artifact run here is an invalid run.
semantic_occurrence : Text.Run, U64, U64 -> Try(Semantics.OccurrenceId, KernelFacadePages.Error)
semantic_occurrence = |run, block, run_index| match run.unicode {
	OccurrenceText(occurrence) => Ok(occurrence)
	ArtifactText(_) => Err(InvalidRun({ block, run: run_index }))
}

## The number of leaf blocks the first page's lead region receives.
lead_leaves : FlowSelection -> U64
lead_leaves = |flow| match flow {
	NoFlowTemplate => 0
	WithFlowTemplate({ continuation: _, first: _, lead }) | WithScopedFlow({ template: { continuation: _, first: _, lead }, scopes: _ }) => match lead {
		NoLead => 0
		Lead({ frame: _, leaves }) => leaves
	}
}

## The lead region is placed as one unit in its own region, so its blocks
## carry no page-flow policy: no explicit break, no keep, and whole-block
## line minimums. Only the lead's blocks are rewritten.
lead_policies : List(KernelPageLayout.Block), U64 -> List(KernelPageLayout.Block)
lead_policies = |blocks, count| {
	var $blocks = blocks
	var $index = 0
	while $index < count {
		block = list_at($blocks, $index)
		lines = block.lines.length()
		$blocks = list_set($blocks, $index, { ..block, policy: { break_before: False, keep_together: False, keep_with_next: NoKeep, minimum_first_lines: lines, minimum_last_lines: lines } })
		$index = $index + 1
	}
	$blocks
}

## Keep groups inside the lead region are subsumed by the region's single
## unit; only body-flow groups reach page layout.
flow_groups : List(KernelPageLayout.KeepGroup), U64 -> List(KernelPageLayout.KeepGroup)
flow_groups = |groups, lead_units| if (lead_units == 0) groups else groups.keep_if(|group| group.blocks.start() >= lead_units)

## Scope boundaries name original leaves and are translated once into
## paginator units. No unit may straddle one of these full-child boundaries.
layout_scopes : FlowSelection, List(U64) -> List(KernelPageLayout.ScopedFrame)
layout_scopes = |flow, unit_of_block| match flow {
	WithScopedFlow({ scopes, template: _ }) => {
		var $scopes = List.with_capacity(scopes.len())
		for scope in scopes {
			first = scope.leaves.start()
			last = first + scope.leaves.length()
			start = if (unit_of_block.is_empty()) first else list_at(unit_of_block, first)
			end = if (unit_of_block.is_empty()) last else list_at(unit_of_block, last - 1) + 1
			$scopes = $scopes.append({ blocks: Semantics.Range.from_start_and_length(start, end - start), opening: scope.opening, continuation: scope.continuation })
		}
		$scopes
	}
	_ => []
}

scope_policies : List(KernelPageLayout.Block), FlowSelection, List(U64) -> List(KernelPageLayout.Block)
scope_policies = |blocks, flow, unit_of_block| {
	var $blocks = blocks
	for scope in layout_scopes(flow, unit_of_block) {
		start = scope.blocks.start()
		end = start + scope.blocks.length()
		if start > 0 {
			block = list_at($blocks, start)
			$blocks = list_set($blocks, start, { ..block, policy: { ..block.policy, break_before: True } })
		}
		if end < $blocks.len() {
			block = list_at($blocks, end)
			$blocks = list_set($blocks, end, { ..block, policy: { ..block.policy, break_before: True } })
		}
	}
	$blocks
}

layout_template : KernelFacadePages.FlowTemplate, U64 -> KernelPageLayout.Template
layout_template = |template, lead_units| {
	continuation: template.continuation,
	first: template.first,
	lead: match template.lead {
		NoLead => NoLead
		Lead({ frame, leaves: _ }) => Lead({ blocks: lead_units, frame })
	},
}

# `ScaleToFit` scales a 600 × 900 pt drawing by the largest factor that
# fits the body frame (in thousandths, rounding the anchor height up); a
# floor above it and an `Exact` figure are oversize.
expect {
	drawing = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 600, 900), Color.srgb8({ blue: 0, green: 0, red: 0 }))
	page = { height: Layout.Unit.points(842), width: Layout.Unit.points(595) }
	theme = Theme.{ page_margin: { bottom: Layout.Unit.points(48), left: Layout.Unit.points(56), right: Layout.Unit.points(56), top: Layout.Unit.points(48) } }
	authoring = |fit| Document.normalize(Document.from_blocks({ contents: [Document.fitted_figure(drawing, "A plan", NoCaption, fit)], language: "en-AU", title: "Fit" }))
	scaled = match plan_flow(authoring(ScaleToFit({ minimum_percent: 50 })), [], concrete_row_count, [], page, theme, NoFlowTemplate) {
		Ok({ decorations: [], heights: [height], scales: [scale] }) => scale == 805 and height == 724500
		_ => False
	}
	floored = match plan_flow(authoring(ScaleToFit({ minimum_percent: 90 })), [], concrete_row_count, [], page, theme, NoFlowTemplate) {
		Err(FigureScaleFloor({ block: 0, floor: 90, scale: 805 })) => True
		_ => False
	}
	exact = match plan_flow(authoring(Exact), [], concrete_row_count, [], page, theme, NoFlowTemplate) {
		Err(FigureOversize({ block: 0, frame_height: 746000, frame_width: 483000, height: 900000, width: 600000 })) => True
		_ => False
	}
	scaled and floored and exact
}

## Fit each custom block's paragraphs into its measured box: every leaf is
## unsplittable (the group is one keep-together unit), the first reserves
## the top inset above its first line (with any decorations above it), and
## the last reserves the bottom inset and the unused measured height below
## its last line, so the block occupies exactly its measured height. The
## content (lines and the spacing between the paragraphs) must fit the box
## less twice the inset (`CustomMeasureShort`); nothing is clipped or
## shrunk. `units` maps a leaf to its page-layout unit (empty when they
## coincide). O(customs + custom leaves); documents without custom blocks
## return their blocks untouched.
apply_customs : Document.NormalizedAuthoring, List(KernelPageLayout.Block), List(U64) -> Try(List(KernelPageLayout.Block), KernelFacadePages.Error)
apply_customs = |authoring, page_blocks, units| {
	if authoring.customs.is_empty() {
		return Ok(page_blocks)
	}
	var $blocks = page_blocks
	var $custom = 0
	while $custom < authoring.customs.len() {
		custom = list_at(authoring.customs, $custom)
		group = list_at(authoring.groups, custom.group)
		first = if (units.is_empty()) group.first_block else list_at(units, group.first_block)
		last = if (units.is_empty()) group.block_end - 1 else list_at(units, group.block_end - 1)
		inset = nonnegative_raw(custom.inset)?
		height = nonnegative_raw(custom.height)?
		var $content = 0
		var $unit = first
		while $unit <= last {
			block = list_at($blocks, $unit)
			$content = checked_add($content, checked_mul(block.lines.length(), nonnegative_raw(block.leading)?)?)?
			if $unit < last {
				$content = checked_add($content, nonnegative_raw(block.space_after)?)?
			}
			policy = block.policy
			$blocks = list_set($blocks, $unit, { ..block, policy: { ..policy, keep_together: True } })
			$unit = $unit + 1
		}
		available = checked_sub(height, checked_mul(inset, 2)?)?
		if $content > available {
			return Err(CustomMeasureShort({ available, content: $content, custom: $custom }))
		}
		head = list_at($blocks, first)
		$blocks = list_set($blocks, first, { ..head, decoration: Layout.Unit.from_raw(checked_add(nonnegative_raw(head.decoration)?, inset)?.to_i64_wrap()) })
		tail = list_at($blocks, last)
		$blocks = list_set($blocks, last, { ..tail, trailing: Layout.Unit.from_raw((height - inset - $content).to_i64_wrap()) })
		$custom = $custom + 1
	}
	Ok($blocks)
}

## Place every custom panel from its first leaf's explicit semantic occurrence
## and accepted page fragment. A zero inset has no decoration band; the
## fragment's content top plus the inset is the measured box's top.
## Both arenas are ordered, so the cursor visits each fragment at most once.
panel_paints : Document.NormalizedAuthoring, List(KernelPageLayout.Fragment), List(KernelFacadeShape.BlockRuns), List(Text.Run) -> Try(List(KernelFacadePages.PanelPaint), KernelFacadePages.Error)
panel_paints = |authoring, fragments, block_runs, runs| {
	if authoring.customs.is_empty() {
		return Ok([])
	}
	var $paints = List.with_capacity(authoring.customs.len())
	var $fragment = 0
	var $custom = 0
	while $custom < authoring.customs.len() {
		custom = list_at(authoring.customs, $custom)
		leaf = list_at(authoring.groups, custom.group).first_block
		body = match list_at(block_runs, leaf) {
			TextBlock({ body: logical, .. }) => logical
			ContentlessCell | EmptySourceLine(_) => return Err(InvalidBlock({ block: leaf }))
		}
		run = logical_run_first(body, leaf, runs.len())?
		occurrence = semantic_occurrence(list_at(runs, run), leaf, run)?
		var $found = False
		while $fragment < fragments.len() and !$found {
			match list_at(fragments, $fragment).owner {
				Content(value) => {
					if value == occurrence {
						$found = True
					} else if value.index() > occurrence.index() {
						return Err(InvalidBlock({ block: leaf }))
					} else {
						$fragment = $fragment + 1
					}
				}
				SourceBlock(_) => {
					$fragment = $fragment + 1
				}
			}
		}
		if !$found {
			return Err(InvalidBlock({ block: leaf }))
		}
		fragment = list_at(fragments, $fragment)
		geometry = fragment.geometry
		top = checked_add(nonnegative_raw(geometry.origin.y)?, checked_add(nonnegative_raw(geometry.size.height)?, nonnegative_raw(custom.inset)?)?)?
		bottom = checked_sub(top, nonnegative_raw(custom.height)?)?
		$paints = $paints.append({ custom: $custom, origin: { x: geometry.origin.x, y: Layout.Unit.from_raw(bottom.to_i64_wrap()) }, page: fragment.page.index() })
		$custom = $custom + 1
	}
	Ok($paints)
}

mapped_lead_count : FlowSelection, List(U64) -> U64
mapped_lead_count = |flow, units| {
	leaves = lead_leaves(flow)
	if (leaves == 0) 0 else list_at(units, leaves - 1) + 1
}

concrete_row_count : KernelFacadeLines.BlockLines -> [Rows(U64), NoRows]
concrete_row_count = |block| match block {
	TextBlock({ body, .. }) => Rows(body.lines.length())
	ContentlessCell | EmptySourceLine(_) => NoRows
}

## Geometry planning over measured rows. These rows have item identities and
## widths, but no provisional Unicode range or text-semantic fragment.
build_measured : Document.NormalizedAuthoring, KernelFacadePages.MeasuredInput, Layout.Size, Theme, FlowSelection, KernelFacadePages.Limits -> Try(KernelFacadePages.Measured, KernelFacadePages.Error)
build_measured = |authoring, input, page_size, theme, flow, limits| {
	if input.blocks.len() != authoring.blocks.len() or input.blocks.is_empty() {
		return Err(InvalidBlock({ block: input.blocks.len() }))
	}
	check_limit(input.blocks.len(), limits.max_blocks, Blocks)?
	check_page_breaks(authoring.page_breaks, input.blocks.len(), lead_leaves(flow))?
	flow_facts = plan_flow(authoring, input.blocks, measured_row_count, input.figure_frames, page_size, theme, flow)?
	author_keeps = authored_keeps(authoring.groups, input.blocks.len())
	gap = nonnegative_raw(theme.table.row_gap)?
	spacing = nonnegative_raw(theme.paragraph_spacing)?
	no_row = { body_rule: False, cells: Semantics.Range.from_start_and_length(0, 0), fill: NoFill, grid: 0, rule_above: False, rule_below: False, table: 0 }
	var $blocks = []
	var $units = []
	var $grid_rows = []
	var $row_info = []
	var $table_info = []
	var $unit_of_block = List.repeat(0, input.blocks.len())
	var $footer_groups = []
	var $footer_sources = []
	var $source = 0
	var $table = 0
	var $cell = 0
	var $break = 0
	var $spacer = 0
	var $index = 0
	while $index < input.blocks.len() {
		source_start = $source < authoring.sources.len() and list_at(authoring.groups, list_at(authoring.sources, $source).group).first_block == $index
		table_start = $table < input.tables.len() and list_at(authoring.groups, list_at(input.tables, $table).group).first_block == $index
		if source_start {
			source = list_at(authoring.sources, $source)
			group = list_at(authoring.groups, source.group)
			start = $grid_rows.len()
			var $leaf = group.first_block
			while $leaf < group.block_end {
				$unit_of_block = list_set($unit_of_block, $leaf, $units.len())
				match list_at(input.blocks, $leaf) {
					EmptySourceLine({ source: id, line }) => {
						if id != $source {
							return Err(InvalidBlock({ block: $leaf }))
						}
						check_limit(checked_add($grid_rows.len(), 1)?, limits.max_rows, Rows)?
						$grid_rows = $grid_rows.append(NoTextRow({ source: id, line }))
					}
					MeasuredText(text) => {
						var $row = 0
						while $row < text.rows.length() {
							check_limit(checked_add($grid_rows.len(), 1)?, limits.max_rows, Rows)?
							$grid_rows = $grid_rows.append(BodyRow({ block: $leaf, row: text.rows.start() + $row, offset: text.body_offset, label: NoLabel }))
							$row = $row + 1
						}
					}
					_ => return Err(InvalidBlock({ block: $leaf }))
				}
				$leaf = $leaf + 1
			}
			spaced = spacer_total(authoring.spacers, $spacer, group.block_end)
			$spacer = spaced.cursor
			break_before = $break < authoring.page_breaks.len() and list_at(authoring.page_breaks, $break).block == $index
			if break_before {
				$break = $break + 1
			}
			keep = if (author_keeps.is_empty()) NoKeep else list_at(author_keeps, group.block_end - 1)
			$blocks = $blocks.append({ baseline_offset: source.size, leading: source.leading, decoration: leaf_decoration(flow_facts, $index), lead: Layout.Unit.from_raw(0), trailing: Layout.Unit.from_raw(0), lines: Semantics.Range.from_start_and_length(start, $grid_rows.len() - start), owner: SourceBlock({ source: $source, padding: source.padding }), policy: { break_before, keep_together: source.fragmentation == Unsplittable, keep_with_next: keep, minimum_first_lines: 1, minimum_last_lines: 1 }, space_after: Layout.Unit.from_raw(checked_add(spacing, spaced.amount)?.to_i64_wrap()) })
			$units = $units.append(SourceUnit($source))
			$row_info = $row_info.append(no_row)
			$source = $source + 1
			$index = group.block_end
		} else if table_start {
			table_geometry = list_at(input.tables, $table)
			group = list_at(authoring.groups, table_geometry.group)
			table = list_at(authoring.tables, $table)
			break_before = $break < authoring.page_breaks.len() and list_at(authoring.page_breaks, $break).block == $index
			if break_before {
				$break = $break + 1
			}
			var $pending_break = break_before
			if table.caption {
				text = measured_text(list_at(input.blocks, $index), $index)?
				start = $grid_rows.len()
				var $row = 0
				while $row < text.rows.length() {
					check_limit(checked_add($grid_rows.len(), 1)?, limits.max_rows, Rows)?
					$grid_rows = $grid_rows.append(BodyRow({ block: $index, row: text.rows.start() + $row, offset: text.body_offset, label: NoLabel }))
					$row = $row + 1
				}
				$unit_of_block = list_set($unit_of_block, $index, $units.len())
				$blocks = $blocks.append({ ..measured_leaf(text, start), decoration: leaf_decoration(flow_facts, $index), policy: { break_before: $pending_break, keep_together: True, keep_with_next: Required, minimum_first_lines: U64.min(2, text.rows.length()), minimum_last_lines: U64.min(2, text.rows.length()) }, space_after: Layout.Unit.from_raw(gap.to_i64_wrap()) })
				$units = $units.append(LeafUnit($index))
				$row_info = $row_info.append(no_row)
				$pending_break = False
			}
			header_first = $units.len()
			var $header_height = 0
			var $ordinal = 0
			var $row_group = table_geometry.group + 1
			while $row_group < group.group_end {
				row = list_at(authoring.groups, $row_group)
				section = match row.kind {
					TableRow(value) => value
					_ => return Err(InvalidBlock({ block: row.first_block }))
				}
				first_cell = $cell
				var $grid = 0
				var $leading = 0
				var $size = 0
				var $owner = Semantics.OccurrenceId.from_index(0)
				var $seen = False
				var $leaf = row.first_block
				while $leaf < row.block_end {
					match list_at(input.blocks, $leaf) {
						ContentlessCell => {}
						MeasuredText(text) => {
							if !$seen {
								$leading = positive_raw(text.leading)?
								$owner = text.owner
								$seen = True
							}
							else if positive_raw(text.leading)? != $leading {
								return Err(InvalidBlock({ block: $leaf }))
							}
							$size = U64.max($size, positive_raw(text.size)?)
							$grid = U64.max($grid, text.rows.length())
						}
						_ => return Err(InvalidBlock({ block: $leaf }))
					}
					$unit_of_block = list_set($unit_of_block, $leaf, $units.len())
					$cell = $cell + 1
					$leaf = $leaf + 1
				}
				if !$seen {
					$grid = 1
					$leading = positive_raw(Theme.body_style(theme).leading)?
					$size = positive_raw(Theme.body_style(theme).size)?
				}
				if $grid == 0 {
					return Err(InvalidBlock({ block: row.first_block }))
				}
				start = $grid_rows.len()
				var $local = 0
				while $local < $grid {
					check_limit(checked_add($grid_rows.len(), 1)?, limits.max_rows, Rows)?
					$grid_rows = $grid_rows.append(TableGrid)
					$local = $local + 1
				}
				last_row = $row_group + 1 == group.group_end
				last_body = section == Body and (
					last_row or (
						match list_at(authoring.groups, $row_group + 1).kind {
							TableRow(Footer) => True
							_ => False
						}
					)
				)
				first_footer = section == Footer and (
					match list_at(authoring.groups, $row_group - 1).kind {
						TableRow(Footer) => False
						_ => True
					}
				)
				last_header = section == Header and (
					match list_at(authoring.groups, $row_group + 1).kind {
						TableRow(Header) => False
						_ => True
					}
				)
				authored = if (author_keeps.is_empty()) NoKeep else list_at(author_keeps, row.block_end - 1)
				keep = if (section == Header) Required else if (last_body and table.footer_rows > 0) Preferred(FooterCarry) else if (last_row) authored else NoKeep
				spaced = spacer_total(authoring.spacers, $spacer, row.block_end)
				if last_row {
					$spacer = spaced.cursor
				}
				space = if (last_row) checked_add(spacing, spaced.amount)? else gap
				fill = match section {
					Header => theme.table.header_fill
					Footer => theme.table.footer_fill
					Body => if ($ordinal % 2 == 0) theme.table.body_fills.odd else theme.table.body_fills.even
				}
				$row_info = $row_info.append({ body_rule: section == Body and $ordinal > 0, cells: Semantics.Range.from_start_and_length(first_cell, $cell - first_cell), fill, grid: $grid, rule_above: first_footer, rule_below: last_header, table: $table })
				if section == Body {
					$ordinal = $ordinal + 1
				}
				minimum = U64.min(2, $grid)
				$blocks = $blocks.append({ baseline_offset: Layout.Unit.from_raw($size.to_i64_wrap()), leading: Layout.Unit.from_raw($leading.to_i64_wrap()), lines: Semantics.Range.from_start_and_length(start, $grid), owner: Content($owner), decoration: leaf_decoration(flow_facts, row.first_block), trailing: Layout.Unit.from_raw(0), lead: Layout.Unit.from_raw((if (section == Header) 0 else $header_height).to_i64_wrap()), policy: { break_before: $pending_break, keep_together: section != Body or table.row_split == KeepRows, keep_with_next: keep, minimum_first_lines: minimum, minimum_last_lines: minimum }, space_after: Layout.Unit.from_raw(space.to_i64_wrap()) })
				$units = $units.append(RowUnit($row_group))
				$pending_break = False
				if section == Header {
					$header_height = checked_add($header_height, checked_add(checked_mul($grid, $leading)?, gap)?)?
				}
				$row_group = $row_group + 1
			}
			if table.footer_rows > 1 {
				$footer_groups = $footer_groups.append({ blocks: Semantics.Range.from_start_and_length($units.len() - table.footer_rows, table.footer_rows) })
				$footer_sources = $footer_sources.append(FooterRows({ first: group.group_end - table.footer_rows, last: group.group_end - 1 }))
			}
			$table_info = $table_info.append({ offset: table_geometry.offset, width: table_geometry.width, header_height: $header_height, header_units: Semantics.Range.from_start_and_length(header_first, table.header_rows) })
			$table = $table + 1
			$index = group.block_end
		} else {
			text = measured_text(list_at(input.blocks, $index), $index)?
			start = $grid_rows.len()
			var $row = 0
			while $row < text.rows.length() {
				label = if $row == 0 {
					match text.label {
						NoLabel => NoLabel
						Label(value) => Label({ row: value.rows.start(), offset: value.offset })
					}
				} else NoLabel
				check_limit(checked_add($grid_rows.len(), 1)?, limits.max_rows, Rows)?
				$grid_rows = $grid_rows.append(BodyRow({ block: $index, row: text.rows.start() + $row, offset: text.body_offset, label }))
				$row = $row + 1
			}
			authored = if (author_keeps.is_empty()) NoKeep else list_at(author_keeps, $index)
			theme_keep = keeps_with_next(list_at(authoring.blocks, $index).kind) and $index + 1 < input.blocks.len()
			keep = match authored {
				Required => Required
				_ => if (theme_keep) Preferred(HeadingKeep) else authored
			}
			spaced = spacer_total(authoring.spacers, $spacer, $index + 1)
			$spacer = spaced.cursor
			break_before = $break < authoring.page_breaks.len() and list_at(authoring.page_breaks, $break).block == $index
			if break_before {
				$break = $break + 1
			}
			list_spacing = if (measured_continues_list(authoring, input.blocks, $index, text.level)) 0 else spacing
			$blocks = $blocks.append(flow_block(authoring, flow_facts, $index, { ..measured_leaf(text, start), policy: { break_before, keep_together: keeps_together(list_at(authoring.blocks, $index).kind), keep_with_next: keep, minimum_first_lines: U64.min(2, text.rows.length()), minimum_last_lines: U64.min(2, text.rows.length()) }, space_after: Layout.Unit.from_raw(checked_add(list_spacing, spaced.amount)?.to_i64_wrap()) }))
			$unit_of_block = list_set($unit_of_block, $index, $units.len())
			$units = $units.append(LeafUnit($index))
			$row_info = $row_info.append(no_row)
			$index = $index + 1
		}
		check_limit($grid_rows.len(), limits.max_rows, Rows)?
	}
	$blocks = apply_customs(authoring, $blocks, $unit_of_block)?
	merged = merge_groups(unit_groups(authoring, $unit_of_block), $footer_groups, $footer_sources)
	lead = mapped_lead_count(flow, $unit_of_block)
	containers = callout_containers(authoring, |group| list_at(input.group_frames, group), $unit_of_block, theme)?
	selection = match flow {
		NoFlowTemplate => NoTemplate
		WithFlowTemplate(template) | WithScopedFlow({ template, scopes: _ }) => WithTemplate(layout_template(template, lead))
	}
	$blocks = scope_policies(lead_policies($blocks, lead), flow, $unit_of_block)
	choice = KernelPageLayout.Choice.build($blocks, flow_groups(merged.groups, lead), $grid_rows.len(), { margins: theme.page_margin, page: page_size }, selection, layout_scopes(flow, $unit_of_block), containers, limits.page) ? |error| TableLayout({ error, groups: merged.sources, units: $units })
	continuation_top = match flow {
		NoFlowTemplate => Layout.Unit.from_raw(0)
		WithFlowTemplate(template) | WithScopedFlow({ template, scopes: _ }) => template.continuation.top
	}
	Ok(KernelFacadePages.Measured.({ choice, continuation_top, blocks: $blocks, units: $units, unit_of_block: $unit_of_block, grid_rows: $grid_rows, row_info: $row_info, table_info: $table_info, flow: flow_facts }))
}

MeasuredTextInfo : { rows : Semantics.Range, size : Layout.Unit, leading : Layout.Unit, owner : Semantics.OccurrenceId, level : U64, body_offset : Layout.Unit, label : [NoLabel, Label({ rows : Semantics.Range, offset : Layout.Unit })] }

measured_text : KernelFacadePages.MeasuredBlock, U64 -> Try(MeasuredTextInfo, KernelFacadePages.Error)
measured_text = |block, index| match block {
	MeasuredText(text) => if (text.rows.length() == 0) Err(InvalidBlock({ block: index })) else Ok(text)
	_ => Err(InvalidBlock({ block: index }))
}

measured_row_count : KernelFacadePages.MeasuredBlock -> [Rows(U64), NoRows]
measured_row_count = |block| match block {
	MeasuredText(text) => Rows(text.rows.length())
	_ => NoRows
}

measured_leaf : MeasuredTextInfo, U64 -> KernelPageLayout.Block
measured_leaf = |text, start| { baseline_offset: text.size, leading: text.leading, lines: Semantics.Range.from_start_and_length(start, text.rows.length()), owner: Content(text.owner), decoration: Layout.Unit.from_raw(0), lead: Layout.Unit.from_raw(0), trailing: Layout.Unit.from_raw(0), policy: { break_before: False, keep_together: False, keep_with_next: NoKeep, minimum_first_lines: U64.min(2, text.rows.length()), minimum_last_lines: U64.min(2, text.rows.length()) }, space_after: Layout.Unit.from_raw(0) }

measured_continues_list : Document.NormalizedAuthoring, List(KernelFacadePages.MeasuredBlock), U64, U64 -> Bool
measured_continues_list = |authoring, blocks, index, level| {
	if index + 1 >= blocks.len() {
		return False
	}
	match (list_at(authoring.blocks, index).kind, list_at(authoring.blocks, index + 1).kind) {
		(Bullet({ list: left, .. }), Bullet({ list: right, .. })) => left == right
		_ => {
			next_level = match list_at(blocks, index + 1) {
				MeasuredText(text) => text.level
				_ => 0
			}
			list = outermost_list(authoring.groups, list_at(authoring.blocks, index).parent)
			level > 0 and next_level > 0 and list != 0 and list == outermost_list(authoring.groups, list_at(authoring.blocks, index + 1).parent)
		}
	}
}

expect {
	authoring = Document.normalize(Document.from_blocks({ contents: [Document.paragraph("Measured paragraph")], language: "en-AU", title: "Geometry" }))
	input = { blocks: [MeasuredText({ rows: Semantics.Range.from_start_and_length(0, 100), size: Layout.Unit.points(11), leading: Layout.Unit.points(14), owner: Semantics.OccurrenceId.from_index(0), level: 0, body_offset: Layout.Unit.points(0), label: NoLabel })], cells: [], tables: [], group_frames: [], source_frames: [], figure_frames: [] }
	limits = KernelFacadePages.Limits.make({ max_blocks: 10, max_rows: 100, page: KernelPageLayout.Limits.make({ max_blocks: 10, max_fragments: 10, max_lines: 100, max_pages: 10, max_placements: 100 }) })
	page = { height: Layout.Unit.points(842), width: Layout.Unit.points(595) }
	plan = KernelFacadePages.Measured.build(authoring, input, page, Theme.{ page_margin: { bottom: 48, top: 48, left: 56, right: 56 } }, NoFlowTemplate, limits)?
	view = KernelFacadePages.Measured.view(plan)
	paint = KernelFacadePages.Measured.paint(plan, authoring, input, List.repeat(1, 100), page, Theme.{ page_margin: { bottom: 48, top: 48, left: 56, right: 56 } }, limits)?
	KernelPageLayout.Choice.pages(view.choice).len() == 2 and view.grid_rows.len() == 100 and KernelPageLayout.Choice.spans(view.choice).map(|span| span.rows.length()) == [53, 47] and paint.rows.len() == 100 and list_at(paint.rows, 0).origin.y.raw() == 783000 and list_at(paint.rows, 99).origin.y.raw() == 139000 and list_at(paint.rows, 99).row == 99
}

## With no active table/container span, repeated measured headers consume
## the same frame facts as ordinary text: default, global, or scoped.
measured_header_frame_test : [Plain, Template, Scoped] -> Try(Bool, KernelFacadePages.Error)
measured_header_frame_test = |kind| {
	table = Document.table({ caption: NoCaption, columns: [{ width: Share(1), align: Start }], header_rows: [Document.row([Document.header_cell(Column, [Document.plain_text("Head")])])], body_rows: [0, 1, 2, 3].map(|_| Document.row([Document.cell([Document.plain_text("Body")])])), footer_rows: [], row_split: KeepRows })
	contents = if (kind == Scoped) [Document.page_scope({}, [table])] else [table]
	authoring = Document.normalize(Document.from_blocks({ contents, language: "en", title: "Measured header frames" }))
	input = {
		blocks: [0, 1, 2, 3, 4].map(|index| MeasuredText({ rows: Semantics.Range.from_start_and_length(index, 1), size: Layout.Unit.points(11), leading: Layout.Unit.points(14), owner: Semantics.OccurrenceId.from_index(index), level: 0, body_offset: Layout.Unit.points(0), label: NoLabel })),
		cells: authoring.cells.map(|cell| { offset: 0, align: Start, block: cell.block, width: 72000, x: 4000 }),
		tables: [{ offset: 0, columns: [80000], group: if (kind == Scoped) 1 else 0, width: 80000 }],
		group_frames: List.repeat({ offset: 0, width: 80000 }, authoring.groups.len()),
		source_frames: [],
		figure_frames: [],
	}
	first = { height: Layout.Unit.points(80), top: Layout.Unit.points(0) }
	next = { height: Layout.Unit.points(60), top: Layout.Unit.points(20) }
	flow = match kind {
		Plain => NoFlowTemplate
		Template => WithFlowTemplate({ first, continuation: next, lead: NoLead })
		Scoped => WithScopedFlow({ template: { first, continuation: first, lead: NoLead }, scopes: [{ leaves: Semantics.Range.from_start_and_length(0, 5), opening: first, continuation: next }] })
	}
	theme : Theme
	theme = { body: { size: 11, leading: 14 }, page_margin: { top: 10, bottom: 10, left: 10, right: 10 } }
	page = { height: Layout.Unit.points(100), width: Layout.Unit.points(100) }
	limits = KernelFacadePages.Limits.make({ max_blocks: 10, max_rows: 100, page: KernelPageLayout.Limits.make({ max_blocks: 10, max_fragments: 10, max_lines: 100, max_pages: 10, max_placements: 100 }) })
	plan = KernelFacadePages.Measured.build(authoring, input, page, theme, flow, limits)?
	view = KernelFacadePages.Measured.view(plan)
	paint = KernelFacadePages.Measured.paint(plan, authoring, input, List.repeat(1000, 5), page, theme, limits)?
	repeated = paint.rows.keep_if(|row| row.artifact)
	Ok(KernelPageLayout.Choice.pages(view.choice).len() == 2 and KernelPageLayout.Choice.lead_bands(view.choice).is_empty() and repeated.len() == 1 and list_at(repeated, 0).page == 1 and list_at(repeated, 0).origin.y == Layout.Unit.points(if (kind == Plain) 79 else 59))
}

expect measured_header_frame_test(Plain) == Ok(True)
expect measured_header_frame_test(Template) == Ok(True)
expect measured_header_frame_test(Scoped) == Ok(True)

MeasuredRuleStyle : { gap : U64, padding : U64, rule : TableRuleStyle, body_rule : TableRuleStyle, column_rule : TableRuleStyle, frame : TableRuleStyle }

measured_rule_style : Theme -> Try(MeasuredRuleStyle, KernelFacadePages.Error)
measured_rule_style = |theme| {
	table_style = theme.table
	gap = nonnegative_raw(table_style.row_gap)?
	rule = match table_style.rule {
		NoRule => NoTableRule
		Rule({ color, width }) => {
			thickness = nonnegative_raw(width)?
			if thickness > gap {
				return Err(TableRuleWidth({ gap, rule: HeaderFooterRule, width: thickness }))
			}
			if (thickness == 0) NoTableRule else TableRule({ color, width: thickness })
		}
	}
	body_rule = match table_style.body_rule {
		NoRule => NoTableRule
		Rule({ color, width }) => {
			thickness = nonnegative_raw(width)?
			if thickness > gap {
				return Err(TableRuleWidth({ gap, rule: BodyRule, width: thickness }))
			}
			if (thickness == 0) NoTableRule else TableRule({ color, width: thickness })
		}
	}
	padding = nonnegative_raw(table_style.cell_padding)?
	column_rule = match table_style.column_rule {
		NoRule => NoTableRule
		Rule({ color, width }) => {
			thickness = nonnegative_raw(width)?
			if thickness > 2 * padding {
				return Err(TableRuleWidth({ gap: 2 * padding, rule: ColumnRule, width: thickness }))
			}
			if (thickness == 0) NoTableRule else TableRule({ color, width: thickness })
		}
	}
	frame = match table_style.frame {
		NoRule => NoTableRule
		Rule({ color, width }) => {
			thickness = nonnegative_raw(width)?
			room = U64.min(padding, gap / 2)
			if thickness > room {
				return Err(TableRuleWidth({ gap: room, rule: FrameRule, width: thickness }))
			}
			if (thickness == 0) NoTableRule else TableRule({ color, width: thickness })
		}
	}
	Ok({ gap, padding, rule, body_rule, column_rule, frame })
}

paint_measured : KernelFacadePages.MeasuredView, Document.NormalizedAuthoring, KernelFacadePages.MeasuredInput, List(U64), Layout.Size, Theme, KernelFacadePages.Limits -> Try(KernelFacadePages.MeasuredPaint, KernelFacadePages.Error)
paint_measured = |plan, authoring, input, advances, page_size, theme, limits| {
	style = measured_rule_style(theme)?
	gap = style.gap
	padding = style.padding
	margin_left = nonnegative_raw(theme.page_margin.left)?
	frame_top = checked_sub(positive_raw(page_size.height)?, nonnegative_raw(theme.page_margin.top)?)?
	default_page_top = checked_sub(frame_top, nonnegative_raw(plan.continuation_top)?)?
	page_frames = KernelPageLayout.Choice.page_frames(plan.choice)
	spans = KernelPageLayout.Choice.spans(plan.choice)
	leads = KernelPageLayout.Choice.lead_bands(plan.choice)
	var $lead = 0
	var $paints = []
	var $rules = []
	var $fills = []
	var $repeats = []
	var $splits = []
	var $sources = []
	var $repeated = 0
	var $blank = 0
	var $segment = NoSegment
	for page in KernelPageLayout.Choice.pages(plan.choice) {
		page_index = page.id.index()
		first_span = list_at(spans, page.spans.start())
		first_unit = first_span.block
		first_block = list_at(plan.blocks, first_unit)
		if nonnegative_raw(first_block.lead)? > 0 {
			while $lead < leads.len() and list_at(leads, $lead).page < page_index {
				$lead = $lead + 1
			}

			## Uncontained headers need only the declared/committed page frame;
			## active containers retain their padding-aware accepted lead band.
			selected_page_top = if (page_frames.is_empty()) default_page_top else checked_sub(frame_top, nonnegative_raw(list_at(page_frames, page_index).top)?)?
			page_top = if ($lead < leads.len() and list_at(leads, $lead).page == page_index) list_at(leads, $lead).top else selected_page_top
			info = list_at(plan.table_info, list_at(plan.row_info, first_unit).table)
			var $used = 0
			var $header = info.header_units.start()
			while $header < range_end(info.header_units)? {
				header_block = list_at(plan.blocks, $header)
				header_row = list_at(plan.row_info, $header)
				leading = positive_raw(header_block.leading)?
				baseline_offset = positive_raw(header_block.baseline_offset)?
				var $cell = header_row.cells.start()
				while $cell < range_end(header_row.cells)? {
					cell = list_at(input.cells, $cell)
					match list_at(input.blocks, cell.block) {
						ContentlessCell => {}
						MeasuredText(text) => {
							var $local = 0
							while $local < text.rows.length() {
								row = text.rows.start() + $local
								y = checked_sub(page_top, checked_add($used, checked_add(baseline_offset, checked_mul($local, leading)?)?)?)?
								x = checked_add(margin_left, measured_cell_offset(cell, list_at(advances, row))?)?
								check_limit(checked_add($paints.len(), 1)?, limits.max_rows, Rows)?
								$paints = $paints.append({ row, block: cell.block, origin: { x: Layout.Unit.from_raw(x.to_i64_wrap()), y: Layout.Unit.from_raw(y.to_i64_wrap()) }, page: page_index, artifact: True })
								$local = $local + 1
							}
						}
						_ => return Err(InvalidBlock({ block: cell.block }))
					}
					$cell = $cell + 1
				}
				row_top = checked_sub(page_top, $used)?
				row_bottom = checked_sub(row_top, checked_mul(header_row.grid, leading)?)?
				$fills = append_fill($fills, header_row.fill, page_index, { bottom: row_bottom, gap, top: row_top, width: info.width, x: margin_left + info.offset })
				$fills = append_cell_fills($fills, authoring, input.cells, header_row.cells, { bottom: row_bottom, gap, padding, page: page_index, top: row_top, x: margin_left + info.offset })
				$rules = append_column_rules($rules, style.column_rule, input.cells, header_row.cells, { bottom: row_bottom, gap, padding, page: page_index, top: row_top, x: margin_left + info.offset })
				$segment = extend_segment($segment, header_row.table, row_top, row_bottom, gap)
				$used = checked_add($used, checked_add(checked_mul(header_row.grid, leading)?, gap)?)?
				$header = $header + 1
			}
			$repeated = $repeated + info.header_units.length()
			$repeats = $repeats.append({ group: list_at(input.tables, list_at(plan.row_info, first_unit).table).group, page: page_index, rows: info.header_units.length() })
			$rules = append_rule($rules, style.rule, page_index, margin_left + info.offset, info.width, checked_sub(page_top, checked_sub($used, gap / 2)?)?)
		}
		var $index = page.spans.start()
		while $index < range_end(page.spans)? {
			span = list_at(spans, $index)
			unit = span.block
			unit_block = list_at(plan.blocks, unit)
			first_grid = span.rows.start() - unit_block.lines.start()
			taken = span.rows.length()
			match list_at(plan.units, unit) {
				LeafUnit(_) | SourceUnit(_) => {
					$rules = close_segment($rules, style.frame, $segment, page_index, margin_left, plan.table_info)
					$segment = NoSegment
					match list_at(plan.units, unit) {
						SourceUnit(source_id) => {
							source = list_at(authoring.sources, source_id)
							frame = list_at(input.source_frames, source_id)
							source_padding = nonnegative_raw(source.padding)?
							x = checked_sub(checked_add(margin_left, nonnegative_raw(frame.offset)?)?, source_padding)?
							y = checked_sub(nonnegative_raw(span.geometry.origin.y)?, source_padding)?
							rect = { origin: { x: Layout.Unit.from_raw(x.to_i64_wrap()), y: Layout.Unit.from_raw(y.to_i64_wrap()) }, size: { width: Layout.Unit.from_raw(checked_add(nonnegative_raw(frame.width)?, checked_mul(source_padding, 2)?)?.to_i64_wrap()), height: Layout.Unit.from_raw(checked_add(nonnegative_raw(span.geometry.size.height)?, checked_mul(source_padding, 2)?)?.to_i64_wrap()) } }
							is_first = first_grid == 0
							is_last = first_grid + taken == unit_block.lines.length()
							part = if (is_first and is_last) Whole else if (is_first) First else if (is_last) Last else Middle
							$sources = $sources.append({ source: source_id, page: page_index, lines: Semantics.Range.from_start_and_length(first_grid, taken), rect, part })
							match source.background {
								NoBackground => {}
								Background(color) => {
									$fills = $fills.append({ color, layer: Behind, page: page_index, rect })
								}
							}
						}
						_ => {}
					}
					var $local = 0
					while $local < taken {
						grid = list_at(plan.grid_rows, span.rows.start() + $local)
						y = checked_sub(nonnegative_raw(span.baseline.y)?, checked_mul($local, positive_raw(span.leading)?)?)?
						match grid {
							NoTextRow(_) => {
								$blank = $blank + 1
							}
							BodyRow(row) => {
								match row.label {
									NoLabel => {}
									Label(label) => {
										x = checked_add(margin_left, nonnegative_raw(label.offset)?)?
										check_limit(checked_add($paints.len(), 1)?, limits.max_rows, Rows)?
										$paints = $paints.append({ row: label.row, block: row.block, origin: { x: Layout.Unit.from_raw(x.to_i64_wrap()), y: Layout.Unit.from_raw(y.to_i64_wrap()) }, page: page_index, artifact: False })
									}
								}
								x = checked_add(margin_left, nonnegative_raw(row.offset)?)?
								check_limit(checked_add($paints.len(), 1)?, limits.max_rows, Rows)?
								$paints = $paints.append({ row: row.row, block: row.block, origin: { x: Layout.Unit.from_raw(x.to_i64_wrap()), y: Layout.Unit.from_raw(y.to_i64_wrap()) }, page: page_index, artifact: False })
							}
							TableGrid => return Err(InvalidBlock({ block: unit }))
						}
						$local = $local + 1
					}
				}
				RowUnit(row_group) => {
					info = list_at(plan.row_info, unit)
					if first_grid > 0 {
						$splits = $splits.append({ group: row_group, page: page_index })
					}
					var $cell = info.cells.start()
					while $cell < range_end(info.cells)? {
						cell = list_at(input.cells, $cell)
						match list_at(input.blocks, cell.block) {
							ContentlessCell => {}
							MeasuredText(text) => {
								var $grid = first_grid
								while $grid < first_grid + taken and $grid < text.rows.length() {
									row = text.rows.start() + $grid
									y = checked_sub(nonnegative_raw(span.baseline.y)?, checked_mul($grid - first_grid, positive_raw(span.leading)?)?)?
									x = checked_add(margin_left, measured_cell_offset(cell, list_at(advances, row))?)?
									check_limit(checked_add($paints.len(), 1)?, limits.max_rows, Rows)?
									$paints = $paints.append({ row, block: cell.block, origin: { x: Layout.Unit.from_raw(x.to_i64_wrap()), y: Layout.Unit.from_raw(y.to_i64_wrap()) }, page: page_index, artifact: False })
									$grid = $grid + 1
								}
							}
							_ => return Err(InvalidBlock({ block: cell.block }))
						}
						$cell = $cell + 1
					}
					info_table = list_at(plan.table_info, info.table)
					table_width = info_table.width
					table_x = margin_left + info_table.offset
					bottom = nonnegative_raw(span.geometry.origin.y)?
					top = checked_add(bottom, nonnegative_raw(span.geometry.size.height)?)?
					$fills = append_fill($fills, info.fill, page_index, { bottom, gap, top, width: table_width, x: table_x })
					$fills = append_cell_fills($fills, authoring, input.cells, info.cells, { bottom, gap, padding, page: page_index, top, x: table_x })
					$rules = append_column_rules($rules, style.column_rule, input.cells, info.cells, { bottom, gap, padding, page: page_index, top, x: table_x })
					$rules = close_other_segment($rules, style.frame, $segment, info.table, { page: page_index, tables: plan.table_info, x: margin_left })
					$segment = extend_segment($segment, info.table, top, bottom, gap)
					if info.body_rule and first_grid == 0 and $index > page.spans.start() {
						$rules = append_rule($rules, style.body_rule, page_index, table_x, table_width, checked_add(top, gap / 2)?)
					}
					if info.rule_below and first_grid + taken == info.grid {
						$rules = append_rule($rules, style.rule, page_index, table_x, table_width, checked_sub(bottom, gap / 2)?)
					}
					if info.rule_above and first_grid == 0 and $index > page.spans.start() {
						$rules = append_rule($rules, style.rule, page_index, table_x, table_width, checked_add(top, gap / 2)?)
					}
				}
			}
			$index = $index + 1
		}
		$rules = close_segment($rules, style.frame, $segment, page_index, margin_left, plan.table_info)
		$segment = NoSegment
	}
	decorations = decoration_paints(authoring, KernelPageLayout.Choice.bands(plan.choice), plan.unit_of_block, margin_left)?
	panels = measured_custom_panels(authoring, plan)?
	callouts = KernelPageLayout.Choice.container_fragments(plan.choice)
	Ok({ rows: $paints, rules: merge_callout_rules(callout_rules(authoring, callouts), behind_first($fills, $rules)), flow: { decorations, figure_scales: plan.flow.scales, panels }, repeats: $repeats, splits: $splits, source_fragments: $sources, callout_fragments: callouts, work: { blank_rows: $blank, repeated_header_paints: $repeated } })
}

measured_cell_offset : KernelFacadeTables.CellGeometry, U64 -> Try(U64, KernelFacadePages.Error)
measured_cell_offset = |cell, advance| {
	if advance > cell.width {
		return Err(InvalidLine({ block: cell.block, line: 0 }))
	}
	slack = cell.width - advance
	align = match cell.align {
		Start => 0
		End => slack
		Center => slack // 2
	}
	checked_add(cell.offset, checked_add(cell.x, align)?)
}

measured_custom_panels : Document.NormalizedAuthoring, KernelFacadePages.MeasuredView -> Try(List(KernelFacadePages.PanelPaint), KernelFacadePages.Error)
measured_custom_panels = |authoring, plan| {
	var $out = []
	var $index = 0
	var $span = 0
	spans = KernelPageLayout.Choice.spans(plan.choice)
	for custom in authoring.customs {
		leaf = list_at(authoring.groups, custom.group).first_block
		unit = list_at(plan.unit_of_block, leaf)
		while $span < spans.len() and list_at(spans, $span).block < unit {
			$span = $span + 1
		}
		if $span >= spans.len() or list_at(spans, $span).block != unit {
			return Err(InvalidBlock({ block: leaf }))
		}
		span = list_at(spans, $span)
		top = checked_add(nonnegative_raw(span.geometry.origin.y)?, checked_add(nonnegative_raw(span.geometry.size.height)?, nonnegative_raw(custom.inset)?)?)?
		bottom = checked_sub(top, nonnegative_raw(custom.height)?)?
		$out = $out.append({ custom: $index, origin: { x: span.geometry.origin.x, y: Layout.Unit.from_raw(bottom.to_i64_wrap()) }, page: span.page.index() })
		$index = $index + 1
	}
	Ok($out)
}
