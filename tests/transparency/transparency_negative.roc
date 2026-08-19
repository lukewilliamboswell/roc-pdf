app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	context = match args.get(1) {
		Ok(text) => match U64.from_str(text) {
			Ok(value) => value
			Err(_) => {
				crash "production-visual transparency negative context must be an unsigned integer"
			}
		}
		Err(OutOfBounds) => {
			crash "production-visual transparency negatives require a runtime context"
		}
	}

	match Fixture.atomic_negatives(context) {
		Ok(value) => value
		Err(_) => {
			crash "production-visual transparency negative evidence failed"
		}
	}
}
