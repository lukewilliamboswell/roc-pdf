app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.2.1/9Qpttb6LTgcMaVsSBLsnaiS2mDUrf6Bxa6dX9Rqwviz4.tar.zst",
	pdf_quality: "../package/fuzz_evidence.roc",
}

import fuzz.Fuzz
import pdf_quality.Gate3FuzzTargets

Input := { font : U8, glyphs : List(U8), retained_limit : U8 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| {
		{
			font: Fuzz.u8_in(0, 4),
			glyphs: Fuzz.list(Fuzz.u8, 32),
			retained_limit: Fuzz.u8_in(0, 96),
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
