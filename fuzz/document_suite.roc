app [target] {
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
