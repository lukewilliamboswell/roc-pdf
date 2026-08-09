app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3UnicodeVectorEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	match Gate3UnicodeVectorEvidence.uax_boundary_vectors(args.len()) {
		Ok(result) => result
		Err(_) => crash "Gate 3 UAX boundary-vector evidence failed"
	}
}
