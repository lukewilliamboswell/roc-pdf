import Layout
import KernelUnicode
import Font
import Semantics
import Text

## The measurement domain for rich text containing symbolic references.
## Item indexes are deliberately not Unicode, glyph or cluster indexes.
## A reference occupies one unbreakable item of its authored width until
## accepted pagination supplies the exact Unicode that will be painted.
KernelReferenceLayout :: [].{
	ItemId :: U64.{
		is_eq : _
		from_index : U64 -> ItemId
		from_index = |index| ItemId.(index)
		index : ItemId -> U64
		index = |ItemId.(index)| index
	}
	Boundary : [Allowed, Mandatory, Prohibited]
	Item : {
		advance : Layout.Unit,
		after : Boundary,
		source : [LiteralCluster({ cluster : U64, run : U64 }), ReferenceAtom(U64)],
	}
	Line : { advance : Layout.Unit, items : Semantics.IndexRange }
	Limits : { max_items : U64, max_lines : U64 }
	Error : [ArithmeticOverflow, EmptyItems, InvalidAdvance({ item : U64 }), InvalidFinalBoundary, InvalidLiteral({ run : U64 }), InvalidWidth, LimitExceeded, Unbreakable({ first : ItemId, last : ItemId, required : Layout.Unit, width : Layout.Unit })]
	Work : { boundary_visits : U64, item_visits : U64, line_writes : U64, validation_visits : U64 }
	BuildWork : { atom_writes : U64, cluster_visits : U64, glyph_index_visits : U64 }
	Measured : { items : List(Item), work : BuildWork }

	## The exact source-scalar holds intersecting one physical run, as a
	## span into the shared hold arena. A forward merge prepares these
	## spans; appending a run never scans an earlier run's holds again.
	Holds : { ranges : List(Semantics.IndexRange), span : Semantics.IndexRange }

	## A consuming builder has no Try around its growing arena. Failure
	## drops that arena and retains only one compact error; every caller
	## reassigns the returned builder. `finish` freezes the item store once.
	Builder :: [Failed(Error), Open({ items : List(Item), limits : Limits, work : BuildWork })].{
		start : Limits -> Builder
		start = |limits| Builder.Open({ items: [], limits, work: { atom_writes: 0, cluster_visits: 0, glyph_index_visits: 0 } })

		## Append one actual shaped run and its source's boundary facts.
		## Holds use source-scalar coordinates and withhold only tailorable
		## opportunities strictly inside their ranges, just as Code does.
		run : Builder, Text.Store, Text.RunId, KernelUnicode.UnicodeAnalysis, Holds -> Builder
		run = |builder, store, run, analysis, holds| append_run(builder, store, run, analysis, holds)

		## An atom is isolated from surrounding shaping and has one fixed
		## width-bearing item; its resolved text can never split that item.
		reference : Builder, U64, Layout.Unit -> Builder
		reference = |builder, reference, width| append_reference(builder, reference, width)

		## Only an authored mandatory break ends a paragraph segment. A
		## literal chunk ending at an atom does not invent a line break.
		segment_end : Builder -> Builder
		segment_end = |builder| end_segment(builder)

		position : Builder -> Try(U64, Error)
		position = |builder| match builder {
			Failed(error) => Err(error)
			Open(state) => Ok(state.items.len())
		}

		finish : Builder -> Try(Measured, Error)
		finish = |builder| match end_segment(builder) {
			Failed(error) => Err(error)
			Open(state) => Ok({ items: state.items, work: state.work })
		}
	}
	Measure : { max_content : Layout.Unit, min_content : Layout.Unit, widest : Semantics.IndexRange, work : Work }
	Plan : { lines : List(Line), work : Work }

	## Exact intrinsic widths of the same item sequence used by wrapping.
	## Tables consume these facts before selecting column widths.
	measure : List(Item), Limits -> Try(Measure, Error)
	measure = |items, limits| measure_items(items, limits)

	## Greedy latest-legal-boundary wrapping. Each item is inspected at
	## most twice, and a resume cursor is a scalar item index. No earlier
	## line is remeasured or retained as a rollback checkpoint.
	wrap : List(Item), Layout.Unit, Limits -> Try(Plan, Error)
	wrap = |items, width, limits| wrap_items(items, width, limits)
}

