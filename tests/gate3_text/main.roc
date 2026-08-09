app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3TextEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Err(OutOfBounds) => {
			crash "Gate 3 text evidence requires a mode"
		}
		Ok(value) => value
	}
	if mode == "visible" {
		return match Gate3TextEvidence.visible_text(args.len() - 2) {
			Err(_) => {
				crash "Gate 3 visible text evidence failed"
			}
			Ok(result) => result
		}
	}
	crash "unknown Gate 3 text evidence mode"
}
