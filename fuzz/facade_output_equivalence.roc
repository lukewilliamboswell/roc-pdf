## TODO(pin-bump): this target passes `roc check` but cannot be built under the
## pinned compiler, because `roc build --fuzz` requires the LLVM backend and any
## LLVM build of the `Pdf` facade pipeline panics there with "record update base
## type differed from its result type in SpecConstr". The existing
## `tests/gate3_pdf_facade_chunks/main.roc` reproduces it under `--opt=speed`
## alone, so this is not specific to the fuzz target.
##
## Fixed upstream by `47a14ba38c` (2026-08-13), which the pinned
## `nightly-2026-08-08-195c9e7` predates. Verified against upstream
## `f70f90af36`: this target builds and runs clean. Remove this note when
## `.roc-version` moves past that commit; see fuzz/README.md.
app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.2.1/9Qpttb6LTgcMaVsSBLsnaiS2mDUrf6Bxa6dX9Rqwviz4.tar.zst",
	pdf_quality: "../package/fuzz_evidence.roc",
}

import fuzz.Fuzz
import pdf_quality.Gate3FacadeFuzzTargets

Input := {
	blocks : List({ items : List(Str), kind : U8, level : U8, text : Str }),
	language : U8,
	title : Str,
}.{
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
			language: Fuzz.u8,
			title: Fuzz.str,
		}.Fuzz
	}
}

test : Input -> Fuzz.Outcome
test = |Input.(input)| {
	if Gate3FacadeFuzzTargets.facade_output(input) Fuzz.keep else crash "facade output contracts disagreed"
}

target = Fuzz.target({
	name: "roc-pdf-facade-output-equivalence",
	test,
	show: |input| Str.inspect(input),
})
