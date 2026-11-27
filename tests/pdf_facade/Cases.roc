import pdf.Document
import pdf.Image
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import "../assets/jpeg-fuzz-corpus/rgb-8x8.jpg" as jpeg_bytes : List(U8)
import "../assets/jpeg-fuzz-corpus/rgb-exif-orientation-6.jpg" as rotated_jpeg : List(U8)

## The pdf_facade family's typed cases and their dispatch, run by a fixture
## group app.
##
## `Output` and `Image` take the runtime zero that selects the authored title
## or document, and `ChunksNegative` the runtime argument count (1) it
## validates, so the compiler cannot evaluate the evidence at compile time.
Cases :: [].{
	Case : [
		Output({ context : U64 }),
		Image({ context : U64 }),
		SharedRaster({ pages : U64 }),
		SharedJpeg({ pages : U64 }),
		Chunks({ compression : [Balanced, Fastest, Smallest], retention : [Own, Share] }),
		ChunksNegative({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Output({ context }) => facade_output(context)
			Image({ context }) => image_output(context)
			SharedRaster({ pages }) => shared_raster(pages)
			SharedJpeg({ pages }) => shared_jpeg(pages)
			Chunks({ compression, retention }) => chunked_output(retention, compression)
			ChunksNegative({ context }) => chunks_negative(context)
		}
	}
}

facade_document = Pdf.document({
	contents: [Pdf.paragraph("Café PDF generation in pure Roc.")],
	language: "en-AU",
	title: "text-layout public facade output",
})

## The successful structural carrier is independent of the rejected document.
## Keep its generation outside the measured negative operation; the runtime
## guard and chunk export rejection below remain inside that operation.
chunk_rejection_bytes = Pdf.to_bytes_with(Pdf.document({ contents: [], language: "en-AU", title: "Blank" }), { profile: Archive }) ?? []

# This is the public one-import positive boundary. Its emitted bytes are
# checked structurally by scripts/check_facade_output.py.
expect {
	bytes = Pdf.to_bytes_with(facade_document, { profile: Archive })?
	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 667
}

# Unavailable authored content has no text-layout facade renderer. The typed
# error carries no bytes, so the failure is atomic rather than a blank-output
# fallback.
expect {
	document = Pdf.document({
		contents: [Pdf.footnote("Not implemented")],
		language: "en-AU",
		title: "Atomic negative",
	})

	match Pdf.to_bytes_with(document, { profile: Archive }) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, .. }], .. })) => True
		_ => False
	}
}

facade_output : U64 -> { bytes : List(U8), work : List(U64) }
facade_output = |context| {
	title = if context == 0 {
		"text-layout public facade output"
	} else {
		crash "text-layout public facade runtime guard is invalid"
	}
	document = Pdf.document({
		contents: [Pdf.paragraph("Café PDF generation in pure Roc.")],
		language: "en-AU",
		title,
	})
	bytes = Pdf.to_bytes_with(document, { profile: Archive }) ?? []

	{ bytes, work: [bytes.len()] }
}

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
	drawing = Scene.Drawing.empty.image({ image: image, placement: Layout.rect({ x: 0, y: 0, width: 320, height: 160 }) })
	Pdf.document({
		contents: [
			Pdf.title("Field palette"),
			Pdf.figure({ drawing: drawing, alt: "A four-color field palette arranged in mirrored bands", caption: Pdf.caption("Figure 1 — Field palette") }),
			Pdf.paragraph("The image, caption, and alternative text travel through the public facade."),
		],
		language: "en",
		title: "Image figure facade evidence",
	})
}

expect {
	bytes = Pdf.to_bytes_with(figure_document, { profile: Archive })?
	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 1000
}

## The runtime zero `context` selects the authored document, so the compiler
## cannot evaluate the facade pipeline at compile time.
image_output : U64 -> { bytes : List(U8), work : List(U64) }
image_output = |context| {
	document = if context == 0 {
		figure_document
	} else {
		crash "image-figure facade argument invalid"
	}
	bytes = Pdf.to_bytes_with(document, { profile: Archive }) ?? []
	{ bytes, work: [image_pixels.len(), bytes.len()] }
}

## Three figures on each page place A, B, A. The RGB planes match while
## the alpha planes differ. Figure text and marked content stay distinct.
shared_raster : U64 -> { bytes : List(U8), work : List(U64) }
shared_raster = |pages| {
	raster = |alpha| Image.Source.rgb8({
		alpha: PackedAlpha({ bytes: alpha, row_stride: 2 }),
		dimensions: { width: 2, height: 1 },
		pixels: [30, 60, 90, 120, 150, 180],
		row_stride: 6,
	})
	shared_figures(pages, raster([0, 255]), raster([255, 0]), "Survey figure raster sharing")
}

shared_jpeg : U64 -> { bytes : List(U8), work : List(U64) }
shared_jpeg = |pages| {
	image = Image.Source.jpeg_srgb(jpeg_bytes, RequireDisplayReady)
	shared_figures(pages, image, image, "Survey figure JPEG sharing")
}

