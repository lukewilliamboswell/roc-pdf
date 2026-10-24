import pdf.Document
import pdf.Pdf

## The navigation_facade family's typed cases and their dispatch, run by a
## fixture group app.
##
## Each `context` is the runtime value the original fixture derived its zero
## guard from (the argument count 2 for `Output` and `Twice`, the parsed
## context 1 for `Negatives`), so the compiler cannot evaluate the evidence at
## compile time.
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

## The authored facade navigation document: named destinations on headings,
## a URI link, internal links, a link paragraph long enough to fragment
## across the page break so its annotations split per page, an authored
## outline, and page labels.
build_document : U64 -> Document
build_document = |guard| {
	filler = "The survey continues along the ridge line and records each site in order. "
	var $contents = [
		Pdf.title("Coastal survey"),
		Pdf.destination_heading("overview", 1, "Overview"),
		Pdf.paragraph("The overview names each region surveyed in the spring season."),
		Pdf.link("Atlas of Living Australia", "https://www.ala.org.au/species?q=acacia&page=1"),
	]
	var $index = 0
	while $index < 56 + guard {
		$contents = $contents.append(Pdf.paragraph(filler))
		$index = $index + 1
	}
	$contents = $contents
		.append(Pdf.paragraph("Ridge notes."))
		.append(Pdf.internal_link("Return to the overview section for the region list and the seasonal notes that introduce the survey method in detail, including the site selection rules, the recording cadence for each habitat class, the calibration steps applied before every visit, and the way regional totals roll up into the published seasonal summary tables", "overview"))
		.append(Pdf.destination_heading("results", 2, "Results"))
		.append(Pdf.paragraph("Recorded species counts rose in every region."))
		.append(Pdf.internal_link("See the results", "results"))
	document = Pdf.document({
		contents: $contents,
		language: "en-AU",
		title: "Coastal survey",
	})
	document
		.with_outline([
			{ depth: 0, destination: "overview", open: True, title: "Overview" },
			{ depth: 1, destination: "results", open: False, title: "Results" },
		])
		.with_page_labels([
			{ prefix: "", start_number: 1, start_page: 0, style: RomanLower },
			{ prefix: "", start_number: 2, start_page: 1, style: DecimalArabic },
		])
}

facade : U64, Bool -> { bytes : List(U8), work : List(U64) }
facade = |context, twice| {
	guard = U64.mod_by(context, 1)
	document = build_document(guard)
	first = match Pdf.to_bytes(document) {
		Ok(bytes) => bytes
		Err(error) => {
			crash "production-visual navigation facade generation failed: ${Str.inspect(error)}"
		}
	}
	if twice {
		second = match Pdf.to_bytes(build_document(guard)) {
			Ok(bytes) => bytes
			Err(_) => {
				crash "production-visual navigation facade regeneration failed"
			}
		}
		identical = if (first == second) 1 else 0
		{ bytes: first, work: [identical, first.len()] }
	} else {
		{ bytes: first, work: [first.len()] }
	}
}

## Atomic facade navigation rejections: each document differs from a valid
## authoring in exactly one navigation fact, every rejection surfaces the
## exact typed InvalidNavigation cause, and no bytes escape. The carrier
## snapshot is an unrelated valid navigation document.
run_negatives : U64 -> U64
run_negatives = |guard| {
	base_title = if (guard == 0) "Navigation negatives" else "guarded"
	document = |contents| Pdf.document({ contents, language: "en-AU", title: base_title })
	expect_rejection = |doc, matches| match Pdf.to_bytes(doc) {
		Err(InvalidNavigation(error)) => if (matches(error)) 1 else 0
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

negatives : U64 -> { bytes : List(U8), work : List(U64) }
negatives = |context| {
	guard = U64.mod_by(context, 1)
	passed = run_negatives(guard)
	if passed != 9 {
		crash "production-visual navigation facade negatives failed: ${passed.to_str()} of 9"
	}
	carrier_title = if (guard == 0) "Navigation carrier" else "guarded"
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
