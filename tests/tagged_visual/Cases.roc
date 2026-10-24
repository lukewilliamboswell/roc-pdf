import Fixture
import StressFixture

## The tagged-visual family's typed cases and their dispatch, run by a fixture group app.
##
## `context` is the runtime zero the minimal fixture takes so that the compiler
## cannot evaluate the evidence at compile time. `phase` selects where command
## stress stops: 0 runs every phase, 1 scene, 2 resource, 3 content.
Cases :: [].{
	Case : [
		Minimal({ context : U64 }),
		CommandStress({ command_count : U64, phase : U8 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Minimal({ context }) =>
				match Fixture.minimal_pdf(context) {
					Err(_) => crash "tagged-visual evidence generation failed"
					Ok(bytes) => { bytes, work: [1, bytes.len()] }
				}

			CommandStress({ command_count, phase }) =>
				match StressFixture.command_stress_phase(command_count, phase) {
					Err(_) => crash "tagged-visual command stress failed"
					Ok(result) => result
				}
		}
	}
}
