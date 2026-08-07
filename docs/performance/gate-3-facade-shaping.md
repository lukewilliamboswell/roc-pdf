# Gate 3 facade batch shaping

This slice connects normalized facade semantics to the built-in Latin shaper
without materializing one `Text.Store` per authored block. Font inspection is
an explicit earlier-stage input. The evidence facade imports the packaged TTF
as `List(U8)`, inspects it once, and passes the validated inspection into
facade shaping; the shaping kernel neither embeds font source syntax nor
re-parses the font.

Preparation consumes only facts established by earlier stages: normalized
block kinds, semantic block ownership, the validated occurrence store, the
interned source table, and the authored theme. It writes exact-length dense
request, style, and block-to-run stores. List labels are emitted before their
bodies so run order follows the semantic `Lbl`, `LBody` order. A batch-wide
language/script/direction/instance/writing-mode record is retained once;
compact requests carry only source identity, occurrence identity, and size.
Mixed occurrence languages, unsupported theme faces, artifact text, invalid
ownership, and every request limit remain typed failures.

Batch shaping validates cumulative source-byte, scalar, cluster, and glyph
limits before output allocation. It scans each unique Unicode source once into
a dense glyph template table containing exact scalar/UTF-8 ranges, glyph IDs,
and source font widths. Per-occurrence emission then scales the cached width and
writes globally dense runs, clusters, glyph indices, glyphs, and advances. The
six-source fixture therefore performs UTF-8 iteration, cmap lookup, and metric
lookup once per unique source rather than once per repeated paragraph. Final
glyph records remain occurrence-owned; the cache does not share mutable output
ranges or infer semantic ownership.

## Ownership and allocation review

Three drafts were rejected before pinning evidence:

- Reopening `Scalar.iter` and validating source facts for every request measured
  4,298 allocations at 1,000 paragraphs and 40,335 at 10,000.
- Caching unique-source glyph templates removed one allocation per repeated
  paragraph but still measured 3,304 and 30,341 because preparation retained
  append-built temporary selection buffers.
- Direct compact preparation reduced that to 2,271 and 20,308, revealing that
  the two final append-built request/style buffers still lost uniqueness across
  the fallible traversal.

The accepted design derives the exact request cardinality from the validated
semantic occurrence store, checks the bound before allocation, initializes
both dense buffers to that exact length, and writes each index once. The
preparation-only audit measures 259 allocations at 1,000 paragraphs and 296 at
10,000. Full shaping adds 24 allocations at either scale.

## Pinned optimized evidence

| Paragraphs | Requests/runs | Scalars/clusters/glyphs | Unique sources | Source bytes | Exact allocations |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 1,006 | 4,021 | 6 | 4,025 | 283 |
| 10,000 | 10,006 | 40,021 | 6 | 40,025 | 320 |

Both cases inspect the 166,300-byte built-in font with 17 tables, retain exact
global run/cluster/glyph-index/glyph cardinalities, perform 24 metric reads and
six script-run visits across the six unique sources, and emit the same 667-byte
deterministic evidence PDF. A tenfold scale adds 37 allocations while repeated
source cache work stays constant and occurrence/glyph work increases by its
declared linear bounds.
