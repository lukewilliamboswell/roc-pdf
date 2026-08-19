app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Pdf
import pdf.Color
import pdf.Layout
import pdf.Image
import pdf.Scene

make_report : Str -> Try(List(U8), Pdf.Error)
make_report = |summary| {
	document = Pdf.document({
		contents: [
			Pdf.title("Quarterly report"),
			Pdf.heading(1, "Summary"),
			Pdf.paragraph(summary),
			Pdf.bullets(["Searchable text", "Tagged reading order"]),
		],
		language: "en-AU",
		title: "Quarterly report",
	})

	Pdf.to_bytes(document)
}

## The one-import Standard facade emits authored content without exposing
## resources, glyphs, scenes, or PDF objects.
expect {
	bytes = make_report("Typed facade output")?
	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 667
}

## Forward figure authoring keeps drawing ownership and alternative text in the
## public shape, then rejects atomically until its semantic lowering closes.
expect {
	drawing = Scene.drawing({}).rectangle(
		Layout.rect(0, 0, 120, 48),
		Color.srgb8({ red: 20, green: 90, blue: 140 }),
	)
	document = Pdf.document({
		contents: [Pdf.figure(drawing, "Blue panel", Pdf.no_caption)],
		language: "en",
		title: "Forward figure",
	})

	match Pdf.prepare(document, Pdf.Options.default) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, feature: Feature(code), stage: AuthoringValidation, .. }], truncation: Complete, .. })) => code == "document.figure"
		_ => False
	}
}

## A single packed raster lowers as one tagged Figure with authored alternative
## text, while its placement remains independent of its pixel dimensions.
expect {
	image = Image.Source.rgb8({
		alpha: NoAlpha,
		dimensions: { height: 2, width: 2 },
		pixels: [20, 90, 140, 240, 180, 40, 40, 160, 90, 245, 245, 240],
		row_stride: 6,
	})
	drawing = Scene.drawing({}).image(image, Layout.rect(0, 0, 160, 90))
	document = Pdf.document({
		contents: [Pdf.figure(drawing, "Four-color editorial illustration", Pdf.caption("Figure 1 — Palette study"))],
		language: "en",
		title: "Raster figure",
	})
	bytes = Pdf.to_bytes(document)?
	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 1000
}

## Malformed packed data and missing alternative text are rejected before a
## byte value exists; the facade never repairs, pads, or drops the image.
expect {
	bad_image = Image.Source.rgb8({ alpha: NoAlpha, dimensions: { height: 2, width: 2 }, pixels: [255, 0, 0], row_stride: 6 })
	bad_drawing = Scene.drawing({}).image(bad_image, Layout.rect(0, 0, 120, 60))
	bad_document = Pdf.document({ contents: [Pdf.figure(bad_drawing, "Malformed raster", Pdf.no_caption)], language: "en", title: "Bad raster" })
	empty_alt_document = Pdf.document({ contents: [Pdf.figure(bad_drawing, "", Pdf.no_caption)], language: "en", title: "Missing alternative" })
	bad_rejected = match Pdf.to_bytes(bad_document) {
		Err(UnsupportedAuthoringContent({ blocks: 1 })) => True
		_ => False
	}
	empty_rejected = match Pdf.prepare(empty_alt_document, Pdf.Options.default) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, feature: Feature("document.figure"), .. }], .. })) => True
		_ => False
	}
	bad_rejected and empty_rejected
}

## Navigation authoring is typed: links, named destinations, an outline, and
## page labels flow through the same one-import facade.
expect {
	document = Pdf.document({
		contents: [
			Pdf.title("Field guide"),
			Pdf.destination_heading("habitat", 1, "Habitat"),
			Pdf.paragraph("Wetlands and coastal heath."),
			Pdf.link("Atlas of Living Australia", "https://www.ala.org.au/"),
			Pdf.internal_link("See the habitat notes", "habitat"),
		],
		language: "en-AU",
		title: "Field guide",
	})
	navigated = document
		.with_outline([{ depth: 0, destination: "habitat", open: True, title: "Habitat" }])
		.with_page_labels([{ prefix: "", start_number: 1, start_page: 0, style: DecimalArabic }])
	bytes = Pdf.to_bytes(navigated)?

	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 4717
}

## Nested profile and option modules use current package shorthand syntax.
expect {
	options = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Archive)
	document = Pdf.document({ contents: [], language: "en-AU", title: "Archive" })

	match Pdf.to_bytes_with(document, options) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, feature: Feature(code), .. }], .. })) => code == "profile.archive"
		_ => False
	}
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |_| { bytes: [], work: [] }
