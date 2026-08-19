app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	repetitions = if args.len() > 1 {
		match args.get(1) {
			Ok(text) => match U64.from_str(text) {
				Ok(value) => value
				Err(_) => {
					crash "text-layout repetition count must be an unsigned integer"
				}
			}
			Err(OutOfBounds) => {
				crash "text-layout argument index invariant failed"
			}
		}
	} else {
		crash "text-layout Unicode evidence requires a repetition count"
	}

	match Fixture.unicode_analysis(repetitions) {
		Ok(result) => result
		Err(_) => {
			crash "text-layout Unicode evidence failed"
		}
	}
}
