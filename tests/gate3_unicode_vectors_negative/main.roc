app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3UnicodeVectorEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	match Gate3UnicodeVectorEvidence.atomic_limit_negatives(args.len()) {
		Ok(result) => result
		Err(_) => crash "Gate 3 UAX atomic limit negative failed"
	}
}
