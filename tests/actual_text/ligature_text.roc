app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
	unicode: "https://github.com/roc-lang/unicode/releases/download/4.0.0/3DGC3M4b2pxaRLg4i8cmxWkm2E2WbCPCLntQzf2mkbUV.tar.zst",
}

import Fixture

## One test-only advanced `fi` ligature. The run retains its logical two-scalar
## source, parsed Type-4 `liga` fact, one painted ligature glyph, and the
## required ActualText extraction boundary.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| match Fixture.ligature_text(args.len() - 1) {
	Err(_) => crash "text-layout ligature text evidence failed"
	Ok(output) => output
}
