app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3Evidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Ok(value) => value
		Err(OutOfBounds) => {
			crash "Gate 3 evidence requires a mode or repetition count"
		}
	}
	if mode == "font" {
		return match Gate3Evidence.font_inspection(args.len() - 2) {
			Ok(result) => result
			Err(_) => {
				crash "Gate 3 font evidence failed"
			}
		}
	}
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

	match Gate3Evidence.unicode_analysis(repetitions) {
		Ok(result) => result
		Err(_) => {
			crash "Gate 3 Unicode evidence failed"
		}
	}
}
