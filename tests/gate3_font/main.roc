app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3FontEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Err(OutOfBounds) => {
			crash "Gate 3 font evidence requires a mode"
		}
		Ok(value) => value
	}
	if mode == "font" {
		return match Gate3FontEvidence.font_inspection(args.len() - 2) {
			Err(_) => {
				crash "Gate 3 font inspection evidence failed"
			}
			Ok(result) => result
		}
	}
	if mode == "plan" {
		return match Gate3FontEvidence.font_planning(args.len() - 2) {
			Err(_) => {
				crash "Gate 3 font planning evidence failed"
			}
			Ok(result) => result
		}
	}
	if mode == "caller" {
		return match Gate3FontEvidence.caller_registration(args.len() - 2) {
			Err(_) => {
				crash "Gate 3 caller font registration evidence failed"
			}
			Ok(result) => result
		}
	}
	if mode == "multi" {
		return match Gate3FontEvidence.multi_face_planning(args.len() - 2) {
			Err(_) => {
				crash "Gate 3 multi-face planning evidence failed"
			}
			Ok(result) => result
		}
	}
	crash "unknown Gate 3 font evidence mode"
}
