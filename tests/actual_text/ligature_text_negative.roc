app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
	unicode: "https://github.com/roc-lang/unicode/releases/download/4.0.0/3DGC3M4b2pxaRLg4i8cmxWkm2E2WbCPCLntQzf2mkbUV.tar.zst",
}

import Fixture

## A mismatched GSUB result cannot cross the advanced-shaping boundary. The
## blank carrier proves transactional rejection; it is never a text fallback.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| match Fixture.ligature_negative(args.len() - 1) {
	Err(_) => crash "text-layout ligature negative evidence failed"
	Ok(output) => output
}
