import pdf.Color
import pdf.Document
import pdf.Layout
import pdf.Pdf

Cases :: [].{
	Case : [AtomicBudget({ count : U64 }), Report({ count : U64, wtpdf : Bool })]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Report({ count, wtpdf }) => evidence(count, wtpdf)
			AtomicBudget({ count }) => atomic_budget(count)
		}
		match result {
			Ok(view) => view
			Err(error) => crash "INTER_LATIN_REPORT_FAILED: ${Str.inspect(error)}"
		}
	}
}

atomic_budget : U64 -> Try({ bytes : List(U8), work : List(U64) }, Pdf.Error)
atomic_budget = |count| {
	large = Str.join_with(List.repeat("a", count), "")
	document = Pdf.document({ title: "Inter Latin budget", language: "en", contents: [Pdf.paragraph(large)] })
	if !is_budget(Pdf.to_bytes_with(document, themed)) or !is_budget(Pdf.to_chunks_with(document, themed)) {
		crash "INTER_LATIN_BUDGET_EMITTED_OR_WAS_NOT_LOCATED"
	}
	view = evidence(2, False)?
	Ok({ ..view, work: view.work.append(2) })
}

themed : Pdf.Options
themed = { theme: { family: BuiltIn(Sans), latin_shaping: InterLatin } }

evidence : U64, Bool -> Try({ bytes : List(U8), work : List(U64) }, Pdf.Error)
evidence = |count, wtpdf| {
	if count != 2 and count != 20 {
		crash "INTER_LATIN_SCALE_INVALID"
	}
	workflow = frame("Decision workflow", 131, "AV Proposed -> Decided → Archived")
	colored = Pdf.scoped({ text: Themed(Color.srgb8({ red: 12, green: 52, blue: 116 })) }, [workflow])
	isolated = frame("Break isolation", 15, "a->b")
	var $contents = [isolated]
	var $index = 0
	while $index < count {
		$contents = $contents.append(if ($index % 2 == 0) workflow else colored)
		$index = $index + 1
	}
	document = Pdf.document({ title: "Inter Latin shaping", language: "en-AU", contents: $contents })
	selected_options : Pdf.Options
	selected_options = { ..themed, wtpdf: if (wtpdf) DeclareAccessibility else NoWtpdfDeclaration }
	reported = Pdf.prepare_with_report(document, { options: selected_options })?
	bytes = Pdf.to_bytes_prepared(reported.prepared)?
	ordinary = Pdf.to_bytes_with(document, selected_options)?
	if bytes != ordinary {
		crash "INTER_LATIN_REPORT_ALTERED_PDF"
	}
	facts = reported.report.facts
	if facts.blocks.len() != count + 1 or !facts.blocks.all(|block| block.role == "P" and block.fragments == 2) {
		crash "INTER_LATIN_REPORT_LOST_WRAPPED_OWNERS"
	}
	fragments = facts.pages.map(|page| page.fragments).sum()
	Ok({ bytes, work: [facts.pages.len(), facts.blocks.len(), fragments, count // 2, bytes.len()] })
}

frame : Str, I64, Str -> Document.Block
frame = |name, width, context| Pdf.custom_block({
	name,
	inset: 6,
	size: { width: Layout.Unit.points(width + 12), height: 44 },
	contents: [Pdf.paragraph(context)],
})

is_budget : Try(a, Pdf.Error) -> Bool
is_budget = |result| match result {
	Err(InvalidDocument({ diagnostics: [{ code: BudgetExceeded, feature: Feature("text.latin_shaping_budget"), details: ["contents[0]"], .. }], .. })) => True
	_ => False
}