shared_figures : U64, Image.Source, Image.Source, Str -> { bytes : List(U8), work : List(U64) }
shared_figures = |pages, a, b, title| {
	empty : List(Document.Block)
	empty = []
	var $blocks = empty
	var $page = 0
	while $page < pages {
		if $page > 0 {
			$blocks = $blocks.append(Pdf.page_break)
		}
		var $placement = 0
		while $placement < 3 {
			image = if ($placement == 1) b else a
			reading = ($page * 3 + $placement + 1).to_str()
			drawing = Scene.Drawing.empty.image({ image, placement: Layout.rect({ x: 0, y: 0, width: 90, height: 36 }) })
			$blocks = $blocks.append(
				Pdf.figure({
					drawing,
					alt: "Image description ${reading}",
					caption: Pdf.caption("Survey figure ${reading}"),
				}),
			)
			$placement = $placement + 1
		}
		$page = $page + 1
	}
	document = Pdf.document({ contents: $blocks, language: "en", title })
	bytes = Pdf.to_bytes_with(document, { profile: Archive }) ?? []
	{ bytes, work: [3 * pages, bytes.len()] }
}

# Shared encoded sources still pass through the format and orientation
# inspector. Both failures keep the facade's existing image diagnostic.
expect {
	rejects = |bytes, reason| {
		image = Image.Source.jpeg_srgb(bytes, RequireDisplayReady)
		drawing = Scene.Drawing.empty.image({ image, placement: Layout.rect({ x: 0, y: 0, width: 90, height: 36 }) })
		document = Pdf.document({
			contents: [Pdf.figure({ drawing, alt: "First image", caption: Pdf.no_caption }), Pdf.figure({ drawing, alt: "Second image", caption: Pdf.no_caption })],
			language: "en",
			title: "JPEG source rejection",
		})
		match Pdf.prepare(document, Pdf.Options.default) {
			Err(InvalidDocument({ diagnostics: [{ code: InvalidRelationship, details: [detail], feature: Feature("image.invalid"), .. }], .. })) => detail == reason
			_ => False
		}
	}
	rejects(rotated_jpeg, "OrientationRequiresTransform")
		and rejects([0xff, 0xd8, 0, 0], "InvalidJpegSegment")
}

## The authored chunked facade drives the same sealed plan as the buffered
## facade, so the concatenated chunks are byte-identical by construction.
## The counters pin the deterministic plan-derived chunk sequence: count,
## largest chunk, an order-sensitive offset weight, and the identity bit.
## The compression choice is sealed by preparation: the identity bit also
## requires the prepared buffered output to equal the one-shot output. The
## `smallest` snapshot is byte-identical to the file this fixture wrote
## before the choice existed.
chunked_output : [Own, Share], [Balanced, Fastest, Smallest] -> { bytes : List(U8), work : List(U64) }
chunked_output = |retention_choice, compression_choice| {
	retention = match retention_choice {
		Share => Pdf.ChunkRetention.ShareUnchangedResources
		Own => Pdf.ChunkRetention.OwnChunks
	}
	compression = match compression_choice {
		Balanced => Pdf.Compression.Balanced
		Fastest => Pdf.Compression.Fastest
		Smallest => Pdf.Compression.Smallest
	}
	document = Pdf.document({
		contents: [Pdf.paragraph("Café PDF generation in pure Roc.")],
		language: "en-AU",
		title: "text-layout public facade output",
	})
	options = Pdf.Options.{ profile: Archive, chunk_retention: retention, compression }
	buffered = Pdf.to_bytes_with(document, options) ?? []
	prepared = match Pdf.prepare(document, options) {
		Err(_) => crash "text-layout chunked facade preparation failed"
		Ok(value) => value
	}
	prepared_buffered = Pdf.to_bytes_prepared(prepared) ?? []
	var $encoder = match Pdf.to_chunks_prepared(prepared, retention) {
		Err(_) => crash "text-layout chunked facade encoder failed"
		Ok(value) => value
	}
	var $bytes = []
	var $chunks = 0
	var $max_chunk_bytes = 0
	var $chunk_offset_weight = 0
	var $done = False
	while $done == False {
		match Pdf.next_chunk($encoder) {
			Done => {
				$done = True
			}
			Emit(chunk, next) => {
				$chunks = $chunks + 1
				if chunk.len() > $max_chunk_bytes {
					$max_chunk_bytes = chunk.len()
				}
				$chunk_offset_weight = $chunk_offset_weight + $chunks * chunk.len()
				$bytes = append_bytes($bytes, chunk)
				$encoder = next
			}
		}
	}
	byte_identical = if ($bytes == buffered and prepared_buffered == buffered) 1 else 0
	{ bytes: $bytes, work: [$chunks, $max_chunk_bytes, $chunk_offset_weight, byte_identical, $bytes.len()] }
}

append_bytes : List(U8), List(U8) -> List(U8)
append_bytes = |target, source| {
	length = source.len()
	var $out = List.reserve(target, length)
	var $index = 0
	while $index < length {
		match source.get($index) {
			Ok(byte) => {
				$out = $out.append(byte)
			}
			Err(OutOfBounds) => {
				crash "text-layout chunked facade chunk index invariant failed"
			}
		}
		$index = $index + 1
	}
	$out
}

## Unavailable authored content must reject before any chunk exists; the
## blank structural carrier is the transactional test result, not a fallback.
chunks_negative : U64 -> { bytes : List(U8), work : List(U64) }
chunks_negative = |context| {
	title = if context == 1 {
		"Chunk rejection"
	} else {
		crash "text-layout chunked facade negative runtime guard is invalid"
	}
	document = Pdf.document({
		contents: [Pdf.footnote("Not implemented")],
		language: "en-AU",
		title,
	})
	rejected = match Pdf.to_chunks_with(document, { profile: Archive }) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, .. }], .. })) => 1
		_ => 0
	}
	if rejected != 1 {
		crash "text-layout chunked facade negative was accepted"
	}
	bytes = chunk_rejection_bytes

	{ bytes, work: [rejected, bytes.len()] }
}
