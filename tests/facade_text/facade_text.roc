app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = list_at(args, 1)
	repetitions = match U64.from_str(list_at(args, 2)) {
		Err(_) => {
			crash "text-layout facade text repetition count is invalid"
		}
		Ok(value) => value
	}
	result = match mode {
		"materialize" => Fixture.materialize(repetitions)
		"prepare" => Fixture.prepare(repetitions)
		_ => {
			crash "text-layout facade text mode is invalid"
		}
	}
	match result {
		Err(_) => {
			crash "text-layout facade text evidence failed"
		}
		Ok(value) => value
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "text-layout facade text argument missing"
	}
	Ok(value) => value
}
