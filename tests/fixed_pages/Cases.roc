import pdf.Document
import pdf.Layout
import pdf.Pdf
import remittance.Remittance

Cases :: [].{
	Case : [
		AtomicNegatives({ context : U64 }),
		RemittancePages({ count : U64 }),
		Wtpdf,
	]
	Stats : { bytes : List(U8), work : List(U64) }

	run : Case -> Stats
	run = |case| {
		result = match case {
			RemittancePages({ count }) => {
				if count != 2 and count != 20 {
					crash "CASE_SCALE_INVALID"
				}
				evidence(count, Pdf.Options.default)
			}
			Wtpdf => evidence(2, { wtpdf: DeclareAccessibility })
			AtomicNegatives({ context }) => {
				if context != 0 {
					crash "CASE_CONTEXT_INVALID"
				}
				atomic_negatives({})
			}
		}
		match result {
			Ok(stats) => stats
			Err(error) => crash "FIXED_REMITTANCE_REJECTED: ${Str.inspect(error)}"
		}
	}
}

evidence : U64, Pdf.Options -> Try(Cases.Stats, Pdf.Error)
evidence = |count, options| {
	{ prepared, report } = Pdf.prepare_with_report(Remittance.document(count), options)?
	bytes = Pdf.to_bytes_prepared(prepared)?
	fragments = report.facts.pages.map(|page| page.fragments).sum()
	if report.facts.pages.len() != count or fragments != count * 5 or !authored_paths(report.facts.blocks, count) {
		crash "FIXED_REMITTANCE_REPORT_DISAGREES_WITH_AUTHORSHIP"
	}
	Ok({ bytes, work: [report.facts.pages.len(), report.facts.blocks.len(), fragments, count * 5, count * 2, bytes.len()] })
}

authored_paths : List(Pdf.ReportBlock), U64 -> Bool
authored_paths = |blocks, count| {
	if blocks.len() != count * 5 {
		return False
	}
	roles = ["Title", "P", "H1", "P", "P"]
	var $page = 0
	var $placement = 0
	for block in blocks {
		role = roles.get($placement) ?? crash "FIXED_REMITTANCE_ROLE_INDEX"
		path = "pages[${$page.to_str()}].placements[${$placement.to_str()}]"
		if block.path != path or block.role != role or block.first_page != $page + 1 or block.last_page != $page + 1 or block.fragments != 1 {
			return False
		}
		$placement = $placement + 1
		if $placement == 5 {
			$placement = 0
			$page = $page + 1
		}
	}
	True
}

atomic_negatives : {} -> Try(Cases.Stats, Pdf.Error)
atomic_negatives = |_| {
	samples = [
		(permutation_document([0]), "layout.fixed.paint_order", "pages[0].paint_order"),
		(permutation_document([0, 0]), "layout.fixed.paint_order", "pages[0].paint_order[1]"),
		(permutation_document([0, 2]), "layout.fixed.paint_order", "pages[0].paint_order[1]"),
		(frame_document(Layout.rect({ x: 54, y: 700, width: 0, height: 42 })), "layout.fixed.frame", "pages[0].placements[0].frame"),
		(frame_document(Layout.rect({ x: -1, y: 700, width: 210, height: 42 })), "layout.fixed.frame", "pages[0].placements[0].frame"),
		(frame_document(Layout.rect({ x: 590, y: 700, width: 23, height: 42 })), "layout.fixed.frame", "pages[0].placements[0].frame"),
		(frame_document({ origin: { x: Layout.Unit.millipoints(I64.highest), y: 700 }, size: { width: 1, height: 42 } }), "layout.fixed.frame", "pages[0].placements[0].frame"),
		(frame_document(Layout.rect({ x: 54, y: 700, width: 320, height: 1 })), "layout.fixed.text_height", "pages[0].placements[0]"),
	]
	for (document, feature, path) in samples {
		if !rejects(Pdf.to_bytes(document), feature, path) {
			crash "FIXED_REMITTANCE_EXPECTED_BYTE_REJECTION: ${feature} at ${path}"
		}
		if !rejects(Pdf.to_chunks_with(document, {}), feature, path) {
			crash "FIXED_REMITTANCE_EXPECTED_CHUNK_REJECTION: ${feature} at ${path}"
		}
	}
	flush_frame = Layout.rect({ x: 400, y: 750, width: 212, height: 42 })
	_ = Pdf.to_bytes(frame_document(flush_frame))?
	carrier = evidence(2, Pdf.Options.default)?
	Ok({ ..carrier, work: carrier.work.append(samples.len()).append(samples.len()).append(1) })
}

rejects : Try(a, Pdf.Error), Str, Str -> Bool
rejects = |result, feature, path| match result {
	Err(InvalidDocument({ diagnostics: [{ code: LayoutConstraintViolated, feature: Feature(actual_feature), details, location: Document, stage: AuthoringValidation, .. }], truncation: Complete, .. })) =>
		actual_feature == feature and details.get(0) == Ok(path)
	_ => False
}

frame_document : Layout.Rect -> Document
frame_document = |frame| {
	page = Pdf.fixed_page({ width: 612, height: 792 })
		.place({ block: Pdf.paragraph("Invoice reference R-1042"), frame })
		.finish()
	Pdf.fixed_document({ title: "Remittance frame", language: "en-AU", pages: [page] })
}

permutation_document : List(U64) -> Document
permutation_document = |order| {
	page = Pdf.fixed_page({ width: 612, height: 792 })
		.place({ block: Pdf.paragraph("Apply this payment to the invoice below."), frame: Layout.rect({ x: 54, y: 700, width: 504, height: 36 }) })
		.place({ block: Pdf.paragraph("Invoice reference R-1042"), frame: Layout.rect({ x: 54, y: 640, width: 504, height: 36 }) })
		.with_paint_order(order)
		.finish()
	Pdf.fixed_document({ title: "Remittance paint order", language: "en-AU", pages: [page] })
}