append_run : KernelReferenceLayout.Builder, Text.Store, Text.RunId, KernelUnicode.UnicodeAnalysis, KernelReferenceLayout.Holds -> KernelReferenceLayout.Builder
append_run = |builder, store, id, analysis, holds| {
	state = match builder {
		Failed(error) => return KernelReferenceLayout.Builder.Failed(error)
		Open(value) => value
	}
	run_index = id.index()
	if run_index >= store.runs.len() {
		return KernelReferenceLayout.Builder.Failed(InvalidLiteral({ run: run_index }))
	}
	run = at(store.runs, run_index)
	start = run.clusters.start()
	length = run.clusters.length()
	if run.id != id or length == 0 or start > store.clusters.len() or length > store.clusters.len() - start or analysis.line_boundaries.len() != analysis.work.scalar_visits + 1 {
		return KernelReferenceLayout.Builder.Failed(InvalidLiteral({ run: run_index }))
	}
	if holds.span.start() > holds.ranges.len() or holds.span.length() > holds.ranges.len() - holds.span.start() {
		return KernelReferenceLayout.Builder.Failed(InvalidLiteral({ run: run_index }))
	}
	run_source_start = run.source.scalars.start()
	run_source_length = run.source.scalars.length()
	if run_source_start > analysis.work.scalar_visits or run_source_length > analysis.work.scalar_visits - run_source_start {
		return KernelReferenceLayout.Builder.Failed(InvalidLiteral({ run: run_index }))
	}
	var $held = holds.span.start()
	var $held_end = 0
	while $held < holds.span.start() + holds.span.length() {
		hold = at(holds.ranges, $held)
		if hold.length() == 0 or hold.start() > analysis.work.scalar_visits or hold.length() > analysis.work.scalar_visits - hold.start() or hold.start() < $held_end {
			return KernelReferenceLayout.Builder.Failed(InvalidLiteral({ run: run_index }))
		}
		end = hold.start() + hold.length()
		if end <= run_source_start or hold.start() >= run_source_start + run_source_length {
			return KernelReferenceLayout.Builder.Failed(InvalidLiteral({ run: run_index }))
		}
		$held_end = end
		$held = $held + 1
	}
	limits = state.limits
	if state.items.len() > limits.max_items or length > limits.max_items - state.items.len() {
		return KernelReferenceLayout.Builder.Failed(LimitExceeded)
	}
	work = state.work
	var $items = state.items
	var $glyph_visits = work.glyph_index_visits
	var $hold = holds.span.start()
	hold_end = holds.span.start() + holds.span.length()
	source_bytes = at(analysis.line_boundaries, analysis.work.scalar_visits).byte_offset
	var $cluster = start
	while $cluster < start + length {
		cluster = at(store.clusters, $cluster)
		scalar_start = cluster.source.scalars.start()
		scalar_length = cluster.source.scalars.length()
		if scalar_start < run_source_start or scalar_start > analysis.work.scalar_visits or scalar_length > analysis.work.scalar_visits - scalar_start or scalar_start + scalar_length > run_source_start + run_source_length {
			return KernelReferenceLayout.Builder.Failed(InvalidLiteral({ run: run_index }))
		}
		boundary_index = scalar_start + scalar_length
		boundary = at(analysis.line_boundaries, boundary_index)
		byte_start = cluster.source.utf8_bytes.start()
		byte_length = cluster.source.utf8_bytes.length()
		if byte_start > source_bytes or byte_length > source_bytes - byte_start or boundary.scalar_offset != boundary_index or boundary.byte_offset != byte_start + byte_length {
			return KernelReferenceLayout.Builder.Failed(InvalidLiteral({ run: run_index }))
		}
		glyph_start = cluster.glyphs.start()
		glyph_length = cluster.glyphs.length()
		if glyph_start > store.glyph_indices.len() or glyph_length > store.glyph_indices.len() - glyph_start {
			return KernelReferenceLayout.Builder.Failed(InvalidLiteral({ run: run_index }))
		}
		var $advance = 0
		var $glyph = glyph_start
		while $glyph < glyph_start + glyph_length {
			index = at(store.glyph_indices, $glyph)
			if index >= store.glyphs.len() {
				return KernelReferenceLayout.Builder.Failed(InvalidLiteral({ run: run_index }))
			}
			next = match plus($advance, at(store.glyphs, index).advance_x.raw()) {
				Ok(value) => value
				Err(error) => return KernelReferenceLayout.Builder.Failed(error)
			}
			$advance = next
			$glyph = $glyph + 1
			$glyph_visits = $glyph_visits + 1
		}
		if $advance < 0 {
			return KernelReferenceLayout.Builder.Failed(InvalidAdvance({ item: $items.len() }))
		}
		while $hold < hold_end and at(holds.ranges, $hold).start() + at(holds.ranges, $hold).length() <= boundary_index {
			$hold = $hold + 1
		}
		var $after = boundary.decision
		if boundary.decision == Allowed and boundary.authority == Tailorable and $hold < hold_end {
			hold = at(holds.ranges, $hold)
			if boundary_index > hold.start() and boundary_index < hold.start() + hold.length() {
				$after = Prohibited
			}
		}
		if boundary_index == analysis.work.scalar_visits and $after == Mandatory {
			$after = Allowed
		}
		$items = $items.append({ advance: Layout.Unit.from_raw($advance), after: $after, source: LiteralCluster({ cluster: $cluster, run: run_index }) })
		$cluster = $cluster + 1
	}
	KernelReferenceLayout.Builder.Open({ items: $items, limits, work: { atom_writes: work.atom_writes, cluster_visits: work.cluster_visits + length, glyph_index_visits: $glyph_visits } })
}

