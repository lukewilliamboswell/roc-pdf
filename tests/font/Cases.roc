import Fixture

## The font family's typed cases and their dispatch, run by a fixture group app.
##
## Each `context` is the runtime zero the fixture takes so that the compiler
## cannot evaluate the evidence at compile time.
Cases :: [].{
	Case : [
		Font({ context : U64 }),
		Plan({ context : U64 }),
		Caller({ context : U64 }),
		Multi({ context : U64 }),
		Probe({ clusters : U64, context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Font({ context }) =>
				match Fixture.font_inspection(context) {
					Err(_) => crash "text-layout font inspection evidence failed"
					Ok(result) => result
				}

			Plan({ context }) =>
				match Fixture.font_planning(context) {
					Err(_) => crash "text-layout font planning evidence failed"
					Ok(result) => result
				}

			Caller({ context }) =>
				match Fixture.caller_registration(context) {
					Err(_) => crash "text-layout caller font registration evidence failed"
					Ok(result) => result
				}

			Multi({ context }) =>
				match Fixture.multi_face_planning(context) {
					Err(_) => crash "text-layout multi-face planning evidence failed"
					Ok(result) => result
				}

			Probe({ clusters, context }) =>
				match Fixture.multi_face_probe_scale(clusters, context) {
					Err(_) => crash "text-layout adversarial probe evidence failed"
					Ok(result) => result
				}
		}
	}
}
