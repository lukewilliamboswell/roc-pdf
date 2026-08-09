app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = match args.get(1) {
		Ok("negative") => Gate3ActualTextEvidence.supplementary_negative(args.len() - 2)
		Ok(_) | Err(OutOfBounds) => Gate3ActualTextEvidence.supplementary_text(args.len() - 1)
	}
	match result {
		Err(_) => crash "Gate 3 supplementary text evidence failed"
		Ok(output) => output
	}
}
