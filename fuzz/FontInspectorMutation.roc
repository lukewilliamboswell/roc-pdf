import fuzz.Fuzz
import "../package/RocPdfSans-Regular.ttf" as valid_bytes : List(U8)
import FontTargets

test : List(U8) -> Fuzz.Outcome
test = |bytes| {
	if (FontTargets.inspect_mutation(bytes)) Fuzz.keep else crash "successful font inspection violated retained facts"
}

FontInspectorMutation :: [].{
	target = Fuzz.target_with({
		name: "roc-pdf-font-inspector-mutation",
		examples: [
			Fuzz.saved({ name: "valid-source", revision: "1", bytes: valid_bytes }),
			Fuzz.example({ name: "empty-source", revision: "1", make: || [] }),
		],
		generator: Fuzz.raw_bytes,
		test,
		show: |bytes| Str.inspect({ byte_count: bytes.len(), bytes }),
	})
}
