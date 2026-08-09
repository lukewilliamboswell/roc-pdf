app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3ShapeEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Err(OutOfBounds) => {
			crash "Gate 3 shaping evidence requires a mode"
		}
		Ok(value) => value
	}
	if mode == "shape" {
		return match Gate3ShapeEvidence.shaping(args.len() - 2) {
			Err(_) => {
				crash "Gate 3 shaping evidence failed"
			}
			Ok(result) => result
		}
	}
	crash "unknown Gate 3 shaping evidence mode"
}
