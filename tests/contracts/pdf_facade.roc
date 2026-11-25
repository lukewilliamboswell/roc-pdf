app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "../platform/main.roc",
}

import pdf.Pdf
import pdf.Font
import pdf.Color
import pdf.Layout
import pdf.Image
import pdf.Scene
import pdf.Theme
import "../../vendor/fonts/Inter-4.1-Regular.ttf" as inter_full : List(U8)

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

# The one-import Standard facade emits authored content without exposing
# resources, glyphs, scenes, or PDF objects.
expect {
	bytes = make_report("Typed facade output")?
	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 667
}

# A vector drawing is flow figure content: one tagged `Figure` owning its
# drawing, with its alternative text.
expect {
	drawing = Scene.Drawing.empty.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 120, height: 48 }), color: Color.srgb8({ red: 20, green: 90, blue: 140 }) })
	document = Pdf.document({
		contents: [Pdf.figure({ drawing: drawing, alt: "Blue panel", caption: Pdf.no_caption })],
		language: "en",
		title: "Forward figure",
	})

	match Pdf.to_bytes(document) {
		Ok(bytes) => bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n")
		Err(_) => False
	}
}

# A single packed raster lowers as one tagged Figure with authored alternative
# text, while its placement remains independent of its pixel dimensions.
expect {
	image = Image.Source.rgb8({
		alpha: NoAlpha,
		dimensions: { height: 2, width: 2 },
		pixels: [20, 90, 140, 240, 180, 40, 40, 160, 90, 245, 245, 240],
		row_stride: 6,
	})
	drawing = Scene.Drawing.empty.image({ image: image, placement: Layout.rect({ x: 0, y: 0, width: 160, height: 90 }) })
	document = Pdf.document({
		contents: [Pdf.figure({ drawing: drawing, alt: "Four-color editorial illustration", caption: Pdf.caption("Figure 1 — Palette study") })],
		language: "en",
		title: "Raster figure",
	})
	bytes = Pdf.to_bytes(document)?
	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 1000
}

# Malformed packed data and missing alternative text are rejected before a
# byte value exists; the facade never repairs, pads, or drops the image.
expect {
	bad_image = Image.Source.rgb8({ alpha: NoAlpha, dimensions: { height: 2, width: 2 }, pixels: [255, 0, 0], row_stride: 6 })
	bad_drawing = Scene.Drawing.empty.image({ image: bad_image, placement: Layout.rect({ x: 0, y: 0, width: 120, height: 60 }) })
	bad_document = Pdf.document({ contents: [Pdf.figure({ drawing: bad_drawing, alt: "Malformed raster", caption: Pdf.no_caption })], language: "en", title: "Bad raster" })
	empty_alt_document = Pdf.document({ contents: [Pdf.figure({ drawing: bad_drawing, alt: "", caption: Pdf.no_caption })], language: "en", title: "Missing alternative" })
	bad_rejected = match Pdf.to_bytes(bad_document) {
		Err(InvalidDocument({ diagnostics: [{ code: InvalidRelationship, details: ["DecodedLengthMismatch"], feature: Feature("image.invalid"), .. }], .. })) => True
		_ => False
	}
	empty_rejected = match Pdf.prepare(empty_alt_document, Pdf.Options.default) {
		Err(InvalidDocument({ diagnostics: [{ code: InvalidRelationship, details: ["contents[0]"], feature: Feature("document.figure_alternative_empty"), .. }], .. })) => True
		_ => False
	}
	bad_rejected and empty_rejected
}

