app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

## One real UAX #9 right-to-left paragraph. The resolved visual order and the
## mirrored bracket presentation are dependency facts; the logical source is
## preserved for extraction, never replaced by the paint order.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = match args.get(1) {
		Ok("negative") => Gate3ActualTextEvidence.rtl_negative(args.len() - 2)
		Ok(_) | Err(OutOfBounds) => Gate3ActualTextEvidence.rtl_text(args.len() - 1)
	}
	match result {
		Err(_) => crash "Gate 3 RTL text evidence failed"
		Ok(output) => output
	}
}
