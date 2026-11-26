import KernelSpan

## The line fitter resolves each note to the first measured citation line.
## Pagination checks a candidate's half-open line span against this prefix
## index. Repeated citations do not enter the index.
KernelFootnoteReserve :: [].{
	Binding : { line : U64, note : U64, height : U64 }
	Error : [InvalidBinding(U64), ArithmeticOverflow]
	Reservation : { first : U64, end : U64, height : U64 }

	Plan :: { marks : List(Mark) }.{
		empty : Plan
		empty = Plan.{ marks: [] }

		build : List(Binding), U64, U64 -> Try(Plan, Error)
		build = |bindings, body_lines, capacity| {
			var $marks = List.with_capacity(bindings.len())
			var $previous = 0
			var $total = 0
			for input in bindings {
				if input.line >= body_lines or input.line < $previous or input.height == 0 {
					return Err(InvalidBinding(input.note))
				}
				$total = KernelSpan.end_within($total, input.height, capacity) ? |_| ArithmeticOverflow
				$marks = $marks.append({ binding: input, through: $total })
				$previous = input.line
			}
			Ok(Plan.{ marks: $marks })
		}

		is_empty : Plan -> Bool
		is_empty = |plan| plan.marks.is_empty()

		binding : Plan, U64 -> Binding
		binding = |plan, index| mark_at(plan.marks, index).binding

		## Every note moves with the first citation line. A cut immediately
		## before that line leaves its complete footprint on the next page.
		range : Plan, U64, U64 -> Reservation
		range = |plan, start, end| {
			first = lower_bound(plan.marks, start)
			past = lower_bound(plan.marks, end)
			{ first, end: past, height: prefix(plan.marks, past) - prefix(plan.marks, first) }
		}

		## Take the largest prefix that fits both the uniform body rows and
		## any notes whose first citations would be included. Candidate fit
		## is monotone as the end advances, including equal-line notes.
		fit_lines : Plan, U64, U64, U64, U64 -> U64
		fit_lines = |plan, start, limit, leading, available| {
			max_rows = U64.min(limit, available // leading)
			if plan.marks.is_empty() or max_rows == 0 {
				return max_rows
			}
			first = prefix(plan.marks, lower_bound(plan.marks, start))
			var $low = 0
			var $high = max_rows
			while $low < $high {
				middle = $low + ($high - $low + 1) // 2
				notes = prefix(plan.marks, lower_bound(plan.marks, start + middle)) - first
				if notes <= available - middle * leading {
					$low = middle
				} else {
					$high = middle - 1
				}
			}
			$low
		}
	}
}

Mark : { binding : KernelFootnoteReserve.Binding, through : U64 }

lower_bound : List(Mark), U64 -> U64
lower_bound = |marks, line| {
	var $low = 0
	var $high = marks.len()
	while $low < $high {
		middle = $low + ($high - $low) // 2
		if mark_at(marks, middle).binding.line < line {
			$low = middle + 1
		} else {
			$high = middle
		}
	}
	$low
}

prefix : List(Mark), U64 -> U64
prefix = |marks, past| if (past == 0) 0 else mark_at(marks, past - 1).through

mark_at : List(Mark), U64 -> Mark
mark_at = |marks, index| marks.get(index) ?? crash "checked footnote mark index"

expect {
	plan = KernelFootnoteReserve.Plan.build(
		[
			{ line: 1, note: 6, height: 30 },
			{ line: 1, note: 7, height: 40 },
			{ line: 3, note: 8, height: 10 },
		],
		5,
		80,
	) ?? crash "valid note spans"
	KernelFootnoteReserve.Plan.range(plan, 0, 1) == { first: 0, end: 0, height: 0 }
		and KernelFootnoteReserve.Plan.range(plan, 1, 2) == { first: 0, end: 2, height: 70 }
		and KernelFootnoteReserve.Plan.range(plan, 2, 4) == { first: 2, end: 3, height: 10 }
		and KernelFootnoteReserve.Plan.fit_lines(plan, 0, 5, 10, 89) == 1
		and KernelFootnoteReserve.Plan.fit_lines(plan, 0, 5, 10, 90) == 2
		and KernelFootnoteReserve.Plan.fit_lines(plan, 1, 4, 10, 79) == 0
		and KernelFootnoteReserve.Plan.fit_lines(plan, 1, 4, 10, 80) == 1
}
