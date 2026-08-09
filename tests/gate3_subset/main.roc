app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3SubsetEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Err(OutOfBounds) => {
			crash "Gate 3 subset evidence requires a mode"
		}
		Ok(value) => value
	}
	if mode == "program" {
		return match Gate3SubsetEvidence.font_program(args.len() - 2) {
			Err(_) => {
				crash "Gate 3 font-program evidence failed"
			}
			Ok(result) => result
		}
	}
	if mode == "subset" {
		return match Gate3SubsetEvidence.font_subset(args.len() - 2) {
			Err(_) => {
				crash "Gate 3 font-subset evidence failed"
			}
			Ok(result) => result
		}
	}
	crash "unknown Gate 3 subset evidence mode"
}
