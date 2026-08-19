app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
	unicode: "https://github.com/roc-lang/unicode/releases/download/4.0.0/3DGC3M4b2pxaRLg4i8cmxWkm2E2WbCPCLntQzf2mkbUV.tar.zst",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = match args.get(1) {
		Ok("malformed") => Fixture.soft_hyphen_negative("malformed", args.len() - 2)
		Ok("unselected") => Fixture.soft_hyphen_negative("unselected", args.len() - 2)
		Ok("external-malformed") => Fixture.soft_hyphen_negative("external-malformed", args.len() - 2)
		Ok("external-unselected") => Fixture.soft_hyphen_negative("external-unselected", args.len() - 2)
		Err(OutOfBounds) => Fixture.soft_hyphen_text(args.len() - 1)
		Ok(_) => crash "text-layout soft-hyphen evidence mode is invalid"
	}
	match result {
		Ok(output) => output
		Err(_) => crash "text-layout soft-hyphen evidence failed"
	}
}
