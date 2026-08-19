app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.2.1/9Qpttb6LTgcMaVsSBLsnaiS2mDUrf6Bxa6dX9Rqwviz4.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import FontTargets

test : List(U8) -> Fuzz.Outcome
test = |bytes| {
	if FontTargets.inspect_mutation(bytes) Fuzz.keep else crash "successful font inspection violated retained facts"
}

target = Fuzz.target_with({
	name: "roc-pdf-font-inspector-mutation",
	generator: Fuzz.raw_bytes,
	test,
	show: |bytes| Str.inspect({ byte_count: bytes.len(), bytes }),
})
