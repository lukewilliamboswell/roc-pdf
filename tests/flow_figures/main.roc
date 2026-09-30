app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture
import pf.Metrics

Case : [
	Report({ context : U64 }),
	Sections({ sections : U64 }),
	Labels({ count : U64 }),
	AtomicNegatives({ context : U64 }),
]

CaseSpec : { case : Case, schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	case_json = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => crash "CASE_SPEC_MISSING: flow_figures requires exactly one JSON case argument"
	}
	if args.len() != 2 {
		crash "CASE_SPEC_ARITY: flow_figures requires exactly one JSON case argument"
	}
	parsed : Try(CaseSpec, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(case_json)
	spec = match parsed {
		Ok(value) => value
		Err(InvalidJson(detail)) => crash "CASE_SPEC_INVALID_JSON: ${detail}"
		Err(MissingRequiredField(field)) => crash "CASE_SPEC_MISSING_FIELD: ${field}"
	}
	if spec.schema_version != 1 {
		crash "CASE_SPEC_UNSUPPORTED_VERSION: flow_figures supports schema_version 1"
	}
	if Json.to_str(spec) != case_json {
		crash "CASE_SPEC_NON_CANONICAL: flow_figures rejects unknown fields and non-canonical JSON"
	}
	Metrics.reset_allocations!()
	result = match spec.case {
		Report({ context }) => Fixture.report(context)
		Sections({ sections }) => Fixture.sections(sections)
		Labels({ count }) => Fixture.labels(count)
		AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
	}
	match result {
		Ok(value) => value
		Err(_) => crash "CASE_EXECUTION_FAILED: flow_figures fixture rejected the typed case"
	}
}
