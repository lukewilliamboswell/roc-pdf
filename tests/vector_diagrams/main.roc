app [main!] {
	diagram: "../../examples/vector-diagrams/package.roc",
	pdf: "../../package/main.roc",
	pf: platform "../platform/main.roc",
}

import diagram.Diagram
import diagram.PreparedDiagram
import pdf.Pdf
import pf.Metrics

CaseSpec : { case : [Diagrams({ count : U64 })], schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	case_json = args.get(1) ?? ""
	spec : CaseSpec
	spec = match Json.parse(case_json) {
		Ok(value) => value
		Err(_) => crash "CASE_SPEC_INVALID_JSON"
	}
	if args.len() != 2 or spec.schema_version != 1 or Json.to_str(spec) != case_json {
		crash "CASE_SPEC_INVALID"
	}
	Diagrams({ count }) = spec.case
	if count == 0 or count > 50 {
		crash "CASE_SCALE_INVALID"
	}
	Metrics.reset_allocations!()
	options = match Diagram.options(count) {
		Ok(value) => value
		Err(_) => crash "FONT_REJECTED"
	}
	result = match Pdf.prepare_with_report(Diagram.document(count), options) {
		Ok(value) => value
		Err(_) => crash "DOCUMENT_REJECTED"
	}

	bytes = match Pdf.to_bytes_prepared(result.prepared) {
		Ok(value) => value
		Err(_) => crash "EMISSION_REJECTED"
	}
	fragments = result.report.facts.pages.map(|page| page.fragments).sum()

	## Exact authored commands and output bytes, alongside allocation/byte
	## evidence, catch growth regressions without probing private compiler APIs.
	{ bytes, work: [count, count * PreparedDiagram.drawing({}).command_count(), count * 5, result.report.facts.pages.len(), fragments, bytes.len()] }
}
