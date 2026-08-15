app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.2.1/9Qpttb6LTgcMaVsSBLsnaiS2mDUrf6Bxa6dX9Rqwviz4.tar.zst",
	pdf_quality: "../package/fuzz_evidence.roc",
}

import fuzz.Fuzz
import pdf_quality.Gate3FuzzTargets

## Glyph choices and the retained budget are sized against the widest fixture,
## which has 1376 glyphs. A `U8` choice could select only its first 256 glyphs,
## and a budget capped at 96 rejected every large subset before it was built.
Input := { font : U8, glyphs : List(U64), retained_limit : U64 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| {
		{
			font: Fuzz.u8_in(0, 4),
			glyphs: Fuzz.list(Fuzz.u64_in(0, 2047), 128),
			retained_limit: Fuzz.u64_in(0, 1536),
		}.Fuzz
	}
}

test : Input -> Fuzz.Outcome
test = |input| {
	if Gate3FuzzTargets.subset_roundtrip(input) Fuzz.keep else crash "font subset round trip violated its plan"
}

target = Fuzz.target({
	name: "roc-pdf-font-subset-roundtrip",
	test,
	show: |input| Str.inspect(input),
})
