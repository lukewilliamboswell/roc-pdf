app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
	unicode: "https://github.com/roc-lang/unicode/releases/download/4.0.0/3DGC3M4b2pxaRLg4i8cmxWkm2E2WbCPCLntQzf2mkbUV.tar.zst",
}

import Fixture

## One real UAX #9 right-to-left paragraph. The resolved visual order and the
## mirrored bracket presentation are dependency facts; the logical source is
## preserved for extraction, never replaced by the paint order.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = match args.get(1) {
		Ok("negative") => Fixture.rtl_negative(args.len() - 2)
		Ok(_) | Err(OutOfBounds) => Fixture.rtl_text(args.len() - 1)
	}
	match result {
		Err(_) => crash "text-layout RTL text evidence failed"
		Ok(output) => output
	}
}
