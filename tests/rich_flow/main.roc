app [main!] {
	pdf: "../../package/all.roc",
	pf: platform "../platform/main.roc",
}

import Fixture
import pf.Metrics

Case : [Lists({ count : U64 })]

CaseSpec : { case : Case, schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	case_json = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => crash "CASE_SPEC_MISSING: rich_flow requires exactly one JSON case argument"
	}
	if args.len() != 2 {
		crash "CASE_SPEC_ARITY: rich_flow requires exactly one JSON case argument"
	}
	parsed : Try(CaseSpec, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(case_json)
	spec = match parsed {
		Ok(value) => value
		Err(InvalidJson(detail)) => crash "CASE_SPEC_INVALID_JSON: ${detail}"
		Err(MissingRequiredField(field)) => crash "CASE_SPEC_MISSING_FIELD: ${field}"
	}
	if spec.schema_version != 1 {
		crash "CASE_SPEC_UNSUPPORTED_VERSION: rich_flow supports schema_version 1"
	}
	if Json.to_str(spec) != case_json {
		crash "CASE_SPEC_NON_CANONICAL: rich_flow rejects unknown fields and non-canonical JSON"
	}
	Metrics.reset_allocations!()
	result = match spec.case {
		Lists({ count }) => Fixture.lists(count)
	}
	match result {
		Ok(value) => value
		Err(error) => crash "CASE_EXECUTION_FAILED: ${Str.inspect(error)}"
	}
}
