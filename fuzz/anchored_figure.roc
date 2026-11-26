app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import AnchoredFigureModel

target = Fuzz.suite([
	Fuzz.target({
		name: "roc-pdf-anchored-figure",
		examples: [
			Fuzz.example({ name: "pair-fits-after-preceding-context", revision: "1", make: || Input.{ mode: 0, height: 44, lines: 1, lead: 0 } }),
			Fuzz.example({ name: "deferred-pair-fits-exactly", revision: "1", make: || Input.{ mode: 1, height: 44, lines: 1, lead: 55 } }),
			Fuzz.example({ name: "next-frame-is-one-millipoint-short", revision: "1", make: || Input.{ mode: 2, height: 44, lines: 1, lead: 55 } }),
			Fuzz.example({ name: "forced-break-before-a-fitting-pair", revision: "1", make: || Input.{ mode: 3, height: 44, lines: 1, lead: 0 } }),
			Fuzz.example({ name: "forced-break-before-oversized-pair", revision: "1", make: || Input.{ mode: 4, height: 44, lines: 1, lead: 0 } }),
		],
		test,
		show: |input| Str.inspect(input),
	}),
])

Input := { mode : U8, height : U8, lines : U8, lead : U8 }.{
	parser_for : _
	encoder_for : _

	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { mode: Fuzz.u8, height: Fuzz.u8, lines: Fuzz.u8, lead: Fuzz.u8 }.Fuzz
}

test : Input -> Fuzz.Outcome
test = |input| {
	mode = input.mode % 5
	drawing = 20 + (input.height % 90).to_u64()
	lines = 1 + (input.lines % 4).to_u64()
	spacer = (input.lead % 31).to_u64()
	required = (lines * 14 + drawing + 22) * 1000
	capacity = match mode {
		0 => required + (18 + spacer) * 1000
		1 | 3 => required
		_ => required - 1
	}
	if AnchoredFigureModel.check({ capacity, drawing, lines, spacer, force_break: mode >= 3, emit: True }) {
		Fuzz.keep
	} else {
		crash "Anchored figure disagrees with the frame and order oracle: ${Str.inspect(input)}"
	}
}
