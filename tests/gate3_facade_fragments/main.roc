app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3FacadeFragmentEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = list_at(args, 1)
	repetitions = match U64.from_str(list_at(args, 2)) {
		Err(_) => {
			crash "Gate 3 facade fragment repetition count is invalid"
		}
		Ok(value) => value
	}
	result = match mode {
		"arena" => Gate3FacadeFragmentEvidence.arena(repetitions)
		"negative" => Gate3FacadeFragmentEvidence.negative(repetitions)
		"prepare" => Gate3FacadeFragmentEvidence.prepare(repetitions)
		"scene" => Gate3FacadeFragmentEvidence.scene_validate(repetitions)
		"validate" => Gate3FacadeFragmentEvidence.validate(repetitions)
		_ => {
			crash "Gate 3 facade fragment mode is invalid"
		}
	}
	match result {
		Err(_) => {
			crash "Gate 3 facade fragment evidence failed"
		}
		Ok(value) => value
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "Gate 3 facade fragment argument missing"
	}
	Ok(value) => value
}
