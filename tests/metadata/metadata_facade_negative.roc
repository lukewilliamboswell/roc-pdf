app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Document
import pdf.Pdf

## Atomic facade metadata negatives: each authored document differs from a
## valid one in exactly one metadata fact and rejects with the exact typed
## error before any byte or chunk exists. The snapshot payload is an
## unrelated valid single-paragraph document.
make : Str, Str -> Document
make = |language, title| Pdf.document({ contents: [Pdf.paragraph("Body")], language, title })

rejected : Document, (Pdf.Error -> Bool) -> U64
rejected = |document, matches| match Pdf.to_bytes(document) {
	Err(error) => if matches(error) 1 else 0
	Ok(_) => 0
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	context = match args.get(1) {
		Ok(text) => match U64.from_str(text) {
			Ok(value) => value
			Err(_) => {
				crash "production-visual facade metadata negative context must be an unsigned integer"
			}
		}
		Err(OutOfBounds) => {
			crash "production-visual facade metadata negatives require a runtime context"
		}
	}
	if context != 1 {
		crash "production-visual facade metadata negatives expect context 1"
	}

	## The runtime-derived guard keeps the exercised facade pipelines out of
	## compile-time evaluation; it is always zero.
	guard = U64.mod_by(context, 2) - 1
	valid_title = if guard == 0 "Valid" else "guarded"

	var $rejections = 0
	$rejections = $rejections + rejected(make("en_AU", valid_title), |error| error == InvalidMetadata(MalformedLanguageTag({ offset: 2 })))
	$rejections = $rejections + rejected(make("en-au", valid_title), |error| error == InvalidMetadata(LanguageNotCanonicalCase({ offset: 3 })))
	$rejections = $rejections + rejected(make("en-x-priv", valid_title), |error| error == InvalidMetadata(UnsupportedLanguageForm({ offset: 3 })))
	$rejections = $rejections + rejected(make("", valid_title), |error| error == InvalidMetadata(EmptyLanguage))
	$rejections = $rejections + rejected(make("en-AU", ""), |error| error == InvalidMetadata(EmptyTitle))
	$rejections = $rejections + rejected(make("en-AU", "Bad\u(0007)title"), |error| error == InvalidMetadata(InvalidTitleScalar({ offset: 3 })))
	$rejections = $rejections + rejected(
		make("en-AU", valid_title).with_created("2026-02-30T00:00:00Z"),
		|error| error == InvalidMetadata(InvalidTimestamp({ field: Created, offset: 8 })),
	)
	$rejections = $rejections + rejected(
		make("en-AU", valid_title).with_modified("2026-08-18 09:30:00Z"),
		|error| error == InvalidMetadata(InvalidTimestamp({ field: Modified, offset: 10 })),
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
