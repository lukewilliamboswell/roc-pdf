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
			crash "text-layout facade authoring repetition count is invalid"
		}
		Ok(value) => value
	}
	result = match mode {
		"builder" => Fixture.normalize_builder(repetitions)
		"ordered" => Fixture.ordered_facade(repetitions)
		"layout" => Fixture.line_layout(repetitions)
		"lines" => Fixture.line_facade(repetitions)
		"pages" => Fixture.page_layout(repetitions)
		"paginate" => Fixture.page_facade(repetitions)
		"semantics" => Fixture.semantic_facade(repetitions)
		"shape" => Fixture.shape_facade(repetitions)
		"simple" => Fixture.normalize_simple(repetitions)
		"source-shared" => Fixture.source_cache_shared(repetitions)
		"source-unique" => Fixture.source_cache_unique(repetitions)
		_ => {
			crash "text-layout facade authoring mode is invalid"
		}
	}
	match result {
		Err(_) => {
			crash "text-layout facade authoring evidence failed"
		}
		Ok(value) => value
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "text-layout facade authoring argument missing"
	}
	Ok(value) => value
}
