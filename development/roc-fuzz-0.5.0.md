# Supervised fuzzing migration

## Immutable inputs and scope

The platform/API upgrade uses the official
[roc-fuzz release](https://github.com/lukewilliamboswell/roc-fuzz/releases/tag/0.5.0)
at source `d8228759b21fef688ecda2fac5d584a12f314e35`.

| Input | Identity |
| --- | --- |
| Platform bundle | `9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst` |
| Bundle bytes | 2,242,328 |
| SHA-256 | `aed4032105af1cc910604949f43636b7bff6aec4a82184631213153b8e2dd23f` |
| Consumer compiler | `nightly-2026-10-28-bad769b` |
| Compiler used to publish the platform | `nightly-2026-10-27-de79a0f` |

Downloaded bytes independently match the official release asset digest. All ten
application headers name this exact content-addressed bundle. The production
package, its compiler pin and all 425 product metric/snapshot contracts remain
unchanged. The [previous compatibility record](roc-fuzz-0.4.5.md) is retained.

## Input and ownership contracts

All nine property targets declare positive or expected-error examples. Nominal
inputs derive the platform's existing encoder/parser protocols. Decoded values
pass explicit property preconditions for every bounded list, selector and
aggregate text size; generator bias alone no longer defines those limits.

The old entropy generators and five-font mapping are unchanged. The complete
upstream `Arbitrary.roc` file is byte-identical between the intermediate and
current platform releases. Its string generator uses `Str.from_utf8` and consumes
a valid prefix, not lossy replacement: every generated string's UTF-8 bytes
consume distinct original entropy bytes. Capacity variation does not add text.
The aggregate 4,096-byte text domain therefore preserves every previous input
within the existing 4,096-byte structured-target entropy cap. Boundary expects
include exactly 4,096 bytes, 4,097 bytes, excess blocks and combined text overflow.

The decoder now reserves the byte prefix `RFZ` for versioned input forms;
unsupported versions/forms reject before the property, so this is not a claim
that every arbitrary future byte string retains the old interpretation. All 75
pre-upgrade structured corpus inputs checked here lack that reserved prefix,
and the retained old executable and migrated executable produced byte-identical
`show` output for every one. Input/representative hashes are retained in the
migration evidence. Future reserved-prefix witnesses require an explicit format
decision, not an automatic relabelling or silent corpus conversion.

A raw valid font cannot use a typed `List(U8)` example: the binary codec permits
4,096 value nodes, so a 166,300-byte font encoded as individual bytes is rejected
before the property. The initial supervised probe reproduced that rejection.
`Fuzz.saved` now preserves the original raw font and JPEG witnesses, retaining
their actual inspector interpretation without weakening decoder limits.

Saved original inputs preserve storage-sensitive findings; typed examples encode
logical values rather than allocation capacity, sharing or slices. Inspection
and subset properties retain source/subset `StyleFacts` equality and the
changed-angle negative oracle. The optional full packaged-font selector campaign
remains a separate coverage expansion: existing raw inspection stays bounded at
512 KiB and the friendly command's 1 MiB limit does not admit every Merriweather
file. No old font selector or retained input is silently remapped.

## Supervised verification and explicit acceptance

The harness invokes `run --report-dir=...` with declared source/compiler/platform
identity, original per-input timeout, RSS and whole-target bounds, and a fresh
report directory. It checks actual report provenance, effective native options,
metric version, host/profile, baseline path, nonempty example inventory, complete
valid observations and useful exploration. A provider's successful unbaselined
exit is insufficient: project verification requires an exact matched baseline.
Negative policy checks reject wrong identities/budgets, absent baselines, empty
inventory, incomplete metrics/traces and zero accepted exploration.

The separate `--accept-baselines` operation is maintainer-only and never called
by CI verification. Recorded builds bind the complete local source/asset closure,
compiler, target, platform and binary digests; `--no-build` refuses stale input.
Both the smoke and scheduled workflows retain complete reports on success and
failure, including build diagnostics when no supervisor could start.

Initial named-example baselines are separate from product dev-backend evidence.
Native and Linux observations are reviewed and accepted independently under the
`llvm-fuzz` profile. Exact per-host observation files live in `fuzz/baselines/`;
verification does not accept increases or reductions implicitly.

## Named profiling measurements

The profiling adapter uses named `Fuzz.measure!` regions, captures scalar counts
before consuming returned stage values, and replays each workload in a fresh
supervisor process. The consumer reads allocation observations from typed JSON;
its old debug protocol supplies output metadata only.

The initial port incorrectly interpreted `Stats.allocs` as the old combined
allocation count. The report workload appeared to fall to 1,028 allocations;
its 421 separately reported reallocations restore the established 1,449 events.
Both the source metadata and Python consumer now use `allocs + reallocs`.
All ten corrected selector results exactly match the retained old profile,
including PDF bytes/fingerprints. This is instrumentation migration, not a
performance improvement or product rebaseline.

Empty input successfully runs every workload: 23 complete observations comprise
the automatic property, 16 document phases and six kernels. Selector 255 is
explicitly rejected. The profiling application deliberately declares `examples:
[]` and is a replay/measurement aid, not a fuzz campaign or a baseline gate.
Profile comparisons require matching host, compiler, backend, platform and count
definition; old instrumentation snapshots are retained separately. Reuse also
checks the complete profiler source/helper/asset closure, actual compiler,
backend/host/platform and executable digest. Saved profiles record that verified
build provenance separately, so deliberate freshly rebuilt code comparisons
remain possible. Independent review caught the previous stale `--no-build`
filename reuse; actual CLI probes now reject a stale source stamp, wrong compiler
and modified executable before measurement. Restoring the trusted artifact then
replays all ten selectors successfully. Platform-header binding also rejects a
wrong dependency or a comment decoy rather than assigning the expected digest
to an unrelated freshly built platform.

## Completion evidence

All nine targets built with zero errors and warnings and executed successfully
on native Apple Silicon macOS and Linux x64musl. Each host independently checked
all 18 examples before explicit initial acceptance. Both complete host entries
now match in every input digest, region identity and allocation statistic; Linux
acceptance preserved the native entries unchanged. These new exact LLVM example
baselines are initial instrumentation evidence, not replacement product baselines.

Both hosts then passed all nine real supervised smoke campaigns with exact
matched baselines, complete example observations and nonzero accepted exploration.
The final native verification also proved that every accepted baseline file's
bytes stayed unchanged. Increases, reductions, inventory changes and payload
changes still require separate explicit acceptance.

Linux execution used the verified Alpine amd64 manifest
`alpine@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce`,
whose local image-content ID is
`sha256:b66e0ce64844f5c6435b0c4bfd965558199ab0f53270846861c979cb1ac29365`.
The first invocation incorrectly used that image-content ID as a repository
manifest and Docker rejected it before any target ran. Reusing the already
verified executables with the correct manifest resolved that infrastructure
failure; no compiler, property, timeout, memory or baseline policy was weakened.

The [retained observation review](roc-fuzz-0.5.0-observations.json) binds exact
per-host baselines, build fingerprints, actual campaign counts and execution
controls, the 75 legacy corpus comparisons, and all ten native/Linux profiling
results. The profile results also match the prior platform's saved observations,
including source output lengths/fingerprints. Initial subset examples containing
glyph zero were corrected after review showed they reached only allowed planning
rejection; the committed successful regular and CJK examples actually traverse
planning, subsetting and reinspection (107 and 80 allocation events respectively).
The separate zero-budget example retains intentional planning rejection.

Integrated `./scripts/test.py --allocation-baselines` validation passed after the
Roc migration: 45 source-validation tasks, 13 fresh fixture builds and all 425
product cases, with no product allocation/byte/work or PDF baseline change.
Independent review confirmed the profiler identity fix and both-host baseline
schemas. The complete PR's commit-bound CI remains the publication/merge gate;
no release or deployment is performed by this upgrade.
