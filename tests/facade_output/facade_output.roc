app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = list_at(args, 1)
	value = match U64.from_str(list_at(args, 2)) {
		Err(_) => {
			crash "text-layout facade output numeric argument is invalid"
		}
		Ok(parsed) => parsed
	}
	result = match mode {
		"negative" => Fixture.negative(value)
		"probe" => Fixture.probe(value)
		"visible" => Fixture.visible(value)
		_ => {
			crash "text-layout facade output mode is invalid"
		}
	}
	match result {
		Err(_) => {
			crash "text-layout facade output evidence failed"
		}
		Ok(output) => output
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "text-layout facade output argument missing"
	}
	Ok(value) => value
}
