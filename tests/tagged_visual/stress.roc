app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import StressFixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	command_count = if args.len() > 1 {
		match args.get(1) {
			Ok(text) => match U64.from_str(text) {
				Ok(value) => value
				Err(_) => 0
			}
			Err(OutOfBounds) => 0
		}
	} else {
		0
	}
	phase = if args.len() > 2 {
		match args.get(2) {
			Ok("scene") => 1
			Ok("resource") => 2
			Ok("content") => 3
			_ => 0
		}
	} else {
		0
	}
	match StressFixture.command_stress_phase(command_count, phase) {
		Err(_) => {
			crash "tagged-visual command stress failed"
		}
		Ok(result) => result
	}
}
