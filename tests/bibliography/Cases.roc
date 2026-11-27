import pdf.Document
import pdf.Pdf

Cases :: [].{
	Case : [Graph({ count : U64, wtpdf : Bool }), Atomic]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| match case {
		Graph({ count, wtpdf }) => graph(count, wtpdf)
		Atomic => {
			cases = [
				{ body: [cite("missing")], feature: "bibliography.citation", path: "contents[0].inlines[1]" },
				{ body: [cite("ordinary"), Pdf.destination_paragraph({ name: "ordinary", text: "Ordinary target" })], feature: "bibliography.citation", path: "contents[0].inlines[1]" },
				{ body: [Pdf.bibliography([entry_a, entry_a])], feature: "bibliography.entry", path: "contents[0].entries[1]" },
				{ body: [Pdf.bibliography([{ target: "space name", text: "Bad target" }])], feature: "bibliography.entry", path: "contents[0].entries[0]" },
				{ body: [Pdf.bibliography([{ target: "blank", text: "    " }])], feature: "bibliography.entry", path: "contents[0].entries[0]" },
				{ body: [Pdf.destination_paragraph({ name: "policy", text: "Occupied target" }), Pdf.bibliography([entry_a])], feature: "bibliography.entry", path: "contents[1].entries[0]" },
				{ body: [Pdf.rich_paragraph([Pdf.citation({ target: "policy", text: " " })]), Pdf.bibliography([entry_a])], feature: "bibliography.citation", path: "contents[0].inlines[0]" },
				{ body: [Pdf.bibliography([])], feature: "bibliography.empty", path: "contents[0]" },
			]
			for scenario in cases {
				document = Pdf.document({ contents: scenario.body, title: "Rejected citation", language: "en" })
				options : Pdf.Options
				options = {}
				if !rejects(Pdf.to_bytes_with(document, options), scenario.feature, scenario.path) or !rejects(Pdf.to_chunks_with(document, options), scenario.feature, scenario.path) {
					crash "BIBLIOGRAPHY_REJECTION_FAILED: ${Str.inspect(Pdf.to_bytes_with(document, options))}"
				}
			}
			result = graph(2, False)
			{ ..result, work: result.work.append(cases.len() * 2) }
		}
	}
}

cite : Str -> Document.Block
cite = |target| Pdf.rich_paragraph([
	Pdf.text("Read the "),
	Pdf.citation({ target, text: if (target == "checklist") "Recovery checklist" else "Service-level policy" }),
	Pdf.text(" before closing the incident."),
])

entry_a : Pdf.BibliographyEntry
entry_a = { target: "policy", text: "Payments Reliability. Service-level policy, revision 3.2." }

graph : U64, Bool -> { bytes : List(U8), work : List(U64) }
graph = |count, wtpdf| {
	var $contents = [Pdf.title("Incident review register")]
	var $index = 0
	while $index < count {
		$contents = $contents.append(cite(if ($index % 2 == 0) "checklist" else "policy"))
		$index = $index + 1
	}
	$contents = $contents.append(Pdf.page_break).append(Pdf.heading(1, "Bibliography")).append(
		Pdf.bibliography([entry_a, { target: "checklist", text: "Payments Reliability. Recovery checklist, revision 2.4." }]),
	)
	document = Pdf.document({ contents: $contents, title: "Incident review register", language: "en" })
	options : Pdf.Options
	options = { wtpdf: if (wtpdf) DeclareAccessibility else NoWtpdfDeclaration }
	reported = require(Pdf.prepare_with_report(document, { options: options }))
	bytes = require(Pdf.to_bytes_prepared(reported.prepared))
	ordinary = require(Pdf.to_bytes_with(document, options))
	facts = reported.report.facts
	entry_paths = facts.blocks.keep_if(|block| block.role == "BibEntry").map(|block| block.path)
	link_reviews = reported.report.obligations.count_if(|review| review.obligation == LinkPurposeMeaningful)
	expected = ["contents[${(count + 3).to_str()}].entries[0]", "contents[${(count + 3).to_str()}].entries[1]"]
	if ordinary != bytes or facts.blocks.len() != count + 4 or entry_paths != expected or link_reviews != count {
		crash "BIBLIOGRAPHY_REPORT_CHANGED_OUTPUT"
	}
	{ bytes, work: [facts.pages.len(), facts.blocks.len(), count, count * 2, bytes.len()] }
}

rejects : Try(a, Pdf.Error), Str, Str -> Bool
rejects = |result, expected, path| match result {
	Err(InvalidDocument({ diagnostics: [{ code: InvalidRelationship, feature: Feature(feature), details: [detail], .. }], .. })) => feature == expected and detail == path
	_ => False
}

require : Try(a, e) -> a
require = |result| match result {
	Ok(value) => value
	Err(error) => crash "BIBLIOGRAPHY_PREPARATION_FAILED: ${Str.inspect(error)}"
}
