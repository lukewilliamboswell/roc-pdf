# contract-definition text and font planning type slice

## Scope

This define-only slice establishes the advanced shaped-run interchange and the
pre-shaping font-selection plan. It does not parse fonts, select faces, shape
text, subset fonts, lay out glyphs, or emit PDF bytes.

## Representation and ownership

- Font resources own bytes once. Faces, static instances, policies, plans,
  themes, and shaped runs refer to them through dense scalar identities.
- A face's sparse Unicode coverage and supported scripts are ranges into flat
  store buffers. A font plan stores ordered ranges of grapheme clusters assigned
  to instances; it does not copy source Unicode, clusters, coverage, or fonts.
- Glyphs, cluster-to-glyph indices, substitutions, transformations, and runs
  occupy separate contiguous buffers. Variable relationships use exact scalar
  ranges rather than recursive lists per run or cluster.
- One `Font.FaceId` now crosses theme, planning, and resource boundaries. One
  `Text.RunId` crosses shaping and scene boundaries. No alias reconciliation or
  payload lookup by names is required later.
- Packaged coverage, built-in shaping, and advanced shaped-run interchange are
  distinct typed capability facts. Coverage never silently authorizes shaping.

## Complexity and future executable contract

Font selection operates on complete grapheme clusters. For `g` clusters, `f`
ordered candidate faces, and at most `s` searched coverage spans per face, the
declared conservative bound is `O(g * f * s)`. Exact `grapheme_visits`,
`face_visits`, and `coverage_span_visits` counters make that bound observable.
Implementations may use indexed coverage to reduce work but must preserve the
same ordered selection result and counters appropriate to that algorithm.

Run traversal is linear in runs, glyphs, clusters, substitutions, and
transformations. Hot glyph and cluster loops are direct indexed loops over the
flat buffers. No `Iter`, closure, source suffix, font-byte copy, or recursive
per-glyph value is stored in the contract.

## Lifetime and failure

Planning reads validated face facts and source cluster ranges, then returns a
compact plan or a bounded error list. Rejection carries no partial usable plan.
Uncovered clusters, prohibited embedding, and unsupported built-in shaping are
distinct failures; none permits system lookup, substitution, outlining, or
rasterization. Phase-local parse, coverage, and shaping caches require complete
keys and are introduced with their executable evidence.

## Evidence

`examples/advanced_text_contract.roc` compiles a whole-cluster face assignment,
a many-to-one cluster, an occurrence-owned shaped run, and visible text paint.
The package tests prove opaque identities preserve their scalar backing. Exact
optimized allocation and scaled-work evidence belongs to the capability implementing
font planning and shaping rather than this define-only representation.
