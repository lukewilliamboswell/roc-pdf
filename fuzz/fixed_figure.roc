app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import pdf.Color
import pdf.Document
import pdf.Layout
import pdf.Pdf
import pdf.Scene

target = Fuzz.suite([
	Fuzz.target({
		name: "roc-pdf-fixed-figure",
		examples: [
			Fuzz.example({ name: "exact-fit-letter", revision: "1", make: || Input.{ mode: 0, variant: 0 } }),
			Fuzz.example({ name: "wide-fit-a4-reordered", revision: "1", make: || Input.{ mode: 0, variant: 255 } }),
			Fuzz.example({ name: "one-unit-outside-the-page", revision: "1", make: || Input.{ mode: 1, variant: 0 } }),
			Fuzz.example({ name: "picture-too-wide", revision: "1", make: || Input.{ mode: 2, variant: 0 } }),
			Fuzz.example({ name: "caption-does-not-fit", revision: "1", make: || Input.{ mode: 3, variant: 1 } }),
			Fuzz.example({ name: "duplicate-figure-paint", revision: "1", make: || Input.{ mode: 4, variant: 1 } }),
		],
		test,
		show: |input| Str.inspect(input),
	}),
])

Input := { mode : U8, variant : U8 }.{
	parser_for : _
	encoder_for : _

	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { mode: Fuzz.u8, variant: Fuzz.u8 }.Fuzz
}

authored : Input -> Document
authored = |input| {
	mode = input.mode % 5
	letter = input.variant % 2 == 0
	width = if (letter) 612 else 595
	height = if (letter) 792 else 842
	frame_width = if (mode == 2) 127 else 128 + (input.variant % 77).to_u64().to_i64_wrap()
	frame_height = if (mode == 3) 61 else 62 + (input.variant % 13).to_u64().to_i64_wrap()
	tint : Color.SourceValue
	tint = "#005A63"
	drawing = Scene.Drawing.empty.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 128, height: 40 }), color: tint })
	figure = Pdf.figure({ drawing, alt: "Teal patch", caption: Pdf.caption("Frame check") })
	x = 1000 * (width - frame_width) + if (mode == 1) 1 else 0
	frame : Layout.Rect
	frame = { origin: { x: Layout.Unit.millipoints(x), y: Layout.Unit.points(height - frame_height) }, size: { width: Layout.Unit.points(frame_width), height: Layout.Unit.points(frame_height) } }
	order = if mode == 4 {
		[2, 0, 2]
	} else if letter {
		[2, 0, 1]
	} else {
		[1, 2, 0]
	}
	page = Pdf.fixed_page({ width: Layout.Unit.points(width), height: Layout.Unit.points(height) })
		.place({ block: Pdf.title("Brief"), frame: Layout.rect({ x: 20, y: 638, width: 200, height: 45 }) })
		.place({ block: Pdf.paragraph("Key facts"), frame: Layout.rect({ x: 20, y: 590, width: 200, height: 25 }) })
		.place({ block: figure, frame })
		.with_paint_order(order)
		.finish()
	Pdf.fixed_document({ pages: [page], title: "Fixed figure property", language: "en" })
}

test : Input -> Fuzz.Outcome
test = |input| {
	doc = authored(input)
	mode = input.mode % 5
	if mode == 0 {
		expected = [
			("pages[0].placements[0]", "Title"),
			("pages[0].placements[1]", "P"),
			("pages[0].placements[2]", "Figure"),
			("pages[0].placements[2].caption", "Caption"),
		]
		match Pdf.prepare_with_report(doc, {}) {
			Ok(value) if value.report.facts.blocks.map(|block| (block.path, block.role)) == expected => Fuzz.keep
			_ => crash "a valid fixed figure lost its authored report paths"
		}
	} else {
		{ feature, path } = match mode {
			1 => { feature: "layout.fixed.frame", path: "pages[0].placements[2].frame" }
			2 | 3 => { feature: "layout.fixed.figure_frame", path: "pages[0].placements[2]" }
			_ => { feature: "layout.fixed.paint_order", path: "pages[0].paint_order[2]" }
		}
		if matches(Pdf.to_bytes(doc), feature, path) and matches(Pdf.to_chunks(doc), feature, path) {
			Fuzz.keep
		} else {
			crash "an invalid fixed figure escaped before its located rejection"
		}
	}
}

matches : Try(a, Pdf.Error), Str, Str -> Bool
matches = |result, feature, path| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature(actual), details, .. }], truncation: Complete, .. })) => actual == feature and details.get(0) == Ok(path)
	_ => False
}
