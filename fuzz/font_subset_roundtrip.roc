app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import FontTargets

## Glyph choices and the retained budget are sized against the widest fixture,
## which has 1376 glyphs. A `U8` choice could select only its first 256 glyphs,
## and a budget capped at 96 rejected every large subset before it was built.
Input := { font : U8, glyphs : List(U64), retained_limit : U64 }.{
	parser_for : _
	encoder_for : _

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
test = |Input.(input)| {
	if input.font > 4 or input.glyphs.len() > 128 or input.retained_limit > 1536 or input.glyphs.any(|choice| choice > 2047) {
		return Fuzz.reject
	}
	if (FontTargets.subset_roundtrip(input)) Fuzz.keep else crash "font subset round trip violated its plan"
}

target = Fuzz.target({
	name: "roc-pdf-font-subset-roundtrip",
	examples: [
		Fuzz.example({ name: "regular-glyph-closure", revision: "1", make: || Input.{ font: 0, glyphs: [32, 65, 127, 512, 1375], retained_limit: 1536 } }),
		Fuzz.example({ name: "cjk-glyph-closure", revision: "1", make: || Input.{ font: 2, glyphs: [1], retained_limit: 1536 } }),
		Fuzz.example({ name: "bounded-plan-rejection", revision: "1", make: || Input.{ font: 0, glyphs: [65, 66], retained_limit: 0 } }),
	],

	test,
	show: |input| Str.inspect(input),
})
