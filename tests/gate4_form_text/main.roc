app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate4FormTextEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	guard = match args.get(1) {
		Ok(text) => match U64.from_str(text) {
			Ok(value) => value
			Err(_) => {
				crash "Gate 4 form text guard must be an unsigned integer"
			}
		}
		Err(OutOfBounds) => {
			crash "Gate 4 form text evidence requires a runtime guard"
		}
	}

	match Gate4FormTextEvidence.text_form(guard) {
		Ok(value) => value
		Err(_) => {
			crash "Gate 4 form text evidence failed"
		}
	}
}
