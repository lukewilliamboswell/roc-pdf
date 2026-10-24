import pdf.KernelReferenceLayout
import pdf.Layout
import pdf.Pdf

## The reference_layout family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Atoms({ count : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		count = match case {
			Atoms({ count: value }) => value
		}
		if count != 100 and count != 1000 {
			crash "CASE_SPEC_INVALID_SCALE: reference_layout"
		}
		limits = { max_items: count, max_lines: count }
		var $builder = KernelReferenceLayout.Builder.start(limits)
		var $index = 0
		while $index < count {
			$builder = KernelReferenceLayout.Builder.reference($builder, $index, Layout.Unit.points((1 + $index % 3).to_i64_wrap()))
			$index = $index + 1
		}
		measured = match KernelReferenceLayout.Builder.finish($builder) {
			Ok(value) => value
			Err(_) => crash "CASE_BUILD_FAILED: reference_layout"
		}
		widths = match KernelReferenceLayout.measure(measured.items, limits) {
			Ok(value) => value
			Err(_) => crash "CASE_MEASURE_FAILED: reference_layout"
		}
		plan = match KernelReferenceLayout.wrap(measured.items, 4, limits) {
			Ok(value) => value
			Err(_) => crash "CASE_WRAP_FAILED: reference_layout"
		}
		var $cursor = 0
		var $range_sum = 0
		var $advance_sum = 0
		for line in plan.lines {
			if line.items.start() != $cursor or line.items.length() == 0 or line.advance > 4 {
				crash "CASE_COVERAGE_FAILED: reference_layout"
			}
			$range_sum = $range_sum + (line.items.start() + 1) * line.items.length()
			$advance_sum = $advance_sum + line.advance.raw().to_u64_wrap()
			$cursor = $cursor + line.items.length()
		}
		if $cursor != count {
			crash "CASE_COVERAGE_FAILED: reference_layout"
		}

		## The blank PDF is only a common output carrier for this kernel's
		## allocation/work evidence. No symbolic item is painted or presented
		## as a resolved document reference by this focused measurement case.
		bytes = match Pdf.to_bytes(Pdf.document({ contents: [], language: "en", title: "Symbolic reference measurement ${count.to_str()}" })) {
			Ok(value) => value
			Err(_) => crash "CASE_CARRIER_FAILED: reference_layout"
		}
		{ bytes, work: [measured.work.atom_writes, measured.work.cluster_visits, measured.work.glyph_index_visits, widths.work.item_visits, widths.work.validation_visits, plan.work.item_visits, plan.work.boundary_visits, plan.work.line_writes, plan.lines.len(), $range_sum, $advance_sum] }
	}
}
