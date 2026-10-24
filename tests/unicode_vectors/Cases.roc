import Fixture

## The unicode_vectors family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		BoundaryVectors,
		AtomicLimits,
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			BoundaryVectors => Fixture.uax_boundary_vectors(1)
			AtomicLimits => Fixture.atomic_limit_negatives(1)
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: unicode_vectors fixture rejected the typed case"
		}
	}
}
