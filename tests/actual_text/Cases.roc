import Fixture

## The actual_text family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
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

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
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
}
