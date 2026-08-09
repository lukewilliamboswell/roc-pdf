app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	guard = if args.len() == 1 0 else 1
	match Gate3ActualTextEvidence.supplementary_negative(guard) {
		Err(_) => crash "Gate 3 supplementary text negative evidence failed"
		Ok(output) => output
	}
}
