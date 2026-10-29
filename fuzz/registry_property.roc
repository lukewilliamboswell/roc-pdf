app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst",
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
	parser_for : _
	encoder_for : _

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
	if input.clusters.len() > 6 or input.policies.len() > 3 or input.registrations.len() > 4 or input.clusters.any(|cluster| cluster.scalars.len() > 3) or input.policies.any(|policy| policy.len() > 4) or input.registrations.any(|registration| registration.scripts.len() > 3) {
		return Fuzz.reject
	}
	if (RegistryTargets.registry_boundary(input)) Fuzz.keep else crash "font registry boundary violated its public contract"
}

target = Fuzz.target({
	name: "roc-pdf-registry-property",
	examples: [
		Fuzz.example({ name: "ordered-latin-and-han", revision: "1", make: || Input.{ facade: 2, plan_policy: 2, probe: 1, clusters: [{ scalars: [0], script: 0 }, { scalars: [6], script: 1 }, { scalars: [9], script: 0 }], policies: [[0, 1]], registrations: [{ font: 1, limits: 0, provision: 1, scripts: [0] }, { font: 2, limits: 0, provision: 1, scripts: [1] }] } }),
		Fuzz.example({ name: "common-script-regression", revision: "1", make: || Input.{ facade: 99, plan_policy: 3, probe: 0, clusters: [{ scalars: [110], script: 43 }], policies: [], registrations: [{ font: 0, limits: 0, provision: 0, scripts: [0] }, { font: 0, limits: 0, provision: 0, scripts: [] }] } }),
	],

	test,
	show: |input| Str.inspect(input),
})
