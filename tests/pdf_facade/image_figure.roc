app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Image
import pdf.Layout
import pdf.Pdf
import pdf.Scene

image_pixels : List(U8)
image_pixels = [
	20,
	90,
	140,
	20,
	90,
	140,
	240,
	180,
	40,
	240,
	180,
	40,
	40,
	160,
	90,
	40,
	160,
	90,
	245,
	245,
	240,
	245,
	245,
	240,
	20,
	90,
	140,
	20,
	90,
	140,
	240,
	180,
	40,
	240,
	180,
	40,
	40,
	160,
	90,
	40,
	160,
	90,
	245,
	245,
	240,
	245,
	245,
	240,
	245,
	245,
	240,
	245,
	245,
	240,
	40,
	160,
	90,
	40,
	160,
	90,
	240,
	180,
	40,
	240,
	180,
	40,
	20,
	90,
	140,
	20,
	90,
	140,
	245,
	245,
	240,
	245,
	245,
	240,
	40,
	160,
	90,
	40,
	160,
	90,
	240,
	180,
	40,
	240,
	180,
	40,
	20,
	90,
	140,
	20,
	90,
	140,
]

figure_document = {
	image = Image.Source.rgb8({
		alpha: NoAlpha,
		dimensions: { height: 4, width: 8 },
		pixels: image_pixels,
		row_stride: 24,
	})
	drawing = Scene.drawing({}).image(image, Layout.rect(0, 0, 320, 160))
	Pdf.document({
		contents: [
			Pdf.title("Field palette"),
			Pdf.figure(drawing, "A four-color field palette arranged in mirrored bands", Pdf.caption("Figure 1 — Field palette")),
			Pdf.paragraph("The image, caption, and alternative text travel through the public facade."),
		],
		language: "en",
		title: "Image figure facade evidence",
	})
}

expect {
	bytes = Pdf.to_bytes(figure_document)?
	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 1000
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	if list_at(args, 1) != "image" {
		crash "image-figure facade argument invalid"
	}
	bytes = Pdf.to_bytes(figure_document) ?? []
	{ bytes, work: [image_pixels.len(), bytes.len()] }
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "image-figure facade argument missing"
}
