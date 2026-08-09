app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = match args.get(1) {
		Ok("malformed") => Gate3ActualTextEvidence.soft_hyphen_negative("malformed", args.len() - 2)
		Ok("unselected") => Gate3ActualTextEvidence.soft_hyphen_negative("unselected", args.len() - 2)
		Ok("external") => Gate3ActualTextEvidence.soft_hyphen_negative("external", args.len() - 2)
		Err(OutOfBounds) => Gate3ActualTextEvidence.soft_hyphen_text(args.len() - 1)
		Ok(_) => crash "Gate 3 soft-hyphen evidence mode is invalid"
	}
	match result {
		Ok(output) => output
		Err(_) => crash "Gate 3 soft-hyphen evidence failed"
	}
}
