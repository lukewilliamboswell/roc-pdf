import pdf.Document
import pdf.Pdf

## The metadata_facade family's typed cases and their dispatch, run by a
## fixture group app.
##
## `Output` and `Twice` take the runtime zero that selects the authored title;
## `Negatives` takes the runtime context 1 it validates. Either keeps the
## compiler from evaluating the evidence at compile time.
Cases :: [].{
	Case : [
		Output({ context : U64 }),
		Twice({ context : U64 }),
		Negatives({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Output({ context }) => facade(context, False)
			Twice({ context }) => facade(context, True)
			Negatives({ context }) => negatives(context)
		}
	}
}

## The public one-import facade path for the production-visual metadata slice: a
## multi-page document whose validated language, escaped non-ASCII metadata
## title, and explicit timestamps flow into the catalog `/Lang`, the
## canonical XMP stream, and the packaged sRGB output intent. The emitted
## bytes are checked structurally by scripts/check_metadata.py.
facade_title : Str
facade_title = "Café Metadata & <Report> — 概要"

facade_document : Str -> Document
facade_document = |title| {
	paragraph_count : U64
	paragraph_count = 40

	var $contents = List.with_capacity(paragraph_count + 1)
	$contents = $contents.append(Pdf.title("Deterministic metadata"))
	var $index = 0
	while $index < paragraph_count {
		$contents = $contents.append(Pdf.paragraph("Paragraph ${Str.inspect($index)} carries the same document language and shares one packaged sRGB output-intent profile."))
		$index = $index + 1
	}
	document = Pdf.document({ contents: $contents, language: "en-AU", title })
	document.with_created("2026-01-02T03:04:05Z").with_modified("2026-08-18T09:30:00Z")
}

# Invalid metadata rejects atomically through the facade with the exact
# typed validation fact and no bytes.
expect {
	document = Pdf.document({ contents: [Pdf.paragraph("Body")], language: "en-au", title: "Case" })

	match Pdf.to_bytes(document) {
		Err(InvalidMetadata(LanguageNotCanonicalCase({ offset: 3 }))) => True
		_ => False
	}
}

facade : U64, Bool -> { bytes : List(U8), work : List(U64) }
facade = |context, twice| {
	title = if (context != 0) "unused" else facade_title
	document = facade_document(title)
	bytes = match Pdf.to_bytes(document) {
		Ok(value) => value
		Err(_) => {
			crash "production-visual facade metadata generation failed"
		}
	}
	if twice {
		second = match Pdf.to_bytes(facade_document(title)) {
			Ok(value) => value
			Err(_) => {
				crash "production-visual facade metadata regeneration failed"
			}
		}
		identical = if (bytes == second) 1 else 0
		{ bytes, work: [identical, bytes.len()] }
	} else {
		{ bytes, work: [bytes.len()] }
	}
}

## Atomic facade metadata negatives: each authored document differs from a
## valid one in exactly one metadata fact and rejects with the exact typed
## error before any byte or chunk exists. The snapshot payload is an
## unrelated valid single-paragraph document.
make : Str, Str -> Document
make = |language, title| Pdf.document({ contents: [Pdf.paragraph("Body")], language, title })

rejected : Document, (Pdf.Error -> Bool) -> U64
rejected = |document, matches| match Pdf.to_bytes(document) {
	Err(error) => if (matches(error)) 1 else 0
	Ok(_) => 0
}

negatives : U64 -> { bytes : List(U8), work : List(U64) }
negatives = |context| {
	if context != 1 {
		crash "production-visual facade metadata negatives expect context 1"
	}

	## The runtime-derived guard keeps the exercised facade pipelines out of
	## compile-time evaluation; it is always zero.
	guard = U64.mod_by(context, 2) - 1
	valid_title = if (guard == 0) "Valid" else "guarded"

	var $rejections = 0
	$rejections = $rejections + rejected(
		make("en_AU", valid_title),
		|error| match error {
			InvalidMetadata(MalformedLanguageTag({ offset: 2 })) => True
			_ => False
		},
	)
	$rejections = $rejections + rejected(
		make("en-au", valid_title),
		|error| match error {
			InvalidMetadata(LanguageNotCanonicalCase({ offset: 3 })) => True
			_ => False
		},
	)
	$rejections = $rejections + rejected(
		make("en-x-priv", valid_title),
		|error| match error {
			InvalidMetadata(UnsupportedLanguageForm({ offset: 3 })) => True
			_ => False
		},
	)
	$rejections = $rejections + rejected(
		make("", valid_title),
		|error| match error {
			InvalidMetadata(EmptyLanguage) => True
			_ => False
		},
	)
	$rejections = $rejections + rejected(
		make("en-AU", ""),
		|error| match error {
			InvalidMetadata(EmptyTitle) => True
			_ => False
		},
	)
	$rejections = $rejections + rejected(
		make("en-AU", "Bad\u(0007)title"),
		|error| match error {
			InvalidMetadata(InvalidTitleScalar({ offset: 3 })) => True
			_ => False
		},
	)
	$rejections = $rejections + rejected(
		make("en-AU", valid_title).with_created("2026-02-30T00:00:00Z"),
		|error| match error {
			InvalidMetadata(InvalidTimestamp({ field: Created, offset: 8 })) => True
			_ => False
		},
	)
	$rejections = $rejections + rejected(
		make("en-AU", valid_title).with_modified("2026-08-18 09:30:00Z"),
		|error| match error {
			InvalidMetadata(InvalidTimestamp({ field: Modified, offset: 10 })) => True
			_ => False
		},
	)

	## The chunked path rejects identically before any chunk exists.
	chunk_rejected = match Pdf.to_chunks(make("en-au", valid_title)) {
		Err(InvalidMetadata(LanguageNotCanonicalCase({ offset: 3 }))) => 1
		_ => 0
	}
	$rejections = $rejections + chunk_rejected

	carrier = match Pdf.to_bytes(make("en-AU", valid_title)) {
		Ok(value) => value
		Err(_) => {
			crash "production-visual facade metadata carrier generation failed"
		}
	}
	{ bytes: carrier, work: [$rejections, carrier.len()] }
}
