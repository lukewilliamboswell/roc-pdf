app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture
import pf.Metrics

Case : [
	Letter({ paragraphs : U64 }),
	Report({ sections : U64 }),
	Ordered({ sections : U64 }),
	Numbering({ context : U64 }),
	Images({ context : U64 }),
	AtomicNegatives({ context : U64 }),
	PageSizes({ context : U64 }),
	Backdrops({ pages : U64 }),
	FurnitureGroups({ context : U64 }),
]

CaseSpec : { case : Case, schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	case_json = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => crash "CASE_SPEC_MISSING: page_templates requires exactly one JSON case argument"
	}
	if args.len() != 2 {
		crash "CASE_SPEC_ARITY: page_templates requires exactly one JSON case argument"
	}
	parsed : Try(CaseSpec, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(case_json)
	spec = match parsed {
		Ok(value) => value
		Err(InvalidJson(detail)) => crash "CASE_SPEC_INVALID_JSON: ${detail}"
		Err(MissingRequiredField(field)) => crash "CASE_SPEC_MISSING_FIELD: ${field}"
	}
	if spec.schema_version != 1 {
		crash "CASE_SPEC_UNSUPPORTED_VERSION: page_templates supports schema_version 1"
	}
	if Json.to_str(spec) != case_json {
		crash "CASE_SPEC_NON_CANONICAL: page_templates rejects unknown fields and non-canonical JSON"
	}
	Metrics.reset_allocations!()
	result = match spec.case {
		Letter({ paragraphs }) => Fixture.letter(paragraphs)
		Report({ sections }) => Fixture.report(sections)
		Ordered({ sections }) => Fixture.ordered(sections)
		Numbering({ context }) => Fixture.numbering(context)
		Images({ context }) => Fixture.images(context)
		AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
		PageSizes({ context }) => Fixture.page_sizes(context)
		Backdrops({ pages }) => Fixture.backdrops(pages)
		FurnitureGroups({ context }) => Fixture.furniture_groups(context)
	}
	match result {
		Ok(value) => value
		Err(_) => crash "CASE_EXECUTION_FAILED: page_templates fixture rejected the typed case"
	}
}
