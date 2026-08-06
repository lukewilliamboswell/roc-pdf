# Gate 3 caller-font text slice

This slice routes the public caller-font boundary through the existing Gate 3
text stages without branching on provenance. The application imports a
7,816-byte fixture as `List(U8)`, registers it, selects its returned face through
`Theme`, and the pipeline consumes the retained validation facts for shaping,
global glyph planning, composite closure, sanitized subsetting, Type 0
embedding, CID mapping, `ToUnicode`, and visible text emission.

The work also removes two built-in-font assumptions discovered by the caller
fixture. TrueType inspection now validates and retains exact source ranges for
the Windows Unicode family, full, and PostScript names. Subset construction
prefixes and copies those ranges directly from the retained source allocation;
it no longer constructs a hardcoded `Roc PDF Sans` identity. PDF font
dictionaries derive their PostScript identity from the validated source, and
the descriptor derives CapHeight from the validated OS/2 table. The built-in
visible-text snapshot therefore changes only from the incorrect hardcoded
`/CapHeight 1014` to the exact `/CapHeight 728`; its glyph subset digest and
rendered pixels are unchanged.

The caller PDF is 9,155 bytes and uses 180 Roc allocations. Exact work evidence
records 7,816 input and retained bytes, zero copied payload bytes, 17 tables, 15
parsed glyphs, 9 cmap mappings, 4 component edges, 8 text glyphs, an 11-entry
font plan, a 6,820-byte sanitized subset, 271 content bytes, 14 PDF objects, and
7,091 payload bytes. Independent inspection pins the caller PostScript name in
all three PDF font dictionaries, the prefixed family/full/PostScript names
inside the embedded subset, OS/2 CapHeight 728, widths, the identity CID map,
all eight Unicode mappings, and the exact subset digest.

PDFBox extracts exact UTF-8 `Café PDF`. PDFBox rendering produces the same
declared 72-dpi bounds and ink metrics as the built-in fixture because both
fixtures use the same source outlines. CI runs the same comparison with the
pinned PDFium Chromium 7988 renderer. A checksum-valid twin with restricted
OS/2 embedding rights fails registration with `EmbeddingRightsProhibited` and
never returns a registry or emits a PDF.

Replacing constructed hardcoded name strings with validated source ranges is
also an allocation improvement: the built-in subset case drops from 104 to 94
allocations, and the PDF-font-object case drops from 271 to 262. Caller
registration increases from 74 to 75 allocations because its public face fact
now materializes the small PostScript-name value; the 7,816-byte payload remains
uncopied. Remaining caller-font closure evidence covers source-allocation
reference counts through final subset emission and one-parse reuse across many
placements.
