app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3FacadeOutputEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	runtime_guard = match U64.from_str(list_at(args, 1)) {
		Err(_) => crash "Gate 3 facade output negative numeric argument is invalid"
		Ok(parsed) => parsed
	}
	match Gate3FacadeOutputEvidence.negative(runtime_guard) {
		Err(_) => crash "Gate 3 facade output negative evidence failed"
		Ok(output) => output
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "Gate 3 facade output negative argument missing"
	Ok(value) => value
}
