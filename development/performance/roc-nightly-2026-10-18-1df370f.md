# Roc October 18 compiler and allocation sweep

The upgrade selects the published `nightly-2026-10-18-1df370f`, unicode
4.3.0 and roc-deflate 0.4.0-rc4. A series of allocation sweeps follows it.
Every PDF snapshot is byte-identical and every work vector is unchanged.

| Metric (x64musl, all 399 changed cases) | October 14 | After sweep | Change |
| --- | ---: | ---: | ---: |
| Roc allocation events | 17,096,086 | 2,494,350 | -85.4% |
| Requested allocated bytes | 13,438,767,464 | 8,962,507,379 | -33.3% |
| Changed work vectors | 0 | 0 | 0 |

Ten cases are unchanged. No case allocates more often. The
[per-case comparison](roc-nightly-2026-10-18-allocations.csv) lists every
changed case.

## Measurement and comparison controls

The baselines were measured with `./scripts/test.py --compare-baselines` from
an empty `XDG_CACHE_HOME`, using the dev backend and Zig 0.16.0 on Linux x86_64
(x64musl). The arm64mac expectations were not measured independently on a Mac.
They copy the x64musl values, because the October 14 review found the two
targets identical in every case. Re-measure them on a Mac when one is
available.

## Toolchain changes

- The new compiler reports code after a diverging `while True` as unreachable.
  Two trailing expressions in `KernelEmit` were removed.
- The new `roc fmt` parenthesizes inline `if` conditions.
- unicode 4.3.0 and roc-deflate 0.4.0-rc3 are released against this nightly.
  The harness now tolerates any warning located in a downloaded package; until
  those releases, such packages still reported `unreachable code` there.
- roc-deflate 0.4.0-rc4 reuses its Huffman, cost and writer tables across
  blocks: a level-10 stream allocates 30 times instead of 114, with output
  byte-identical to rc2 and rc3 at every level. Its match cache now starts at
  four entries per input byte. That accounts for the three cases that request
  more bytes:
  - structural-kernel stateful dynamic DEFLATE: +13.3%
  - structural-kernel one-block dynamic DEFLATE: +7.5%
  - production-visual shared-constant opacity x1000: +0.5%

## Method

`fuzz/allocation_profile.roc` measures each stage of representative documents
and single kernels with roc-fuzz's `Fuzz.measure_allocs!`. It also
fingerprints each PDF so that any byte change shows up, and
`scripts/profile.py` diffs one run against the previous one.
`scripts/alloc_trace.py` attributes every `roc_alloc` and `roc_realloc` to its
Roc caller under gdb, using a `--debug` speed build. On the profiled report
document, a run takes 1,521 allocations instead of 8,577, and a ten-copy
report takes 3,272 instead of 44,333.

## Allocation causes removed

- **Literal and string copies.** `Str.to_utf8` allocates on every call for
  short strings. Content operators, `append_ascii`, resource names, standard
  structure names (`KernelLex.name_bytes`) and element identifiers
  (`KernelLex.compare_utf8`) now read bytes in place or use static constants.
- **Per-item lists.** Removed allocations:
  - composite glyph edges, once per composite glyph of a registered font
  - a copy of every text cluster's scalars
  - SHA-256 schedules, now a rolling 16-word window
  - identity digest results, now appended in place
  - xref rows
  - attribute owner lists
  - one-kid `/K` arrays (`KernelObject.add_array_one`)
  - duplicated structure-element base entries
- **Growth from empty.**
  - Unicode analysis lists, scalar offsets and text run bodies are sized from
    their known bounds.
  - Scene and text-ownership validation reuse one cleared work list across
    groups.
- **Object-stream members.** `emit_value` is infallible:
  `KernelOutputBound` rejects a nested stream value before any
  `KernelStructure.Plan` exists. Members are therefore written straight onto
  the object-stream batch.

  Writing them onto the batch through `emit_value`'s former `Try` was measured
  first, and the batch was copied once per object (emission +20%). The rule in
  [emission linearity](emission-linearity.md) still holds on this compiler.

## Compiler workarounds re-tested on nightly-2026-10-18

- **Removed.** The theme defaults (roc-lang/roc#11922), the chunk retention
  options (#11946) and the bundle's named byte imports (#11907) no longer
  need their workarounds and are written directly.
- **Kept: `--no-cache` for fixture builds (#11826).** The issue is closed,
  but a shared build cache still changes results. Built into a cold cache,
  26 cases differ from `--no-cache`: `static PDF/A-4 archived report scaling
  x400` allocates 13,877 times instead of 13,473. A warm cache matches every
  allocation count, but six cases request 32 bytes fewer. `scripts/test.py`
  keeps `--no-cache`.
- **roc-deflate.** The fork's workarounds for #11933 and #11934 were removed
  in lukewilliamboswell/roc-deflate#4, with no allocation change and
  byte-identical output. roc-pdf stays on 0.4.0-rc4.
- **`List.map` reuse.** The compiler disables in-place `List.map` reuse at
  `--opt=dev` by design, so the dev baselines charge one allocation per map.
- **Unused-branch warning.** The new warning duplicates roc-lang/roc#12395,
  which roc-pdf does not hit.
- **Accumulator beside another list.** Returning `emit_commands`' frame stack
  beside its stream bytes, so that one cleared stack serves every stream,
  still copies the stack: `rich flow shared callouts x100` allocated 5,350
  times instead of 4,592. The change was not kept. See
  [emission linearity](emission-linearity.md).
