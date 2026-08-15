app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.2.1/9Qpttb6LTgcMaVsSBLsnaiS2mDUrf6Bxa6dX9Rqwviz4.tar.zst",
	pdf_quality: "../package/fuzz_evidence.roc",
}

import fuzz.Fuzz
import pdf_quality.Gate2FuzzTargets

test : List(U8) -> Fuzz.Outcome
test = |bytes| {
	if Gate2FuzzTargets.jpeg_mutation(bytes) Fuzz.keep else crash "accepted JPEG violated its sanitized-stream facts"
}

target = Fuzz.target_with({
	name: "roc-pdf-jpeg-inspector-mutation",
	generator: Fuzz.raw_bytes,
	test,
	show: |bytes| Str.inspect({ byte_count: bytes.len(), bytes }),
})
