app [main!] {
	pf: platform "../platform/main.roc",
	evidence: "../../package/evidence.roc",
}

import evidence.Gate3PdfFontEvidence

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Err(OutOfBounds) => {
			crash "Gate 3 PDF font evidence requires a mode"
		}
		Ok(value) => value
	}
	if mode == "objects" {
		return match Gate3PdfFontEvidence.font_objects(args.len() - 2) {
			Err(_) => {
				crash "Gate 3 PDF font object evidence failed"
			}
			Ok(result) => result
		}
	}
	crash "unknown Gate 3 PDF font evidence mode"
}
