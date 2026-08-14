app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.2.1/9Qpttb6LTgcMaVsSBLsnaiS2mDUrf6Bxa6dX9Rqwviz4.tar.zst",
	pdf_quality: "../package/fuzz_evidence.roc",
}

import fuzz.Fuzz
import pdf_quality.Gate3FuzzTargets

test : List(U8) -> Fuzz.Outcome
test = |bytes| {
	if Gate3FuzzTargets.inspect_mutation(bytes) Fuzz.keep else crash "successful font inspection violated retained facts"
}

target = Fuzz.target_with({
	name: "roc-pdf-font-inspector-mutation",
	generator: Fuzz.raw_bytes,
	test,
	show: |bytes| Str.inspect({ byte_count: bytes.len(), bytes }),
})
