app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture
import pf.Metrics

Case : [
	Showcase,
	Unique,
	Shared,
	Share({ scale : U64 }),
	States({ scale : U64 }),
	Nest({ scale : U64 }),
	Forms({ scale : U64 }),
	AtomicNegatives({ context : U64 }),
]

CaseSpec : { case : Case, schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	case_json = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => crash "CASE_SPEC_MISSING: transparency requires exactly one JSON case argument"
	}
	if args.len() != 2 {
		crash "CASE_SPEC_ARITY: transparency requires exactly one JSON case argument"
	}
	parsed : Try(CaseSpec, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(case_json)
	spec = match parsed {
		Ok(value) => value
		Err(InvalidJson(detail)) => crash "CASE_SPEC_INVALID_JSON: ${detail}"
		Err(MissingRequiredField(field)) => crash "CASE_SPEC_MISSING_FIELD: ${field}"
	}
	if spec.schema_version != 1 {
		crash "CASE_SPEC_UNSUPPORTED_VERSION: transparency supports schema_version 1"
	}
	if Json.to_str(spec) != case_json {
		crash "CASE_SPEC_NON_CANONICAL: transparency rejects unknown fields and non-canonical JSON"
	}
	Metrics.reset_allocations!()
	result = match spec.case {
		Showcase => Fixture.scenario("showcase", 0)
		Unique => Fixture.scenario("unique", 0)
		Shared => Fixture.scenario("shared", 0)
		Share({ scale }) => Fixture.scenario("share", scale)
		States({ scale }) => Fixture.scenario("states", scale)
		Nest({ scale }) => Fixture.scenario("nest", scale)
		Forms({ scale }) => Fixture.scenario("forms", scale)
		AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
	}
	match result {
		Ok(value) => value
		Err(_) => crash "CASE_EXECUTION_FAILED: transparency fixture rejected the typed case"
	}
}
