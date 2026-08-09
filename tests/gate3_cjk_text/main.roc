app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/actual_text_evidence.roc",
}

import evidence.Gate3ActualTextEvidence

## One explicit advanced caller-style Han run. The font is test-only and the
## source, language, script, glyph, cluster, and width facts are not inferred
## by PDF lowering.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = match args.get(1) {
		Ok("negative") => Gate3ActualTextEvidence.cjk_negative(args.len() - 2)
		Ok(_) | Err(OutOfBounds) => Gate3ActualTextEvidence.cjk_text(args.len() - 1)
	}
	match result {
		Err(_) => crash "Gate 3 CJK text evidence failed"
		Ok(output) => output
	}
}
