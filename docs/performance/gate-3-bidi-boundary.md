# Gate 3 bounded bidirectional prerequisite

## Scope and evidence boundary

This slice adds the private `KernelBidiBoundary` handoff. It is intentionally
not a complete UAX #9 implementation and is not connected to shaping,
`KernelPdfText`, or PDF lowering. It establishes the representation boundary
that later work must consume rather than infer from glyph order or paint
positions:

- `Paragraph` owns a source-relative scalar-class buffer, the UAX #9 P2/P3
  paragraph base level, and its logical scalar/UTF-8 ranges.
- `LineOrder` preserves those logical ranges and returns a separate dense
  visual cluster-ID list.
- The only accepted line shape is a single resolved level: every scalar must
  be strong `L` at even level, or strong `R`/`AL` at odd level. Its visual
  sequence is respectively identity or UAX #9 L2 reversal. Neutrals, numbers,
  embeddings, overrides, isolates, bracket pairs, and mirrored characters are
  rejected with `UnsupportedSingleLevelClass`; no fallback order is emitted.

The positive inputs `abc` and `אבג` are direct UAX #9 revision 51 P2/P3 and
single-level L2 derivations. The evidence checks an even base/`[0,1,2]` visual
order and an odd base/`[2,1,0]` visual order. They are internal facts only:
they do **not** claim right-to-left PDF output, shaping, font coverage,
mirroring, extraction, or renderer behavior.

Two atomic negatives prove that malformed facts never pass the boundary: a
mutated paragraph base is rejected by `validate_paragraph`, and a line whose
UTF-8 range does not match its clusters is rejected by the line resolver. The
fixture emits a blank Gate 1 PDF only to use the common scenario protocol; the
typed assertions are the structural inspection for this internal stage.

## Representation, limits, and work

The analysis takes the immutable source and existing `KernelUnicode` analysis,
then writes one compact `ScalarClass` tag per scalar. The line resolver reads
that buffer directly over the selected line range and writes one dense cluster
ID per cluster. It retains no substrings, glyphs, cluster payload copies, or
paint coordinates. The source is not retained by the new fact; the owning
earlier source store remains the sole text owner.

`max_scalars`, `max_clusters`, and `max_visual_order` are checked before every
derived buffer grows. Paragraph analysis is `O(S)` time and `O(S)` scalar tags;
single-level line resolution is `O(Ls + Lc)` time and `O(Lc)` output storage.
The diagnostic path stops at the first invalid scalar or cluster and returns no
partial fact. `validate_paragraph` deliberately performs a second source walk
only for boundary validation and malformed-fact tests; the ordinary staged
analysis-to-line path does not.

The focused scenario resets the allocator before fixture construction. It
builds two three-scalar paragraphs, resolves two three-cluster lines, verifies
the two atomic negative paths, and serializes the unchanged blank protocol
PDF. Python and structural-checker allocations are excluded.

| Target | Backend | Paragraph scalars | Line scalars | Clusters / visual IDs | Exact allocations | Work |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| x64musl | dev | 6 | 6 | 6 / 6 | 70 | `[6, 6, 6, 6, 6, 2, 667]` |

The local x64musl allocation baseline is reviewed as two exact-capacity class
buffers plus two exact-capacity visual-order buffers and the fixture's existing
blank-PDF protocol allocation shape. It is not an optimized/speed-mode result,
and no cross-platform allocation claim is made by this slice.

## Remaining dependency

The pinned Unicode 17 package supplies `BidiClass` and scalar mirror/bracket
properties but no UAX #9 paragraph resolver. Full revision-51 work remains:
explicit embeddings/overrides/isolate handling, weak and neutral resolution,
bracket-pair rules, resolved levels, line-level L1/L2 across mixed runs,
mirror decisions, conformance-vector corpus coverage, typed shaping handoff,
font-coverage validation, and visual PDF lowering with logical `/ActualText`.
Until those facts exist, all non-single-level inputs remain rejected and Gate 3
remains open.

## Superseded (2026-08-14)

The single-level boundary recorded here has been replaced by a real UAX #9
revision-51 resolver over the pinned dependency's `Bidi` module. This record
remains as the historical account of the prerequisite; the resolver, its
normative conformance vectors, and the right-to-left output slice are
recorded in [`gate-3-rtl-text.md`](gate-3-rtl-text.md).
