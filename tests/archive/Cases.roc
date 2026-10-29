import pdf.Document
import pdf.Font
import pdf.Image
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme
import "../assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)
import "../assets/jpeg-fuzz-corpus/rgb-8x8.jpg" as jpeg_bytes : List(U8)

## The archive family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Blank({}),
		Report({ scale : U64 }),
		Figures({}),
		Navigation({ scale : U64 }),
		Caller({ scale : U64 }),
		ChunkedOwn({ scale : U64 }),
		ChunkedShare({ scale : U64 }),
		FiguresStandard({}),
		NavigationStandard({ scale : U64 }),
		Profiles({ scale : U64 }),
		Negatives({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Blank({}) => {
				bytes = generate(Pdf.document({ contents: [], language: "en-AU", title: "Archived blank" }), archive)
				{ bytes, work: [bytes.len()] }
			}
			Report({ scale }) => {
				bytes = generate(report_document(scale), archive)
				{ bytes, work: [bytes.len()] }
			}
			Figures({}) => {
				bytes = generate(figure_document({}), archive)
				{ bytes, work: [bytes.len()] }
			}
			Navigation({ scale }) => {
				bytes = generate(navigation_document(scale), archive)
				{ bytes, work: [bytes.len()] }
			}
			Caller({ scale }) => {
				bytes = caller_bytes(scale)
				{ bytes, work: [bytes.len()] }
			}
			ChunkedOwn({ scale }) => chunked_twins(scale, Pdf.ChunkRetention.OwnChunks)
			ChunkedShare({ scale }) => chunked_twins(scale, Pdf.ChunkRetention.ShareUnchangedResources)
			FiguresStandard({}) => {
				## Standard twins of single-page Archive documents; the renderer
				## matrix requires Archive and Standard to rasterize identically
				## because the identification is metadata only.
				bytes = generate(figure_document({}), standard)
				{ bytes, work: [bytes.len()] }
			}
			NavigationStandard({ scale }) => {
				bytes = generate(navigation_document(scale), standard)
				{ bytes, work: [bytes.len()] }
			}
			Profiles({ scale }) => {
				## The same document under both profiles: Archive adds exactly the
				## PDF/A identification to the canonical packet, so the output grows
				## by the 112 packet bytes plus any stream-length and cross-reference
				## digit carry, and the Standard twin never declares it.
				document = report_document(scale)
				archived = generate(document, archive)
				plain = generate(document, standard)
				{ bytes: archived, work: [archived.len(), plain.len(), archived.len() - plain.len()] }
			}
			Negatives({ context }) => negatives(context)
		}
	}
}

## The public static PDF/A-4 path. Every mode authors through the one-import
## facade, selects `Pdf.Profile.Archive` explicitly, and emits bytes that the
## pinned veraPDF `4` profile must accept with zero failed checks
## (scripts/check_pdfa4.py) and that scripts/check_pdfa4_structure.py
## inspects structurally.
archive : Pdf.Options
archive = Pdf.Options.{ profile: Pdf.Profile.Archive }

standard : Pdf.Options
standard = Pdf.Options.{ profile: Pdf.Profile.Standard }

report_document : U64 -> Document
report_document = |paragraphs| {
	var $contents = List.with_capacity(paragraphs + 6)
	$contents = $contents.append(Pdf.title("Archived operations report"))
	$contents = $contents.append(Pdf.heading(1, "Summary"))
	$contents = $contents.append(Pdf.bullets(["Deterministic bytes", "Embedded fonts and profile", "Canonical metadata"]))
	$contents = $contents.append(Pdf.heading(1, "Details"))
	var $index = 0
	while $index < paragraphs {
		$contents = $contents.append(Pdf.paragraph("Paragraph ${Str.inspect($index)} of the archived report keeps its static appearance: every font is embedded, the sRGB output intent characterizes every color, and nothing depends on external resources."))
		$index = $index + 1
	}
	document = Pdf.document({ contents: $contents, language: "en-AU", title: "Archived report & <summary> — 概要" })
	document.with_created("2026-09-28T01:02:03Z").with_modified("2026-09-28T04:05:06Z")
}

stripes : U64, U64 -> List(U8)
stripes = |width, height| {
	var $pixels = List.with_capacity(width * height * 3)
	var $row = 0
	while $row < height {
		var $column = 0
		while $column < width {
			shade = ((($row + $column) % 4) * 60).to_u8_wrap()
			$pixels = $pixels.append(20).append(90 + shade / 2).append(140 + shade / 3)
			$column = $column + 1
		}
		$row = $row + 1
	}
	$pixels
}

ramp : U64, U64 -> List(U8)
ramp = |width, height| {
	var $bytes = List.with_capacity(width * height)
	var $index = 0
	while $index < width * height {
		$bytes = $bytes.append((($index * 255) / (width * height)).to_u8_wrap())
		$index = $index + 1
	}
	$bytes
}

