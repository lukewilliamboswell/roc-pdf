app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| match Gate3ActualTextEvidence.reordered_text(args.len() - 1) {
	Err(_) => {
		crash "Gate 3 ActualText evidence failed"
	}
	Ok(result) => result
}
