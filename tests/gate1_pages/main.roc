app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate1Evidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	page_count = if args.len() > 1 4096 else 2048
	Gate1Evidence.generate_blank(page_count)
}
