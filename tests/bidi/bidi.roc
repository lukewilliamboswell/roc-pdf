app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture

## Pinned UAX #9 revision-51 vectors transcribed from the normative Unicode
## 17.0.0 BidiCharacterTest conformance file. The blank structural carrier is
## the common scenario protocol, not bidi output.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	match Fixture.uax9_vectors(args.len() - 1) {
		Err(_) => crash "text-layout UAX #9 vector evidence failed"
		Ok(result) => result
	}
}