append_reference : KernelReferenceLayout.Builder, U64, Layout.Unit -> KernelReferenceLayout.Builder
append_reference = |builder, reference, width| {
	state = match builder {
		Failed(error) => return KernelReferenceLayout.Builder.Failed(error)
		Open(value) => value
	}
	if width <= 0 {
		return KernelReferenceLayout.Builder.Failed(InvalidAdvance({ item: state.items.len() }))
	}
	if state.items.len() >= state.limits.max_items {
		return KernelReferenceLayout.Builder.Failed(LimitExceeded)
	}
	limits = state.limits
	work = state.work
	length = state.items.len()
	var $items = state.items
	if length > 0 {
		previous = at($items, length - 1)
		if previous.after != Mandatory {
			$items = set($items, length - 1, { ..previous, after: Allowed })
		}
	}
	$items = $items.append({ advance: width, after: Allowed, source: ReferenceAtom(reference) })
	KernelReferenceLayout.Builder.Open({ items: $items, limits, work: { ..work, atom_writes: work.atom_writes + 1 } })
}

end_segment : KernelReferenceLayout.Builder -> KernelReferenceLayout.Builder
end_segment = |builder| {
	state = match builder {
		Failed(error) => return KernelReferenceLayout.Builder.Failed(error)
		Open(value) => value
	}
	length = state.items.len()
	if length == 0 {
		return KernelReferenceLayout.Builder.Failed(EmptyItems)
	}
	limits = state.limits
	work = state.work
	previous = at(state.items, length - 1)
	items = set(state.items, length - 1, { ..previous, after: Mandatory })
	KernelReferenceLayout.Builder.Open({ items, limits, work })
}

measure_items : List(KernelReferenceLayout.Item), KernelReferenceLayout.Limits -> Try(KernelReferenceLayout.Measure, KernelReferenceLayout.Error)
measure_items = |items, limits| {
	validate(items, limits)?
	var $max = 0
	var $min = 0
	var $line = 0
	var $piece = 0
	var $piece_start = 0
	var $widest_start = 0
	var $widest_length = 0
	var $index = 0
	while $index < items.len() {
		item = at(items, $index)
		$line = plus($line, item.advance.raw())?
		$piece = plus($piece, item.advance.raw())?
		if item.after != Prohibited {
			if $piece > $min {
				$min = $piece
				$widest_start = $piece_start
				$widest_length = $index + 1 - $piece_start
			}
			$piece = 0
			$piece_start = $index + 1
		}
		if item.after == Mandatory {
			$max = I64.max($max, $line)
			$line = 0
		}
		$index = $index + 1
	}
	Ok({ max_content: Layout.Unit.from_raw($max), min_content: Layout.Unit.from_raw($min), widest: Semantics.IndexRange.from_start_and_length({ start: $widest_start, length: $widest_length }), work: { boundary_visits: items.len(), item_visits: items.len(), line_writes: 0, validation_visits: items.len() } })
}

