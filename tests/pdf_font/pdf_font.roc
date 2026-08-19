app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Err(OutOfBounds) => {
			crash "text-layout PDF font evidence requires a mode"
		}
		Ok(value) => value
	}
	if mode == "objects" {
		return match Fixture.font_objects(args.len() - 2) {
			Err(_) => {
				crash "text-layout PDF font object evidence failed"
			}
			Ok(result) => result
		}
	}
	crash "unknown text-layout PDF font evidence mode"
}
