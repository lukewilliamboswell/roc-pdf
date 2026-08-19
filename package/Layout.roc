import Semantics

Layout :: [].{
	Unit :: I64.{

		## One point is exactly 1,000 layout units. The full I64 raw range is valid;
		## arithmetic introduced by later capabilities must report overflow explicitly.
		units_per_point : U64
		units_per_point = 1000

		from_raw : I64 -> Unit
		from_raw = |raw| Unit.(raw)

		## Convert whole PDF points to the package's fixed-point unit.
		points : I64 -> Unit
		points = |value| Unit.(value * 1000)

		## Construct a unit from the native 1/1000-point scale.
		millipoints : I64 -> Unit
		millipoints = |value| Unit.(value)

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

	StyleId :: U64.{
		from_index : U64 -> StyleId
		from_index = |index| StyleId.(index)

		index : StyleId -> U64
		index = |StyleId.(index)| index
	}

	ResourceStateId :: U64.{
		from_index : U64 -> ResourceStateId
		from_index = |index| ResourceStateId.(index)

		index : ResourceStateId -> U64
		index = |ResourceStateId.(index)| index
	}

	HyphenationDataId :: U64.{
		from_index : U64 -> HyphenationDataId
		from_index = |index| HyphenationDataId.(index)

		index : HyphenationDataId -> U64
		index = |HyphenationDataId.(index)| index
	}

	ReferenceId :: U64.{
		from_index : U64 -> ReferenceId
		from_index = |index| ReferenceId.(index)

		index : ReferenceId -> U64
		index = |ReferenceId.(index)| index
	}

	Point : { x : Unit, y : Unit }
	Size : { height : Unit, width : Unit }
	Rect : { origin : Point, size : Size }

	## Construct a point from whole PDF points.
	point : I64, I64 -> Point
	point = |x_points, y_points| { x: Unit.points(x_points), y: Unit.points(y_points) }

	## Construct a rectangle from whole-point x, y, width, and height values.
	rect : I64, I64, I64, I64 -> Rect
	rect = |x_points, y_points, width_points, height_points| {
		origin: point(x_points, y_points),
		size: { height: Unit.points(height_points), width: Unit.points(width_points) },
	}

	Constraints : {
		available : Size,
		column : U64,
		page : Semantics.PageId,
	}

	## Measurement and hyphenation caches include every fact that can affect
	## their result. Resource state is an interned identity of exact inputs.
	MeasurementKey : {
		constraints : Constraints,
		resources : ResourceStateId,
		source : SourceId,
		style : StyleId,
	}
	HyphenationKey : {
		language : Semantics.Language,
		patterns : HyphenationDataId,
		source : SourceId,
		source_range : Semantics.TextRange,
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
		comparison_work : U64,
		continuation_steps : U64,
		materialized_fragments : U64,
		reference_visits : U64,
		retained_cache_bytes : U64,
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

	Placement : {
		fragment : Semantics.FragmentId,
		geometry : Rect,
	}

	ReferenceValue : [Counter(I64), Page(Semantics.PageId), Text(Str), TotalPages(U64)]
	ResolvedReference : { id : ReferenceId, value : ReferenceValue }
	ResolvedReferences : {
		entries : List(ResolvedReference),
		state : ReferenceStateId,
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

## Exact layout cache identities remain compact dense IDs.
expect Layout.ResourceStateId.from_index(11).index() == 11

## Nested public type modules construct opaque layout units directly.
expect Layout.Unit.from_raw(25).raw() == 25

## Nested public type modules construct opaque component IDs directly.
expect Layout.ComponentId.from_index(12).index() == 12
