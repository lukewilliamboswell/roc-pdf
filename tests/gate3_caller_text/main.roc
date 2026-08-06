app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/caller_evidence.roc",
}

import evidence.Gate3CallerTextEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| match Gate3CallerTextEvidence.visible_text(args.len() - 1) {
	Err(_) => {
		crash "Gate 3 caller-font text evidence failed"
	}
	Ok(result) => result
}
