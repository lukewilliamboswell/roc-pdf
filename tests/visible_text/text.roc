app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Err(OutOfBounds) => {
			crash "text-layout text evidence requires a mode"
		}
		Ok(value) => value
	}
	if mode == "visible" {
		return match Fixture.visible_text(args.len() - 2) {
			Err(_) => {
				crash "text-layout visible text evidence failed"
			}
			Ok(result) => result
		}
	}
	crash "unknown text-layout text evidence mode"
}
