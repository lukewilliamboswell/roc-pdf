app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	match Fixture.atomic_negatives(args.len()) {
		Ok(result) => result
		Err(_) => {
			crash "production-visual resource-graph atomic negatives failed"
		}
	}
}
