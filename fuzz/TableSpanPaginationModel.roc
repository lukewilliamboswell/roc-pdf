import fuzz.Model
import pdf.Document
import pdf.KernelFacadePages
import pdf.KernelFacadeTableGrid
import pdf.KernelPageLayout
import pdf.Layout
import pdf.Semantics
import pdf.Theme

TableSpanPaginationModel := [].{}

Policy : [KeepRows, SplitSpans]

Action : [Policy(Policy), Capacity(U64), FirstRow(U64), Note(U64), Footer(Bool)]

World : { capacity : U64, first : U64, note : U64, footer : [Pending, Set(Bool)], policy : [Pending, Set(Policy)] }

machine : Model.Machine(World, Action)
machine = {
	init: { capacity: 0, first: 0, note: 0, footer: Pending, policy: Pending },
	actions: |world| {
		if world.policy == Pending {
			[Policy(KeepRows), Policy(SplitSpans)]
		} else if world.capacity == 0 {
			[Capacity(5), Capacity(6), Capacity(7)]
		} else if world.first == 0 {
			[FirstRow(2), FirstRow(3)]
		} else if world.note == 0 {
			[Note(4), Note(5), Note(6)]
		} else if world.footer == Pending {
			[Footer(False), Footer(True)]
		} else {
			[]
		}
	},
	step: |world, action| match action {
		Policy(policy) => { ..world, policy: Set(policy) }
		Capacity(capacity) => { ..world, capacity }
		FirstRow(first) => { ..world, first }
		Note(note) => { ..world, note }
		Footer(footer) => { ..world, footer: Set(footer) }
	},
	rules: [
		Model.always(
			"production row cuts are legal and each note line keeps its original cell",
			|world| match (world.policy, world.footer) {
				(Set(policy), Set(footer)) => agrees(world, policy, footer)
				_ => True
			},
		),
		Model.sometimes("a continued note crosses the page and repaints the header", |world| world.policy == Set(SplitSpans) and world.capacity == 5 and world.first == 2 and world.note == 6 and world.footer == Set(False)),
		Model.sometimes("a kept span group fits only without the footer", |world| world.policy == Set(KeepRows) and world.capacity == 7 and world.first == 3 and world.note == 6 and world.footer == Set(True)),
		Model.sometimes("the individually fitting rows cannot fit together", |world| world.policy == Set(KeepRows) and world.capacity == 5 and world.first == 2 and world.note == 6 and world.footer == Set(True)),
	],
}

## The input uses one-point rows and zero gap. The header consumes one
## slot on every page. A footer can merge into the last body page if
## another line fits, or consume its own page. Body cuts prefer two or
## more lines of the same row on each side when capacity permits.
legal_cuts : World, Bool -> List(U64)
legal_cuts = |world, footer| {
	span_height = U64.max(world.note, world.first + 2)
	room = world.capacity - 1
	total = span_height + if (footer) 1 else 0
	if total <= room {
		return [total]
	}
	var $legal = []
	var $preferred = []
	var $take = world.first
	while $take <= room and $take <= span_height {
		if total - $take <= room {
			$legal = $legal.append($take)
			remainder = span_height - $take
			within = $take - world.first
			if within == 0 or remainder == 0 or (within >= 2 and remainder >= 2) {
				$preferred = $preferred.append($take)
			}
		}
		$take = $take + 1
	}
	if ($preferred.is_empty()) $legal else $preferred
}

