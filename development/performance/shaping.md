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

## Validation

The convenience fixture shapes `Café PDF` into one-to-one clusters. The
advanced fixture validates `A` plus combining grave mapping through `ccmp` to
the font’s `Agrave` glyph while retaining the two-scalar source range. These
checks cover the declared shaping boundary; they do not establish a built-in
OpenType GSUB/GPOS engine or bidirectional resolution.

Current exact allocation and work expectations live in the matching scenarios
in [`tests/spec.json`](../../tests/spec.json). Review changes with the
[allocation baseline protocol](../testing.md#allocation-baselines).
