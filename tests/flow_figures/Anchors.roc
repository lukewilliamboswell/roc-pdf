import pdf.Color
import pdf.Document
import pdf.Layout
import pdf.Pdf
import pdf.Scene

Anchors :: [].{
	Error : [EvidenceFailure, BadScale, MissingRejection(Str)]
	Stats : { bytes : List(U8), work : List(U64) }

	evidence : U64 -> Try(Stats, Error)
	evidence = |count| {
		if count != 1 and count != 12 {
			return Err(BadScale)
		}
		doc = repeated(count)
		{ prepared, report } = Pdf.prepare_with_report(doc, { options: options(170) }) ? |_| EvidenceFailure
		if report.facts.pages.len() != 2 * count or report.facts.blocks.len() != 4 * count {
			return Err(EvidenceFailure)
		}
		var $index = 0
		while $index < count {
			first_page = 2 * $index + 1
			anchor_page = first_page + 1
			order = report.facts.blocks.sublist({ start: 4 * $index, len: 4 })
			member = "contents[${(4 * $index + 2).to_str()}]"
			expected = [("P", first_page), ("P", anchor_page), ("Figure", anchor_page), ("Caption", anchor_page)]
			review = order.map(|block| (block.role, block.first_page))
			paths = order.drop_first(1).map(|block| block.path)
			if review != expected or paths != ["${member}.anchor", "${member}.figure", "${member}.figure.caption"] or !order.all(|block| block.first_page == block.last_page) {
				return Err(EvidenceFailure)
			}
			$index = $index + 1
		}
		if report.obligations.count_if(|entry| entry.obligation == AlternativeTextMeaningful) != count or !report.obligations.contains({ obligation: ReadingOrderMeaningful, path: "document" }) {
			return Err(EvidenceFailure)
		}
		bytes = Pdf.to_bytes_prepared(prepared) ? |_| EvidenceFailure
		fragments = report.facts.pages.map(|page| page.fragments).sum()
		Ok({ bytes, work: [count, report.facts.pages.len(), report.facts.blocks.len(), fragments, report.facts.outcomes.len(), bytes.len()] })
	}

	rejections : {} -> Try(Stats, Error)
	rejections = |_| {
		normal = repeated(1)
		meta = |block| Pdf.document({ contents: [block], title: "Anchor rejection", language: "en-AU" })
		examined = [
			(normal, options(136), "layout.anchored_figure_fit", ["contents[2].anchor", "contents[2].figure"]),
			(meta(pair(prose(1), "", "API gateway request path")), options(170), "document.figure_alternative_empty", ["contents[0].figure"]),
			(meta(pair(prose(1), description, "")), options(170), "document.figure_caption_empty", ["contents[0].figure.caption"]),
			(meta(pair([], description, "API gateway request path")), options(170), "semantics.inline_empty", ["contents[0].anchor"]),
		]
		for (doc, policy, code, path) in examined {
			if !rejected(Pdf.to_bytes_with(doc, policy), code, path) or !rejected(Pdf.to_chunks_with(doc, policy), code, path) {
				return Err(MissingRejection(code))
			}
		}
		carrier = evidence(1)?
		Ok({ ..carrier, work: carrier.work.append(examined.len()) })
	}
}

options : I64 -> Pdf.Options
options = |height| {
	page_size: Custom({ width: 310, height: Layout.Unit.points(height) }),
	theme: { page_margin: { top: 20, bottom: 20, left: 20, right: 20 }, body: { size: 10, leading: 14 }, paragraph_spacing: 4 },
	wtpdf: DeclareAccessibility,
}

description : Str
description = "Teal rectangle represents the API gateway."

pair : List(Pdf.Inline), Str, Str -> Document.Block
pair = |anchor, alternative, caption| {
	teal : Color.SourceValue
	teal = "#176E73"
	drawing = Scene.Drawing.empty.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 96, height: 64 }), color: teal })
	Pdf.anchored_figure(anchor, { drawing, alt: alternative, caption })
}

prose : U64 -> List(Pdf.Inline)
prose = |ordinal| [
	Pdf.text("Anchor ${ordinal.to_str()}: a payment reaches the gateway."),
	Pdf.line_break,
	Pdf.text("Follow the request in the diagram."),
]

repeated : U64 -> Document
repeated = |count| {
	var $blocks = List.with_capacity(4 * count - 1)
	var $index = 0
	while $index < count {
		if $index > 0 {
			$blocks = $blocks.append(Pdf.page_break)
		}
		$blocks = $blocks.append(Pdf.paragraph("Incident context ${($index + 1).to_str()}")).append(Pdf.spacer(60)).append(pair(prose($index + 1), description, "API gateway request path"))
		$index = $index + 1
	}
	Pdf.document({ contents: $blocks, title: "Anchored payment diagrams", language: "en-AU" })
}

rejected : Try(a, Pdf.Error), Str, List(Str) -> Bool
rejected = |result, code, paths| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature(actual), details, .. }], truncation: Complete, .. })) => actual == code and details == paths
	_ => False
}
