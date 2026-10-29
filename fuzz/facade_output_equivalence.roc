app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import InputBounds
import FacadeTargets

Input := {
	blocks : List({ items : List(Str), kind : U8, level : U8, text : Str }),
	compression : U8,
	language : U8,
	title : Str,
}.{
	parser_for : _
	encoder_for : _

	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| {
		{
			blocks: Fuzz.list(
				{
					items: Fuzz.list(Fuzz.str, 4),
					kind: Fuzz.u8,
					level: Fuzz.u8,
					text: Fuzz.str,
				}.Fuzz,
				8,
			),
			compression: Fuzz.u8,
			language: Fuzz.u8,
			title: Fuzz.str,
		}.Fuzz
	}
}

test : Input -> Fuzz.Outcome
test = |Input.(input)| {
	if !InputBounds.document({ blocks: input.blocks, title: input.title }) {
		return Fuzz.reject
	}
	if (FacadeTargets.facade_output(input)) Fuzz.keep else crash "facade output contracts disagreed"
}

target = Fuzz.target({
	name: "roc-pdf-facade-output-equivalence",
	examples: [
		Fuzz.example({ name: "paragraph-and-bullets", revision: "1", make: || Input.{ blocks: [{ items: [], kind: 2, level: 0, text: "Searchable report text." }, { items: ["First", "Second"], kind: 3, level: 0, text: "" }], compression: 0, language: 0, title: "Deterministic report" } }),
		Fuzz.example({ name: "atomic-text-rejection", revision: "1", make: || Input.{ blocks: [{ items: [], kind: 2, level: 0, text: "Unsupported: Ʞ" }], compression: 2, language: 0, title: "Rejected report" } }),
	],

	test,
	show: |input| Str.inspect(input),
})
