import diagram.Diagram
import diagram.PreparedDiagram
import pdf.Font
import pdf.Pdf

## The vector_diagrams family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Diagrams({ count : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		Diagrams({ count }) = case
		if count == 0 or count > 50 {
			crash "CASE_SCALE_INVALID"
		}
		options = match Diagram.options(Font.ValidationLimits.default) {
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
}
