app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	guard = match args.get(1) {
		Ok(text) => match U64.from_str(text) {
			Ok(value) => value
			Err(_) => {
				crash "production-visual form text guard must be an unsigned integer"
			}
		}
		Err(OutOfBounds) => {
			crash "production-visual form text evidence requires a runtime guard"
		}
	}

	match Fixture.text_form(guard) {
		Ok(value) => value
		Err(_) => {
			crash "production-visual form text evidence failed"
		}
	}
}
