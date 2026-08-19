app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
	unicode: "https://github.com/roc-lang/unicode/releases/download/4.0.0/3DGC3M4b2pxaRLg4i8cmxWkm2E2WbCPCLntQzf2mkbUV.tar.zst",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| match Fixture.external_discretionary_hyphen_text(args.len() - 1) {
	Ok(output) => output
	Err(_) => crash "text-layout external discretionary-hyphen evidence failed"
}
