app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Document
import pdf.Pdf

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

## Invalid metadata rejects atomically through the facade with the exact
## typed validation fact and no bytes.
expect {
	document = Pdf.document({ contents: [Pdf.paragraph("Body")], language: "en-au", title: "Case" })

	match Pdf.to_bytes(document) {
		Err(InvalidMetadata(LanguageNotCanonicalCase({ offset: 3 }))) => True
		_ => False
	}
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => {
			crash "production-visual facade metadata evidence requires a mode"
		}
	}
	title = if mode == "unused" "unused" else facade_title
	document = facade_document(title)
	bytes = match Pdf.to_bytes(document) {
		Ok(value) => value
		Err(_) => {
			crash "production-visual facade metadata generation failed"
		}
	}
	if mode == "twice" {
		second = match Pdf.to_bytes(facade_document(title)) {
			Ok(value) => value
			Err(_) => {
				crash "production-visual facade metadata regeneration failed"
			}
		}
		identical = if bytes == second 1 else 0
		{ bytes, work: [identical, bytes.len()] }
	} else {
		{ bytes, work: [bytes.len()] }
	}
}
