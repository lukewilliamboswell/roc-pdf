app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate4ResourceGraphEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => {
			crash "Gate 4 resource-graph evidence requires a scenario mode"
		}
	}
	scale = match args.get(2) {
		Ok(text) => match U64.from_str(text) {
			Ok(value) => value
			Err(_) => {
				crash "Gate 4 resource-graph scale must be an unsigned integer"
			}
		}
		Err(OutOfBounds) => {
			crash "Gate 4 resource-graph evidence requires a scale"
		}
	}

	result = if mode == "collide" {
		Gate4ResourceGraphEvidence.collision_plan(scale)
	} else if mode == "shared" {
		Gate4ResourceGraphEvidence.ownership_plan(Retained, scale)
	} else if mode == "unique" {
		Gate4ResourceGraphEvidence.ownership_plan(Unique, scale)
	} else {
		Gate4ResourceGraphEvidence.resource_plan(mode, scale)
	}

	match result {
		Ok(value) => value
		Err(_) => {
			crash "Gate 4 resource-graph evidence failed"
		}
	}
}
