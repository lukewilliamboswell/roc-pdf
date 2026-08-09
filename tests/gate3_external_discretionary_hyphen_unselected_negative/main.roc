app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| match Gate3ActualTextEvidence.soft_hyphen_negative("external-unselected", args.len() - 1) {
	Ok(output) => output
	Err(_) => crash "Gate 3 unselected external discretionary-hyphen evidence failed"
}
