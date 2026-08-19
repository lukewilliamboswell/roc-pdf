app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
	unicode: "https://github.com/roc-lang/unicode/releases/download/4.0.0/3DGC3M4b2pxaRLg4i8cmxWkm2E2WbCPCLntQzf2mkbUV.tar.zst",
}

import Fixture

## A Latin cluster falsely itemized as Hani is rejected by the finite policy
## before any shaped store or PDF plan can exist.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = Fixture.multi_face_negative(args.len() - 1)
	match result {
		Ok(output) => output
		Err(_) => crash "text-layout multi-face negative evidence failed"
	}
}
