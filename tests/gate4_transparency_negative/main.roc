app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate4TransparencyEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	context = match args.get(1) {
		Ok(text) => match U64.from_str(text) {
			Ok(value) => value
			Err(_) => {
				crash "Gate 4 transparency negative context must be an unsigned integer"
			}
		}
		Err(OutOfBounds) => {
			crash "Gate 4 transparency negatives require a runtime context"
		}
	}

	match Gate4TransparencyEvidence.atomic_negatives(context) {
		Ok(value) => value
		Err(_) => {
			crash "Gate 4 transparency negative evidence failed"
		}
	}
}