# Navigation authoring is typed: links, named destinations, an outline, and
# page labels flow through the same one-import facade.
expect {
	document = Pdf.document({
		contents: [
			Pdf.title("Field guide"),
			Pdf.destination_heading({ name: "habitat", level: 1, text: "Habitat" }),
			Pdf.paragraph("Wetlands and coastal heath."),
			Pdf.link({ text: "Atlas of Living Australia", uri: "https://www.ala.org.au/" }),
			Pdf.internal_link({ text: "See the habitat notes", destination: "habitat" }),
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

# Nested profile and option modules use current package shorthand syntax;
# the Archive profile is executable through the public options.
expect {
	options = Pdf.Options.{ profile: Pdf.Profile.Archive }
	document = Pdf.document({ contents: [], language: "en-AU", title: "Archive" })
	bytes = Pdf.to_bytes_with(document, options)?

	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n")
}

# AccessibleArchive rejects a blank page transactionally with a located diagnostic.
expect {
	options = Pdf.Options.{ profile: Pdf.Profile.AccessibleArchive }
	document = Pdf.document({ contents: [], language: "en-AU", title: "Accessible" })

	match Pdf.to_chunks_with(document, options) {
		Err(InvalidDocument({ diagnostics: [{ code: ProfileRequirementViolated, feature: Feature("profile.accessible_archive.empty_structure"), details: ["contents"], .. }], .. })) => True
		_ => False
	}
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |_| { bytes: [], work: [] }

# Original-byte foreground ranges use only the supported release facade.
# The source face can be the registered packaged face; no private module or
# token semantic element is needed by an external highlighter.
expect {
	registered = Font.Registry.empty.register_built_in(Font.ValidationLimits.default)?
	keyword : Pdf.SourceForeground
	keyword = { start: 0, end: 3, color: "#8000c0" }
	document = Pdf.document({ title: "Source foreground contract", language: "en", contents: [Pdf.source_block({ text: "app [main!] {}\n", face: Face(registered.face), foregrounds: [keyword] })] })
	bytes = Pdf.to_bytes_with(document, { fonts: Registered(registered.registry) })?
	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n")
}

# A real caller face maps U+E000 to a glyph. Even with coverage, the
# shaper rejects script Zzzz at the original location before ToUnicode
# or ActualText planning. Verify both emission entry points and profiles.
expect {
	reg = Font.Registry.empty.register({ bytes: inter_full, registration: { provision: BuiltIn, scripts: ["Latn"] }, limits: Font.ValidationLimits.default })?
	pua = "a\u(E000)a"
	content = [
		(Pdf.paragraph(pua), "contents[0]"),
		(Pdf.rich_paragraph([Pdf.text("a"), Pdf.in_language("en", [Pdf.text(pua)])]), "contents[0].inlines[1].inlines[0]"),
		(Pdf.source_block({ text: pua, face: Face(reg.face) }), "contents[0]"),
	]
	face_covers = reg.registry.store().coverage_spans.any(|span| span.first <= 0xE000 and span.last >= 0xE000)
	options = Pdf.Options.{ fonts: Registered(reg.registry), theme: Theme.{ face: reg.face }, profile: Archive }
	make = |block| Pdf.document({ contents: [block], language: "en", title: "Caller-text coverage" })
	accepted = Pdf.to_bytes_with(make(Pdf.paragraph("aaa")), options)?
	face_covers and !accepted.is_empty() and content.all(
		|(block, path)| {
			doc = make(block)
			rejects_private_use(Pdf.to_bytes_with(doc, options), path)
				and rejects_private_use(Pdf.to_chunks_with(doc, { ..options, profile: AccessibleArchive }), path)
		},
	)
}

rejects_private_use : Try(a, Pdf.Error), Str -> Bool
rejects_private_use = |result, path| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature("text.unsupported_script"), details: [located], stage: AuthoringValidation, .. }], .. })) => located == path
	_ => False
}

# Turn each valid standalone PDF string into one private-use authoring
# error. The chunked path must reject before returning an encoder.
expect {
	drawing = Scene.Drawing.empty.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 20, height: 20 }), color: Color.srgb8({ red: 30, green: 40, blue: 50 }) })
	make = |suffix| {
		doc = Pdf.document({
			contents: [
				Pdf.destination_heading({ name: "section", level: 1, text: "Section" }),
				Pdf.rich_paragraph([Pdf.expansion({ text: "ID", expanded: "Identifier" })]),
				Pdf.figure({ drawing, alt: "Illustration", caption: Pdf.no_caption }),
			],
			language: "en-AU",
			title: "Readable strings",
		})
		doc
			.with_outline([{ depth: 0, destination: "section", open: True, title: "Section${suffix}" }])
			.with_page_labels([{ prefix: "S-", start_number: 1, start_page: 0, style: DecimalArabic }])
	}
	suffix = "\u(E000)"
	base = make("")
	label = base.with_page_labels([{ prefix: "S-${suffix}", start_number: 1, start_page: 0, style: DecimalArabic }])
	expanded = Pdf.document({ contents: [Pdf.rich_paragraph([Pdf.expansion({ text: "ID", expanded: "Identifier${suffix}" })])], language: "en-AU", title: "Expanded text" })
	figure = Pdf.document({ contents: [Pdf.figure({ drawing, alt: "Illustration${suffix}", caption: Pdf.no_caption })], language: "en-AU", title: "Illustration" })
	cases = [(make(suffix), "outline[0].title"), (label, "page_labels[0].prefix"), (expanded, "contents[0].inlines[0]"), (figure, "contents[0]")]
	options = Pdf.Options.{ profile: AccessibleArchive }
	Pdf.to_bytes_with(base, options).is_ok() and cases.all(
		|(doc, path)| {
			Pdf.to_bytes_with(doc, { profile: Archive }).is_ok()
				and rejects_readable_string(Pdf.to_bytes_with(doc, options), path)
				and rejects_readable_string(Pdf.to_chunks_with(doc, options), path)
		},
	)
}

