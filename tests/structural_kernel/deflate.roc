app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

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
	Fixture.generate_deflate_stream(input_bytes)
}
