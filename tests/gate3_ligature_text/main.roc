app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

## One test-only advanced `fi` ligature. The run retains its logical two-scalar
## source, parsed Type-4 `liga` fact, one painted ligature glyph, and the
## required ActualText extraction boundary.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| match Gate3ActualTextEvidence.ligature_text(args.len() - 1) {
	Err(_) => crash "Gate 3 ligature text evidence failed"
	Ok(output) => output
}
