app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

## A Latin cluster falsely itemized as Hani is rejected by the finite policy
## before any shaped store or PDF plan can exist.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = Gate3ActualTextEvidence.multi_face_negative(args.len() - 1)
	match result {
		Ok(output) => output
		Err(_) => crash "Gate 3 multi-face negative evidence failed"
	}
}
