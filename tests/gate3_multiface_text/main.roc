app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

## Advanced boundary proof: ordered caller/test faces are selected per source
## cluster before shaping, then emitted as two resources without fallback.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = Gate3ActualTextEvidence.multi_face_text(args.len() - 1)
	match result {
		Ok(output) => output
		Err(_) => crash "Gate 3 multi-face output evidence failed"
	}
}
