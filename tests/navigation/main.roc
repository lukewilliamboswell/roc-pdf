app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture
import pf.Metrics

Case : [
	Showcase,
	Annotations({ scale : U64 }),
	Quads({ scale : U64 }),
	Share({ scale : U64 }),
	Appearance({ scale : U64 }),
	OutlineDeep({ scale : U64 }),
	OutlineWide({ scale : U64 }),
	Names({ scale : U64 }),
	Labels({ scale : U64 }),
	Unique,
	Retained,
	AtomicNegatives({ context : U64 }),
]

CaseSpec : { case : Case, schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	case_json = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => crash "CASE_SPEC_MISSING: navigation requires exactly one JSON case argument"
	}
	if args.len() != 2 {
		crash "CASE_SPEC_ARITY: navigation requires exactly one JSON case argument"
	}
	parsed : Try(CaseSpec, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(case_json)
	spec = match parsed {
		Ok(value) => value
		Err(InvalidJson(detail)) => crash "CASE_SPEC_INVALID_JSON: ${detail}"
		Err(MissingRequiredField(field)) => crash "CASE_SPEC_MISSING_FIELD: ${field}"
	}
	if spec.schema_version != 1 {
		crash "CASE_SPEC_UNSUPPORTED_VERSION: navigation supports schema_version 1"
	}
	if Json.to_str(spec) != case_json {
		crash "CASE_SPEC_NON_CANONICAL: navigation rejects unknown fields and non-canonical JSON"
	}
	Metrics.reset_allocations!()
	result = match spec.case {
		Showcase => Fixture.scenario("showcase", 0)
		Annotations({ scale }) => Fixture.scenario("annots", scale)
		Quads({ scale }) => Fixture.scenario("quads", scale)
		Share({ scale }) => Fixture.scenario("share", scale)
		Appearance({ scale }) => Fixture.scenario("appearance", scale)
		OutlineDeep({ scale }) => Fixture.scenario("outline_deep", scale)
		OutlineWide({ scale }) => Fixture.scenario("outline_wide", scale)
		Names({ scale }) => Fixture.scenario("names", scale)
		Labels({ scale }) => Fixture.scenario("labels", scale)
		Unique => Fixture.scenario("unique", 0)
		Retained => Fixture.scenario("retained", 0)
		AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
	}
	match result {
		Ok(value) => value
		Err(_) => crash "CASE_EXECUTION_FAILED: navigation fixture rejected the typed case"
	}
}
