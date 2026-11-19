app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.7.0/HBigHQhVZWEF2EkLxpYK35u8P6UNsAmPYxpNFTxXK1Br.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import FontInspectorMutation
import FontInspectorRepair
import FontSubsetRoundtrip

target = Fuzz.suite([
	FontInspectorMutation.target,
	FontInspectorRepair.target,
	FontSubsetRoundtrip.target,
])
