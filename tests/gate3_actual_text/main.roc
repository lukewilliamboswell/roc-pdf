app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = match args.get(1) {
		Ok("combining") => Gate3ActualTextEvidence.combining_text(args.len() - 2)
		Ok("combining-negative") => Gate3ActualTextEvidence.combining_negative(args.len() - 2)
		Ok("reordered") | Err(OutOfBounds) => Gate3ActualTextEvidence.reordered_text(args.len() - 1)
		Ok(_) => {
			crash "Gate 3 ActualText evidence mode is invalid"
		}
	}
	match result {
		Err(_) => {
			crash "Gate 3 ActualText evidence failed"
		}
		Ok(output) => output
	}
}
