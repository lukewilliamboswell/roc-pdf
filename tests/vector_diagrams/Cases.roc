import diagram.Diagram
import diagram.PreparedDiagram
import pdf.Font
import pdf.Pdf

## The vector_diagrams family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		ArchiveDiagrams({ count : U64 }),
		Diagrams({ count : U64 }),
	]
	Stats : { bytes : List(U8), work : List(U64) }

	run : Case -> Stats
	run = |case| {
		{ count: scale, archive } = match case {
			ArchiveDiagrams({ count }) => { count, archive: True }
			Diagrams({ count }) => { count, archive: False }
		}
		if scale == 0 or scale > 50 {
			crash "CASE_SCALE_INVALID"
		}
		match render(scale, archive) {
			Ok(stats) => stats
			Err(_) => crash "VECTOR_DOCUMENT_REJECTED"
		}
	}
}

## Keep default registration fallible without matching a compile-time-known
## success in isolation. The whole document pipeline depends on runtime count.
render : U64, Bool -> Try(Cases.Stats, [FontRegistration(Font.ResourceError), Preparation(Pdf.Error), Emission(Pdf.Error)])
render = |count, archive| {
	options = Diagram.options(Font.ValidationLimits.default).map_err(|error| FontRegistration(error))?
	result = Pdf.prepare_with_report(Diagram.document(count), { options: if (archive) { ..options, profile: Archive, wtpdf: NoWtpdfDeclaration } else options }).map_err(|error| Preparation(error))?
	bytes = Pdf.to_bytes_prepared(result.prepared).map_err(|error| Emission(error))?
	fragments = result.report.facts.pages.map(|page| page.fragments).sum()

	## Exact authored commands and output bytes, alongside allocation/byte
	## evidence, catch growth regressions without probing private compiler APIs.
	Ok({ bytes, work: [count, count * PreparedDiagram.drawing({}).command_count(), count * 5, result.report.facts.pages.len(), fragments, bytes.len()] })
}
