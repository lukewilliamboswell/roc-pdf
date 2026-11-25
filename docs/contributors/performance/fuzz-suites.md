# Fuzz suite ownership and allocation profile

Nine properties share two LLVM executables. Font inspection, repair and subset
round trips share `font_suite`; JPEG inspection, facade output and structure,
navigation, registry and theme checks share `document_suite`. Each executable
builds once per invocation. Selecting several properties from one suite still
builds only that suite.

The supervisor selects each member by its declared name, after the harness
checks the executable's complete inventory. Examples, corpus directories,
input bounds, baselines, deadlines and reports remain per property. Dispatch
and input preparation stay outside the measured `$property` region. Neither
combining members nor selecting a subset changes a property's input encoding
or measurement boundary.

Builds use `--fuzz --specialize=yes --no-cache`, the compiler in
[`.roc-version`](../../../.roc-version), and the platform pinned by
[`scripts/fuzz.py`](../../../scripts/fuzz.py). The executable stamp binds the
complete local source/asset closure, compiler, target, platform SHA-256, flags
and executable digest. `--no-build` rejects a changed identity. The suite's
source closure includes every member, even when only one member is selected.

## Reviewed allocation observations

This baseline review used Roc `nightly-2026-11-18-a520eed` and roc-fuzz 0.7.0, archive
SHA-256 `94130c93aa2abb204beb21f06338ecc39c5808e1358d905f219769ecf260e5f2`.
Clean native Linux and macOS producers at
[`f98ea23`](https://github.com/lukewilliamboswell/roc-pdf/commit/f98ea231e023aeca1025d85a3001cab584b2fcf8)
in [run 44431349279](https://github.com/lukewilliamboswell/roc-pdf/actions/runs/44431349279)
retain source receipts, build argv/stamps and supervised reports. Artifacts
14486807429 (Linux) and 14485874119 (macOS) contain the measurements. Independent
local macOS builds agree exactly with both producers for all 18 examples.

Every example retains its name, revision, original input digest, complete
allocation capture, passing property/trace checks and zero exit-live
allocations. Five properties retain all accepted observations. Four properties
have the six changed examples below. Events count allocations plus
reallocations; bytes count all requested allocation sizes.

| Property / example | Prior events | New events | Prior bytes | New bytes |
| --- | ---: | ---: | ---: | ---: |
| JPEG / valid source | 23 | 23 | 7,288 | 7,240 |
| Output equivalence / paragraph and bullets | 3,448 | 3,807 | 15,042,175 | 12,526,831 |
| Output equivalence / atomic rejection | 415 | 271 | 1,540,170 | 44,418 |
| Structure / heading and body | 955 | 1,008 | 3,957,006 | 2,959,032 |
| Navigation / named destination and link | 3,434 | 3,746 | 15,802,336 | 11,808,168 |
| Navigation / unknown destination | 1,731 | 1,741 | 8,657,555 | 5,666,407 |

Isolated JPEG and output-equivalence executables match their suite members
exactly. Restoring only the prior SHA implementation leaves the JPEG and atomic
rejection measurements unchanged. For paragraph-and-bullets it removes exactly
640 events and 25,600 requested bytes: the builtin digest path owns temporary
digest lists where the previous digest append wrote directly into its caller's
accumulator. This is a bounded cost per digest, with geometric destination
buffer growth preserved; it does not copy the accumulated identity payload.

The remaining facade reductions follow reuse of compile-time validated
packaged-font facts. Registration under caller-supplied limits continues to
inspect caller bytes. Rejected text avoids repeated packaged-font inspection;
positive documents keep the same fonts, validation facts, subsetting and
emission. The JPEG control built from identical source and platform under the
previous compiler retains its old 7,288-byte observation, isolating its 48-byte
reduction to the compiler change. All six changed examples reduce requested
bytes and peak-live bytes. These observations preserve the dev-backend PDF,
work and retention contracts, which are reviewed separately in the
[compiler profile](toolchain-profile.md).
