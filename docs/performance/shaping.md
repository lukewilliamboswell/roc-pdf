# text-layout simple and advanced shaping slice

This slice implements two separate promises rather than treating font coverage
as shaping support.

The built-in convenience shaper consumes the earlier `KernelUnicode` analysis
and one exact `KernelFont.Inspection`. Its initial declared capability is
horizontal left-to-right Latin with exactly one scalar in each grapheme. It
maps every scalar through the validated cmap, rejects missing glyphs and glyph
zero, reads each horizontal metric once, and scales advances to the fixed
1,000-units-per-point layout space with checked integer arithmetic and a fixed
nearest-integer rule. Unsupported direction, writing mode, script, or cluster
shape is a typed error; there is no substitution or font fallback.

The advanced boundary accepts caller-supplied positioned runs but does not
trust their relationships. A bounded validation pass builds one scalar-to-byte
boundary list and proves:

- dense run IDs and exact instance/occurrence ownership;
- a positive layout size carried by every run for later PDF text scaling;
- complete ordered source, run, cluster, glyph, and auxiliary partitions;
- cluster-kind cardinality and exact UTF-8/scalar boundaries;
- valid nonzero glyph IDs and horizontal advances;
- every glyph reference stays inside its run and occurs exactly once; and
- substitution/transformation ranges stay inside their owning run.

Validation returns the same flat `Text.Store`; it does not copy glyph or
cluster payloads. Negative twins reject a duplicate glyph reference, `.notdef`,
a non-positive size, and an inconsistent Unicode byte range without returning a
partially validated store.

## Historical optimized-backend evidence (superseded)

The speed-backend values preserve the original shaping representation review;
they are not current allocation baselines. Current exact dev-backend values
are the matching scenario in [`tests/spec.json`](../../tests/spec.json), with
the transition reviewed in [the dev-backend rebaseline](dev-backend-allocation-rebaseline-2026-08-09.md).

The convenience path shapes `Café PDF` at 11 points into eight glyphs and eight
one-to-one clusters. The advanced path validates a real composition relationship
for `A` plus combining grave mapping through `ccmp` to the font's `Agrave`
glyph, retaining the two-scalar source range and one-glyph presentation.

| Target | Optimization | Simple scalars/glyphs | Advanced scalars/glyphs | Simple advance | Exact allocations |
| --- | --- | ---: | ---: | ---: | ---: |
| arm64mac | speed | 8 / 8 | 2 / 1 | 49,247 | 89 |
| x64musl | speed | 8 / 8 | 2 / 1 | 49,247 | 89 |

The x64musl row is the accepted same-compiler expectation and is exercised by
the configured cross-target job. This slice does not yet claim a built-in
OpenType GSUB/GPOS engine, bidirectional resolution, PDF text-object lowering,
or text-layout closure.
