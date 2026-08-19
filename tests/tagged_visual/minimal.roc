app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| match Fixture.minimal_pdf(if args.len() == 1 0 else 1) {
	Err(_) => {
		crash "tagged-visual evidence generation failed"
	}
	Ok(bytes) => { bytes, work: [1, bytes.len()] }
}
