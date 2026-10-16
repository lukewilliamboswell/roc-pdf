app [main!] {
	pdf: "../../package/all.roc",
	pf: platform "../platform/main.roc",
}

import Fixture
import pf.Metrics

Case : [HanOnly({ same_body : Bool }), Multiple({ context : U64 }), OnlyText({ context : U64 }), BareBlank({ context : U64 }), Han({ context : U64 }), Defaults({ context : U64 }), Blank({ lines : U64 }), Short({ context : U64 }), Long({ lines : U64 }), NearBottom({ lines : U64 }), Wrapping({ context : U64 }), Unicode({ context : U64 }), Negatives({ context : U64 })]

CaseSpec : { case : Case, schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	json = match args.get(1) {
		Ok(value) => value
		Err(_) => crash "CASE_SPEC_MISSING: source_blocks"
	}
	parsed : Try(CaseSpec, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(json)
	spec = match parsed {
		Ok(value) => value
		Err(_) => crash "CASE_SPEC_INVALID_JSON: source_blocks"
	}
	if args.len() != 2 or spec.schema_version != 1 or Json.to_str(spec) != json {
		crash "CASE_SPEC_INVALID: source_blocks"
	}
	Metrics.reset_allocations!()
	result = match spec.case {
		HanOnly({ same_body }) => Fixture.han_only(same_body)
		Multiple({ context }) => Fixture.multiple(context)
		OnlyText({ context }) => Fixture.only_text(context)
		BareBlank({ context }) => Fixture.bare_blank(context)
		Han({ context }) => Fixture.han(context)
		Defaults({ context }) => Fixture.defaults(context)
		Blank({ lines }) => Fixture.blank(lines)
		Short({ context }) => Fixture.short(context)
		Long({ lines }) => Fixture.long(lines)
		NearBottom({ lines }) => Fixture.near_bottom(lines)
		Wrapping({ context }) => Fixture.wrapping(context)
		Unicode({ context }) => Fixture.unicode(context)
		Negatives({ context }) => Fixture.negatives(context)
	}
	match result {
		Ok(value) => value
		Err(error) => crash "SOURCE_BLOCK_EVIDENCE: ${Str.inspect(error)}"
	}
}
