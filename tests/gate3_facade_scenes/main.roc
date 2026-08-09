app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3FacadeSceneEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = list_at(args, 1)
	repetitions = match U64.from_str(list_at(args, 2)) {
		Err(_) => {
			crash "Gate 3 facade scene repetition count is invalid"
		}
		Ok(value) => value
	}
	result = match mode {
		"arena" => Gate3FacadeSceneEvidence.arena(repetitions)
		"negative" => Gate3FacadeSceneEvidence.negative(repetitions)
		"prepare" => Gate3FacadeSceneEvidence.prepare(repetitions)
		_ => {
			crash "Gate 3 facade scene mode is invalid"
		}
	}
	match result {
		Err(_) => {
			crash "Gate 3 facade scene evidence failed"
		}
		Ok(value) => value
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "Gate 3 facade scene argument missing"
	}
	Ok(value) => value
}
