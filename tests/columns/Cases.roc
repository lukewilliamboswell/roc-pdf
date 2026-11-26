import pdf.Document
import pdf.Layout
import pdf.Pdf
import pilot.Pilot

Cases :: [].{
	Case : [Article({ copies : U64 }), Wtpdf, Rejections]
	Stats : { bytes : List(U8), work : List(U64) }

	run : Case -> Stats
	run = |case| {
		result = match case {
			Article({ copies }) if copies == 1 or copies == 10 => evidence(copies, Pilot.options)
			Article(_) => crash "CASE_SCALE_INVALID"
			Wtpdf => evidence(1, { ..Pilot.options, wtpdf: DeclareAccessibility })
			Rejections => negatives({})
		}
		match result {
			Ok(stats) => stats
			Err(error) => crash "PILOT_FINDINGS_REJECTED: ${Str.inspect(error)}"
		}
	}
}

evidence : U64, Pdf.Options -> Try(Cases.Stats, Pdf.Error)
evidence = |copies, options| {
	{ prepared, report } = Pdf.prepare_with_report(Pilot.document(copies), { options: options })?
	bytes = Pdf.to_bytes_prepared(prepared)?
	page_count = report.facts.pages.len()
	fragments = report.facts.pages.map(|page| page.fragments).sum()
	if report.facts.blocks.len() != copies + 1 {
		crash "PILOT_REPORT_BLOCK_COUNT"
	}
	zero : U64
	zero = 0
	var $pos = zero
	for block in report.facts.blocks {
		path = "contents[0].contents[${$pos.to_str()}]"
		if block.path != path {
			crash "PILOT_REPORT_PATH: expected ${path} got ${block.path}"
		}
		if $pos == 0 {
			if block.role != "Title" or block.first_page != 1 or block.last_page != 1 or block.fragments != 1 {
				crash "PILOT_REPORT_TITLE"
			}
		} else if block.role != "P" or block.last_page <= block.first_page or block.fragments < 3 {
			crash "PILOT_REPORT_PARAGRAPH_CONTINUATION"
		}
		$pos = $pos + 1
	}
	Ok({ bytes, work: [page_count, report.facts.blocks.len(), fragments, bytes.len()] })
}

negatives : {} -> Try(Cases.Stats, Pdf.Error)
negatives = |_| {
	width_over = Layout.Unit.millipoints(206001)
	samples = [
		(Pilot.kept({}), "layout.columns.keep_conflict", "contents[0].contents[1]"),
		(document(width_over, [Pdf.paragraph("Boundary.")]), "layout.columns.width", "contents[0]"),
		(document(0, [Pdf.paragraph("Boundary.")]), "layout.columns.width", "contents[0].first"),
		(document(206, [Pdf.spacer(20)]), "layout.columns.block", "contents[0].contents[0]"),
		(document(206, []), "layout.columns.empty", "contents[0].contents"),
	]
	for (fixture, feature, path) in samples {
		if !rejects(Pdf.to_bytes_with(fixture, Pilot.options), feature, path) or !rejects(Pdf.to_chunks_with(fixture, Pilot.options), feature, path) {
			crash "PILOT_EXPECTED_ATOMIC_REJECTION: ${feature} at ${path}"
		}
	}
	carrier = evidence(1, Pilot.options)?
	Ok({ ..carrier, work: carrier.work.append(samples.len()).append(samples.len()) })
}

rejects : Try(a, Pdf.Error), Str, Str -> Bool
rejects = |result, feature, path| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature(actual), details, .. }], truncation: Complete, .. })) =>
		actual == feature and details.get(0) == Ok(path)
	_ => False
}

document : Layout.Unit, List(Document.Block) -> Document
document = |first, contents| Pdf.document({
	contents: [Pdf.multi_column({ first, gutter: 16, second: 186, contents })],
	language: "en-AU",
	title: "Column frame check",
})
