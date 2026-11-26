import pdf.Color
import pdf.Document
import pdf.Layout
import pdf.Pdf
import pdf.Scene

## Public fixed-page authoring for the remittance example and scale fixtures.
## The builder order establishes reading order. Each sheet selects its visual
## paint order independently and owns a decorative background and overlay.
Remittance :: [].{
	document : U64 -> Document
	document = |count| {
		var $pages = []
		var $index = 0
		while $index < count {
			$pages = $pages.append(sheet($index))
			$index = $index + 1
		}
		Pdf.fixed_document({ title: "Remittance advice", language: "en-AU", pages: $pages })
	}
}

sheet : U64 -> Document.FixedPage
sheet = |index| {
	alternate = index % 2 == 1
	size : Layout.Size
	size = if (alternate) { width: 595, height: 842 } else { width: 612, height: 792 }
	vertical_offset : I64
	vertical_offset = if (alternate) 50 else 0
	amount = if (alternate) "89.75" else "137.50"
	reference = (1042 + index).to_str()
	order = if (alternate) [4, 0, 1, 3, 2] else [0, 4, 1, 2, 3]
	background = Scene.Drawing.empty.rectangle({
		bounds: Layout.rect({ x: 54, y: 498 + vertical_offset, width: 504, height: 56 }),
		color: Color.srgb8({ red: 235, green: 241, blue: 248 }),
	})
	rule = Scene.Drawing.empty.rectangle({
		bounds: Layout.rect({ x: 54, y: 498 + vertical_offset, width: 504, height: 1 }),
		color: Color.srgb8({ red: 31, green: 53, blue: 82 }),
	})
	Pdf.fixed_page(size)
		.background(background)
		.place({ block: Pdf.title("Remittance advice"), frame: Layout.rect({ x: 54, y: 704 + vertical_offset, width: 504, height: 36 }) })
		.place({ block: Pdf.paragraph("Apply this payment to the invoice below."), frame: Layout.rect({ x: 54, y: 638 + vertical_offset, width: 504, height: 36 }) })
		.place({ block: Pdf.heading(1, "Payment details"), frame: Layout.rect({ x: 54, y: 576 + vertical_offset, width: 504, height: 32 }) })
		.place({ block: Pdf.paragraph("Invoice reference R-${reference}"), frame: Layout.rect({ x: 66, y: 510 + vertical_offset, width: 284, height: 34 }) })
		.place({ block: Pdf.rich_paragraph([Pdf.text("Amount paid AUD ${amount}")]), frame: Layout.rect({ x: 372, y: 510 + vertical_offset, width: 174, height: 34 }) })
		.overlay({ kind: Decoration, drawing: rule })
		.with_paint_order(order)
		.finish()
}
