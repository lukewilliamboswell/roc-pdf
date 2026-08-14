app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

## An output budget crossing and a cluster cardinality that contradicts the
## resolved expansion must both fail before any scene or PDF plan exists; the
## blank carrier is the transactional test result, not a fallback.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	match Gate3ActualTextEvidence.case_negative(args.len() - 1) {
		Err(_) => crash "Gate 3 case transformation negative evidence failed"
		Ok(output) => output
	}
}
