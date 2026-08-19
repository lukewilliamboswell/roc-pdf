app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
	unicode: "https://github.com/roc-lang/unicode/releases/download/4.0.0/3DGC3M4b2pxaRLg4i8cmxWkm2E2WbCPCLntQzf2mkbUV.tar.zst",
}

import Fixture
import pf.Metrics

Case : [
	Reordered,
	SoftHyphen,
	SoftHyphenMalformedNegative,
	SoftHyphenUnselectedNegative,
	ExternalDiscretionaryHyphen,
	ExternalDiscretionaryHyphenMalformedNegative,
	ExternalDiscretionaryHyphenUnselectedNegative,
	Supplementary,
	SupplementaryNegative,
	Cjk,
	CjkNegative,
	MultiFace,
	MultiFaceNegative,
	Combining,
	CombiningNegative,
	Ligature,
	LigatureNegative,
	Rtl,
	RtlNegative,
	CaseTransform,
	CaseTransformNegative,
]

CaseSpec : { case : Case, schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	case_json = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => crash "CASE_SPEC_MISSING: actual_text requires exactly one JSON case argument"
	}
	if args.len() != 2 {
		crash "CASE_SPEC_ARITY: actual_text requires exactly one JSON case argument"
	}
	parsed : Try(CaseSpec, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(case_json)
	spec = match parsed {
		Ok(value) => value
		Err(InvalidJson(detail)) => crash "CASE_SPEC_INVALID_JSON: ${detail}"
		Err(MissingRequiredField(field)) => crash "CASE_SPEC_MISSING_FIELD: ${field}"
	}
	if spec.schema_version != 1 {
		crash "CASE_SPEC_UNSUPPORTED_VERSION: actual_text supports schema_version 1"
	}
	if Json.to_str(spec) != case_json {
		crash "CASE_SPEC_NON_CANONICAL: actual_text rejects unknown fields and non-canonical JSON"
	}
	Metrics.reset_allocations!()
	result = match spec.case {
		Reordered => Fixture.reordered_text(0)
		SoftHyphen => Fixture.soft_hyphen_text(0)
		SoftHyphenMalformedNegative => Fixture.soft_hyphen_negative("malformed", 0)
		SoftHyphenUnselectedNegative => Fixture.soft_hyphen_negative("unselected", 0)
		ExternalDiscretionaryHyphen => Fixture.external_discretionary_hyphen_text(0)
		ExternalDiscretionaryHyphenMalformedNegative => Fixture.soft_hyphen_negative("external-malformed", 0)
		ExternalDiscretionaryHyphenUnselectedNegative => Fixture.soft_hyphen_negative("external-unselected", 0)
		Supplementary => Fixture.supplementary_text(0)
		SupplementaryNegative => Fixture.supplementary_negative(0)
		Cjk => Fixture.cjk_text(0)
		CjkNegative => Fixture.cjk_negative(0)
		MultiFace => Fixture.multi_face_text(0)
		MultiFaceNegative => Fixture.multi_face_negative(0)
		Combining => Fixture.combining_text(0)
		CombiningNegative => Fixture.combining_negative(0)
		Ligature => Fixture.ligature_text(0)
		LigatureNegative => Fixture.ligature_negative(0)
		Rtl => Fixture.rtl_text(0)
		RtlNegative => Fixture.rtl_negative(0)
		CaseTransform => Fixture.case_text(0)
		CaseTransformNegative => Fixture.case_negative(0)
	}
	match result {
		Ok(value) => value
		Err(_) => crash "CASE_EXECUTION_FAILED: actual_text fixture rejected the typed case"
	}
}
