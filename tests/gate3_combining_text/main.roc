app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

## One explicit advanced decomposed combining-mark run. The A + U+0300 source,
## cluster, and precomposed-glyph facts are supplied to validation; PDF
## lowering never normalizes the source or infers Unicode from the glyph ID.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = match args.get(1) {
		Ok("negative") => Gate3ActualTextEvidence.combining_negative(args.len() - 2)
		Ok(_) | Err(OutOfBounds) => Gate3ActualTextEvidence.combining_text(args.len() - 1)
	}
	match result {
		Err(_) => crash "Gate 3 combining text evidence failed"
		Ok(output) => output
	}
}
