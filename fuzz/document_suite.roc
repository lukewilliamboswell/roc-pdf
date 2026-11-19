app [target] {
	deflate: "https://github.com/lukewilliamboswell/roc-deflate/releases/download/0.4.0-rc4/FoGWbhCP9K1Qk7HA9wcSxHYTpiwTHmCpfNUZx7rAGSSk.tar.zst",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.7.0/HBigHQhVZWEF2EkLxpYK35u8P6UNsAmPYxpNFTxXK1Br.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import JpegInspectorMutation
import FacadeOutputEquivalence
import FacadeStructure
import NavigationProperty
import RegistryProperty
import ThemeOptions

target = Fuzz.suite([
	JpegInspectorMutation.target,
	FacadeOutputEquivalence.target,
	FacadeStructure.target,
	NavigationProperty.target,
	RegistryProperty.target,
	ThemeOptions.target,
])
