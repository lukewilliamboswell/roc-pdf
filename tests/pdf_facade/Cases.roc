import pdf.Image
import pdf.Layout
import pdf.Pdf
import pdf.Scene

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
		Chunks({ compression : [Balanced, Fastest, Smallest], retention : [Own, Share] }),
		ChunksNegative({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Output({ context }) => facade_output(context)
			Image({ context }) => image_output(context)
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

# This is the public one-import positive boundary. Its emitted bytes are
# checked structurally by scripts/check_facade_output.py.
expect {
	bytes = Pdf.to_bytes(facade_document)?
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

	match Pdf.to_bytes(document) {
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
	bytes = Pdf.to_bytes(document) ?? []

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
	bytes = Pdf.to_bytes(figure_document)?
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
	bytes = Pdf.to_bytes(document) ?? []
	{ bytes, work: [image_pixels.len(), bytes.len()] }
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
	options = Pdf.Options.{ chunk_retention: retention, compression }
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
	rejected = match Pdf.to_chunks(document) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, .. }], .. })) => 1
		_ => 0
	}
	if rejected != 1 {
		crash "text-layout chunked facade negative was accepted"
	}
	blank = Pdf.document({ contents: [], language: "en-AU", title: "Blank" })
	bytes = Pdf.to_bytes(blank) ?? []

	{ bytes, work: [rejected, bytes.len()] }
}
