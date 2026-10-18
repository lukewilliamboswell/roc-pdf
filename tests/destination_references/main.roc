app [main!] {
	pdf: "../../package/all.roc",
	pf: platform "../platform/main.roc",
}

import Fixture
import pf.Metrics

Case : [References({ sections : U64 }), Styled({ context : U64 }), Ordered({ context : U64 }), Negatives({ context : U64 })]

CaseSpec : { case : Case, schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	if args.len() != 2 {
		crash "CASE_SPEC_ARITY: destination_references"
	}
	json = match args.get(1) {
		Ok(value) => value
		Err(_) => crash "CASE_SPEC_MISSING: destination_references"
	}
	parsed : Try(CaseSpec, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(json)
	spec = match parsed {
		Ok(value) => value
		Err(_) => crash "CASE_SPEC_INVALID_JSON: destination_references"
	}
	if spec.schema_version != 1 or Json.to_str(spec) != json {
		crash "CASE_SPEC_NON_CANONICAL: destination_references"
	}
	Metrics.reset_allocations!()
	result = match spec.case {
		References({ sections }) => Fixture.references(sections)
		Styled({ context }) => Fixture.styled(context)
		Ordered({ context }) => Fixture.ordered(context)
		Negatives({ context }) => Fixture.negatives(context)
	}
	match result {
		Ok(value) => value
		Err(error) => crash "CASE_EXECUTION_FAILED: destination_references ${Str.inspect(error)}"
	}
}
