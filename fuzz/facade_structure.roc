app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.2.1/9Qpttb6LTgcMaVsSBLsnaiS2mDUrf6Bxa6dX9Rqwviz4.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import pdf.Document
import pdf.Pdf
import StructureOracle

## The generated shape is deliberately the same one `facade_output_equivalence`
## uses, because that generator already produces documents that survive metadata
## validation, so the budget is spent on emitted structure rather than on
## rediscovering that a malformed language tag is rejected.
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

## `facade_output_equivalence` only checks that output agrees with itself: that
## it is deterministic, and that the buffered and chunked encoders produce the
## same bytes. Nothing there asks whether those bytes are a valid file, so an
## emitter that consistently produced the same broken document would pass it.
## This target closes that gap by requiring every accepted document to satisfy
## an independent structural oracle.
##
## A typed facade error is an ordinary outcome: rejecting a document is a
## contract, not a defect. Only bytes the facade claims to have produced are
## held to the structure.
test : Input -> Fuzz.Outcome
test = |Input.(input)| {
	document = Pdf.document({
		contents: input.blocks.map(block_for),
		language: language_for(input.language),
		title: input.title,
	})
	match Pdf.to_bytes_with(document, Pdf.Options.default) {
		Err(_) => Fuzz.keep
		Ok(bytes) => match StructureOracle.check(bytes) {
			Ok(_) => Fuzz.keep
			Err(failure) => crash "the structural oracle rejected emitted bytes: ${Str.inspect(failure)}"
		}
	}
}

target = Fuzz.target({
	name: "roc-pdf-facade-structure",
	test,
	show: |input| Str.inspect(input),
})

block_for : { items : List(Str), kind : U8, level : U8, text : Str } -> Document.Block
block_for = |block| match block.kind % 4 {
	0 => Pdf.title(block.text)
	1 => Pdf.heading(block.level % 6 + 1, block.text)
	2 => Pdf.paragraph(block.text)
	_ => Pdf.bullets(block.items)
}

## A closed set of valid tags keeps most generated documents past metadata
## validation, which is what gets the generator to the emitter at all.
language_for : U8 -> Str
language_for = |choice| match choice % 4 {
	0 => "en-AU"
	1 => "en-GB"
	2 => "de-DE"
	_ => "ja-JP"
}
