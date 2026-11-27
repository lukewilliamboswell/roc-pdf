app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
	pdf: "../package/main.roc",
}

import fuzz.Fuzz
import pdf.Layout
import pdf.Pdf

Input := { sample : U8, width : U8, repeats : U8 }.{
	parser_for : _
	encoder_for : _

	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { sample: Fuzz.u8, width: Fuzz.u8, repeats: Fuzz.u8 }.Fuzz
}

target = Fuzz.suite([
	Fuzz.target({
		name: "roc-pdf-inter-latin",
		examples: [
			Fuzz.example({ name: "kern-exact-fit", revision: "1", make: || Input.{ sample: 0, width: 3, repeats: 0 } }),
			Fuzz.example({ name: "ligature-misses-by-one", revision: "1", make: || Input.{ sample: 1, width: 2, repeats: 0 } }),
			Fuzz.example({ name: "literal-arrow", revision: "1", make: || Input.{ sample: 2, width: 3, repeats: 1 } }),
			Fuzz.example({ name: "unsafe-break-reshaped", revision: "1", make: || Input.{ sample: 3, width: 3, repeats: 0 } }),
		],
		test,
		show: |input| Str.inspect(input),
	}),
])

test : Input -> Fuzz.Outcome
test = |Input.(input)| {
	# HarfBuzz 14.6.0 widths on the pinned exact Inter Regular bytes,
	# rounded to millipoints at 11 pt. The minimum content width of a->b
	# is the wider reshaped side, >b, where the ligature disappears.
	(text, minimum) = match input.sample % 4 {
		0 => ("AV", 14426)
		1 => ("->", 10495)
		2 => ("→", 10495)
		_ => ("a->b", 14013)
	}
	width = minimum + (input.width % 7).to_i64() - 3
	block = Pdf.custom_block({
		name: "Inter width boundary",
		inset: 2,
		size: { width: Layout.Unit.millipoints(width + 4000), height: 44 },
		contents: [Pdf.paragraph(text)],
	})
	document = Pdf.document({ title: "Inter Latin boundary", language: "en", contents: List.repeat(block, (input.repeats % 4).to_u64() + 1) })
	options : Pdf.Options
	options = { theme: { family: BuiltIn(Sans), latin_shaping: InterLatin } }
	passes = match Pdf.to_bytes_with(document, options) {
		Ok(bytes) => width >= minimum and !bytes.is_empty()
		Err(InvalidDocument(_)) => width < minimum
		Err(_) => False
	}
	if passes {
		Fuzz.keep
	} else {
		crash "Inter Latin width disagreed with the minimum-content checkpoint"
	}
}
