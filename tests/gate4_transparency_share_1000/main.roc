app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate4TransparencyEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => {
			crash "Gate 4 transparency evidence requires a scenario mode"
		}
	}
	scale = match args.get(2) {
		Ok(text) => match U64.from_str(text) {
			Ok(value) => value
			Err(_) => {
				crash "Gate 4 transparency scale must be an unsigned integer"
			}
		}
		Err(OutOfBounds) => {
			crash "Gate 4 transparency evidence requires a scale"
		}
	}

	match Gate4TransparencyEvidence.scenario(mode, scale) {
		Ok(value) => value
		Err(_) => {
			crash "Gate 4 transparency evidence failed"
		}
	}
}
