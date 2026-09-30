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
		TableRuleWidth({ gap : U64, width : U64 }),
	]
	Limits :: { max_blocks : U64, max_rows : U64, page : KernelPageLayout.Limits }.{
		make : { max_blocks : U64, max_rows : U64, page : KernelPageLayout.Limits } -> Limits
		make = |limits| Limits.(limits)
	}

	## One painted row: a body line at `body_offset` from the flow edge, the
	## logical run it belongs to (its explicit-line-break segment when the
	## body has several), and an optional generated label at `offset`.
	Row : {
		body_line : U64,
		body_offset : Layout.Unit,
		body_runs : KernelFacadeShape.LogicalRun,
		label : [Label({ line : U64, offset : Layout.Unit, runs : KernelFacadeShape.LogicalRun }), NoLabel],
	}

	## A page-layout unit of a document with tables: one leaf block, or one
	## table row (its row group), whose cells stand side by side.
	Unit : [LeafUnit(U64), RowUnit(U64)]

	## The source of one required page-layout group of a document with
	## tables: the `k`-th authored `keep_together` in preorder, or a table's
	## footer rows (their first and last row groups).
	KeepSource : [AuthoredKeep(U64), FooterRows({ first : U64, last : U64 })]

	## Page-template flow geometry: the first page's and every later page's
	## flow frame, and the first page's lead region receiving the first
	## `leaves` normalized leaf blocks (the lead region's group).
	FlowTemplate : { continuation : KernelPageLayout.Frame, first : KernelPageLayout.Frame, lead : [Lead({ frame : KernelPageLayout.Frame, leaves : U64 }), NoLead] }

	## A table rule: a filled rectangle on a page, painted as a layout
	## decoration artifact in the theme's rule color.
	Rule : { color : Color.SourceValue, page : U64, rect : Layout.Rect }

	## One placed in-flow decoration: its index in the normalized
	## decorations, its page, and its drawing's bottom-left corner.
	DecorationPaint : { decoration : U64, origin : Layout.Point, page : U64 }

	## The flow drawings' layout facts: each figure's uniform scale in
	## thousandths (1000 unless `ScaleToFit` reduced it), and every placed
	## decoration in document order.
	FlowPaints : { decorations : List(DecorationPaint), figure_scales : List(U64) }

	Work : {
		block_planning_visits : U64,
		block_writes : U64,
		label_rows : U64,
		page : KernelPageLayout.Work,
		repeated_header_paints : U64,
		row_writes : U64,
	}

	## `placed` is `FromLayout` when every row is one page-layout line and
	## the page layout's own pages and placements apply; a document with
	## tables rebuilds them, one placement per painted cell line, and names
	## its repeated-header rows (ascending row indexes) in `artifact_rows`.
	Plan :: {
		artifact_rows : List(U64),
		flow : FlowPaints,
		page : KernelPageLayout.Plan,
		placed : [FromLayout, Rebuilt({ pages : List(KernelPageLayout.Page), placements : List(KernelPageLayout.PlacedLine) })],
		rows : List(Row),
		rules : List(Rule),
		units : List(Unit),
		work : Work,
	}.{
		build : Document.NormalizedAuthoring, KernelFacadeShape.Plan, KernelFacadeLines.Plan, Layout.Size, Theme, Limits -> Try(Plan, Error)
		build = |authoring, shape, lines, page, theme, limits| build_plan(authoring, shape, lines, page, theme, NoFlowTemplate, limits)

		## Pagination under page templates: per-page flow frames and the
		## first page's lead region. The frames come from the templates'
		## fixed region heights alone, never from painted furniture.
		build_with_template : Document.NormalizedAuthoring, KernelFacadeShape.Plan, KernelFacadeLines.Plan, Layout.Size, Theme, FlowTemplate, Limits -> Try(Plan, Error)
		build_with_template = |authoring, shape, lines, page, theme, template, limits| build_plan(authoring, shape, lines, page, theme, WithFlowTemplate(template), limits)

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
FlowSelection : [NoFlowTemplate, WithFlowTemplate(KernelFacadePages.FlowTemplate)]

build_plan : Document.NormalizedAuthoring, KernelFacadeShape.Plan, KernelFacadeLines.Plan, Layout.Size, Theme, FlowSelection, KernelFacadePages.Limits -> Try(KernelFacadePages.Plan, KernelFacadePages.Error)
build_plan = |authoring, shape, line_plan, page_size, theme, flow, limits| {
	match KernelFacadeLines.Plan.geometry(line_plan) {
		WithTables(tables) => return build_table_plan(authoring, shape, line_plan, page_size, theme, flow, limits, tables)
		NoTables => {}
	}
	block_lines = KernelFacadeLines.Plan.blocks(line_plan)
	block_runs = KernelFacadeShape.Plan.block_runs(shape)
	styles = KernelFacadeShape.Plan.styles(shape)
	shape_requests = KernelFacadeShape.Plan.requests(shape)
	shape_batch = KernelFacadeShape.Plan.shape(shape)
	line_batch = KernelFacadeLines.Plan.line(line_plan)
	lines = KernelLineLayout.BatchPlan.lines(line_batch)
	if authoring.blocks.len() == 0 or authoring.blocks.len() != block_lines.len() or block_lines.len() != block_runs.len() or styles.len() != shape_batch.store.runs.len() {
		return Err(InvalidBlock({ block: 0 }))
	}
	check_limit(authoring.blocks.len(), limits.max_blocks, Blocks)?
	check_page_breaks(authoring.page_breaks, authoring.blocks.len(), lead_leaves(flow))?
	author_keeps = authored_keeps(authoring.groups, authoring.blocks.len())
	flow_facts = plan_flow(authoring, block_lines, page_size, theme, flow)?
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
				assert_logical_identity(shape_batch.store.runs, styles, body_run, $block_index)?
				body_record = list_at(shape_batch.store.runs, body_index)
				body_style = list_at(styles, body_index)
				segmented = list_at(shape_requests, body_index).source.index() != list_at(shape_requests, body_index + body_run.physical.length() - 1).source.index()
				visual_start = $visual_lines.len()
				var $segment_start = body_index
				var $segment_length = if segmented segment_length(shape_requests, body_index, body_index + body_run.physical.length()) else body_run.physical.length()
				var $local = 0
				while $local < body_lines.lines.length() {
					body_line_index = body_lines.lines.start() + $local
					label = if $local == 0 {
						match (label_lines, label_run) {
							(NoLabel, NoLabel) => NoLabel
							(Label(label_range), Label(label_id)) => {
								_label_index = logical_run_first(label_id, $block_index, shape_batch.store.runs.len())?
								assert_logical_identity(shape_batch.store.runs, styles, label_id, $block_index)?
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

					## A line belongs to the explicit-line-break segment whose
					## physical runs hold its first cluster.
					if segmented {
						while $segment_start + $segment_length < body_index + body_run.physical.length() and line.clusters.start() >= segment_cluster_end(shape_batch.store.runs, $segment_start, $segment_length)? {
							$segment_start = $segment_start + $segment_length
							$segment_length = segment_length(shape_requests, $segment_start, body_index + body_run.physical.length())
						}
					}
					runs = if segmented { physical: Semantics.Range.from_start_and_length($segment_start, $segment_length) } else body_run
					$visual_lines = $visual_lines.append(line)
					$rows = $rows.append({ body_line: body_line_index, body_offset, body_runs: runs, label })
					$local = $local + 1
				}
				minimum = U64.min(2, body_lines.lines.length())
				theme_keep = keeps_with_next(author_block.kind) and $block_index + 1 < block_lines.len()
				authored = if author_keeps.is_empty() NoKeep else list_at(author_keeps, $block_index)
				keep_with_next = match authored {
					Required => Required
					_ => if theme_keep Preferred(HeadingKeep) else authored
				}
				spacing = if continues_list(authoring, block_runs, $block_index, level) 0 else nonnegative_raw(Theme.paragraph_spacing(theme))?
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
							baseline_offset: body_record.size,
							decoration: Layout.Unit.from_raw(0),
							lead: Layout.Unit.from_raw(0),
							leading: body_style.leading,
							lines: Semantics.Range.from_start_and_length(visual_start, body_lines.lines.length()),
							occurrence: semantic_occurrence(body_record, $block_index, body_index)?,
							policy: {
								break_before,
								keep_together: keeps_together(author_block.kind),
								keep_with_next,
								minimum_first_lines: minimum,
								minimum_last_lines: minimum,
							},
							space_after: Layout.Unit.from_raw(checked_add(spacing, spaced.amount)?.to_i64_wrap()),
						},
					),
				)
			}
		}
		$block_index = $block_index + 1
	}
	if $visual_lines.len() != $row_count or $rows.len() != $row_count {
		return Err(InvalidBlock({ block: block_lines.len() }))
	}
	keep_groups = together_groups(authoring.groups)
	constraints = { margins: Theme.page_margin(theme), page: page_size }
	page = match flow {
		NoFlowTemplate => (
			if keep_groups.is_empty() {
				KernelPageLayout.Plan.build($page_blocks, $visual_lines, constraints, limits.page)
			} else {
				KernelPageLayout.Plan.build_with_groups($page_blocks, keep_groups, $visual_lines, constraints, limits.page)
			}
		) ? PageLayout
		WithFlowTemplate(template) => {
			leaves = lead_leaves(flow)
			KernelPageLayout.Plan.build_with_template(lead_policies($page_blocks, leaves), flow_groups(keep_groups, leaves), $visual_lines, constraints, layout_template(template, leaves), limits.page) ? PageLayout
		}
	}
	decorations = decoration_paints(authoring, KernelPageLayout.Plan.bands(page), [], nonnegative_raw(Theme.page_margin(theme).left)?)?
	Ok(
		KernelFacadePages.Plan.{
			artifact_rows: [],
			flow: { decorations, figure_scales: flow_facts.scales },
			page,
			placed: FromLayout,
			rows: $rows,
			rules: [],
			units: [],
			work: {
				block_planning_visits: block_lines.len(),
				block_writes: $page_blocks.len(),
				label_rows: $label_rows,
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
RowInfo : { cells : Semantics.Range, grid : U64, rule_above : Bool, rule_below : Bool, table : U64 }

## One table's repeat facts: its header row units, the height they and the
## gap after them reserve on a continuation page, and its width.
TableInfo : { header_height : U64, header_units : Semantics.Range, width : U64 }

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
	table_style = Theme.table_style(theme)
	gap = nonnegative_raw(table_style.row_gap)?
	rule = match table_style.rule {
		NoRule => NoTableRule
		Rule({ color, width }) => {
			thickness = nonnegative_raw(width)?
			if thickness > gap {
				return Err(TableRuleWidth({ gap, width: thickness }))
			}
			if thickness == 0 NoTableRule else TableRule({ color, width: thickness })
		}
	}
	paragraph_spacing = nonnegative_raw(Theme.paragraph_spacing(theme))?
	flow_facts = plan_flow(authoring, block_lines, page_size, theme, flow)?
	cell_geometry = KernelFacadeTables.Plan.cells(tables)
	table_geometry = KernelFacadeTables.Plan.tables(tables)
	table_sources = KernelFacadeTables.Plan.sources(tables)
	synthetic = { advance: Layout.Unit.from_raw(0), clusters: Semantics.Range.from_start_and_length(0, 0), source: { scalars: Semantics.Range.from_start_and_length(0, 0), utf8_bytes: Semantics.Range.from_start_and_length(0, 0) } }
	dummy_row = { body_line: 0, body_offset: Layout.Unit.from_raw(0), body_runs: { physical: Semantics.Range.from_start_and_length(0, 0) }, label: NoLabel }
	no_row = { cells: Semantics.Range.from_start_and_length(0, 0), grid: 0, rule_above: False, rule_below: False, table: 0 }
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
	var $label_rows = 0
	var $break_cursor = 0
	var $spacer_cursor = 0
	var $table_cursor = 0
	var $cell_cursor = 0
	var $block_index = 0
	while $block_index < blocks.len() {
		table_start = if $table_cursor < table_geometry.len() list_at(authoring.groups, list_at(table_geometry, $table_cursor).group).first_block == $block_index else False
		if table_start {
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
					{ block_lines, block_runs, lines, shape_batch, shape_requests, styles },
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
				var $block = row.first_block
				while $block < row.block_end {
					geometry = list_at(cell_geometry, $cell_cursor)
					match (list_at(block_lines, $block), list_at(block_runs, $block)) {
						(TextBlock({ body: body_lines, body_offset: _, label: _ }), TextBlock({ body: body_run, label: _, level: _ })) => {
							body_index = logical_run_first(body_run, $block, shape_batch.store.runs.len())?
							assert_logical_identity(shape_batch.store.runs, styles, body_run, $block)?
							record = list_at(shape_batch.store.runs, body_index)
							style = list_at(styles, body_index)
							if $block == row.first_block {
								$leading = positive_raw(style.leading)?
								$size = positive_raw(record.size)?
								$occurrence = semantic_occurrence(record, $block, body_index)?
							} else if positive_raw(style.leading)? != $leading or positive_raw(record.size)? != $size {
								return Err(InvalidRun({ block: $block, run: body_index }))
							}
							$cell_starts = $cell_starts.append($cell_rows.len())
							$cell_rows = append_cell_rows($cell_rows, { body_lines: body_lines.lines, body_run, geometry, lines, requests: shape_requests, sources: table_sources, store: shape_batch.store }, $block)?
							$grid = U64.max($grid, body_lines.lines.length())
						}
					}
					$unit_of_block = list_set($unit_of_block, $block, $units.len())
					$cell_cursor = $cell_cursor + 1
					$block = $block + 1
				}
				if $grid == 0 {
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
				last_body = section == Body and ($row_group + 1 == group.group_end or (match list_at(authoring.groups, $row_group + 1).kind {
					TableRow(Footer) => True
					_ => False
				}))
				first_footer = section == Footer and (match list_at(authoring.groups, $row_group - 1).kind {
					TableRow(Footer) => False
					_ => True
				})
				last_header = section == Header and (match list_at(authoring.groups, $row_group + 1).kind {
					TableRow(Header) => False
					_ => True
				})
				authored = if author_keeps.is_empty() NoKeep else list_at(author_keeps, row.block_end - 1)
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
				lead = if section != Header and table.header_rows > 0 $header_height else 0
				minimum = U64.min(2, $grid)
				$units = $units.append(RowUnit($row_group))
				$row_info = $row_info.append({ cells: Semantics.Range.from_start_and_length(first_cell, $cell_cursor - first_cell), grid: $grid, rule_above: first_footer, rule_below: last_header, table: $table_cursor })
				$page_blocks = $page_blocks.append({
					baseline_offset: Layout.Unit.from_raw($size.to_i64_wrap()),
					decoration: leaf_decoration(flow_facts, row.first_block),
					lead: Layout.Unit.from_raw(lead.to_i64_wrap()),
					leading: Layout.Unit.from_raw($leading.to_i64_wrap()),
					lines: Semantics.Range.from_start_and_length(visual_start, $grid),
					occurrence: $occurrence,
					policy: {
						break_before: $pending_break,
						keep_together: section != Body or table.row_split == KeepRows,
						keep_with_next,
						minimum_first_lines: minimum,
						minimum_last_lines: minimum,
					},
					space_after: Layout.Unit.from_raw(spacing.to_i64_wrap()),
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
			$table_info = $table_info.append({ header_height: $header_height, header_units: Semantics.Range.from_start_and_length(header_first, table.header_rows), width: list_at(table_geometry, $table_cursor).width })
			$table_cursor = $table_cursor + 1
			$block_index = group.block_end
		} else {
			author_block = list_at(blocks, $block_index)
			placed = table_leaf_unit(
				{ block_lines, block_runs, lines, shape_batch, shape_requests, styles },
				$block_index,
				{ lines: $visual_lines, rows: $line_rows },
			)?
			$visual_lines = placed.lines
			$line_rows = placed.rows
			$label_rows = $label_rows + placed.labels
			theme_keep = keeps_with_next(author_block.kind) and $block_index + 1 < blocks.len()
			authored = if author_keeps.is_empty() NoKeep else list_at(author_keeps, $block_index)
			keep_with_next = match authored {
				Required => Required
				_ => if theme_keep Preferred(HeadingKeep) else authored
			}
			level = match list_at(block_runs, $block_index) {
				TextBlock({ body: _, label: _, level: value }) => value
			}
			spacing = if continues_list(authoring, block_runs, $block_index, level) 0 else paragraph_spacing
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
	merged = merge_groups(unit_groups(authoring.groups, $unit_of_block), $footer_groups, $footer_sources)
	constraints = { margins: Theme.page_margin(theme), page: page_size }
	page = match flow {
		NoFlowTemplate => (
			if merged.groups.is_empty() {
				KernelPageLayout.Plan.build($page_blocks, $visual_lines, constraints, limits.page)
			} else {
				KernelPageLayout.Plan.build_with_groups($page_blocks, merged.groups, $visual_lines, constraints, limits.page)
			}
		) ? |error| TableLayout({ error, groups: merged.sources, units: $units })
		WithFlowTemplate(template) => {
			leaves = lead_leaves(flow)
			units = if leaves == 0 0 else list_at($unit_of_block, leaves - 1) + 1
			KernelPageLayout.Plan.build_with_template(lead_policies($page_blocks, units), flow_groups(merged.groups, units), $visual_lines, constraints, layout_template(template, units), limits.page) ? |error| TableLayout({ error, groups: merged.sources, units: $units })
		}
	}

	## Rebuild the placements: one per painted cell line and leaf line, with
	## each continued table's header rows repainted first as artifacts.
	margins = Theme.page_margin(theme)
	frame_top = checked_sub(positive_raw(page_size.height)?, nonnegative_raw(margins.top)?)?

	## A continued table repaints its header rows at the top of a later
	## page's flow region, which a continuation template may move down.
	page_top = match flow {
		NoFlowTemplate => frame_top
		WithFlowTemplate(template) => checked_sub(frame_top, nonnegative_raw(template.continuation.top)?)?
	}
	margin_left = nonnegative_raw(margins.left)?
	layout_pages = KernelPageLayout.Plan.pages(page)
	layout_fragments = KernelPageLayout.Plan.fragments(page)
	layout_placements = KernelPageLayout.Plan.placements(page)
	var $rows = List.with_capacity($cell_rows.len() + $line_rows.len())
	var $placements = List.with_capacity($cell_rows.len() + $line_rows.len())
	var $pages = List.with_capacity(layout_pages.len())
	var $artifact_rows = []
	var $rules = []
	var $repeated = 0
	var $unit = 0
	var $placement_cursor = 0
	for layout_page in layout_pages {
		page_index = layout_page.id.index()
		placement_start = $placements.len()
		first_fragment = layout_page.fragments.start()
		fragment_end = first_fragment + layout_page.fragments.length()
		first = list_at(layout_fragments, first_fragment)
		while range_end(list_at($page_blocks, $unit).lines)? <= first.lines.start() {
			$unit = $unit + 1
		}
		lead_unit = list_at($page_blocks, $unit)
		if nonnegative_raw(lead_unit.lead)? > 0 {
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
				$used = checked_add($used, checked_add(checked_mul(header_row.grid, leading)?, gap)?)?
				$header = $header + 1
			}
			$repeated = $repeated + info.header_units.length()
			$rules = append_rule($rules, rule, page_index, margin_left, info.width, checked_sub(page_top, checked_sub($used, gap / 2)?)?)
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
					var $local = 0
					while $local < taken {
						placed = list_at(layout_placements, $placement_cursor + $local)
						$placements = $placements.append({ ..placed, line: $rows.len() })
						$rows = $rows.append(list_at($line_rows, fragment.lines.start() + $local))
						$local = $local + 1
					}
				}
				RowUnit(_) => {
					info = list_at($row_info, $unit)
					first_grid = fragment.lines.start() - unit_block.lines.start()
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
					bottom = fragment.layout.geometry.origin.y.raw().to_u64_wrap()
					if info.rule_below and first_grid + taken == info.grid {
						$rules = append_rule($rules, rule, page_index, margin_left, table_width, checked_sub(bottom, gap / 2)?)
					}
					if info.rule_above and first_grid == 0 and $fragment > first_fragment {
						top = checked_add(bottom, fragment.layout.geometry.size.height.raw().to_u64_wrap())?
						$rules = append_rule($rules, rule, page_index, margin_left, table_width, checked_add(top, gap / 2)?)
					}
				}
			}
			$placement_cursor = $placement_cursor + taken
			$fragment = $fragment + 1
		}
		$pages = $pages.append({ ..layout_page, placements: Semantics.Range.from_start_and_length(placement_start, $placements.len() - placement_start) })
	}
	check_limit($rows.len(), limits.max_rows, Rows)?
	decorations = decoration_paints(authoring, KernelPageLayout.Plan.bands(page), $unit_of_block, margin_left)?
	Ok(
		KernelFacadePages.Plan.{
			artifact_rows: $artifact_rows,
			flow: { decorations, figure_scales: flow_facts.scales },
			page,
			placed: Rebuilt({ pages: $pages, placements: $placements }),
			rows: $rows,
			rules: $rules,
			units: $units,
			work: {
				block_planning_visits: block_lines.len(),
				block_writes: $page_blocks.len(),
				label_rows: $label_rows,
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
table_leaf_unit : { block_lines : List(KernelFacadeLines.BlockLines), block_runs : List(KernelFacadeShape.BlockRuns), lines : List(KernelLineLayout.Line), shape_batch : KernelShape.Batch, shape_requests : List(KernelShape.SimpleRequest), styles : List(KernelFacadeShape.RunStyle) }, U64, { lines : List(KernelLineLayout.Line), rows : List(KernelFacadePages.Row) } -> Try({ block : KernelPageLayout.Block, labels : U64, lines : List(KernelLineLayout.Line), minimum : U64, rows : List(KernelFacadePages.Row) }, KernelFacadePages.Error)
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
			assert_logical_identity(shape_batch.store.runs, at.styles, body_run, block_index)?
			body_record = list_at(shape_batch.store.runs, body_index)
			body_style = list_at(at.styles, body_index)
			segmented = list_at(at.shape_requests, body_index).source.index() != list_at(at.shape_requests, body_index + body_run.physical.length() - 1).source.index()
			visual_start = buffers.lines.len()
			var $visual_lines = buffers.lines
			var $rows = buffers.rows
			var $labels = 0
			var $segment_start = body_index
			var $segment_length = if segmented segment_length(at.shape_requests, body_index, body_index + body_run.physical.length()) else body_run.physical.length()
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
						$segment_length = segment_length(at.shape_requests, $segment_start, body_index + body_run.physical.length())
					}
				}
				runs = if segmented { physical: Semantics.Range.from_start_and_length($segment_start, $segment_length) } else body_run
				$visual_lines = $visual_lines.append(line)
				$rows = $rows.append({ body_line: body_line_index, body_offset, body_runs: runs, label })
				$local = $local + 1
			}
			Ok({
				block: {
					baseline_offset: body_record.size,
					decoration: Layout.Unit.from_raw(0),
					lead: Layout.Unit.from_raw(0),
					leading: body_style.leading,
					lines: Semantics.Range.from_start_and_length(visual_start, body_lines.lines.length()),
					occurrence: semantic_occurrence(body_record, block_index, body_index)?,
					policy: { break_before: False, keep_together: False, keep_with_next: NoKeep, minimum_first_lines: 1, minimum_last_lines: 1 },
					space_after: Layout.Unit.from_raw(0),
				},
				labels: $labels,
				lines: $visual_lines,
				minimum: U64.min(2, body_lines.lines.length()),
				rows: $rows,
			})
		}
	}
}

## One row per line of a cell: its body line, its explicit-line-break
## segment's runs, and its offset from the flow edge, which aligns the
## line's visible advance inside the cell's text box. A line that ends at a
## soft break carries the spaces before it in its advance; end and center
## alignment measure the line without them.
append_cell_rows : List(KernelFacadePages.Row), { body_lines : Semantics.Range, body_run : KernelFacadeShape.LogicalRun, geometry : KernelFacadeTables.CellGeometry, lines : List(KernelLineLayout.Line), requests : List(KernelShape.SimpleRequest), sources : List(KernelFacadeSources.Source), store : Text.Store }, U64 -> Try(List(KernelFacadePages.Row), KernelFacadePages.Error)
append_cell_rows = |rows, at, block| {
	body_run = at.body_run
	body_index = body_run.physical.start()
	body_end = body_index + body_run.physical.length()
	segmented = list_at(at.requests, body_index).source.index() != list_at(at.requests, body_end - 1).source.index()
	var $rows = rows
	var $segment_start = body_index
	var $segment_length = if segmented segment_length(at.requests, body_index, body_end) else body_run.physical.length()
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
				$segment_length = segment_length(at.requests, $segment_start, body_end)
			}
		}
		runs = if segmented { physical: Semantics.Range.from_start_and_length($segment_start, $segment_length) } else body_run
		offset = match at.geometry.align {
			Start => at.geometry.x
			alignment => {
				source = list_at(at.sources, list_at(at.requests, $segment_start).source.index()).unicode
				advance = visible_advance(at.store, line, source)?
				slack = if advance < at.geometry.width at.geometry.width - advance else 0
				if alignment == End at.geometry.x + slack else at.geometry.x + slack // 2
			}
		}
		$rows = $rows.append({ body_line: line_index, body_offset: Layout.Unit.from_raw(offset.to_i64_wrap()), body_runs: runs, label: NoLabel })
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
				$advance = if width > $advance 0 else $advance - width
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
	end = if cell + 1 < starts.len() list_at(starts, cell + 1) else total
	end - start
}

