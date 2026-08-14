app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

## The shortened combining UTF-8 cluster range must fail before any scene or
## PDF plan exists; its blank carrier is the transactional test result, not a
## fallback.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	match Gate3ActualTextEvidence.combining_negative(args.len() - 1) {
		Err(_) => crash "Gate 3 combining negative evidence failed"
		Ok(output) => output
	}
}
