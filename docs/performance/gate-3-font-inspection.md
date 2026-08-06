# Gate 3 TrueType inspection slice

This slice introduces the pure Roc inspection boundary for static
TrueType-flavoured OpenType fonts. It accepts only the `0x00010000` sfnt
signature and rejects CFF/OTTO and other font programs explicitly.

The initial production face is a deterministic OFL-1.1 derivative of Inter
4.1 Regular. `scripts/build_builtin_font.py` pins the 411,640-byte upstream
source digest, fontTools 4.61.1, exact Unicode selection, layout-table policy,
and renamed family/PostScript identities. Roc imports the retained `.ttf`
directly as `List(U8)` at compile time; neither inspection nor document
generation performs runtime file I/O or invokes fontTools.

## Representation, ownership, and bounds

- Font bytes are owned once. Table records, cmap groups/segments, coverage
  spans, and the SHA-256 identity contain scalar offsets and facts rather than
  copied table payloads.
- Directory, table-range, alignment, overlap, per-table checksum, whole-font
  checksum, required-table, head, maxp, hhea, hmtx, loca, OS/2 embedding-rights,
  and Unicode cmap invariants are checked before an `Inspection` escapes.
- Every non-empty `glyf` span is parsed within its `loca` bounds. Simple-glyph
  contour endpoints, instructions, packed flags, repeats, coordinate payloads,
  bounding boxes, and reserved bits are validated. Composite records validate
  component IDs, arguments, mutually exclusive transforms, reserved flags,
  optional instructions, graph acyclicity, and the depth declared by `maxp`.
- Cmap selection has a fixed deterministic priority and supports formats 12
  and 4. Coverage excludes glyph zero and surrogate code points.
- Font bytes, tables, glyphs, and cmap mappings have independent limits.
  Invalid or restricted input yields no partial face.
- Directory lookup and table scans are direct dense-list loops. The initial
  overlap proof deliberately performs `T(T-1)/2` comparisons over the strictly
  bounded table count; the evidence records that exact work. Byte checksums,
  loca validation, glyph parsing, composite graph validation, and cmap
  validation are linear in their respective inputs.

The parser retains the caller's exact immutable font allocation. It allocates
flat table, loca, cmap, coverage, component-edge, and digest buffers, but no
object per font byte or outline point. Offset/length views keep the font alive
through subsetting and emission; the source is not copied by the inspection
stage. The retained component edges are an earlier-stage fact consumed by
subset closure rather than rediscovered from incidental glyph bytes.

## Pinned optimized evidence

Measurement resets before the fixture enters Roc. It inspects the imported
166,300-byte `Roc PDF Sans Regular` face, resolves `U+0041`, reads its advance,
and emits the unchanged structural snapshot for the shared fixture protocol.

| Target | Optimization | Font bytes | Tables | Glyphs | Cmap mappings | Loca entries | Composite edges | Exact allocations |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| arm64mac | speed | 166,300 | 17 | 1,376 | 468 | 1,377 | 1,713 | 65 |
| x64musl | speed | 166,300 | 17 | 1,376 | 468 | 1,377 | 1,713 | 65 |

The two-allocation increase from the preceding inspection slice retains the
flat `loca` offsets and component edges needed by later subset planning; it is
not a copy of the font or an allocation per glyph/component.

The x64musl value is the accepted same-compiler expectation and remains to be
executed by the configured cross-target job. The current slice does not yet
claim shaping, subset emission, PDF font objects, or Gate 3 closure; those
remain dependent slices.
