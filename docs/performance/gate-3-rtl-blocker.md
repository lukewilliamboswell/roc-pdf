# Gate 3 real RTL output dependency audit

## Chosen slice and evidence boundary

The next missing Gate 3 matrix row is one real right-to-left paragraph with a
mixed-direction span and a mirrored paired punctuation character. Its source
Unicode must remain logical; UAX #9 must determine its paragraph level and its
per-line visual order; shaping must consume the resulting directional runs; and
the PDF must paint that visual result while `/ActualText` preserves the exact
logical source. The eventual positive case needs a manifest-recorded
caller-supplied face that covers every selected scalar and its required mirrored
presentation, an exact snapshot and dev-backend allocation baseline,
deterministic work counters, direct CID/`ToUnicode`/`ActualText` inspection,
PDFBox extraction, separately pinned PDFBox and PDFium raster facts, and an
atomic invalid-bidi-fact or unavailable-mirror negative that emits no PDF.

This audit does **not** implement that output. A manually reversed glyph list,
a manually asserted `RightToLeft` run, or a reader-dependent text order would
not be UAX #9 evidence and is not an acceptable substitute.

## Existing facts and the bounded prerequisite now present

The pinned Unicode 17 package exports `BidiClass` plus the `BidiProperties`
mirror and paired-bracket data. Those are scalar properties only: its own
public documentation explicitly says it does not run paragraph analysis,
mirror text, or reorder text. `KernelUnicode.analyze` currently retains only
grapheme, UAX #14 line-boundary, and script-itemization buffers. It imports no
bidi module and returns no paragraph base level, resolved level, isolate,
bracket, or logical-to-visual fact.

`Text.Run.direction` is therefore an unproven caller field. The advanced
validator checks its dense source/glyph partitions but accepts a `Reordered`
cluster based only on nonzero cardinality. `KernelLineLayout.Line` preserves a
logical source/cluster interval only, and `KernelFacadeShape` deliberately
hard-codes the public convenience path to horizontal Latin left-to-right.
Finally, PDF text lowering iterates the dense `run.glyphs` range directly;
the `glyph_indices` buffer establishes cluster membership but is not a
per-line visual-paint sequence. `/ActualText` correctly protects logical
extraction for a supplied RTL run, but it cannot prove that the supplied glyph
order came from UAX #9.

Consequently the existing reordered `fa`/`af` ActualText fixture is valuable
context-dependent extraction evidence, not real right-to-left output. It
must not be relabelled as such.

`KernelBidiBoundary` now makes the first dependency explicit without claiming
that it resolves UAX #9 generally. It records P2/P3 paragraph base level and
a source-relative scalar-class buffer, then can produce a separate per-line
visual cluster-ID sequence only when every selected scalar is one strong level:
all `L` at even level or all `R`/`AL` at odd level. The logical source and
cluster ranges remain separate. Mixed direction, neutrals, numbers, isolates,
brackets, and mirrors fail the boundary; the fact is private and is not yet
consumed by shaping or PDF lowering. Its exact dev evidence and ownership
review are recorded in `gate-3-bidi-boundary.md`.

## Required smallest prerequisite

Extend the bounded UAX #9 revision-51 analysis-and-line-resolution boundary before
any RTL output fixture. It must consume the existing immutable source once and
return compact, explicit facts rather than a reordered string:

- Paragraph base level plus resolved embedding/isolate levels over exact
  source scalar and UTF-8 ranges, including the UAX #9 bracket-pair rules.
- A checked per-line resolver that consumes a selected logical line range from
  `KernelLineLayout` and returns a dense visual-order range of cluster/run IDs.
  It must not be inferred from glyph order or from PDF paint positions.
- Explicit mirror decisions, tied to the resolved odd level and source scalar,
  before font planning/shaping. Selection must validate coverage of the
  required presentation scalar; missing coverage or unsupported shaping is a
  typed error, never an unmirrored or substituted fallback.
- A typed handoff into shaping and PDF lowering that keeps logical source ranges
  separate from visual paint order. RTL lowering uses the visual sequence,
  while `ToUnicode` and required `/ActualText` consume the original logical
  occurrence range.

The boundary needs dimensioned limits, flat buffers, checked range partitions,
and deterministic traversal counters. Its correctness evidence must include
pinned UAX #9 conformance vectors covering embeddings, isolates, neutrals,
brackets, mixed numbers, and multi-line reordering; positive and atomic
malformed/mismatched-fact negatives; and a reviewed dev-backend allocation
record. It must also record the exact Unicode data/revision provenance already
pinned by `conformance/normative-baseline.json`.

Only then is a caller-font RTL output slice self-contained: select a
provenanced face with the needed RTL and mirrored glyph coverage, validate its
advanced shaping facts against the resolved directional runs, and lower the
line's verified visual sequence with logical extraction evidence. This keeps
the architecture's source, shaping, line-layout, and paint-order contracts
separate and leaves Gate 3 open.