## A rule rectangle centered on `center` (a y coordinate) across the table.
append_rule : List(KernelFacadePages.Rule), TableRuleStyle, U64, U64, U64, U64 -> List(KernelFacadePages.Rule)
append_rule = |rules, rule, page, x, width, center| match rule {
	NoTableRule => rules
	TableRule({ color, width: thickness }) => {
		bottom = if center > thickness / 2 center - thickness / 2 else 0
		rules.append({
			color,
			page,
			rect: {
				origin: { x: Layout.Unit.from_raw(x.to_i64_wrap()), y: Layout.Unit.from_raw(bottom.to_i64_wrap()) },
				size: { height: Layout.Unit.from_raw(thickness.to_i64_wrap()), width: Layout.Unit.from_raw(width.to_i64_wrap()) },
			},
		})
	}
}

## Authored keep-together groups, from leaf ranges to unit ranges.
unit_groups : List(Document.NormalizedGroup), List(U64) -> List(KernelPageLayout.KeepGroup)
unit_groups = |groups, unit_of_block| {
	var $together = []
	for group in groups {
		match group.kind {
			KeepTogether => {
				first = list_at(unit_of_block, group.first_block)
				last = list_at(unit_of_block, group.block_end - 1)
				$together = $together.append({ blocks: Semantics.Range.from_start_and_length(first, last + 1 - first) })
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
	if raw <= 0 Err(InvalidBlock({ block: 0 })) else Ok(raw.to_u64_wrap())
}

checked_sub : U64, U64 -> Try(U64, KernelFacadePages.Error)
checked_sub = |left, right| if right > left Err(ArithmeticOverflow) else Ok(left - right)

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

## Required keep-together groups in preorder, for page layout.
together_groups : List(Document.NormalizedGroup) -> List(KernelPageLayout.KeepGroup)
together_groups = |groups| {
	var $together = []
	for group in groups {
		match group.kind {
			KeepTogether => {
				$together = $together.append({ blocks: Semantics.Range.from_start_and_length(group.first_block, group.block_end - group.first_block) })
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
## source: one explicit-line-break segment of a body.
segment_length : List(KernelShape.SimpleRequest), U64, U64 -> U64
segment_length = |requests, start, end| {
	source = list_at(requests, start).source.index()
	var $index = start + 1
	while $index < end and list_at(requests, $index).source.index() == source {
		$index = $index + 1
	}
	$index - start
}

segment_cluster_end : List(Text.Run), U64, U64 -> Try(U64, KernelFacadePages.Error)
segment_cluster_end = |runs, start, length| range_end(list_at(runs, start + length - 1).clusters)

nonnegative_raw : Layout.Unit -> Try(U64, KernelFacadePages.Error)
nonnegative_raw = |value| {
	raw = value.raw()
	if raw < 0 Err(InvalidBlock({ block: 0 })) else Ok(raw.to_u64_wrap())
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

## Every physical run of one logical run must carry the identical size and
## leading: pagination treats the logical run as one row source regardless
## of its face or occurrence split. Fill colors may differ between the
## occurrences of a rich paragraph; they are paint facts, not row geometry.
assert_logical_identity : List(Text.Run), List(KernelFacadeShape.RunStyle), KernelFacadeShape.LogicalRun, U64 -> Try({}, KernelFacadePages.Error)
assert_logical_identity = |runs, styles, logical, block| {
	start = logical.physical.start()
	length = logical.physical.length()
	if start >= runs.len() or length > runs.len() - start or start >= styles.len() or length > styles.len() - start {
		return Err(InvalidRun({ block, run: start }))
	}
	first = list_at(runs, start)
	first_style = list_at(styles, start)
	var $index = start + 1
	while $index < start + length {
		run = list_at(runs, $index)
		if run.size.raw() != first.size.raw() or list_at(styles, $index).leading.raw() != first_style.leading.raw() {
			return Err(InvalidRun({ block, run: $index }))
		}
		$index = $index + 1
	}
	Ok({})
}

keeps_together : Document.NormalizedBlockKind -> Bool
keeps_together = |kind| match kind {
	Figure(_) | FigureCaption(_) | Heading(_) | Title => True
	_ => False
}

keeps_with_next : Document.NormalizedBlockKind -> Bool
keeps_with_next = |kind| match kind {
	Heading(_) | Title => True
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
plan_flow : Document.NormalizedAuthoring, List(KernelFacadeLines.BlockLines), Layout.Size, Theme, FlowSelection -> Try(FlowFacts, KernelFacadePages.Error)
plan_flow = |authoring, block_lines, page_size, theme, flow| {
	if authoring.figures.is_empty() and authoring.decorations.is_empty() {
		return Ok({ decorations: [], heights: [], scales: [] })
	}
	margins = Theme.page_margin(theme)
	width = checked_sub(nonnegative_raw(page_size.width)?, checked_add(nonnegative_raw(margins.left)?, nonnegative_raw(margins.right)?)?)?
	body_height = checked_sub(nonnegative_raw(page_size.height)?, checked_add(nonnegative_raw(margins.top)?, nonnegative_raw(margins.bottom)?)?)?
	frames = match flow {
		NoFlowTemplate => { largest: body_height, smallest: body_height }
		WithFlowTemplate(template) => {
			first = nonnegative_raw(template.first.height)?
			continuation = nonnegative_raw(template.continuation.height)?
			{ largest: U64.max(first, continuation), smallest: U64.min(first, continuation) }
		}
	}
	var $decorations = if authoring.decorations.is_empty() [] else List.repeat(0, authoring.blocks.len())
	var $index = 0
	while $index < authoring.decorations.len() {
		decoration = list_at(authoring.decorations, $index)
		drawing = valid_drawing(decoration.drawing, decoration.block)?
		if drawing.width > width or drawing.height > frames.largest {
			return Err(DecorationOversize({ decoration: $index, frame_height: frames.largest, frame_width: width, height: drawing.height, width: drawing.width }))
		}
		if decoration.block >= authoring.blocks.len() {
			return Err(InvalidBlock({ block: decoration.block }))
		}
		$decorations = list_set($decorations, decoration.block, checked_add(list_at($decorations, decoration.block), drawing.height)?)
		$index = $index + 1
	}
	if authoring.figures.is_empty() {
		return Ok({ decorations: $decorations, heights: [], scales: [] })
	}
	leading = nonnegative_raw(Theme.body_style(theme).leading)?
	spacing = nonnegative_raw(Theme.paragraph_spacing(theme))?
	var $heights = List.with_capacity(authoring.figures.len())
	var $scales = List.with_capacity(authoring.figures.len())
	var $block = 0
	while $block < authoring.blocks.len() {
		match list_at(authoring.blocks, $block).kind {
			Figure(figure_index) => {
				if figure_index != $scales.len() {
					return Err(InvalidBlock({ block: $block }))
				}
				figure = list_at(authoring.figures, figure_index)
				drawing = valid_drawing(figure.drawing, $block)?
				above = if $decorations.is_empty() 0 else list_at($decorations, $block)
				caption = if figure.captioned {
					if $block + 1 >= block_lines.len() {
						return Err(InvalidBlock({ block: $block }))
					}
					caption_lines = match list_at(block_lines, $block + 1) {
						TextBlock({ body, body_offset: _, label: _ }) => body.lines.length()
					}
					checked_add(spacing, checked_mul(caption_lines, leading)?)?
				} else {
					0
				}
				rest = checked_add(above, caption)?
				fitted = match figure.fit {
					ExactFit => {
						if drawing.width > width or checked_add(rest, drawing.height)? > frames.largest {
							return Err(FigureOversize({ block: $block, frame_height: frames.largest, frame_width: width, height: drawing.height, width: drawing.width }))
						}
						{ height: drawing.height, scale: 1000 }
					}
					ScaleFit(floor) => {
						oversize = FigureOversize({ block: $block, frame_height: frames.smallest, frame_width: width, height: drawing.height, width: drawing.width })
						if rest >= frames.smallest {
							return Err(oversize)
						}
						by_width = checked_mul(width, 1000)? // drawing.width
						by_height = checked_mul(frames.smallest - rest, 1000)? // drawing.height
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

## A figure or decoration drawing that semantic planning already accepted.
valid_drawing : Document.ValidatedDrawing, U64 -> Try(Document.FlowDrawing, KernelFacadePages.Error)
valid_drawing = |drawing, block| match drawing {
	ValidDrawing(value) => Ok(value)
	InvalidDrawing(_) => Err(InvalidBlock({ block: block }))
}

## The decoration band above leaf `block`.
leaf_decoration : FlowFacts, U64 -> Layout.Unit
leaf_decoration = |facts, block| Layout.Unit.from_raw((if facts.decorations.is_empty() 0 else list_at(facts.decorations, block)).to_i64_wrap())

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
			{ ..decorated, baseline_offset: height, leading: height, policy: { ..policy, keep_with_next: if captioned Required else policy.keep_with_next } }
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
		unit = if units.is_empty() decoration.block else list_at(units, decoration.block)
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
		$paints = $paints.append({ decoration: $index, origin: { x: Layout.Unit.from_raw(margin_left.to_i64_wrap()), y: Layout.Unit.from_raw(bottom.to_i64_wrap()) }, page: band.page })
		$offset = checked_add($offset, drawing.height)?
		$index = $index + 1
	}
	Ok($paints)
}

check_limit : U64, U64, KernelFacadePages.Dimension -> Try({}, KernelFacadePages.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

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

## Leaves of one nested list stack without spacing; the paragraph after the
## outermost list does not.
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
	WithFlowTemplate({ continuation: _, first: _, lead }) => match lead {
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
flow_groups = |groups, lead_units| if lead_units == 0 groups else groups.keep_if(|group| group.blocks.start() >= lead_units)

layout_template : KernelFacadePages.FlowTemplate, U64 -> KernelPageLayout.Template
layout_template = |template, lead_units| {
	continuation: template.continuation,
	first: template.first,
	lead: match template.lead {
		NoLead => NoLead
		Lead({ frame, leaves: _ }) => Lead({ blocks: lead_units, frame })
	},
}

## `ScaleToFit` scales a 600 × 900 pt drawing by the largest factor that
## fits the body frame (in thousandths, rounding the anchor height up); a
## floor above it and an `Exact` figure are oversize.
expect {
	drawing = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 600, 900), Color.srgb8({ blue: 0, green: 0, red: 0 }))
	page = { height: Layout.Unit.points(842), width: Layout.Unit.points(595) }
	theme = Theme.with_page_margin(Theme.default, { bottom: Layout.Unit.points(48), left: Layout.Unit.points(56), right: Layout.Unit.points(56), top: Layout.Unit.points(48) })
	authoring = |fit| Document.normalize(Document.from_blocks({ contents: [Document.figure_fit(Document.figure(drawing, "A plan", NoCaption), fit)], language: "en-AU", title: "Fit" }))
	scaled = match plan_flow(authoring(ScaleToFit({ minimum_percent: 50 })), [], page, theme, NoFlowTemplate) {
		Ok({ decorations: [], heights: [height], scales: [scale] }) => scale == 805 and height == 724500
		_ => False
	}
	floored = match plan_flow(authoring(ScaleToFit({ minimum_percent: 90 })), [], page, theme, NoFlowTemplate) {
		Err(FigureScaleFloor({ block: 0, floor: 90, scale: 805 })) => True
		_ => False
	}
	exact = match plan_flow(authoring(Exact), [], page, theme, NoFlowTemplate) {
		Err(FigureOversize({ block: 0, frame_height: 746000, frame_width: 483000, height: 900000, width: 600000 })) => True
		_ => False
	}
	scaled and floored and exact
}
