app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
	unicode: "https://github.com/roc-lang/unicode/releases/download/4.0.0/3DGC3M4b2pxaRLg4i8cmxWkm2E2WbCPCLntQzf2mkbUV.tar.zst",
}

import Fixture

## Advanced boundary proof: ordered caller/test faces are selected per source
## cluster before shaping, then emitted as two resources without fallback.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = Fixture.multi_face_text(args.len() - 1)
	match result {
		Ok(output) => output
		Err(_) => crash "text-layout multi-face output evidence failed"
	}
}
