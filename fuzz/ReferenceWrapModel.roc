import fuzz.Model
import pdf.KernelReferenceLayout as ReferenceLayout
import pdf.Layout

ReferenceWrapModel := [].{}

Item : [AllowOne, HoldOne, BreakTwo, RefTwo, HoldZero]

Boundary : ReferenceLayout.Boundary

Span : { first : U64, end : U64, width : I64 }

Wrap : [Lines(List(Span)), LineLimit, CannotFit({ first : U64, last : U64, required : I64, width : I64 }), UnexpectedError]

choices : List(Item)
choices = [AllowOne, HoldOne, BreakTwo, RefTwo, HoldZero]

# Each prefix can be finalized by closing its last item. A reference atom
# also permits a cut before it unless the paragraph already requires one.
# A history is an exact key for the authored items and their source identities.
machine : Model.Machine(List(Item), Item)
machine = {
	init: [],
	actions: |items| if (items.len() < 4) choices else [],
	step: |items, item| items.append(item),
	rules: [
		Model.always("intrinsic widths equal sums over mandatory and unbreakable partitions", intrinsic_matches),
		Model.always("wrapping chooses the last fitting legal cut", wrapping_matches),
		Model.sometimes("an atom exactly fills a line before another item", |items| items == [RefTwo, AllowOne]),
		Model.sometimes("a prohibited cut forces an earlier rollback", |items| items == [RefTwo, HoldOne, AllowOne]),
		Model.sometimes("a mandatory break splits items that can fit together", |items| items == [BreakTwo, HoldZero, AllowOne]),
	],
}

expect {
	report = Model.explore(machine, { depth: 5, key: |items| items, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 781 and report.steps == 780 and report.depth == 4 and report.reached.len() == 3
}

width_of : Item -> I64
width_of = |item| match item {
	AllowOne | HoldOne => 1
	BreakTwo | RefTwo => 2
	HoldZero => 0
}

boundary : List(Item), U64, Item -> Boundary
boundary = |items, index, item| {
	if index + 1 == items.len() or item == BreakTwo {
		Mandatory
	} else if item == AllowOne or item == RefTwo or items.get(index + 1) == Ok(RefTwo) {
		Allowed
	} else {
		Prohibited
	}
}

measured_items : List(Item) -> List(ReferenceLayout.Item)
measured_items = |items| items.map_with_index(
	|item, index| {
		advance: Layout.Unit.from_raw(width_of(item)),
		after: boundary(items, index, item),
		source: if (item == RefTwo) ReferenceAtom(index) else LiteralCluster({ cluster: index, run: 0 }),
	},
)

# Split on the requested boundaries, then sum each slice from its source.
partition : List(Item), (Boundary -> Bool) -> List(Span)
partition = |items, cuts| {
	var $spans = []
	var $first = 0
	var $index = 0
	for item in items {
		end = $index + 1
		if cuts(boundary(items, $index, item)) {
			$spans = $spans.append({ first: $first, end, width: slice_width(items, $first, end) })
			$first = end
		}
		$index = end
	}
	$spans
}

slice_width : List(Item), U64, U64 -> I64
slice_width = |items, first, end| items.sublist({ start: first, len: end - first }).fold(0, |sum, item| sum + width_of(item))

intrinsic_matches : List(Item) -> Bool
intrinsic_matches = |items| match ReferenceLayout.measure(measured_items(items), { max_items: 4, max_lines: 4 }) {
	Err(EmptyItems) => items.is_empty()
	Err(_) => False
	Ok(measured) => {
		segments = partition(items, |after| after == Mandatory)
		pieces = partition(items, |after| after != Prohibited)
		longest = segments.fold(0, |best, span| I64.max(best, span.width))
		widest = pieces.fold({ first: 0, end: 0, width: 0 }, |best, span| if (span.width > best.width) span else best)
		measured.max_content.raw() == longest and measured.min_content.raw() == widest.width and
			measured.widest.start() == widest.first and measured.widest.length() == widest.end - widest.first
	}
}

wrapping_matches : List(Item) -> Bool
wrapping_matches = |items| {
	input = measured_items(items)
	if items.is_empty() {
		return ReferenceLayout.wrap(input, 1, { max_items: 4, max_lines: 4 }) == Err(EmptyItems)
	}
	[1, 2, 3, 4].all(|width| [1, 4].all(|max_lines|
		observe(ReferenceLayout.wrap(input, Layout.Unit.from_raw(width), { max_items: 4, max_lines }), input.len()) == expected_wrap(items, width, max_lines)))
}

observe : Try(ReferenceLayout.Plan, ReferenceLayout.Error), U64 -> Wrap
observe = |result, count| match result {
	Ok(plan) if plan.work.item_visits > count * 2 or plan.work.validation_visits != count => UnexpectedError
	Ok(plan) => Lines(
		plan.lines.map(
			|line| {
				first: line.items.start(),
				end: line.items.start() + line.items.length(),
				width: line.advance.raw(),
			},
		),
	)
	Err(LimitExceeded) => LineLimit
	Err(Unbreakable({ first, last, required, width })) => CannotFit({ first: first.index(), last: last.index(), required: required.raw(), width: width.raw() })
	Err(_) => UnexpectedError
}

# Enumerate legal endpoints in each mandatory segment. The last fitting
# endpoint sets the next line, without simulating the production rollback.
expected_wrap : List(Item), I64, U64 -> Wrap
expected_wrap = |items, width, max_lines| {
	segments = partition(items, |after| after == Mandatory)
	cuts = partition(items, |after| after != Prohibited).map(|span| span.end)
	var $lines = []
	for segment in segments {
		var $first = segment.first
		while $first < segment.end {
			first = $first
			available = cuts.keep_if(|end| end > first and end <= segment.end and slice_width(items, first, end) <= width)
			match available.last() {
				Err(ListWasEmpty) => {
					overflow = first_overflow(items, first, segment.end, width)
					return CannotFit({ first, last: overflow - 1, required: slice_width(items, first, overflow), width })
				}
				Ok(end) => {
					if $lines.len() == max_lines {
						return LineLimit
					}
					$lines = $lines.append({ first, end, width: slice_width(items, first, end) })
					$first = end
				}
			}
		}
	}
	Lines($lines)
}

first_overflow : List(Item), U64, U64, I64 -> U64
first_overflow = |items, first, end, width| {
	var $cut = first + 1
	while $cut < end and slice_width(items, first, $cut) <= width {
		$cut = $cut + 1
	}
	$cut
}

# Exercise the checked I64 boundary separately from the finite world.
expect {
	limits = { max_items: 2, max_lines: 2 }
	width = Layout.Unit.from_raw(I64.highest)
	first = ReferenceLayout.Builder.reference(ReferenceLayout.Builder.start(limits), 0, width)
	measured = ReferenceLayout.Builder.finish(ReferenceLayout.Builder.reference(first, 1, 1))?
	items = measured.items
	ReferenceLayout.measure(items, limits) == Err(ArithmeticOverflow) and
		ReferenceLayout.wrap(items, width, limits) == Err(ArithmeticOverflow)
}
