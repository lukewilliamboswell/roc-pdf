app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	match Fixture.atomic_limit_negatives(args.len()) {
		Ok(result) => result
		Err(_) => crash "text-layout UAX atomic limit negative failed"
	}
}
