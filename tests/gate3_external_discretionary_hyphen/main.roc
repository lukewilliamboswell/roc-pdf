app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| match Gate3ActualTextEvidence.external_discretionary_hyphen_text(args.len() - 1) {
	Ok(output) => output
	Err(_) => crash "Gate 3 external discretionary-hyphen evidence failed"
}
