app [main!] {
	pdf: "../../package/all.roc",
	pf: platform "../platform/main.roc",
}

import pdf.KernelReferenceLayout
import pdf.Layout
import pdf.Pdf
import pf.Metrics

Case : [Atoms({ count : U64 })]

CaseSpec : { case : Case, schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	if args.len() != 2 {
		crash "CASE_SPEC_ARITY: reference_layout requires exactly one JSON case"
	}
	json = match args.get(1) {
		Ok(value) => value
		Err(_) => crash "CASE_SPEC_MISSING: reference_layout"
	}
	parsed : Try(CaseSpec, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(json)
	spec = match parsed {
		Ok(value) => value
		Err(_) => crash "CASE_SPEC_INVALID_JSON: reference_layout"
	}
	if spec.schema_version != 1 or Json.to_str(spec) != json {
		crash "CASE_SPEC_NON_CANONICAL: reference_layout"
	}
	count = match spec.case {
		Atoms({ count: value }) => value
	}
	if count != 100 and count != 1000 {
		crash "CASE_SPEC_INVALID_SCALE: reference_layout"
	}
	Metrics.reset_allocations!()
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
	bytes = match Pdf.to_bytes(Pdf.document({ contents: [], language: "en", title: "Symbolic reference measurement "+count.to_str() })) {
		Ok(value) => value
		Err(_) => crash "CASE_CARRIER_FAILED: reference_layout"
	}
	{ bytes, work: [measured.work.atom_writes, measured.work.cluster_visits, measured.work.glyph_index_visits, widths.work.item_visits, widths.work.validation_visits, plan.work.item_visits, plan.work.boundary_visits, plan.work.line_writes, plan.lines.len(), $range_sum, $advance_sum] }
}
