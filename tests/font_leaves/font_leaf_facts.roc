app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => {
			crash "production-visual font-leaf evidence requires a scenario mode"
		}
	}
	scale = match args.get(2) {
		Ok(text) => match U64.from_str(text) {
			Ok(value) => value
			Err(_) => {
				crash "production-visual font-leaf scale must be an unsigned integer"
			}
		}
		Err(OutOfBounds) => {
			crash "production-visual font-leaf evidence requires a scale"
		}
	}

	match Fixture.scenario(mode, scale) {
		Ok(value) => value
		Err(_) => {
			crash "production-visual font-leaf evidence failed"
		}
	}
}
