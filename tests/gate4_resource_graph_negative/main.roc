app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate4ResourceGraphEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	match Gate4ResourceGraphEvidence.atomic_negatives(args.len()) {
		Ok(result) => result
		Err(_) => {
			crash "Gate 4 resource-graph atomic negatives failed"
		}
	}
}
