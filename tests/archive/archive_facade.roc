app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Document
import pdf.Font
import pdf.Image
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme
import "../assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)
import "../assets/jpeg-fuzz-corpus/rgb-8x8.jpg" as jpeg_bytes : List(U8)

## The public static PDF/A-4 path. Every mode authors through the one-import
## facade, selects `Pdf.Profile.Archive` explicitly, and emits bytes that the
## pinned veraPDF `4` profile must accept with zero failed checks
## (scripts/check_pdfa4.py) and that scripts/check_pdfa4_structure.py
## inspects structurally.
archive : Pdf.Options
archive = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Archive)

standard : Pdf.Options
standard = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Standard)

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
			Pdf.figure({ drawing: Scene.drawing({}).image(opaque, Layout.rect(0, 0, 320, 160)), alt: "Teal diagonal stripes on an opaque raster", caption: Pdf.caption("An opaque packed sRGB raster.") }),
			Pdf.figure({ drawing: Scene.drawing({}).image(translucent, Layout.rect(0, 0, 320, 160)), alt: "The same stripes fading from transparent to opaque", caption: Pdf.caption("A packed raster with an alpha plane.") }),
			Pdf.figure({ drawing: Scene.drawing({}).image(gray, Layout.rect(0, 0, 320, 80)), alt: "A left-to-right gray ramp", caption: Pdf.no_caption }),
			Pdf.figure({ drawing: Scene.drawing({}).image(jpeg, Layout.rect(0, 0, 160, 160)), alt: "A small sRGB JPEG test pattern", caption: Pdf.caption("A baseline sRGB JPEG.") }),
		],
		language: "en-AU",
		title: "Archived figures",
	})
}

navigation_document : U64 -> Document
navigation_document = |links| {
	var $contents = List.with_capacity(links + 6)
	$contents = $contents.append(Pdf.title("Archived navigation"))
	$contents = $contents.append(Pdf.destination_heading("overview", 1, "Overview"))
	$contents = $contents.append(Pdf.paragraph("Links, internal destinations, outlines, and page labels remain navigation data in an archival file."))
	var $index = 0
	while $index < links {
		$contents = $contents.append(Pdf.link("Reference ${Str.inspect($index)}", "https://example.com/archive/${Str.inspect($index)}"))
		$index = $index + 1
	}
	$contents = $contents.append(Pdf.destination_heading("appendix", 1, "Appendix"))
	$contents = $contents.append(Pdf.internal_link("Return to the overview", "overview"))
	Pdf.document({ contents: $contents, language: "en-AU", title: "Archived navigation" })
		.with_outline([
			{ depth: 0, destination: "overview", open: True, title: "Overview" },
			{ depth: 0, destination: "appendix", open: False, title: "Appendix" },
		])
		.with_page_labels([{ prefix: "A-", start_number: 1, start_page: 0, style: DecimalArabic }])
}

## The registration limits depend on the runtime scale so the registration is
## evaluated at run time, inside the measured boundary.
caller_bytes : U64 -> List(U8)
caller_bytes = |scale| {
	limits = if scale == 0 Font.ValidationLimits.make({ max_bytes: 0, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 }) else Font.ValidationLimits.default
	registered = match Font.Registry.empty.register(caller_font_bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits) {
		Err(_) => crash "archive caller font registration failed"
		Ok(value) => value
	}
	options = Pdf.Options.with_font_registry(Pdf.Options.with_theme(archive, Theme.with_font(Theme.default, registered.face)), registered.registry)
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
	var $encoder = match Pdf.to_chunks_with(document, Pdf.Options.with_chunk_retention(archive, retention)) {
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

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => {
			crash "archive facade evidence requires a mode"
		}
	}
	scale = match args.get(2) {
		Ok(text) => match U64.from_str(text) {
			Ok(value) => value
			Err(_) => crash "archive facade scale must be an unsigned integer"
		}
		Err(OutOfBounds) => crash "archive facade evidence requires a scale"
	}
	match mode {
		"blank" => {
			bytes = generate(Pdf.document({ contents: [], language: "en-AU", title: "Archived blank" }), archive)
			{ bytes, work: [bytes.len()] }
		}
		"report" => {
			bytes = generate(report_document(scale), archive)
			{ bytes, work: [bytes.len()] }
		}
		"figures" => {
			bytes = generate(figure_document({}), archive)
			{ bytes, work: [bytes.len()] }
		}
		"navigation" => {
			bytes = generate(navigation_document(scale), archive)
			{ bytes, work: [bytes.len()] }
		}
		"caller" => {
			bytes = caller_bytes(scale)
			{ bytes, work: [bytes.len()] }
		}
		"chunked-own" | "chunked-share" => {
			retention = if mode == "chunked-own" Pdf.ChunkRetention.OwnChunks else Pdf.ChunkRetention.ShareUnchangedResources
			document = report_document(scale)
			streamed = chunked(document, retention)
			buffered = generate(document, archive)
			identical = if streamed.bytes == buffered 1 else 0
			{ bytes: streamed.bytes, work: [streamed.bytes.len(), streamed.chunks, identical] }
		}
		"figures-standard" => {
			## Standard twins of single-page Archive documents; the renderer
			## matrix requires Archive and Standard to rasterize identically
			## because the identification is metadata only.
			bytes = generate(figure_document({}), standard)
			{ bytes, work: [bytes.len()] }
		}
		"navigation-standard" => {
			bytes = generate(navigation_document(scale), standard)
			{ bytes, work: [bytes.len()] }
		}
		"profiles" => {
			## The same document under both profiles: Archive adds exactly the
			## PDF/A identification to the canonical packet, so the output grows
			## by the 112 packet bytes plus any stream-length and cross-reference
			## digit carry, and the Standard twin never declares it.
			document = report_document(scale)
			archived = generate(document, archive)
			plain = generate(document, standard)
			{ bytes: archived, work: [archived.len(), plain.len(), archived.len() - plain.len()] }
		}
		_ => crash "archive facade mode is unknown"
	}
}
