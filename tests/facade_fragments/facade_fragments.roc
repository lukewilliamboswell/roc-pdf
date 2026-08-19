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
			crash "text-layout facade fragment repetition count is invalid"
		}
		Ok(value) => value
	}
	result = match mode {
		"arena" => Fixture.arena(repetitions)
		"negative" => Fixture.negative(repetitions)
		"output" => Fixture.output_validate(repetitions)
		"prepare" => Fixture.prepare(repetitions)
		"scene" => Fixture.scene_validate(repetitions)
		"validate" => Fixture.validate(repetitions)
		_ => {
			crash "text-layout facade fragment mode is invalid"
		}
	}
	match result {
		Err(_) => {
			crash "text-layout facade fragment evidence failed"
		}
		Ok(value) => value
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "text-layout facade fragment argument missing"
	}
	Ok(value) => value
}
