app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.2.1/9Qpttb6LTgcMaVsSBLsnaiS2mDUrf6Bxa6dX9Rqwviz4.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import ThemeTargets

## Every theme knob is one unconstrained `U8`. The property maps each byte onto
## a sixteen-rung ladder of layout magnitudes, so a plain `Fuzz.u8` reaches
## every rung and the fuzzer spends its budget on combinations of extremes
## rather than on rediscovering that 11003 behaves like 11000.
##
## The generator decodes these fields in declaration order out of an input
## whose length libFuzzer raises only slowly, so a field placed behind a
## string-carrying one is starved: with `blocks` first, every retained corpus
## entry decoded with all fourteen knobs holding the same exhausted byte, and
## the campaign only ever tested one ladder rung applied to the whole theme at
## once. The knobs are therefore declared first, cheapest surface per byte
## leading, and the two content fields last.
Input := {
	body_leading : U8,
	body_size : U8,
	bullet_indent : U8,
	heading_leading : U8,
	heading_size : U8,
	margin_bottom : U8,
	margin_left : U8,
	margin_right : U8,
	margin_top : U8,
	page_size : U8,
	paragraph_spacing : U8,
	profile : U8,
	title_leading : U8,
	title_size : U8,
	blocks : List({ items : List(Str), kind : U8, level : U8, text : Str }),
	title : Str,
}.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| {
		{
			body_leading: Fuzz.u8,
			body_size: Fuzz.u8,
			bullet_indent: Fuzz.u8,
			heading_leading: Fuzz.u8,
			heading_size: Fuzz.u8,
			margin_bottom: Fuzz.u8,
			margin_left: Fuzz.u8,
			margin_right: Fuzz.u8,
			margin_top: Fuzz.u8,
			page_size: Fuzz.u8,
			paragraph_spacing: Fuzz.u8,
			profile: Fuzz.u8,
			title_leading: Fuzz.u8,
			title_size: Fuzz.u8,
			blocks: Fuzz.list(
				{
					items: Fuzz.list(Fuzz.str, 4),
					kind: Fuzz.u8,
					level: Fuzz.u8,
					text: Fuzz.str,
				}.Fuzz,
				8,
			),
			title: Fuzz.str,
		}.Fuzz
	}
}

test : Input -> Fuzz.Outcome
test = |Input.(input)| {
	if ThemeTargets.theme_output(input) Fuzz.keep else crash "theme output contracts disagreed"
}

target = Fuzz.target({
	name: "roc-pdf-theme-options",
	test,
	show: |input| Str.inspect(input),
})
