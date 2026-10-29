app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import FontTargets

Input := { edits : List(FontTargets.Edit), font : U8 }.{
	parser_for : _
	encoder_for : _

	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| {
		{
			edits: Fuzz.list({ byte: Fuzz.u64, table: Fuzz.u8, value: Fuzz.u8 }.Fuzz, 24),
			font: Fuzz.u8_in(0, 4),
		}.Fuzz
	}
}

test : Input -> Fuzz.Outcome
test = |Input.(input)| {
	if input.edits.len() > 24 or input.font > 4 {
		return Fuzz.reject
	}
	if (FontTargets.inspect_repaired(input)) Fuzz.keep else crash "repaired font inspection violated retained facts"
}

target = Fuzz.target({
	name: "roc-pdf-font-inspector-repair",
	examples: [
		Fuzz.example({ name: "checksum-preserving-regular", revision: "1", make: || Input.{ edits: [], font: 0 } }),
		Fuzz.example({ name: "mutated-name-table", revision: "1", make: || Input.{ edits: [{ byte: 0, table: 5, value: 255 }], font: 1 } }),
	],

	test,
	show: |input| Str.inspect(input),
})
