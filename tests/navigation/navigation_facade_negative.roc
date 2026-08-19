app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Document
import pdf.Pdf

## Atomic facade navigation rejections: each document differs from a valid
## authoring in exactly one navigation fact, every rejection surfaces the
## exact typed InvalidNavigation cause, and no bytes escape. The carrier
## snapshot is an unrelated valid navigation document.
run_negatives : U64 -> U64
run_negatives = |guard| {
	base_title = if guard == 0 "Navigation negatives" else "guarded"
	document = |contents| Pdf.document({ contents, language: "en-AU", title: base_title })
	expect_rejection = |doc, matches| match Pdf.to_bytes(doc) {
		Err(InvalidNavigation(error)) => if matches(error) 1 else 0
		_ => 0
	}

	var $passed = 0
	$passed = $passed + expect_rejection(
		document([Pdf.internal_link("Broken", "missing")]),
		|error| error == UnknownDestinationName({ annotation: 0 }),
	)
	$passed = $passed + expect_rejection(
		document([
			Pdf.destination_heading("twice", 1, "One"),
			Pdf.destination_paragraph("twice", "Two"),
		]),
		|error| error == DuplicateDestinationName({ first: 0, second: 1 }),
	)
	$passed = $passed + expect_rejection(
		document([Pdf.destination_heading("bad name", 1, "Spaced")]),
		|error| error == DestinationNameInvalidByte({ destination: 0, offset: 3 }),
	)
	$passed = $passed + expect_rejection(
		document([Pdf.link("No scheme", "example.org/plain")]),
		|error| error == UriMissingScheme({ annotation: 0 }),
	)
	$passed = $passed + expect_rejection(
		document([Pdf.link("Bad byte", "https://example.org/a b")]),
		|error| error == UriInvalidByte({ annotation: 0, offset: 21 }),
	)
	$passed = $passed + expect_rejection(
		document([Pdf.destination_heading("target", 1, "Target")]).with_outline([
			{ depth: 1, destination: "target", open: True, title: "Broken" },
		]),
		|error| error == OutlineFirstDepthNonzero({ depth: 1 }),
	)
	$passed = $passed + expect_rejection(
		document([Pdf.destination_heading("target", 1, "Target")]).with_outline([
			{ depth: 0, destination: "elsewhere", open: True, title: "Lost" },
		]),
		|error| error == OutlineDestinationUnknown({ entry: 0 }),
	)
	$passed = $passed + expect_rejection(
		document([Pdf.paragraph("Single page")]).with_page_labels([
			{ prefix: "", start_number: 1, start_page: 1, style: DecimalArabic },
		]),
		|error| error == LabelStartPageNotZero({ start: 1 }),
	)
	$passed = $passed + expect_rejection(
		document([Pdf.paragraph("Single page")]).with_page_labels([
			{ prefix: "", start_number: 1, start_page: 0, style: DecimalArabic },
			{ prefix: "", start_number: 1, start_page: 3, style: RomanLower },
		]),
		|error| error == LabelStartPageOutOfRange({ attempted: 3, pages: 1, range: 1 }),
	)
	$passed
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	context = match args.get(1) {
		Ok(text) => match U64.from_str(text) {
			Ok(value) => value
			Err(_) => {
				crash "production-visual navigation facade negative context must be an unsigned integer"
			}
		}
		Err(OutOfBounds) => {
			crash "production-visual navigation facade negatives require a runtime context"
		}
	}
	guard = U64.mod_by(context, 1)
	passed = run_negatives(guard)
	if passed != 9 {
		crash "production-visual navigation facade negatives failed: ${passed.to_str()} of 9"
	}
	carrier_title = if guard == 0 "Navigation carrier" else "guarded"
	carrier = Pdf.document({
		contents: [
			Pdf.title("Navigation carrier"),
			Pdf.destination_heading("start", 1, "Start"),
			Pdf.internal_link("Back to the start", "start"),
		],
		language: "en-AU",
		title: carrier_title,
	})
	bytes = match Pdf.to_bytes(carrier) {
		Ok(value) => value
		Err(_) => {
			crash "production-visual navigation facade carrier failed"
		}
	}
	{ bytes, work: [9, 0, bytes.len()] }
}
