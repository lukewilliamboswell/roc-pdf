app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

## One source-to-presentation case transformation. The uppercase expansion is
## resolved by the pinned dependency; the logical source is preserved for
## extraction, never replaced by the presentation.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = match args.get(1) {
		Ok("negative") => Gate3ActualTextEvidence.case_negative(args.len() - 2)
		Ok(_) | Err(OutOfBounds) => Gate3ActualTextEvidence.case_text(args.len() - 1)
	}
	match result {
		Err(_) => crash "Gate 3 case transformation evidence failed"
		Ok(output) => output
	}
}
