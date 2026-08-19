app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture
import pf.Metrics

Case : [
	Pages({ count : U64 }),
	Indexes({ count : U64 }),
	Outlines({ count : U64 }),
	Resources({ count : U64 }),
	Lexical({ count : U64 }),
	Deflate({ input_bytes : U64 }),
]

CaseSpec : { case : Case, schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	case_json = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => crash "CASE_SPEC_MISSING: structural_kernel requires exactly one JSON case argument"
	}
	if args.len() != 2 {
		crash "CASE_SPEC_ARITY: structural_kernel requires exactly one JSON case argument"
	}
	parsed : Try(CaseSpec, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(case_json)
	spec = match parsed {
		Ok(value) => value
		Err(InvalidJson(detail)) => crash "CASE_SPEC_INVALID_JSON: ${detail}"
		Err(MissingRequiredField(field)) => crash "CASE_SPEC_MISSING_FIELD: ${field}"
	}
	if spec.schema_version != 1 {
		crash "CASE_SPEC_UNSUPPORTED_VERSION: structural_kernel supports schema_version 1"
	}
	if Json.to_str(spec) != case_json {
		crash "CASE_SPEC_NON_CANONICAL: structural_kernel rejects unknown fields and non-canonical JSON"
	}
	Metrics.reset_allocations!()
	result = match spec.case {
		Pages({ count }) => Ok(Fixture.generate_blank(count))
		Indexes({ count }) => Ok(Fixture.generate_blank_with_indexes(count))
		Outlines({ count }) => Ok(Fixture.generate_blank_with_outline(count))
		Resources({ count }) => Ok(Fixture.generate_blank_with_resource_names(count))
		Lexical({ count }) => Ok(Fixture.generate_blank_with_lexical_values(count))
		Deflate({ input_bytes }) => Ok(Fixture.generate_deflate_stream(input_bytes))
	}
	match result {
		Ok(value) => value
		Err(_) => crash "CASE_EXECUTION_FAILED: structural_kernel fixture rejected the typed case"
	}
}
