import brief.Brief
import pdf.Color
import pdf.Document
import pdf.Layout
import pdf.Pdf
import pdf.Scene

Designed :: [].{
	Stats : { bytes : List(U8), work : List(U64) }

	evidence : U64 -> Try(Stats, Pdf.Error)
	evidence = |count| {
		if count != 2 and count != 20 {
			crash "FIXED_BRIEF_SCALE"
		}
		options : Pdf.Options
		options = { theme: Brief.theme, wtpdf: DeclareAccessibility }
		{ prepared, report } = Pdf.prepare_with_report(Brief.document(count), { options: options })?
		bytes = Pdf.to_bytes_prepared(prepared)?
		if report.facts.pages.len() != count or report.facts.blocks.len() != count * 4 or !report.obligations.contains({ obligation: ReadingOrderMeaningful, path: "document" }) {
			crash "FIXED_BRIEF_REPORT"
		}
		alternatives = report.obligations.keep_if(|obligation| obligation.obligation == AlternativeTextMeaningful)
		var $page = 0
		while $page < count {
			prefix = "pages[${$page.to_str()}].placements"
			paths = [("${prefix}[0]", "Title"), ("${prefix}[1]", "P"), ("${prefix}[2]", "Figure"), ("${prefix}[2].caption", "Caption")]
			blocks = report.facts.blocks.sublist({ start: $page * 4, len: 4 })
			if blocks.map(|block| (block.path, block.role)) != paths or !blocks.all(|block| block.first_page == $page + 1 and block.last_page == $page + 1) {
				crash "FIXED_BRIEF_PATHS"
			}
			if report.facts.outcomes.get($page) != Ok(FigureScale({ fit: Exact, path: "${prefix}[2]", scale: 1000 })) or alternatives.get($page) != Ok({ obligation: AlternativeTextMeaningful, path: "${prefix}[2]" }) {
				crash "FIXED_BRIEF_FIGURE_REPORT"
			}
			$page = $page + 1
		}
		fragments = report.facts.pages.map(|page| page.fragments).sum()
		Ok({ bytes, work: [count, count * 3, report.facts.blocks.len(), fragments, report.facts.outcomes.len(), bytes.len()] })
	}

	negatives : {} -> Try(Stats, Pdf.Error)
	negatives = |_| {
		tint : Color.SourceValue
		tint = "#1E7162"
		drawing = Scene.Drawing.empty.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 128, height: 60 }), color: tint })
		frame = Layout.rect({ x: 484, y: 704, width: 128, height: 88 })
		block = Pdf.figure({ drawing, alt: "A solid teal patch", caption: Pdf.caption("Teal patch") })
		too_narrow = Layout.rect({ x: 484, y: 704, width: 127, height: 88 })
		too_short = Layout.rect({ x: 484, y: 704, width: 128, height: 87 })
		outside : Layout.Rect
		outside = { ..frame, origin: { x: Layout.Unit.millipoints(484001), y: frame.origin.y } }
		empty_alt = Pdf.figure({ drawing, alt: "", caption: Pdf.no_caption })
		empty_caption = Pdf.figure({ drawing, alt: "A solid teal patch", caption: Pdf.caption("") })
		scale = Pdf.figure({ drawing, alt: "A solid teal patch", caption: Pdf.no_caption, fit: ScaleToFit({ minimum_percent: 90 }) })
		label = drawing.text({ text: "Teal", origin: Layout.point({ x: 2, y: 2 }), size: 10, color: tint })
		labelled = Pdf.figure({ drawing: label, alt: "A solid teal patch", caption: Pdf.no_caption })
		options : Pdf.Options
		options = { theme: Brief.theme, wtpdf: DeclareAccessibility }

		## The drawing, caption gap and one line fit exactly in both axes.
		_ = Pdf.to_bytes_with(figure_document(block, frame), options)?

		## A narrow figure's ownership anchor does not impose font advance.
		tiny = Scene.Drawing.empty.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 1, height: 1 }), color: tint })
		_ = Pdf.to_bytes_with(figure_document(Pdf.figure({ drawing: tiny, alt: "One teal point", caption: Pdf.no_caption }), Layout.rect({ x: 611, y: 791, width: 1, height: 1 })), options)?
		path = "pages[0].placements[0]"
		cases = [
			(figure_document(block, too_narrow), "layout.fixed.figure_frame", path),
			(figure_document(block, too_short), "layout.fixed.figure_frame", path),
			(figure_document(block, outside), "layout.fixed.frame", "${path}.frame"),
			(figure_document(empty_alt, frame), "document.figure_alternative_empty", path),
			(figure_document(empty_caption, frame), "document.figure_caption_empty", "${path}.caption"),
			(figure_document(scale, frame), "layout.fixed.figure_fit", path),
			(figure_document(labelled, frame), "layout.fixed.figure_labels", path),
		]
		for (document, feature, location) in cases {
			if !rejected(Pdf.to_bytes_with(document, options), feature, location) or !rejected(Pdf.to_chunks_with(document, options), feature, location) {
				crash "FIXED_BRIEF_EXPECTED_ATOMIC_REJECTION ${feature} at ${location}"
			}
		}
		carrier = evidence(2)?
		Ok({ ..carrier, work: carrier.work.append(cases.len()).append(2) })
	}
}

figure_document : Document.Block, Layout.Rect -> Document
figure_document = |block, frame| {
	page = Pdf.fixed_page({ width: 612, height: 792 }).place({ block, frame }).finish()
	Pdf.fixed_document({ title: "Fixed figure boundary", language: "en-AU", pages: [page] })
}

rejected : Try(a, Pdf.Error), Str, Str -> Bool
rejected = |result, feature, path| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature(actual), details, .. }], truncation: Complete, .. })) => actual == feature and details.get(0) == Ok(path)
	_ => False
}
