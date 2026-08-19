app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => {
			crash "production-visual resource-graph evidence requires a scenario mode"
		}
	}
	scale = match args.get(2) {
		Ok(text) => match U64.from_str(text) {
			Ok(value) => value
			Err(_) => {
				crash "production-visual resource-graph scale must be an unsigned integer"
			}
		}
		Err(OutOfBounds) => {
			crash "production-visual resource-graph evidence requires a scale"
		}
	}

	result = if mode == "collide" {
		Fixture.collision_plan(scale)
	} else if mode == "shared" {
		Fixture.ownership_plan(Retained, scale)
	} else if mode == "unique" {
		Fixture.ownership_plan(Unique, scale)
	} else {
		Fixture.resource_plan(mode, scale)
	}

	match result {
		Ok(value) => value
		Err(_) => {
			crash "production-visual resource-graph evidence failed"
		}
	}
}
