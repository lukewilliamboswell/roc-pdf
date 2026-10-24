import Fixture

## The placeholder family's typed cases and their dispatch, run by a fixture group app.
##
## `passes` is how many times the evidence walks the placeholder bytes.
Cases :: [].{
	Case : [
		Placeholder({ passes : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Placeholder({ passes }) => {
				bytes = placeholder_bytes

				var $pass = 0
				var $byte_visits = 0
				while $pass < passes {
					$byte_visits = $byte_visits + bytes.len()
					$pass = $pass + 1
				}

				{ bytes, work: [$pass, $byte_visits] }
			}
		}
	}
}

## The placeholder PDF is a compile-time constant, as it was when the call
## stood in the former argv application's `main!`: the evidence measures
## walking it, not building it.
placeholder_bytes : List(U8)
placeholder_bytes = Fixture.placeholder_pdf(0)
