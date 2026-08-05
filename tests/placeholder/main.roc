app [main!] {
	pf: platform "../platform/main.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	passes = if args.len() == 1 {
		1
	} else {
		4
	}
	bytes = Fixture.placeholder_pdf(0)

	var $pass = 0
	var $byte_visits = 0
	while $pass < passes {
		$byte_visits = $byte_visits + bytes.len()
		$pass = $pass + 1
	}

	{ bytes, work: [$pass, $byte_visits] }
}
