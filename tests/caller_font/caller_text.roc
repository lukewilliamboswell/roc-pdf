app [main!] {
	pdf: "../../package/all.roc",
	pf: platform "../platform/main.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| match Fixture.visible_text(args.len() - 1) {
	Err(_) => {
		crash "text-layout caller-font text evidence failed"
	}
	Ok(result) => result
}