rejects_readable_string : Try(a, Pdf.Error), Str -> Bool
rejects_readable_string = |result, path| match result {
	Err(InvalidDocument({ diagnostics: [{ code: ProfileRequirementViolated, feature: Feature("profile.accessible_archive.private_use_text"), details: [located], stage: AuthoringValidation, .. }], .. })) => located == path
	_ => False
}

# Each BCP 47 placeholder has valid syntax but conveys no specific
# language. Both export paths report the catalog or authored inline path.
expect {
	make = |language, inline| Pdf.document({ contents: [Pdf.rich_paragraph([Pdf.in_language(inline, [Pdf.text("Review the terms.")])])], language, title: "Specific language" })
	archive = Pdf.Options.{ profile: Archive }
	combined = Pdf.Options.{ profile: AccessibleArchive }
	positive = Pdf.to_bytes_with(make("en-AU", "en-GB-x-edition"), combined).is_ok()
	catalog = ["und", "und-Latn", "mul", "mis", "zxx"].map(|tag| (make(tag, "en"), "language"))
	scoped = ["und", "UND-Latn", "mul", "mis", "zxx", "I-Default", "x-internal"].map(|tag| (make("en", tag), "contents[0].inlines[0]"))
	positive and List.concat(catalog, scoped).all(
		|(doc, path)| {
			Pdf.to_bytes_with(doc, archive).is_ok()
				and rejects_unspecified_language(Pdf.to_bytes_with(doc, combined), path)
				and rejects_unspecified_language(Pdf.to_chunks_with(doc, combined), path)
		},
	)
}

rejects_unspecified_language : Try(a, Pdf.Error), Str -> Bool
rejects_unspecified_language = |result, path| match result {
	Err(InvalidDocument({ diagnostics: [{ code: ProfileRequirementViolated, feature: Feature("profile.accessible_archive.language"), details: [located], requirement_ids: ["ROC-PDF-PDFUA2-8-4-4-DEFAULT-LANGUAGE"], stage: AuthoringValidation, .. }], .. })) => located == path
	_ => False
}

# Intent passes through the authored Warning label. Panel and text colours
# are presentation choices, with the combined review carried by the report.
expect {
	ink = Color.srgb8({ red: 120, green: 30, blue: 15 })
	warning = Pdf.scoped({ strong: Themed(ink) }, [Pdf.rich_paragraph([Pdf.strong([Pdf.text("Warning. ")]), Pdf.text("Review the terms.")])])
	doc = Pdf.document({
		contents: [Pdf.callout({ name: "Warning panel", contents: [warning] })],
		language: "en-AU",
		title: "Presentation and structure",
	})
	{ report, .. } = Pdf.prepare_with_report(doc, { profile: AccessibleArchive })?
	report.obligations.contains({ obligation: StructureMeaningful, path: "document" })
		and report.obligations.contains({ obligation: ArtifactClassificationMeaningful, path: "document" })
}

# Dense header associations reach the existing document budget during
# planning. Both public export methods return the same located diagnostic.
expect {
	row = Pdf.row([Pdf.header_cell(Column, [Pdf.text("Heading")])])
	table = Pdf.table({ body_rows: List.repeat(row, 361), caption: Pdf.no_caption, columns: [{ align: Start, width: Content }], footer_rows: [], header_rows: [], row_split: KeepRows })
	doc = Pdf.document({ contents: [table], language: "en-AU", title: "Bounded headers" })
	options = Pdf.Options.{ profile: AccessibleArchive }
	exceeds_header_budget(Pdf.to_bytes_with(doc, options)) and exceeds_header_budget(Pdf.to_chunks_with(doc, options))
}

exceeds_header_budget : Try(a, Pdf.Error) -> Bool
exceeds_header_budget = |result| match result {
	Err(InvalidDocument({ diagnostics: [{ code: BudgetExceeded, details: ["contents[0]"], feature: Feature("document.content_limit"), message, stage: AuthoringValidation, .. }], .. })) =>
		message.starts_with("The document needs 65701 typed attributes and relationships but the facade accepts at most 65536.")
	_ => False
}
