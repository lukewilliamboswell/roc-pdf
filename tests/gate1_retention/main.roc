app [main!] {
	pf: platform "../retention_platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate1Evidence

main! : List(Str) => {
	backing : List(U8),
	bytes : List(U8),
	owned : List(U8),
	shared : List(U8),
	source : List(U8),
	work : List(U64),
}
main! = |args| {
	fill = match args.get(1) {
		Ok(value) => U8.from_str(value) ?? 32
		Err(OutOfBounds) => 32
	}
	Gate1Evidence.retention_probe(fill)
}
