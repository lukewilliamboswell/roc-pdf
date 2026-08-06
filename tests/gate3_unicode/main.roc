app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3UnicodeEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	repetitions = if args.len() > 1 {
		match args.get(1) {
			Ok(text) => match U64.from_str(text) {
				Ok(value) => value
				Err(_) => {
					crash "Gate 3 repetition count must be an unsigned integer"
				}
			}
			Err(OutOfBounds) => {
				crash "Gate 3 argument index invariant failed"
			}
		}
	} else {
		crash "Gate 3 Unicode evidence requires a repetition count"
	}

	match Gate3UnicodeEvidence.unicode_analysis(repetitions) {
		Ok(result) => result
		Err(_) => {
			crash "Gate 3 Unicode evidence failed"
		}
	}
}
