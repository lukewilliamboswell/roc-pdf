app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Document
import pdf.Pdf

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

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	mode = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => {
			crash "Gate 4 navigation facade requires a mode"
		}
	}
	guard = U64.mod_by(args.len(), 1)
	document = build_document(guard)
	first = match Pdf.to_bytes(document) {
		Ok(bytes) => bytes
		Err(error) => {
			crash "Gate 4 navigation facade generation failed: ${Str.inspect(error)}"
		}
	}
	if mode == "twice" {
		second = match Pdf.to_bytes(build_document(guard)) {
			Ok(bytes) => bytes
			Err(_) => {
				crash "Gate 4 navigation facade regeneration failed"
			}
		}
		identical = if first == second 1 else 0
		{ bytes: first, work: [identical, first.len()] }
	} else {
		{ bytes: first, work: [first.len()] }
	}
}
