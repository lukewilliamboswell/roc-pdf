app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

## The corrupt UTF-8 cluster range must fail before any CJK scene or PDF plan
## exists; its blank carrier is the transactional test result, not a fallback.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	match Gate3ActualTextEvidence.cjk_negative(args.len() - 1) {
		Err(_) => crash "Gate 3 CJK negative evidence failed"
		Ok(output) => output
	}
}
