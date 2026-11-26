# International flow evidence

## Hebrew and Latin

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
| Eight rejected delivery attempts and two accepted wrapped paragraphs | 12,615 | 20,400,822 | 1 | 40 |

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
`ua2` accept the gallery invoice and its WTPDF counterpart and both scale layouts, and `wt1a`
accepts the latter. The checked-in preview uses Poppler 26.07.0 at 96 dpi.
The development validation ran on x64musl. The arm64mac fixture baseline
and cross-target bytes require execution on the native target workflow.

## Arabic and Latin

The supplier invoice exercises initial, medial, final and isolated forms
with the audited IBM Plex Sans Arabic Regular font. The Arabic shaper uses
Unicode 18.0.0 DerivedJoiningType supplied by roc-font 0.2.0 and OpenType
Arabic joining and contextual substitutions. The production adapter checks
all positions, glyph IDs and cluster ranges in `السلام` against HarfBuzz
14.6.0 with the exact face, Arab, ar, RTL and default features. The checked
lam-alef cluster owns one glyph and both original letters. The fixture's
tagged owners supply exact logical extraction, writing mode and scope
language. An inline boundary inside a joining word has a located rejection
until supported shaping contexts can cross that boundary.

The positive Arabic cases record 11,586 and 11,588 x64musl allocations and
10,247,973 and 10,251,565 allocated bytes for the combined and WTPDF profiles,
respectively. Each has one page, ten authored blocks and 32 owned fragments.
The atomic case records 13,564 allocations and 18,271,179 bytes for six
attempts through bytes and chunks plus the accepted invoice. The Hebrew
negative fixture reuses its single registered Inter face with a narrower
policy. The expanded fixture dispatch and mode checks changed only its
negative setup measurement (+2.9% allocated bytes), with identical PDFs and
work and unchanged positive baselines. Arlington 1.30.2 accepts both Arabic
snapshots. Explicit veraPDF `4` and `ua2` accept both. Explicit `wt1a` accepts
the WTPDF snapshot.

## Hindi and Latin

The Hindi statement checks a conjunct and pre-base vowel in `वित्तीय`
and a below-base mark in `कृपया`. Layout uses the exact static IBM Plex
Sans Devanagari Regular and the font's OpenType `dev2` features with
Deva, hi and left-to-right direction. Coverage planning keeps each
Unicode grapheme together. The provider may merge contributors into a
single cluster and reorder glyphs according to the script's OpenType
stages. The adapter and the emitted PDF are independently compared to
HarfBuzz 14.6.0 for these choices and positions. Tagged language and exact
logical source remain intact. An inline divide inside a conjunct is
located before paint, and unsupported script or effective language
gives a separate diagnostic.

The two one-page cases use 12,904 and 12,906 allocations, and 11,860,053
and 11,863,645 allocated bytes. Each has ten authored blocks and 36 owned
fragments. The atomic rejection case checks six deliveries and one
accepted statement, using 14,460 allocations and 19,127,093 bytes.
Arlington 1.30.2 and explicit veraPDF `4` and `ua2` accept the two PDFs.
Explicit `wt1a` accepts the WTPDF snapshot.

## Committed-line model

The bounded model in `fuzz/InternationalLineModel.roc` exhausts 37
states at depth three using four independently authored paragraph-level
cases. It retains base direction, bracket and digit contexts, an optional
authored style boundary and one of three exact committed line ranges.
The production analysis and line stages must agree with hand-derived
paragraph levels and independent L1 trailing-space resets and L2 run
reversals. It checks line levels, visual cluster order and logical
ranges, with witnesses for an earlier committed cut on both base
directions. The Hebrew invoice checks the corresponding ordered owner
and paint facts through the public compiler and archived PDF.

## Thai and Latin

The Thai notice uses Unicode 4.4.0 ThaiDictionaryV1 over the case's authored
five words, with the dictionary revision supplied in the public options.
Independently expected scalar cuts 5, 9, 13 and 18 map to bytes 15, 27, 39
and 54. The production shaper and fitter consume the same decisions.
The notice shows the break after เงิน. Its owner retains the full unspaced
text, including SARA AM and combining marks. HarfBuzz 14.6.0 agrees on the
glyphs, advances and offsets of ชำระ in Thai/th/LTR with the exact static
IBM Plex Sans Thai Looped font and default features. The PDF oracle checks
those painted positions and the vertical mark in วันนี้.

The two one-page PDFs each have four authored blocks and 22 owned fragments.
The combined profile uses 7,618 allocations and 8,644,644 bytes. WTPDF
uses 7,620 allocations and 8,648,232 bytes. The six rejected byte/chunk
deliveries and one accepted output use 14,098 allocations and 16,029,534
bytes. The diagnostics cover invalid dictionary revision, an uncovered
dictionary causing an unbreakable segment, and unsupported effective
language. Arlington 1.30.2 and explicit veraPDF `4` and `ua2` accept both
PDFs. Explicit `wt1a` accepts the WTPDF snapshot.
