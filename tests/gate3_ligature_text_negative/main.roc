app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

## A mismatched GSUB result cannot cross the advanced-shaping boundary. The
## blank carrier proves transactional rejection; it is never a text fallback.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| match Gate3ActualTextEvidence.ligature_negative(args.len() - 1) {
	Err(_) => crash "Gate 3 ligature negative evidence failed"
	Ok(output) => output
}
