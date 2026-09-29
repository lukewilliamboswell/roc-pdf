import Layout

## Deterministic reference stabilization (architecture, "Layout, shaping,
## and stabilization"). Each pass consumes an explicit reference state and
## the previous pass's candidate, and returns the complete resolved state
## with a new candidate. An identical consecutive state is success; the
## repetition of an earlier non-identical state is a cycle; exhausting the
## pass budget is exhaustion. No attempted state is accepted as an
## approximation, and only compact states are retained: the current
## candidate and the states seen so far (at most the pass budget), never an
## earlier candidate.
KernelStabilization :: [].{

	## A compact exact reference state: the physical page count and the
	## resolved value of every other reference, in reference order. Page
	## furniture fields resolve from the page count alone, so their states
	## carry no further values.
	State : { pages : U64, values : List(U64) }

	## The state before any pass has resolved a reference.
	initial : State
	initial = { pages: 0, values: [] }

	## Run passes from `initial` until two consecutive states are identical,
	## an earlier non-identical state repeats, or `budget` passes are spent.
	## `step` receives the state to consume, the previous candidate, and the
	## one-based pass number. `work` in the outcome counts exact state
	## comparisons.
	stabilize : State, U64, (State, [Candidate(c), NoCandidate], U64 -> Try({ candidate : c, state : State }, e)) -> Try({ candidate : [Candidate(c), NoCandidate], outcome : Layout.Stabilization(State) }, e)
	stabilize = |start, budget, step| run(start, budget, step)
}

run : KernelStabilization.State, U64, (KernelStabilization.State, [Candidate(c), NoCandidate], U64 -> Try({ candidate : c, state : KernelStabilization.State }, e)) -> Try({ candidate : [Candidate(c), NoCandidate], outcome : Layout.Stabilization(KernelStabilization.State) }, e)
run = |start, budget, step| {
	var $history = [start]
	var $current = start
	var $candidate = NoCandidate
	var $comparisons = 0
	var $pass = 1
	while $pass <= budget {
		stepped = step($current, $candidate, $pass)?
		next = stepped.state
		$comparisons = $comparisons + 1
		if next == $current {
			return Ok({ candidate: Candidate(stepped.candidate), outcome: Stable({ passes: $pass, state: next, work: $comparisons }) })
		}

		## A repeated earlier state is confirmed by exact equality; the
		## history is bounded by the pass budget.
		var $seen = 0
		while $seen + 1 < $history.len() {
			$comparisons = $comparisons + 1
			if list_at($history, $seen) == next {
				return Ok({ candidate: Candidate(stepped.candidate), outcome: Cycle({ first_seen_pass: $seen, repeated: next, repeated_at_pass: $pass }) })
			}
			$seen = $seen + 1
		}
		$history = $history.append(next)
		$current = next
		$candidate = Candidate(stepped.candidate)
		$pass = $pass + 1
	}
	Ok({ candidate: $candidate, outcome: BudgetExhausted({ attempted: $current, passes: budget, work: $comparisons }) })
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "stabilization history index escaped"
}

## A synthetic system whose second pass repeats the first pass's state
## stabilizes in exactly two passes, as page furniture does.
expect {
	stepped = KernelStabilization.stabilize(KernelStabilization.initial, 4, |_state, _candidate, pass| Ok({ candidate: pass, state: { pages: 3, values: [] } }))
	match stepped {
		Ok({ candidate: Candidate(2), outcome: Stable({ passes: 2, state: { pages: 3, values: [] }, work: _ }) }) => True
		_ => False
	}
}

## A synthetic system that alternates between two states is a cycle at the
## pass that repeats the earlier non-identical state.
expect {
	stepped = KernelStabilization.stabilize(
		KernelStabilization.initial,
		4,
		|state, _candidate, pass| {
			pages = if state.pages == 2 3 else 2
			Ok({ candidate: pass, state: { pages, values: [] } })
		},
	)
	match stepped {
		Ok({ outcome: Cycle({ first_seen_pass: 1, repeated: { pages: 2, values: [] }, repeated_at_pass: 3 }), .. }) => True
		_ => False
	}
}

## A synthetic system that never repeats exhausts the fixed pass budget and
## reports its last attempted state, never accepting it.
expect {
	stepped = KernelStabilization.stabilize(KernelStabilization.initial, 4, |state, _candidate, _pass| Ok({ candidate: {}, state: { pages: state.pages + 1, values: [state.pages] } }))
	match stepped {
		Ok({ outcome: BudgetExhausted({ attempted: { pages: 4, values: [3] }, passes: 4, work: _ }), .. }) => True
		_ => False
	}
}

## A failing pass propagates its error unchanged.
expect {
	stepped : Try({ candidate : [Candidate({}), NoCandidate], outcome : Layout.Stabilization(KernelStabilization.State) }, [Rejected])
	stepped = KernelStabilization.stabilize(KernelStabilization.initial, 4, |_state, _candidate, _pass| Err(Rejected))
	match stepped {
		Err(Rejected) => True
		_ => False
	}
}
