app [main!] {
	pf: platform "../platform/main.roc",
}

import Fixture

main! : List(Str) => List(U8)
main! = |args| {
	percent_offset = if args.len() == 1 {
		0
	} else {
		431
	}
	Fixture.placeholder_pdf(percent_offset)
}
