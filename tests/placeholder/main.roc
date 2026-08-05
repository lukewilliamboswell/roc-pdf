app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Foo

main! : List(Str) => List(U8)
main! = |args| {
	percent_offset = if args.len() == 1 {
		0
	} else {
		431
	}
	Foo.placeholder_pdf(percent_offset)
}
