app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

## A mismatched paint sequence and an unmirrored bracket must both fail at the
## bidi handoff, before any scene or PDF plan exists; the blank carrier is the
## transactional test result, not a fallback.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	match Gate3ActualTextEvidence.rtl_negative(args.len() - 1) {
		Err(_) => crash "Gate 3 RTL negative evidence failed"
		Ok(output) => output
	}
}
