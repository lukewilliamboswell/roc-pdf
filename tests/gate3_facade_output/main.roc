app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3FacadeOutputEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = list_at(args, 1)
	value = match U64.from_str(list_at(args, 2)) {
		Err(_) => {
			crash "Gate 3 facade output numeric argument is invalid"
		}
		Ok(parsed) => parsed
	}
	result = match mode {
		"probe" => Gate3FacadeOutputEvidence.probe(value)
		"visible" => Gate3FacadeOutputEvidence.visible(value)
		_ => {
			crash "Gate 3 facade output mode is invalid"
		}
	}
	match result {
		Err(_) => {
			crash "Gate 3 facade output evidence failed"
		}
		Ok(output) => output
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "Gate 3 facade output argument missing"
	}
	Ok(value) => value
}