figure_document : {} -> Document
figure_document = |_| {
	opaque = Image.Source.rgb8({ alpha: NoAlpha, dimensions: { height: 8, width: 16 }, pixels: stripes(16, 8), row_stride: 48 })
	translucent = Image.Source.rgb8({ alpha: PackedAlpha({ bytes: ramp(16, 8), row_stride: 16 }), dimensions: { height: 8, width: 16 }, pixels: stripes(16, 8), row_stride: 48 })
	gray = Image.Source.gray8({ alpha: NoAlpha, dimensions: { height: 8, width: 16 }, pixels: ramp(16, 8), row_stride: 16 })
	jpeg = Image.Source.jpeg_srgb(jpeg_bytes, RequireDisplayReady)
	Pdf.document({
		contents: [
			Pdf.title("Archived figures"),
			Pdf.figure({ drawing: Scene.Drawing.empty.image({ image: opaque, placement: Layout.rect({ x: 0, y: 0, width: 320, height: 160 }) }), alt: "Teal diagonal stripes on an opaque raster", caption: Pdf.caption("An opaque packed sRGB raster.") }),
			Pdf.figure({ drawing: Scene.Drawing.empty.image({ image: translucent, placement: Layout.rect({ x: 0, y: 0, width: 320, height: 160 }) }), alt: "The same stripes fading from transparent to opaque", caption: Pdf.caption("A packed raster with an alpha plane.") }),
			Pdf.figure({ drawing: Scene.Drawing.empty.image({ image: gray, placement: Layout.rect({ x: 0, y: 0, width: 320, height: 80 }) }), alt: "A left-to-right gray ramp", caption: Pdf.no_caption }),
			Pdf.figure({ drawing: Scene.Drawing.empty.image({ image: jpeg, placement: Layout.rect({ x: 0, y: 0, width: 160, height: 160 }) }), alt: "A small sRGB JPEG test pattern", caption: Pdf.caption("A baseline sRGB JPEG.") }),
		],
		language: "en-AU",
		title: "Archived figures",
	})
}

navigation_document : U64 -> Document
navigation_document = |links| {
	var $contents = List.with_capacity(links + 6)
	$contents = $contents.append(Pdf.title("Archived navigation"))
	$contents = $contents.append(Pdf.destination_heading({ name: "overview", level: 1, text: "Overview" }))
	$contents = $contents.append(Pdf.paragraph("Links, internal destinations, outlines, and page labels remain navigation data in an archival file."))
	var $index = 0
	while $index < links {
		$contents = $contents.append(Pdf.link({ text: "Reference ${Str.inspect($index)}", uri: "https://example.com/archive/${Str.inspect($index)}" }))
		$index = $index + 1
	}
	$contents = $contents.append(Pdf.destination_heading({ name: "appendix", level: 1, text: "Appendix" }))
	$contents = $contents.append(Pdf.internal_link({ text: "Return to the overview", destination: "overview" }))
	Pdf.document({
		contents: $contents,
		language: "en-AU",
		title: "Archived navigation",
		outline: [
			{ depth: 0, destination: "overview", open: True, title: "Overview" },
			{ depth: 0, destination: "appendix", open: False, title: "Appendix" },
		],
		page_labels: [{ prefix: "A-", start_number: 1, start_page: 0, style: DecimalArabic }],
	})
}

## The registration limits depend on the runtime scale so the registration is
## evaluated at run time, inside the measured boundary.
caller_bytes : U64 -> List(U8)
caller_bytes = |scale| {
	limits = if (scale == 0) Font.ValidationLimits.make({ max_bytes: 0, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 }) else Font.ValidationLimits.default
	registered = match Font.Registry.empty.register({ bytes: caller_font_bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits: limits }) {
		Err(_) => crash "archive caller font registration failed"
		Ok(value) => value
	}
	options = { ..archive, theme: Theme.{ face: registered.face }, fonts: Registered(registered.registry) }
	document = Pdf.document({ contents: [Pdf.paragraph("Café PDF"), Pdf.paragraph("Café PDF")], language: "en-AU", title: "Archived caller font" })
	generate(document, options)
}

generate : Document, Pdf.Options -> List(U8)
generate = |document, options| match Pdf.to_bytes_with(document, options) {
	Ok(bytes) => bytes
	Err(_) => {
		crash "archive facade generation failed"
	}
}

chunked : Document, Pdf.ChunkRetention -> { bytes : List(U8), chunks : U64 }
chunked = |document, retention| {
	var $encoder = match Pdf.to_chunks_with(document, { ..archive, chunk_retention: retention }) {
		Ok(value) => value
		Err(_) => {
			crash "archive chunked preparation failed"
		}
	}
	var $bytes = []
	var $chunks = 0
	var $done = False
	while !$done {
		match Pdf.next_chunk($encoder) {
			Done => {
				$done = True
			}
			Emit(chunk, next) => {
				$bytes = $bytes.concat(chunk)
				$chunks = $chunks + 1
				$encoder = next
			}
		}
	}
	{ bytes: $bytes, chunks: $chunks }
}

chunked_twins : U64, Pdf.ChunkRetention -> { bytes : List(U8), work : List(U64) }
chunked_twins = |scale, retention| {
	document = report_document(scale)
	streamed = chunked(document, retention)
	buffered = generate(document, archive)
	identical = if (streamed.bytes == buffered) 1 else 0
	{ bytes: streamed.bytes, work: [streamed.bytes.len(), streamed.chunks, identical] }
}

