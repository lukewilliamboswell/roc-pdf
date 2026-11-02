# text-layout TrueType inspection slice

This slice introduces the pure Roc inspection boundary for static
TrueType-flavoured OpenType fonts. It accepts only the `0x00010000` sfnt
signature and rejects CFF/OTTO and other font programs explicitly.

The independent inspection fixture uses a deterministic OFL-1.1 derivative of Inter
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

## Name records

The `name` table is validated record by record: every record's string range
must lie inside the string storage, and only records whose platform encoding
is UTF-16BE must have an even length. Those are the Unicode platform (0), the
Windows platform (3), and the deprecated ISO platform's encoding 1 (ISO
10646). Macintosh-platform (1) names and the other ISO encodings are 8-bit
strings, so an odd length is legal; rejecting it made the whole font
`InvalidFont`, which refused IBM Plex, JetBrains Mono, and Noto Sans Italic
2.015. The selected family, full, and PostScript names still come only from
Windows Unicode records (encoding 10, else 1) in US English, which are
UTF-16BE and checked as such. The change removes a rejection and adds no
allocation or work: the record loop is unchanged. Four `KernelFont` expects
pin it: an odd Macintosh record beside valid Windows records is accepted,
odd Windows and Unicode records are rejected, and an odd Macintosh record
that overruns the string storage is still rejected.

## Allocation validation

Measurement resets before the inspection fixture enters Roc. The fixture
resolves a scalar and its advance from an imported face; offset and component
edge buffers must retain the source without copying its payload.

Current exact allocation and work expectations live in the matching scenarios
in [`tests/spec.json`](../../tests/spec.json). Review changes with the
[allocation baseline protocol](../testing.md#allocation-baselines).
