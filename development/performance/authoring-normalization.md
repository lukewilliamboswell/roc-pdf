# text-layout facade authoring normalization slice

This slice implements the common normalization boundary shared by the simple
`List(Document.Block)` facade and `Document.Builder`. Both paths produce one
flat ordered block/text store before semantic construction or layout. Bullet
lists expand to dense scalar list/item identities; headings retain their level;
page artifacts remain a distinct typed kind. String values are transferred as
shared immutable payloads rather than copied byte-by-byte.

The compact builder stores block tag, text-source ID, and auxiliary value in
three parallel scalar buffers, with text payloads in a fourth flat list. It does
not allocate a boxed union descriptor per block. Ordinary scalar methods remain
ergonomic; `add_paragraphs` is the consumption-shaped large-input path and keeps
all four buffers uniquely owned throughout one direct indexed loop. Only the
final builder escapes that loop.

Normalization is linear in authoring descriptors plus expanded bullet items.
It visits each input descriptor once and writes each normalized block once. It
does not sort, retain list suffixes, rescan text bytes for each output item, or
keep earlier builder/normalization versions. The work vector records authoring
descriptors, normalized blocks, referenced UTF-8 bytes, title/heading/paragraph/
bullet counts, list count, and the structural evidence-carrier bytes.

The executable image-figure slice adds a dense normalized figure store. Its
empty-store representation adds one allocation to the 1,000-paragraph simple
list case under the pinned dev compiler (67 to 68). The 10,000-paragraph simple
case and both compact-builder scales retain their prior counts, so the change
is a reviewed fixed representation effect rather than per-block growth.

## Historical optimized-backend evidence (superseded)

This earlier table documents the authoring-store representation decision only.
Current exact allocation validation uses the matching dev-backend scenario in
[`tests/spec.json`](../../tests/spec.json).

| Path | Paragraphs | Authoring blocks | Normalized blocks | Text bytes | Exact allocations |
| --- | ---: | ---: | ---: | ---: | ---: |
| simple list | 1,000 | 1,003 | 1,004 | 4,019 | 85 |
| compact builder batch | 1,000 | 1,003 | 1,004 | 4,019 | 120 |
| simple list | 10,000 | 10,003 | 10,004 | 40,019 | 93 |
| compact builder batch | 10,000 | 10,003 | 10,004 | 40,019 | 145 |

The tenfold scale adds eight allocations to the simple path and twenty-five to
the builder path rather than one allocation per block. The builder's higher
fixed/logarithmic count is the four dense buffers plus the supplied paragraph
batch; it avoids the thousands of per-call shared-buffer copies measured and
rejected during representation review. Both paths produce identical normalized
work and the same deterministic carrier bytes.

This is authoring-boundary evidence, not useful-facade completion. Semantic
construction, line breaking, pagination, final scene materialization, tagged
text lowering, and `Pdf.to_bytes` integration remain subsequent text-layout slices.
