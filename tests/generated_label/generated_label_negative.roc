app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	runtime_guard = match U64.from_str(list_at(args, 1)) {
		Err(_) => crash "text-layout generated-label negative argument is invalid"
		Ok(value) => value
	}
	Fixture.negative(runtime_guard) ?? crash "text-layout generated-label negative evidence failed"
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "text-layout generated-label negative argument missing"
	Ok(value) => value
}
