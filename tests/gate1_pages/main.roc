app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate1Evidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = if args.len() > 1 {
		match args.get(1) {
			Ok(value) => value
			Err(OutOfBounds) => ""
		}
	} else {
		""
	}
	if mode == "indexes" or mode == "lexical" or mode == "outlines" or mode == "resources" {
		entry_count = if args.len() > 2 {
			match args.get(2) {
				Ok(text) => match U64.from_str(text) {
					Ok(value) => value
					Err(_) => 0
				}
				Err(OutOfBounds) => 0
			}
		} else {
			0
		}
		if mode == "indexes" {
			Gate1Evidence.generate_blank_with_indexes(entry_count)
		} else if mode == "lexical" {
			Gate1Evidence.generate_blank_with_lexical_values(entry_count)
		} else if mode == "outlines" {
			Gate1Evidence.generate_blank_with_outline(entry_count)
		} else {
			Gate1Evidence.generate_blank_with_resource_names(entry_count)
		}
	} else {
		page_count = if mode == "stress" 4096 else 2048
		Gate1Evidence.generate_blank(page_count)
	}
}
