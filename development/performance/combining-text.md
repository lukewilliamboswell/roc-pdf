# text-layout advanced combining-text slice

This slice closes the missing end-to-end evidence for the existing advanced
combining-mark boundary; it does not add built-in OpenType shaping. The source
is the decomposed Unicode sequence `A` plus U+0300. The advanced input carries
one positioned U+00C0 glyph, one `ManyToOne` cluster, and exact scalar range
`(0, 2)` plus UTF-8 range `(0, 3)`. The source remains owned by the semantic
occurrence. PDF lowering consumes those supplied facts and writes a single CID
with the two-scalar `ToUnicode` row `<00410300>`; it neither normalizes source
text nor infers Unicode from the precomposed glyph ID.

The tagged one-page PDF retains its fragment MCID, ParentTree ownership,
Identity-H Type 0 font, CIDFontType2 descendant, embedded deterministic
subset, and one painted CID. The direct checker reconstructs the decomposed
source from that CID and CMap. PDFBox 3.0.8 extracts the exact UTF-8 sequence
`A` plus U+0300 and newline. The fixture deliberately has no `/ActualText`:
one CID has one complete, unambiguous source mapping, so a redundant override
would obscure the distinction between CMap and `ActualText` responsibilities.
The existing reordered fixture remains the required `ActualText` evidence.

Local 72-dpi renderer evidence on the original bytes is deliberately recorded
per engine: PDFBox 3.0.8 measured bounds `(72, 131, 79, 141)`, 45 changed
pixels, 21 dark pixels, and 5,085 grayscale-ink units; PDFium Chromium 7988
measured `(71, 131, 79, 141)`, 55, 21, and 5,413. Their bounds differ by at
most one pixel. These are observed fixture facts pending promotion to the
baseline-controlled renderer suite, not inherited tolerances from the Latin
fixture.

The atomic typed negative shortens the cluster's UTF-8 range from three to two
bytes while leaving its two-scalar range intact. Advanced validation rejects it
as `AdvancedClusterInvalid(SourceRange)` before a scene, object plan, or PDF is
created. The independent checker additionally rejects same-length mutations of
the decomposed CMap row and `/Identity-H` encoding.

The focused deterministic work vector is
`166300,1,1,1,1,2,0,0,1,109,20,8712`: one advanced run, cluster, glyph, and
glyph-index visit; two source scalars; no `ActualText`; one mapping; 109
prepared text bytes; twenty objects; and 8,712 emitted bytes. The built-in
font is inspected once, its 166,300-byte input stays one payload, and its
5,696-byte subset is written once. Since the reviewed dev-backend allocation
rebaseline, the positive and atomic-negative cases are registered in
`tests/spec.json` (`combining-v1-decomposed-built-in`) with byte-exact
snapshots, 144 and 45 dev allocations, the full work vector above, and the
`[1, 667]` counted rejection; `scripts/check_combining.py` runs in the
common validator dispatch and self-test set.

Remaining text-layout extraction/rendering matrix: ligature output, supplementary
plane output, real right-to-left logical/visual output, CJK output,
discretionary and soft hyphens, generated labels, and case transformations.
Those require their own validated face coverage and advanced shaping/presentation
facts; this slice does not pretend that the built-in Latin shaper supplies them.
