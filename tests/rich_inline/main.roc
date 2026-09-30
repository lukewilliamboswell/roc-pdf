app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture
import pf.Metrics

Case : [
	Mixed({ context : U64 }),
	Paragraphs({ count : U64 }),
	Ordered({ context : U64 }),
	CodeFace({ context : U64 }),
	SharedSource({ count : U64 }),
	HeadingFaces({ count : U64 }),
	ScaledCode({ count : U64 }),
	LinkStyle({ count : U64 }),
	ScopedColors({ count : U64 }),
	ScopedText({ count : U64 }),
	AtomicNegatives({ context : U64 }),
	CodeHolds({ count : U64 }),
]

CaseSpec : { case : Case, schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	case_json = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => crash "CASE_SPEC_MISSING: rich_inline requires exactly one JSON case argument"
	}
	if args.len() != 2 {
		crash "CASE_SPEC_ARITY: rich_inline requires exactly one JSON case argument"
	}
	parsed : Try(CaseSpec, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(case_json)
	spec = match parsed {
		Ok(value) => value
		Err(InvalidJson(detail)) => crash "CASE_SPEC_INVALID_JSON: ${detail}"
		Err(MissingRequiredField(field)) => crash "CASE_SPEC_MISSING_FIELD: ${field}"
	}
	if spec.schema_version != 1 {
		crash "CASE_SPEC_UNSUPPORTED_VERSION: rich_inline supports schema_version 1"
	}
	if Json.to_str(spec) != case_json {
		crash "CASE_SPEC_NON_CANONICAL: rich_inline rejects unknown fields and non-canonical JSON"
	}
	Metrics.reset_allocations!()
	result = match spec.case {
		Mixed({ context }) => Fixture.mixed(context)
		Paragraphs({ count }) => Fixture.paragraphs(count)
		Ordered({ context }) => Fixture.ordered(context)
		CodeFace({ context }) => Fixture.code_face(context)
		SharedSource({ count }) => Fixture.shared_source(count)
		HeadingFaces({ count }) => Fixture.heading_faces(count)
		ScaledCode({ count }) => Fixture.scaled_code(count)
		LinkStyle({ count }) => Fixture.link_style(count)
		ScopedColors({ count }) => Fixture.scoped_colors(count)
		ScopedText({ count }) => Fixture.scoped_text(count)
		AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
		CodeHolds({ count }) => Fixture.code_holds(count)
	}
	match result {
		Ok(value) => value
		Err(_) => crash "CASE_EXECUTION_FAILED: rich_inline fixture rejected the typed case"
	}
}
