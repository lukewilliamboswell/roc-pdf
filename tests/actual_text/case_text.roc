app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
	unicode: "https://github.com/roc-lang/unicode/releases/download/4.0.0/3DGC3M4b2pxaRLg4i8cmxWkm2E2WbCPCLntQzf2mkbUV.tar.zst",
}

import Fixture

## One source-to-presentation case transformation. The uppercase expansion is
## resolved by the pinned dependency; the logical source is preserved for
## extraction, never replaced by the presentation.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = match args.get(1) {
		Ok("negative") => Fixture.case_negative(args.len() - 2)
		Ok(_) | Err(OutOfBounds) => Fixture.case_text(args.len() - 1)
	}
	match result {
		Err(_) => crash "text-layout case transformation evidence failed"
		Ok(output) => output
	}
}
