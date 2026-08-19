app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.2.1/9Qpttb6LTgcMaVsSBLsnaiS2mDUrf6Bxa6dX9Rqwviz4.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import RegistryTargets

## Every field is a small choice index into a ladder the property owns, so the
## fuzzer spends its budget on combinations of registrations, policies, and
## clusters rather than on rediscovering that arbitrary bytes are not a font.
##
## The list bounds are chosen against cost, not against the contract: each
## registration inspects a real font fixture, so four of them plus two policies
## already reaches the N > 2 shape that the repository's hand-written registry
## tests stop short of, while leaving the campaign fast enough to explore.
## The generator decodes these fields in declaration order out of an input whose
## length libFuzzer raises only slowly, so a field behind a list-carrying one is
## starved of entropy. The three scalar selectors are therefore declared first:
## with `clusters` leading, retained corpus entries decoded with `facade`,
## `plan_policy`, and `probe` holding one repeated exhausted byte, so a single
## campaign explored only one facade wiring and one probe.
Input := {
	facade : U8,
	plan_policy : U8,
	probe : U8,
	clusters : List({ scalars : List(U8), script : U8 }),
	policies : List(List(U8)),
	registrations : List({ font : U8, limits : U8, provision : U8, scripts : List(U8) }),
}.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| {
		{
			facade: Fuzz.u8,
			plan_policy: Fuzz.u8,
			probe: Fuzz.u8,
			clusters: Fuzz.list({ scalars: Fuzz.list(Fuzz.u8, 3), script: Fuzz.u8 }.Fuzz, 6),
			policies: Fuzz.list(Fuzz.list(Fuzz.u8, 4), 3),
			registrations: Fuzz.list(
				{
					font: Fuzz.u8,
					limits: Fuzz.u8,
					provision: Fuzz.u8,
					scripts: Fuzz.list(Fuzz.u8, 3),
				}.Fuzz,
				4,
			),
		}.Fuzz
	}
}

test : Input -> Fuzz.Outcome
test = |Input.(input)| {
	if RegistryTargets.registry_boundary(input) Fuzz.keep else crash "font registry boundary violated its public contract"
}

target = Fuzz.target({
	name: "roc-pdf-registry-property",
	test,
	show: |input| Str.inspect(input),
})
