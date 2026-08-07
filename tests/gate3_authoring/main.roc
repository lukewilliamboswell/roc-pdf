app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3FacadeEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = list_at(args, 1)
	repetitions = match U64.from_str(list_at(args, 2)) {
		Err(_) => {
			crash "Gate 3 facade authoring repetition count is invalid"
		}
		Ok(value) => value
	}
	result = match mode {
		"builder" => Gate3FacadeEvidence.normalize_builder(repetitions)
		"layout" => Gate3FacadeEvidence.line_layout(repetitions)
		"simple" => Gate3FacadeEvidence.normalize_simple(repetitions)
		_ => {
			crash "Gate 3 facade authoring mode is invalid"
		}
	}
	match result {
		Err(_) => {
			crash "Gate 3 facade authoring evidence failed"
		}
		Ok(value) => value
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "Gate 3 facade authoring argument missing"
	}
	Ok(value) => value
}
