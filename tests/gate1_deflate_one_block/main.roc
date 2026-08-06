app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate1Evidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	input_bytes = if args.len() > 1 {
		match args.get(1) {
			Ok(text) => match U64.from_str(text) {
				Ok(value) => value
				Err(_) => 0
			}
			Err(OutOfBounds) => 0
		}
	} else {
		0
	}
	Gate1Evidence.generate_deflate_stream(input_bytes)
}
