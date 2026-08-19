app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture
import pf.Metrics

Case : [
	Chain({ scale : U64 }),
	Fan({ scale : U64 }),
	Dense({ scale : U64 }),
	Collide({ scale : U64 }),
	Unique({ scale : U64 }),
	Shared({ scale : U64 }),
	AtomicNegatives({ context : U64 }),
]

CaseSpec : { case : Case, schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	case_json = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => crash "CASE_SPEC_MISSING: resource_graph requires exactly one JSON case argument"
	}
	if args.len() != 2 {
		crash "CASE_SPEC_ARITY: resource_graph requires exactly one JSON case argument"
	}
	parsed : Try(CaseSpec, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(case_json)
	spec = match parsed {
		Ok(value) => value
		Err(InvalidJson(detail)) => crash "CASE_SPEC_INVALID_JSON: ${detail}"
		Err(MissingRequiredField(field)) => crash "CASE_SPEC_MISSING_FIELD: ${field}"
	}
	if spec.schema_version != 1 {
		crash "CASE_SPEC_UNSUPPORTED_VERSION: resource_graph supports schema_version 1"
	}
	if Json.to_str(spec) != case_json {
		crash "CASE_SPEC_NON_CANONICAL: resource_graph rejects unknown fields and non-canonical JSON"
	}
	Metrics.reset_allocations!()
	result = match spec.case {
		Chain({ scale }) => Fixture.resource_plan("chain", scale)
		Fan({ scale }) => Fixture.resource_plan("fan", scale)
		Dense({ scale }) => Fixture.resource_plan("dense", scale)
		Collide({ scale }) => Fixture.collision_plan(scale)
		Unique({ scale }) => Fixture.ownership_plan(Unique, scale)
		Shared({ scale }) => Fixture.ownership_plan(Retained, scale)
		AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
	}
	match result {
		Ok(value) => value
		Err(_) => crash "CASE_EXECUTION_FAILED: resource_graph fixture rejected the typed case"
	}
}