wrap_items : List(KernelReferenceLayout.Item), Layout.Unit, KernelReferenceLayout.Limits -> Try(KernelReferenceLayout.Plan, KernelReferenceLayout.Error)
wrap_items = |items, width, limits| {
	validate(items, limits)?
	if width <= 0 {
		return Err(InvalidWidth)
	}
	var $lines = []
	var $start = 0
	var $cursor = 0
	var $advance = 0
	var $break = 0
	var $break_advance = 0
	var $visits = 0
	while $cursor < items.len() {
		item = at(items, $cursor)
		next = plus($advance, item.advance.raw())?
		$visits = $visits + 1
		if next > width.raw() {
			if $break <= $start {
				return Err(Unbreakable({ first: KernelReferenceLayout.ItemId.from_index($start), last: KernelReferenceLayout.ItemId.from_index($cursor), required: Layout.Unit.from_raw(next), width }))
			}
			if $lines.len() >= limits.max_lines {
				return Err(LimitExceeded)
			}
			$lines = $lines.append({ advance: Layout.Unit.from_raw($break_advance), items: Semantics.IndexRange.from_start_and_length({ start: $start, length: $break - $start }) })
			$start = $break
			$cursor = $break
			$advance = 0
			$break_advance = 0
		} else {
			$advance = next
			$cursor = $cursor + 1
			if item.after != Prohibited {
				$break = $cursor
				$break_advance = $advance
			}
			if item.after == Mandatory {
				if $lines.len() >= limits.max_lines {
					return Err(LimitExceeded)
				}
				$lines = $lines.append({ advance: Layout.Unit.from_raw($advance), items: Semantics.IndexRange.from_start_and_length({ start: $start, length: $cursor - $start }) })
				$start = $cursor
				$advance = 0
				$break_advance = 0
			}
		}
	}
	Ok({ lines: $lines, work: { boundary_visits: $visits, item_visits: $visits, line_writes: $lines.len(), validation_visits: items.len() } })
}

validate : List(KernelReferenceLayout.Item), KernelReferenceLayout.Limits -> Try({}, KernelReferenceLayout.Error)
validate = |items, limits| {
	if items.is_empty() {
		return Err(EmptyItems)
	}
	if items.len() > limits.max_items {
		return Err(LimitExceeded)
	}
	if at(items, items.len() - 1).after != Mandatory {
		return Err(InvalidFinalBoundary)
	}
	var $index = 0
	while $index < items.len() {
		item = at(items, $index)
		if item.advance < 0 {
			return Err(InvalidAdvance({ item: $index }))
		}
		match item.source {
			ReferenceAtom(_) => if item.advance == 0 {
				return Err(InvalidAdvance({ item: $index }))
			}
			LiteralCluster(_) => {}
		}
		$index = $index + 1
	}
	Ok({})
}

plus : I64, I64 -> Try(I64, KernelReferenceLayout.Error)
plus = |left, right| match left.plus_try(right) {
	Ok(value) => Ok(value)
	Err(_) => Err(ArithmeticOverflow)
}

at : List(a), U64 -> a
at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(_) => crash "reference-layout cursor escaped its measured item arena"
}

set : List(a), U64, a -> List(a)
set = |items, index, value| match items.set(index, value) {
	Ok(updated) => updated
	Err(_) => crash "reference-layout update escaped its measured item arena"
}

test_items : List(KernelReferenceLayout.Item)
test_items = [
	{ advance: 12, after: Allowed, source: LiteralCluster({ cluster: 0, run: 0 }) },
	{ advance: 20, after: Allowed, source: ReferenceAtom(0) },
	{ advance: 8, after: Mandatory, source: LiteralCluster({ cluster: 1, run: 1 }) },
]

expect {
	plan = KernelReferenceLayout.wrap(test_items, 32, { max_items: 10, max_lines: 10 })?
	plan.lines == [{ advance: 32, items: Semantics.IndexRange.from_start_and_length({ start: 0, length: 2 }) }, { advance: 8, items: Semantics.IndexRange.from_start_and_length({ start: 2, length: 1 }) }]
}

expect {
	measured = KernelReferenceLayout.measure(test_items, { max_items: 10, max_lines: 10 })?
	measured.max_content == 40 and measured.min_content == 20
}

expect {
	only = [{ advance: 20, after: Mandatory, source: ReferenceAtom(0) }]
	plan = KernelReferenceLayout.wrap(only, 20, { max_items: 10, max_lines: 10 })?
	plan.lines.len() == 1
}

expect match KernelReferenceLayout.wrap([{ advance: 20, after: Mandatory, source: ReferenceAtom(0) }], 19, { max_items: 10, max_lines: 10 }) {
	Err(Unbreakable(_)) => True
	_ => False
}

# Repeated short lines keep complete, ordered item coverage and bounded
# work. This catches rescanning already committed lines or losing an atom
# at the boundary where it moves onto the next line.
expect {
	var $items = List.with_capacity(1000)
	while $items.len() < 1000 {
		index = $items.len()
		$items = $items.append({ advance: 1, after: if (index == 999) Mandatory else Allowed, source: ReferenceAtom(index) })
	}
	plan = KernelReferenceLayout.wrap($items, 3, { max_items: 1000, max_lines: 1000 })?
	var $cursor = 0
	var $valid = True
	for line in plan.lines {
		if line.items.start() != $cursor or line.items.length() == 0 or line.advance > 3 {
			$valid = False
		}
		$cursor = $cursor + line.items.length()
	}
	$valid and $cursor == 1000 and plan.lines.len() == 334 and plan.work.item_visits <= 2000 and plan.work.validation_visits == 1000
}

