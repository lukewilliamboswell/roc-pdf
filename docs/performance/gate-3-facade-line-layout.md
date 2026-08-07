# Gate 3 facade line layout

This slice connects the facade's dense shaped-run store to line selection
without copying per-run glyph, cluster, or Unicode buffers. `KernelLineLayout`
selects an exact global run range from the shaped store; emitted line cluster
ranges remain global while line source ranges stay relative to the run's
immutable Unicode source. Later pagination therefore consumes explicit shaped
facts rather than reconstructing character or ownership relationships.

`KernelFacadeLines` derives the usable page width from the typed page geometry
and theme margins. Ordinary runs receive the full content width. List labels
receive the exact bullet indent and their bodies receive the remaining width;
the stage retains separate label/body line ranges so later visual placement
can align them without losing semantic order. Dense run order and complete
coverage are validated before line selection. Artifact text remains a typed
failure until its separate repeated-page path is implemented.

## Cache and complexity review

The cache key is the exact numeric tuple `(source, font instance, size,
available width)`. Script, language, direction, and writing mode are batch-wide
validated shaping facts; source identity denotes the once-analyzed Unicode
value. A representative template is measured once and its local source ranges
are reused while global cluster ranges are shifted to each occurrence's
validated dense run range.

An initial implementation retained unique keys in a list and searched them
linearly after the adjacent-key fast path. It passed repeated-paragraph cases
but was rejected because adversarial unique keys had quadratic comparison
work. The accepted implementation uses an exact power-of-two open-addressed
table sized from the request count. Table slots and every probe are explicit,
bounded work. Exhaustion or a probe limit crossing is a typed error, never
permission to approximate or skip layout.

The hot stores are flat lists: one assignment per run, one cache entry per
unique key, one line template per unique key, one final line per occurrence,
and one block-to-label/body mapping per normalized block. The shaped store,
Unicode sources, and font inspection stay shared. No per-occurrence
`Text.Store`, Unicode analysis, glyph list, or copied source suffix is retained.

## Pinned optimized evidence

| Paragraphs | Blocks | Runs/lines | Templates | Cache hits | Key probes | Table slots | Exact allocations |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 1,004 | 1,006 | 6 | 1,000 | 1,012 | 2,048 | 319 |
| 10,000 | 10,004 | 10,006 | 6 | 10,000 | 10,012 | 32,768 | 356 |

Both cases derive a 451,000-unit A4 content width, visit the six unique line
templates' 30 UAX #14 boundaries and 24 clusters/glyphs once, and materialize
one accepted line per run. A tenfold scale adds 37 allocations. Template work
stays constant; block/run mapping, cache hits, probes, and final line writes
grow linearly. These figures use the pinned release-fast compiler commit and
the repository's optimized no-cache evidence boundary.
