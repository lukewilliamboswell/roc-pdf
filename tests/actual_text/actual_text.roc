app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
	unicode: "https://github.com/roc-lang/unicode/releases/download/4.0.0/3DGC3M4b2pxaRLg4i8cmxWkm2E2WbCPCLntQzf2mkbUV.tar.zst",
}

import Fixture

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	result = match args.get(1) {
		Ok("combining") => Fixture.combining_text(args.len() - 2)
		Ok("combining-negative") => Fixture.combining_negative(args.len() - 2)
		Ok("reordered") | Err(OutOfBounds) => Fixture.reordered_text(args.len() - 1)
		Ok(_) => {
			crash "text-layout ActualText evidence mode is invalid"
		}
	}
	match result {
		Err(_) => {
			crash "text-layout ActualText evidence failed"
		}
		Ok(output) => output
	}
}
