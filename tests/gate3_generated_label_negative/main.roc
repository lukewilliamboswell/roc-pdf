app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/generated_label_evidence.roc",
}

import evidence.Gate3GeneratedLabelEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	runtime_guard = match U64.from_str(list_at(args, 1)) {
		Err(_) => crash "Gate 3 generated-label negative argument is invalid"
		Ok(value) => value
	}
	Gate3GeneratedLabelEvidence.negative(runtime_guard) ?? crash "Gate 3 generated-label negative evidence failed"
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "Gate 3 generated-label negative argument missing"
	Ok(value) => value
}
