app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Err(OutOfBounds) => {
			crash "text-layout shaping evidence requires a mode"
		}
		Ok(value) => value
	}
	if mode == "shape" {
		return match Fixture.shaping(args.len() - 2) {
			Err(_) => {
				crash "text-layout shaping evidence failed"
			}
			Ok(result) => result
		}
	}
	crash "unknown text-layout shaping evidence mode"
}
