app [main!] {
	diagram: "../../examples/vector-diagrams/all.roc",
	pdf: "../../package/all.roc",
	pf: platform "../platform/main.roc",
}

import Fixture
import pf.Metrics

CaseSpec : { case : [Manual({ chapters : U64 })], schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	text = args.get(1) ?? ""
	spec : CaseSpec
	spec = match Json.parse(text) {
		Ok(value) => value
		Err(_) => crash "CASE_SPEC_INVALID_JSON"
	}
	if args.len() != 2 or spec.schema_version != 1 or Json.to_str(spec) != text {
		crash "CASE_SPEC_INVALID"
	}
	Manual({ chapters }) = spec.case
	Metrics.reset_allocations!()
	match Fixture.manual(chapters) {
		Ok(value) => value
		Err(error) => crash "CASE_EXECUTION_FAILED: ${Str.inspect(error)}"
	}
}
