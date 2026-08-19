app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Err(OutOfBounds) => {
			crash "text-layout subset evidence requires a mode"
		}
		Ok(value) => value
	}
	if mode == "program" {
		return match Fixture.font_program(args.len() - 2) {
			Err(_) => {
				crash "text-layout font-program evidence failed"
			}
			Ok(result) => result
		}
	}
	if mode == "subset" {
		return match Fixture.font_subset(args.len() - 2) {
			Err(_) => {
				crash "text-layout font-subset evidence failed"
			}
			Ok(result) => result
		}
	}
	crash "unknown text-layout subset evidence mode"
}
