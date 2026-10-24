import Fixture

## The resource_graph family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Chain({ scale : U64 }),
		Fan({ scale : U64 }),
		Dense({ scale : U64 }),
		Collide({ scale : U64 }),
		Unique({ scale : U64 }),
		Shared({ scale : U64 }),
		AtomicNegatives({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Chain({ scale }) => Fixture.resource_plan("chain", scale)
			Fan({ scale }) => Fixture.resource_plan("fan", scale)
			Dense({ scale }) => Fixture.resource_plan("dense", scale)
			Collide({ scale }) => Fixture.collision_plan(scale)
			Unique({ scale }) => Fixture.ownership_plan(Unique, scale)
			Shared({ scale }) => Fixture.ownership_plan(Retained, scale)
			AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: resource_graph fixture rejected the typed case"
		}
	}
}
