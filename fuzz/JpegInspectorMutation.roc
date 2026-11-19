import fuzz.Fuzz
import "../tests/assets/jpeg-fuzz-corpus/rgb-exif-orientation-6.jpg" as valid_bytes : List(U8)
import JpegTargets

test : List(U8) -> Fuzz.Outcome
test = |bytes| {
	if (JpegTargets.jpeg_mutation(bytes)) Fuzz.keep else crash "accepted JPEG violated its sanitized-stream facts"
}

JpegInspectorMutation :: [].{
	target = Fuzz.target_with({
		name: "roc-pdf-jpeg-inspector-mutation",
		examples: [
			Fuzz.saved({ name: "valid-source", revision: "1", bytes: valid_bytes }),
			Fuzz.example({ name: "empty-source", revision: "1", make: || [] }),
		],
		generator: Fuzz.raw_bytes,
		test,
		show: |bytes| Str.inspect({ byte_count: bytes.len(), bytes }),
	})
}
