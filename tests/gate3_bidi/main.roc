app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3BidiEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	match Gate3BidiEvidence.single_level_boundary(args.len() - 1) {
		Err(_) => crash "Gate 3 bidi boundary evidence failed"
		Ok(result) => result
	}
}
