app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
	unicode: "https://github.com/roc-lang/unicode/releases/download/4.0.0/3DGC3M4b2pxaRLg4i8cmxWkm2E2WbCPCLntQzf2mkbUV.tar.zst",
}

import Fixture

## The corrupt UTF-8 cluster range must fail before any CJK scene or PDF plan
## exists; its blank carrier is the transactional test result, not a fallback.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	match Fixture.cjk_negative(args.len() - 1) {
		Err(_) => crash "text-layout CJK negative evidence failed"
		Ok(output) => output
	}
}