agrees : World, Policy, Bool -> Bool
agrees = |world, policy, footer| {
	column = { align: Start, width: Fixed(4) }
	sample = [Document.plain_text("x")]
	head = Document.row([Document.header_cell(Column, sample), Document.header_cell(Column, sample)])
	note = Document.cell(sample).row_spanning(2)
	body = [Document.row([note, Document.cell(sample)]), Document.row([Document.cell(sample)])]
	foot = if (footer) [Document.row([Document.header_cell(Row, sample).spanning(2)])] else []
	table = Document.table({ header_rows: [head], body_rows: body, footer_rows: foot, columns: [column, column], row_split: if (policy == KeepRows) KeepRows else SplitSpans, caption: NoCaption })
	authoring = Document.normalize(Document.from_blocks({ contents: [table], language: "en", title: "Bounded page cuts" }))
	verified = match KernelFacadeTableGrid.build(authoring, 0, 0, authoring.cells.len(), authoring.tables.get(0) ?? crash "table missing") {
		Ok(Spanning(grid)) => [grid]
		_ => crash "regular model input grid rejected"
	}
	lines = [1, 1, world.note, world.first, 2, 1].take_first(authoring.cells.len())
	input : KernelFacadePages.MeasuredInput
	input = {
		blocks: lines.map_with_index(
			|count, block| MeasuredText({
				body_offset: 0,
				leading: 1,
				size: 1,
				label: NoLabel,
				level: 0,
				owner: Semantics.OccurrenceId.from_index(block),
				rows: range(block * 10, count),
			}),
		),
		cells: authoring.cells.map_with_index(|cell, ordinal| { align: Start, block: cell.block, offset: 0, width: if (ordinal == 5) 8000 else 4000, x: if (ordinal == 1 or ordinal == 3 or ordinal == 4) 4000 else 0 }),
		figure_frames: [],
		group_frames: [{ offset: 0, width: 8000 }],
		source_frames: [],
		table_grids: verified,
		tables: [{ columns: [4000, 4000], group: 0, offset: 0, width: 8000 }],
	}
	page = { height: Layout.Unit.points((world.capacity + 2).to_i64_wrap()), width: Layout.Unit.points(10) }
	theme : Theme
	theme = { page_margin: { top: 1, bottom: 1, left: 1, right: 1 }, table: { cell_padding: 0, row_gap: 0, rule: NoRule } }
	limits = KernelFacadePages.Limits.make({ max_blocks: 6, max_rows: 24, page: KernelPageLayout.Limits.make({ max_blocks: 6, max_fragments: 24, max_lines: 24, max_pages: 3, max_placements: 24 }) })
	must_reject = policy == KeepRows and U64.max(world.note, world.first + 2) + 1 > world.capacity
	choice = KernelFacadePages.Measured.build(authoring, input, page, theme, NoFlowTemplate, limits)
	match choice {
		Err(TableLayout({ error: KeepConflict(GroupTooTall(_)), .. })) => must_reject
		Err(error) => crash "${Str.inspect(world)}: unexpected page layout rejection ${Str.inspect(error)}"
		Ok(plan) => {
			if must_reject {
				return False
			}
			planned = KernelFacadePages.Measured.view(plan).choice
			pages = KernelPageLayout.Choice.pages(planned)
			first_page = pages.get(0) ?? crash "page plan missing first page"
			body_slots = first_page.spans.length()
			first_cut = KernelPageLayout.Choice.spans(planned).sublist({ start: first_page.spans.start(), len: body_slots }).map(|span| span.rows.length()).sum() - 1
			paint = KernelFacadePages.Measured.paint(plan, authoring, input, List.repeat(1000, 60), page, theme, limits) ?? crash "accepted measured plan failed painting"
			notes = paint.rows.keep_if(|row| row.block == 2)
			exact_rows = notes.map(|row| row.row) == List.repeat(0, world.note).map_with_index(|_, ordinal| 20 + ordinal)
			repeats = paint.rows.keep_if(|row| row.artifact)
			exact_repeats = repeats.len() == (pages.len() - 1) * 2 and repeats.all(|row| row.block < 2)
			on_same_page = notes.all(|row| row.page == 0)
			legal_cut = if (policy == KeepRows) on_same_page else legal_cuts(world, footer).contains(first_cut)
			exact_rows and exact_repeats and legal_cut and pages.len() <= 2
		}
	}
}

range : U64, U64 -> Semantics.IndexRange
range = |start, length| Semantics.IndexRange.from_start_and_length({ start, length })

expect {
	report = Model.explore(machine, { depth: 6, key: |world| (world.policy, world.capacity, world.first, world.note, world.footer), verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 129 and report.steps == 128 and report.depth == 5 and report.reached.len() == 3
}
