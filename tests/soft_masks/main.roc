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
	Reuse({ scale : U64 }),
	Masks({ scale : U64 }),
	Chain({ scale : U64 }),
	AtomicNegatives({ context : U64 }),
]

CaseSpec : { schema_version : U64, case : Case }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	case_json = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => crash "CASE_SPEC_MISSING: soft_masks requires exactly one JSON case argument"
	}
	if args.len() != 2 {
		crash "CASE_SPEC_ARITY: soft_masks requires exactly one JSON case argument"
	}

	parsed : Try(CaseSpec, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(case_json)
	spec = match parsed {
		Ok(value) => value
		Err(InvalidJson(detail)) => crash "CASE_SPEC_INVALID_JSON: ${detail}"
		Err(MissingRequiredField(field)) => crash "CASE_SPEC_MISSING_FIELD: ${field}"
	}
	if spec.schema_version != 1 {
		crash "CASE_SPEC_UNSUPPORTED_VERSION: soft_masks supports schema_version 1"
	}
	if Json.to_str(spec) != case_json {
		crash "CASE_SPEC_NON_CANONICAL: soft_masks rejects unknown fields and non-canonical JSON"
	}

	Metrics.reset_allocations!()
	result = match spec.case {
		Showcase => Fixture.scenario("showcase", 0)
		Unique => Fixture.scenario("unique", 0)
		Shared => Fixture.scenario("shared", 0)
		Reuse({ scale }) => if scale > 0 {
			Fixture.scenario("reuse", scale)
		} else {
			crash "CASE_SPEC_INVALID_SCALE: Reuse scale must be positive"
		}
		Masks({ scale }) => if scale > 0 {
			Fixture.scenario("masks", scale)
		} else {
			crash "CASE_SPEC_INVALID_SCALE: Masks scale must be positive"
		}
		Chain({ scale }) => if scale > 0 {
			Fixture.scenario("chain", scale)
		} else {
			crash "CASE_SPEC_INVALID_SCALE: Chain scale must be positive"
		}
		AtomicNegatives({ context }) => if context > 0 {
			Fixture.atomic_negatives(context)
		} else {
			crash "CASE_SPEC_INVALID_CONTEXT: AtomicNegatives context must be positive"
		}
	}
	match result {
		Ok(value) => value
		Err(_) => crash "CASE_EXECUTION_FAILED: soft_masks fixture rejected the typed case"
	}
}
