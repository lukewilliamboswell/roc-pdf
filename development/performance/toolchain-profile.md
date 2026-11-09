# Accepted compiler and allocation profile

The executable allocation expectations describe Roc `nightly-2026-11-07-ad3a5d2`
with Unicode 4.3.2 (bundle SHA-256
`57775c7ea3b46d571cf839c5e27a1833daf658b1d2b3615ca8cce03ced1c646e`).
The dev test host uses Zig 0.16.0, ReleaseFast; Roc fixtures use
`--opt=dev --no-cache`. The LLVM property profile uses the pinned roc-fuzz
0.5.0 platform and `--fuzz --no-cache`, with build policy and local source
closure bound into each executable stamp. Official prebuilt nightly compilers
are used; these measurements do not claim a source compiler build mode.

The prior controlled profile used Roc `nightly-2026-10-28-bad769b` with its
compatible Unicode 4.3.1 dependency. This is a combined compiler/dependency
profile transition, rather than compiler-only causal evidence. The full old
425-case dev suite matched its accepted profile on the same Linux host. Old
cold output-equivalence, structure, navigation and theme controls retained
their accepted observations; representative independent new cold builds and
three replays per control were deterministic. Cache-enabled regional
allocation observations differed from the cold profile, so the canonical LLVM
build disables the cache. No relationship to a particular compiler crash or
lowering policy is asserted.

The final native observations were collected from clean source `d028d683a7db329d271345050627b8b3c702970a` in
[run 42543554263](https://github.com/lukewilliamboswell/roc-pdf/actions/runs/42543554263). Each source receipt retains
empty tracked diffs/status after compiler relocation, the committed file digest
inventory, and the installed compiler's original/current path, version and
executable hash. Each LLVM build receipt records the actual argv and the
source/platform/compiler/binary stamp. Linux and macOS are measured separately.

| Host | Dev evidence artifact | LLVM evidence artifact | Compiler executable SHA-256 |
| --- | ---: | ---: | --- |
| x64musl | 13643745086 | 13643225828 | `abb6d45b11e8fd6e66711cbfd3b776ee87d5408ecfa8d12d6e2c69c333077740` |
| arm64mac | 13643371640 | 13643327634 | `2c97aab7745ba80d4870ae6b14a87b26f0e40eae96f675d02312ec26a9e82929` |

All 425 dev cases retain their PDFs, work counters, dimensions, scale pairs,
retention guards, validators and scenario identities. The 414 changed allocator
rows per host are predominantly reductions; six byte increases remain below
5.61%. Exact allocation counts and the existing 10% allocated-byte ceiling stay
mandatory after the refresh. Both independently measured native targets agree.

Fixture corrections preserve existing measurement contracts: the structural
blank and three Archive static results explicitly retain documented compile-time
scope; three negative cases exclude only their independent successful PDF
carriers. Every rejection/atomicity operation and runtime positive counterpart
remains measured. Grouped/isolated old/new controls preserve PDFs and work;
injecting a real allocation adds exactly one event. See
[fixture grouping](fixture-grouping.md) and
[implementation contracts](../implementation-contracts.md).

The LLVM navigation named example is the sole byte increase above 10%:
7,697,488 to 15,802,336 requested bytes, 1,477 to 3,434 allocation/reallocation
events, and 403,705 to 469,851 peak live bytes. Its original whole-property
boundary and all 35 fault arms remain unchanged. A same-Input diagnostic
preserving generation, bounds and repeatability measured 1,475 events and
7,715,024 bytes under the new profile; isolated original arm 0 contributes
1,959 events and 8,087,312 bytes. These sums match the full property exactly.
The old arm 0 contributed zero events/bytes. The new arm's 469,562-byte peak
plus 289 entry-live bytes also reconciles the whole-property peak. The unknown
arm 6 control remains 357 events/1,086,285 bytes on both profiles and reconciles
its full-property total exactly. Thus the outlier is the fixed valid-base
positive control, which still seals twice and checks nonempty exact byte
equality. No generated-document residual, leak, omitted rejection or changed
input identity is accepted. Other changed LLVM bytes remain below 0.24%.

[Issue 82](https://github.com/lukewilliamboswell/roc-pdf/issues/82) records the
independent source-boundary and profile review. These observations preserve the
architecture's compiler-transition protocol; they do not set a product timing
or memory target. Full native validation must pass after the exact profile is
installed, including exploration that comparison failures intentionally skip.
