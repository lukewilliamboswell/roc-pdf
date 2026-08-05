app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate2Evidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| match Gate2Evidence.minimal_pdf(if args.len() == 1 0 else 1) {
	Err(_) => {
		crash "Gate 2 evidence generation failed"
	}
	Ok(bytes) => { bytes, work: [1, bytes.len()] }
}
