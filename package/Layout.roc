import Semantics

Layout :: [].{
	Unit :: I64.{

		## One point is exactly 1,000 layout units. The full I64 raw range is valid;
		## arithmetic introduced by later gates must report overflow explicitly.
		units_per_point : U64
		units_per_point = 1000

		from_raw : I64 -> Unit
		from_raw = |raw| Unit.(raw)

		raw : Unit -> I64
		raw = |Unit.(raw)| raw
	}

	ComponentId :: U64.{
		from_index : U64 -> ComponentId
		from_index = |index| ComponentId.(index)

		index : ComponentId -> U64
		index = |ComponentId.(index)| index
	}

	SourceId :: U64.{
		from_index : U64 -> SourceId
		from_index = |index| SourceId.(index)

		index : SourceId -> U64
		index = |SourceId.(index)| index
	}

	ReferenceStateId :: U64.{
		from_index : U64 -> ReferenceStateId
		from_index = |index| ReferenceStateId.(index)

		index : ReferenceStateId -> U64
		index = |ReferenceStateId.(index)| index
	}

	Point : { x : Unit, y : Unit }
	Size : { height : Unit, width : Unit }
	Rect : { origin : Point, size : Size }

	Constraints : {
		available : Size,
		column : U64,
		page : Semantics.PageId,
	}

	Measurement : {
		break_candidates : List(Unit),
		minimum : Size,
		preferred : Size,
		work : Work,
	}

	Work : {
		cache_hits : U64,
		cache_misses : U64,
		candidate_visits : U64,
		materialized_fragments : U64,
		source_visits : U64,
	}

	## Continuations use scalar cursors and caller-defined compact state. They
	## never contain source suffixes or previously materialized scenes.
	Continuation(state) : {
		component : ComponentId,
		source : SourceId,
		source_cursor : U64,
		state : state,
	}

	Fragment : {
		geometry : Rect,
		occurrence : Semantics.OccurrenceId,
		source_range : Semantics.SourceRange,
	}

	FragmentResult(state) : [
		Complete({ fragment : Fragment, work : Work }),
		Continue({ continuation : Continuation(state), fragment : Fragment, work : Work }),
	]

	## Custom handlers are supplied to layout as a separate value. A document,
	## continuation, and PreparedDocument retain only data, never these functions.
	Handlers(state, err) : {
		fragment : Constraints, Continuation(state) -> Try(FragmentResult(state), err),
		measure : Constraints, SourceId -> Try(Measurement, err),
	}

	Stabilization(state) : [
		BudgetExhausted({ attempted : state, passes : U64, work : U64 }),
		Cycle({ first_seen_pass : U64, repeated : state, repeated_at_pass : U64 }),
		Stable({ passes : U64, state : state, work : U64 }),
	]
}

## The fixed-point scale is exactly 1,000 units per point.
expect Layout.Unit.units_per_point == 1000

## Opaque layout units preserve signed raw values.
expect Layout.Unit.from_raw(-25).raw() == -25

## Layout component IDs preserve their dense index.
expect Layout.ComponentId.from_index(3).index() == 3

## Reference state IDs preserve their dense index.
expect Layout.ReferenceStateId.from_index(9).index() == 9

## Nested public type modules construct opaque layout units directly.
expect Layout.Unit.from_raw(25).raw() == 25

## Nested public type modules construct opaque component IDs directly.
expect Layout.ComponentId.from_index(12).index() == 12
