# Hebrew and Latin flow evidence

The bilingual invoice uses Unicode 18.0.0 analysis from Unicode 4.4.0
(UAX #9 revision 52, UAX #14 revision 57 and UAX #29 revision 49) and
roc-font 0.2.0 shaping. Earlier checked-in Unicode vectors continue to
exercise their pinned cases. UAX #24 script facts are intersected with
paragraph levels and authored occurrences. Coverage then uses the caller's
ordered exact faces. The shaper uses the provider's default features with
the resolved direction, exact script and author language. The admitted
repertoire avoids joining across UAX #14 opportunities, so shaping both
sides independently before fitting gives final measurement at every legal
boundary. The Latin and Hebrew fonts are pinned in the asset inventory.

`tests/contracts/international_shape.roc` checks source intervals, RTL glyph
order, glyph limits, exact selected fonts and a line whose wrap changes paint
positions while preserving logical owners. The matched HarfBuzz 14.6.0 case
uses the exact gallery Hebrew font, Latin prefix byte origin, Hebr, he, RTL
and default features. It checks glyph IDs, clusters, advances and offsets.
The invoice PDF oracle independently traverses structure owners and reads
the painted positions, ToUnicode and scoped ActualText. Its mutations
change an owned replacement, reorder a mirrored bracket on a committed line,
or change WritingMode. ISO 32000-2 §§9.10, 14.7.5, 14.8.5.4 and 14.9 and
ISO 14289-2:2024 Annex B.1 govern these mappings, scoped replacements,
language and layout attributes.

The fixture group exercises normal preparation, reporting, WTPDF
Accessibility and located rejections for an unsupported script, pointed
grapheme, bidi control and missing face coverage. Each rejection is exercised
through complete bytes and chunk preparation.

| Case | x64musl allocations | Allocated bytes | Pages | Owned fragments |
| --- | ---: | ---: | ---: | ---: |
| Invoice | 20,996 | 11,598,114 | 1 | 80 |
| Invoice with WTPDF Accessibility | 20,998 | 11,601,708 | 1 | 80 |
| Two wrapped address paragraphs | 9,139 | 8,981,649 | 1 | 40 |
| Twenty wrapped address paragraphs | 68,298 | 22,059,961 | 2 | 400 |
| Eight rejected delivery attempts and two accepted wrapped paragraphs | 12,508 | 19,832,372 | 1 | 40 |

The allocation boundary begins before fixture dispatch, including font
registration and preparation with and without the optional report. The
scaling cases alternate two authored ranges and styles. Each source's
paragraph analysis is interned, and each occurrence retains its own item
and physical span. Font programs are reused by exact face, script,
language and direction. The cluster-to-run index is built once and
retains one integer per cluster. Selection, glyph and logical occurrence
buffers append into uniquely owned stores, and visual position buffers are
sized by the committed line. The harness enforces exact allocations and
work and a 110% allocated-byte ceiling.

Arlington 1.30.2 accepts the four PDF snapshots. Explicit veraPDF `4` and
`ua2` accept the gallery invoice and its WTPDF counterpart, and `wt1a`
accepts the latter. The checked-in preview uses Poppler 26.07.0 at 96 dpi.
The development validation ran on x64musl. The arm64mac fixture baseline
and cross-target bytes require execution on the native target workflow.
