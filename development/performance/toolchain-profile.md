# Compiler and allocation baseline evidence

The dev allocation checks use the compiler in [`.roc-version`](../../.roc-version)
and Zig 0.16.0 ReleaseFast hosts. Fixtures build with
`--opt=dev --specialize=yes --no-cache`. The specialization setting is part
of the required schema-8 toolchain identity. The [LLVM fuzz profile](fuzz-suites.md)
documents its separate build and measurement settings.

## November 18 compiler and Unicode transition

The following measurements used Roc `nightly-2026-11-18-a520eed` and Unicode
4.3.3. The compiler was the official prebuilt release.

The prior accepted profile and its controls remain available at the
[previous profile](https://github.com/lukewilliamboswell/roc-pdf/blob/6a91b96/development/performance/toolchain-profile.md).
A complete local replay of its 425 cases under the previous official compiler
matched every recorded observation before this transition. The current profile
combines the compiler/Unicode upgrade with builtin SHA-256 and compile-time
packaged-font inspections. Those implementation changes are accounted for
separately below.

## Lowering policy

The new compiler defaults dev builds to boxy lowering; the prior compiler
used lambda-set specialization. An initial comparison with that new default
changed 413 rows and made the tables atomic-negative workload request about
8.59 GB. Those observations were rejected. Restoring explicit specialization
makes identical current source agree with the prior compiler on the Unicode
analysis and tables controls: 109 allocation events for Unicode analysis
x1000, and 54,403 events / 57,469,569 requested bytes for tables atomic negatives.
Restoring only the former SHA implementation or removing only the cmap cache
does not resolve the boxy result. The accepted policy keeps the dev backend,
measurement boundaries and exact-count guards and explicitly preserves its
previous lowering choice.

## Reviewed implementation costs

Builtin SHA-256 reads borrowed input ranges. It never assembles a concatenated
payload for hashing. Appending a digest now owns a temporary 32-byte list:
one additional event and 40 requested bytes, while the destination accumulator
continues to grow geometrically. Ninety-three changed dev rows reconcile
exactly to this per-digest cost. The incremental prefix/range path serializes
a fixed 106-byte hasher state; its two writes add two events / 228 requested
bytes per resource compared with the former Roc SHA implementation. These
fixed costs depend on digest count, not payload size or accumulated output.
The [pinned compiler implementation](https://github.com/roc-lang/roc/blob/a520eeda6c3745f2543fcdd0fb836d3d1336c5ac/src/builtins/crypto.zig)
defines the serialized state and borrows each input slice.

Resource graph controls separate that streaming cost from a compiler saving.
With all other current source unchanged, the prior compiler requests one
additional 101-byte allocation per resource. This matches the fixed identity
prefix storage size. Under the new compiler, restoring only the former SHA
implementation removes two events / 228 bytes per resource. Against the
previous accepted profile, the combined change is therefore one event /
127 bytes per resource. The forced-collision x100/x1000 pair increases by
100/1,000 events and 12,700/127,000 bytes; chain and fan pairs each plan twice
and double those deltas. The largest byte increase is the x1000 forced
collision case, 5.0102%; its equality, ordering and traversal work is unchanged.
The same-source prior/new compiler comparison covers all 30 kernel cases;
only the 11 resource graph cases change, by the fixed prefix cost.

Compile-time inspection reuses validated facts for the packaged fonts. Caller
registrations and caller-supplied limits continue to inspect their bytes.
Facade and atomic-negative reductions come from avoiding repeated packaged
font work; positive output still uses the same fonts, subsetting and emission.
Validated cmap subsetting now traverses ordered mappings once rather than
restarting a glyph lookup for each covered scalar. Its fold carries one
uniquely owned output builder and preserves coverage validation and retained
glyph filters.
A complete same-source ablation restores only `KernelSha256.roc` from
`6a91b96`, replacing the public or advanced package root through
`--replace-dep`. All 425 cases retain their PDFs and deterministic work.
SHA changes 335 cases; the remaining implementation/compiler changes affect
256 cases, all with lower requested bytes than the prior accepted profile.
The sets overlap in 242 cases: their union is exactly the 349 changed native
rows. The 93 SHA-only rows reconcile to the temporary digest cost; the other
14 non-overlapping rows are reductions. There is no unexplained positive
allocated-byte residual outside the SHA change.

The [LLVM suite review](fuzz-suites.md) records independent suite/isolated,
previous-SHA and previous-compiler controls.

## Native dev evidence

| Native compiler | Executable SHA-256 |
| --- | --- |
| x64musl | `2b91e50739ca09611e4855744d4503fcf400a6ee9d8ec31ea6f7a215fef4330e` |
| arm64mac | `abcbb73607a91a2a272b14ca523cf7d4200471d35356eb9e304389fefab35d9c` |

The clean macOS producer at
[`f98ea23`](https://github.com/lukewilliamboswell/roc-pdf/commit/f98ea231e023aeca1025d85a3001cab584b2fcf8)
in [run 44431349279](https://github.com/lukewilliamboswell/roc-pdf/actions/runs/44431349279),
artifact 14487363262, completed all 425 cases and retains the clean source
receipt, actual build argv, per-case observations and comparison report.
The independently measured Linux producer at
[`f4334f3`](https://github.com/lukewilliamboswell/roc-pdf/commit/f4334f37eeeeac5fefcf3f58f05a912cf0453473)
in [run 44433838951](https://github.com/lukewilliamboswell/roc-pdf/actions/runs/44433838951),
artifact 14488048477, also completes all 425 cases. Its full comparison report
agrees exactly with macOS. Each host changes 349 allocator rows:
205 byte increases and 144 reductions.
A complete local replay under the new compiler also passes all 425 exact
baselines on the same host as the old-profile replay. The real-allocation
injection control changes Unicode analysis x1000 from 109 to exactly 110
events. The dev profiling aid passes all ten named-region workloads.
Every PDF, dimension, scenario identity, deterministic work record, structural
validator and retention contract remains unchanged. The maximum byte increase
stays below the existing 10% limit; exact allocation counts remain mandatory.
Linux uses a generated musl self-relocating startup object because this
compiler links static PIE executables. The startup is built from the pinned
Zig distribution and shared by ordinary and retention test hosts; it does not
change the Roc measurement boundary.

| Subsystem group | Changed rows | Largest byte change |
| --- | ---: | ---: |
| core | 73 | +2.494% |
| default fonts | 7 | -6.744% |
| documents | 42 | +0.967% |
| interactive | 18 | +1.769% |
| kernel | 18 | +5.010% |
| layout | 41 | +0.299% |
| pages | 32 | +0.397% |
| public | 14 | +0.242% |
| public fonts | 11 | +0.252% |
| public output | 14 | -7.352% |
| structure | 26 | +0.860% |
| text | 53 | +0.862% |

Scale-pair counters and retained-input controls continue to guard copying,
sharing, worst-case traversal and source-buffer retention. This profile sets
no product timing or memory targets and does not relax conformance checks.
