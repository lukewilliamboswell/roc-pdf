app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
	unicode: "https://github.com/roc-lang/unicode/releases/download/4.0.0/3DGC3M4b2pxaRLg4i8cmxWkm2E2WbCPCLntQzf2mkbUV.tar.zst",
}

import Fixture

## An output budget crossing and a cluster cardinality that contradicts the
## resolved expansion must both fail before any scene or PDF plan exists; the
## blank carrier is the transactional test result, not a fallback.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	match Fixture.case_negative(args.len() - 1) {
		Err(_) => crash "text-layout case transformation negative evidence failed"
		Ok(output) => output
	}
}