## Atomic public-path negatives for the static PDF/A-4 profile. Earlier
## authoring failures keep their cause. Inter covers U+FEFF, so that witness
## now reaches the Archive ToUnicode rule; explicitly selected Standard
## accepts it, while Archive rejects it without emitting bytes or downgrading.
## U+A7B0 is an uncovered Latin witness for the earlier coverage boundary.
## White-box twins continue to cover unrepresentable profile constructs.
rejects_accessible_archive : Str -> Bool
rejects_accessible_archive = |title| {
	document = Pdf.document({ contents: [Pdf.paragraph("Body")], language: "en-AU", title })
	match Pdf.to_bytes_with(document, Pdf.Options.{ profile: Pdf.Profile.AccessibleArchive }) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, feature: Feature(code), stage: AuthoringValidation, .. }], .. })) => code == "profile.accessible_archive"
		_ => False
	}
}

keeps_metadata_cause : Str -> Bool
keeps_metadata_cause = |language| {
	document = Pdf.document({ contents: [Pdf.paragraph("Body")], language, title: "Archive" })
	match Pdf.to_bytes_with(document, archive) {
		Err(InvalidMetadata(LanguageNotCanonicalCase({ offset: 3 }))) => True
		_ => False
	}
}

keeps_feature_cause : Str -> Bool
keeps_feature_cause = |summary| {
	document = Pdf.document({ contents: [Pdf.complex_table(summary)], language: "en-AU", title: "Archive" })
	match Pdf.to_bytes_with(document, archive) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, feature: Feature(code), .. }], .. })) => code == "table.complex"
		_ => False
	}
}

keeps_content_cause : Str, { text : Str, expected : Str } -> Bool
keeps_content_cause = |title, { text, expected }| {
	document = Pdf.document({ contents: [Pdf.paragraph(text)], language: "en-AU", title })
	match Pdf.to_bytes_with(document, archive) {
		Err(InvalidDocument({ diagnostics: [{ code: FontCoverageMissing, details: ["contents[0]"], feature: Feature(feature), stage: AuthoringValidation, .. }], .. })) => feature == expected
		Err(error) => crash "Archive content witness ${Str.inspect(text)} expected ${expected}, received ${Str.inspect(error)}"
		Ok(_) => crash "Archive content witness ${Str.inspect(text)} unexpectedly emitted bytes"
	}
}

rejects_mapped_bom : Str -> Bool
rejects_mapped_bom = |title| {
	document = Pdf.document({ contents: [Pdf.paragraph("Zero\u(FEFF)width")], language: "en-AU", title })
	standard_accepted = match Pdf.to_bytes_with(document, { ..archive, profile: Standard }) {
		Ok(bytes) => !bytes.is_empty()
		Err(error) => crash "Covered BOM Standard control failed: ${Str.inspect(error)}"
	}
	archive_rejected = match Pdf.to_bytes_with(document, archive) {
		Err(InvalidDocument({ diagnostics: [{ code: ProfileRequirementViolated, feature: Feature("profile.archive"), stage: ProfileValidation, location: Document, details: [], requirement_ids: ["ROC-PDF-PDFA4-6-2-10-7-TO-UNICODE"], clause_references: ["ISO 19005-4:2020 6.2.10.7"], .. }], truncation: Complete, .. })) => True
		Err(error) => crash "Covered BOM Archive witness failed: ${Str.inspect(error)}"
		Ok(_) => crash "Covered BOM Archive witness unexpectedly emitted bytes"
	}
	standard_accepted and archive_rejected
}

accepted : Document -> List(U8)
accepted = |document| match Pdf.to_bytes_with(document, archive) {
	Ok(bytes) => bytes
	Err(_) => {
		crash "archive negative control document failed"
	}
}

## The title is selected by the runtime zero `context`, so the compiler cannot
## evaluate the negatives at compile time. It is a small string, exactly like
## the command-line argument the original fixture received.
negatives : U64 -> { bytes : List(U8), work : List(U64) }
negatives = |context| {
	title = if (context == 0) "Archive negatives" else "guarded"
	checks = [
		rejects_accessible_archive(title),
		keeps_metadata_cause("en-au"),
		keeps_feature_cause(title),
		keeps_content_cause(title, { text: "Missing Latin: \u(A7B0)", expected: "text.coverage_missing" }),
		keeps_content_cause(title, { text: "Private\u(E000)use", expected: "text.unsupported_script" }),
		rejects_mapped_bom(title),
	]
	var $passed = 0
	var $index = 0
	while $index < checks.len() {
		match checks.get($index) {
			Ok(True) => {
				$passed = $passed + 1
			}
			_ => {}
		}
		$index = $index + 1
	}
	if $passed != checks.len() {
		crash "archive facade negative rejected the wrong way: ${Str.inspect(checks)}"
	}
	bytes = accepted(Pdf.document({ contents: [Pdf.paragraph(title)], language: "en-AU", title }))
	{ bytes, work: [$passed, bytes.len()] }
}
