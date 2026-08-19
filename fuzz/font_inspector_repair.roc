app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.2.1/9Qpttb6LTgcMaVsSBLsnaiS2mDUrf6Bxa6dX9Rqwviz4.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import FontTargets

Input := { edits : List(FontTargets.Edit), font : U8 }.{
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
	if FontTargets.inspect_repaired(input) Fuzz.keep else crash "repaired font inspection violated retained facts"
}

target = Fuzz.target({
	name: "roc-pdf-font-inspector-repair",
	test,
	show: |input| Str.inspect(input),
})