test_literal_store : Text.Store
test_literal_store = {
	clusters: [
		{ glyphs: Semantics.IndexRange.from_start_and_length({ start: 0, length: 1 }), kind: OneToOne, source: test_text_range(0, 1) },
		{ glyphs: Semantics.IndexRange.from_start_and_length({ start: 1, length: 1 }), kind: OneToOne, source: test_text_range(1, 1) },
		{ glyphs: Semantics.IndexRange.from_start_and_length({ start: 2, length: 1 }), kind: OneToOne, source: test_text_range(2, 1) },
	],
	glyph_indices: [0, 1, 2],
	glyphs: List.repeat({ advance_x: Layout.Unit.points(2), advance_y: Layout.Unit.points(0), id: Text.GlyphId.from_raw(1), offset_x: Layout.Unit.points(0), offset_y: Layout.Unit.points(0) }, 3),
	runs: [{ actual_text: FromOccurrence, clusters: Semantics.IndexRange.from_start_and_length({ start: 0, length: 3 }), direction: LeftToRight, glyphs: Semantics.IndexRange.from_start_and_length({ start: 0, length: 3 }), id: Text.RunId.from_index(0), instance: Font.InstanceId.from_index(0), language: Language("en"), script: Font.Script.from_iso15924("Latn"), size: Layout.Unit.points(10), source: test_text_range(0, 3), substitutions: Semantics.IndexRange.from_start_and_length({ start: 0, length: 0 }), transformations: Semantics.IndexRange.from_start_and_length({ start: 0, length: 0 }), unicode: OccurrenceText(Semantics.OccurrenceId.from_index(0)), writing_mode: Horizontal }],
	substitutions: [],
	transformations: [],
}

test_text_range : U64, U64 -> Semantics.TextRange
test_text_range = |start, length| { scalars: Semantics.IndexRange.from_start_and_length({ start: start, length: length }), utf8_bytes: Semantics.IndexRange.from_start_and_length({ start: start, length: length }) }

# Literal source-end analysis does not force a line break before the
# following symbolic reference; only the accepted authored segment does.
expect {
	analysis = KernelUnicode.analyze("a b", KernelUnicode.default_limits)?
	var $builder = KernelReferenceLayout.Builder.start({ max_items: 10, max_lines: 10 })
	$builder = KernelReferenceLayout.Builder.run($builder, test_literal_store, Text.RunId.from_index(0), analysis, { ranges: [], span: Semantics.IndexRange.from_start_and_length({ start: 0, length: 0 }) })
	$builder = KernelReferenceLayout.Builder.reference($builder, 0, 3)
	measured = KernelReferenceLayout.Builder.finish($builder)?
	plan = KernelReferenceLayout.wrap(measured.items, 10, { max_items: 10, max_lines: 10 })?
	plan.lines.len() == 1 and at(plan.lines, 0).advance == 9 and measured.work.atom_writes == 1 and measured.work.glyph_index_visits == 3
}

expect {
	analysis = KernelUnicode.analyze("a b", KernelUnicode.default_limits)?
	var $builder = KernelReferenceLayout.Builder.start({ max_items: 10, max_lines: 10 })
	$builder = KernelReferenceLayout.Builder.run($builder, test_literal_store, Text.RunId.from_index(0), analysis, { ranges: [Semantics.IndexRange.from_start_and_length({ start: 0, length: 3 })], span: Semantics.IndexRange.from_start_and_length({ start: 0, length: 1 }) })
	measured = KernelReferenceLayout.Builder.finish($builder)?
	widths = KernelReferenceLayout.measure(measured.items, { max_items: 10, max_lines: 10 })?
	widths.min_content == 6
}

# A failed consuming builder drops its arena and preserves the first
# compact error through subsequent calls; no growing list survives it.
expect {
	var $builder = KernelReferenceLayout.Builder.start({ max_items: 1, max_lines: 1 })
	$builder = KernelReferenceLayout.Builder.reference($builder, 0, 2)
	$builder = KernelReferenceLayout.Builder.reference($builder, 1, 3)
	$builder = KernelReferenceLayout.Builder.reference($builder, 2, 0)
	match KernelReferenceLayout.Builder.finish($builder) {
		Err(LimitExceeded) => True
		_ => False
	}
}
