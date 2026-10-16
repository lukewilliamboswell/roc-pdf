# Preformatted source blocks

Issue #45 adds a distinct whitespace, local typography and continuation
contract. The implementation below keeps canonical source ownership and
measured visual-line continuation explicit. Final integration and cross-target
evidence are recorded separately before this extension slice closes.

## Source preparation

`KernelSourceText.prepare` owns a single canonical UTF-8 source and a dense
line arena. Each line records exact scalar and byte ranges excluding its LF
separator. LF and CRLF inputs become LF. A bare CR rejects. Indentation,
trailing spaces, consecutive empty lines, and the empty final line following
a terminal LF are retained. Even an empty input has one empty source line.
Tabs either reject or expand to spaces at explicit nonzero scalar-column tab
stops; columns count Unicode scalars rather than UTF-8 bytes. Glyph widths and
grapheme-safe visual breaks belong to subsequent measured layout.

The parser checks input bytes, expanded output bytes and line counts before
growth. Errors retain only a byte offset or bounded scalar details; a partial
source or line arena never escapes. A large tab width cannot bypass the
expanded-output budget.

## Ownership and complexity review

The input is immutable. A uniquely owned output byte buffer grows directly
with appends, and one independently owned line buffer holds scalar records.
The parser never constructs a list of copied line strings or returns an
accumulator through a fallible helper that the caller subsequently grows.
There is no repeated concatenation, speculative scene retention, per-byte
closure, resource payload duplication, or retained slice into an unrelated
combined allocation. Once validated, conversion from UTF-8 transfers the output
buffer into the canonical string.

Worst-case work is O(input bytes + expanded output bytes + lines). Each input
byte is visited once (the LF of a CRLF pair is inspected once and consumed
together), and each expanded tab space is appended once. Dense ranges require
O(lines) storage; the canonical source requires O(expanded bytes). Subsequent
stages must consume the produced ranges and must not split or remeasure all
preceding lines on continuation.

## Phase evidence

The `source_text` harness family measures before source construction and
includes a fixed blank-PDF envelope for the standard fixture protocol. Its
16/160 repetition pair exercises Unicode, CRLF, tabs, empty lines and trailing
spaces, validates every exact line range, and asserts six atomic errors.
The blank PDF is an evidence envelope, not a source-block rendering fixture.

With the pinned `nightly-2026-10-14-38a3029` dev backend, arm64mac and x64musl observations
are 399/407 allocations and 1,254,595/1,317,443 allocated bytes. The variable
work is exactly 192/1,920 input bytes, 224/2,240 output bytes, 49/481 line
writes and range checks, and 64/640 expanded spaces. The eight additional
allocation events are geometric growth of the source and line buffers; the
tenfold input does not copy growing prefixes. Both cases retain six atomic
rejections. The focused cases pass the `scripts/test.py` build/run harness functions
with exact allocation/work equality and independent PDF structure checks on
arm64mac and on cross-compiled x64musl in local `alpine:3.22`. Both targets
match the registered metrics and PDF bytes. Arlington 1.30.2 reports 9,022
passed rules, 286 object checks and zero failures for the envelope.
Full integration-suite validation remains
pending.

## Public lowering and continuation

`Pdf.source_block` takes canonicalizable text and an explicitly registered
face, with local size, leading, color, padding, background, wrapping and
fragmentation policy. Defaults are 9/12 pt, black, 8 pt padding, no background,
four-column tab expansion, grapheme-safe wrapping and line continuation.
`RejectLongToken` retains useful ordinary break opportunities, including URL
slashes, but rejects a token requiring emergency grapheme splitting. `Wrap`
permits that splitting explicitly; a single glyph wider than the accepted
content box still rejects. `Unsplittable` retains a located oversize error.

Normalization owns one canonical source per block and one global dense line
arena; each source stores a range into that arena. It never retains copied
line strings. Semantics creates a paragraph containing a PDF 1.7 `Code` node
with the canonical source as ActualText when nonempty. Real line occurrences
carry their exact canonical ranges. Empty lines have explicit layout facts,
without synthetic spaces, glyphs or occurrence IDs. An empty source still
reserves one visual row. Supported scripts use the existing actual script
itemization and covering-face checks.

Normalization bounds retained canonical source text and the flat logical-line
arena at one million bytes and one million rows across the document.
Cumulative counters pass remaining capacity into the parser before growth;
after exhaustion later source placements retain only a typed located
validation fact and no canonical text or line rows.

Ranged shaping consumes the earlier scalar/UTF-8 ranges. It decodes at most
four bytes at each already established scalar boundary, rather than scanning
the source prefix for each line. A validation prepass enforces budgets before
output growth. Whole-source shaping retains its existing contract. Line layout
uses measured clusters and advances a forward cursor; each candidate visit is
counted, including emergency-break candidates. It never remeasures earlier
logical lines during continuation. Selecting a natural break revisits only
the measured suffix after that break, bounded by one fit window; it never
scans the entire remaining long token to choose an emergency break.

Pagination treats a complete source as one `SourceUnit`, owned by its source
index. Its accepted visual-line cursor and measured geometry determine each
fragment; top and bottom padding are charged once per fragment. Panels repeat
as full rectangular background artifacts on Whole/First/Middle/Last fragments,
behind their text. They do not own semantic code content. Empty rows reserve
leading through the same native page path. Final semantic fragments attach
only actual text occurrences. The public report retains compact source
fragment geometry, parts and line ranges, without retaining compiler stages
or duplicating source text.

## Ownership and feature evidence

Font option validation and base-face preparation precede authoring
normalization. Source-face enrichment consumes the normalized source arena
and reuses the prepared base faces, so invalid source-independent font
options reject before allocating an authoring plan. Focused code-face and
heading-face regressions retain their original exact allocation counts.

Source documents select only font candidates used by actual text or drawing
labels. Wholly blank source output has zero font plans and no empty CMap; a
source-only document does not retain an unused body font. Textless scene
output retains its Archive ICC intent without declaring an unused page color
space. Pages continue to share the established resource dictionary.

The source, line, shape, visual-row and page stores use dense scalar records
and spans. Each growing buffer has a single accumulator owner. Fallible line
validation completes before an infallible append; a growing builder never
travels through a `Try` that the caller then updates. Background facts retain
colors and rectangles, not scene copies. No continuation holds a suffix slice
of a larger source allocation. Reports share only compact accepted placement
facts. Worst-case storage is linear in accepted canonical bytes, clusters,
visual lines and fragments. Work is bounded by explicit stage limits and
recorded metric-read, line-candidate and page-candidate counters; the scale
pair must demonstrate growth before this slice closes.

## Public feature evidence

All 16 `source_blocks` cases pass the strict `scripts/test.py` build/run
harness on arm64mac and cross-compiled x64musl in `alpine:3.22`, with exact
allocation counts, allocated bytes, work vectors and PDF snapshots. The
independent byte oracle checks canonical ActualText, every decoded source
character, local face/size/color, empty-row geometry, useful URL slash breaks,
the complete 220-character token, panel artifact ordering and padding,
first/middle/last continuation, and unchanged body spacing. Public report
assertions check fragment parts, rectangles and contiguous visual-line ranges.
Twelve atomic negatives require their exact located diagnostics and no bytes.
The matrix also covers default source/body/furniture styles, precomposed Latin,
Han with separate and shared faces, three source blocks with repeated text,
and wholly empty source output both with and without a background.

| Source lines | Allocations | Allocated bytes | Pages / panels | Metric reads | Line candidates | Page candidates |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 60 | 14,109 | 11,764,848 | 2 / 2 | 1,797 | 1,797 | 62 |
| 600 | 90,209 | 58,407,714 | 11 / 11 | 17,958 | 17,958 | 602 |

The tenfold input grows metric and candidate work approximately tenfold.
Allocation and byte growth include fixed face inspection, font subsetting,
reporting and envelope costs plus linear text/line output. Source logical
ranges bypass the whole-source line-template cache; hash slots are sized from
whole-source requests only, avoiding unused per-line cache capacity. The typed
page owner combines source identity and padding, removing contradictory
owner/kind combinations and one provisional word per block. These are new
feature baselines reviewed against the accepted representation, not changes
accepted for existing fixtures.

All 578 package unit tests pass. Arlington 1.30.2 passes 9,022 rules per source
PDF with zero failures; veraPDF 1.30.2 accepts all 16 as PDF/A-4. PDFium Chromium
7988, PDFBox 3.0.8 and MuPDF 1.28.2 render all 29 pages of the original files
without warnings. Page dimensions and expected ink (including a true white
blank page) agree; PDFBox extraction preserves all non-whitespace source
characters in order. Exact whitespace remains independently checked in the
emitted semantic and glyph facts. The two-page public gallery example also
passes all three readers, Arlington and PDF/A-4; all 90 repeated recipe lines
and the resumed body paragraph survive extraction.

Full integration-suite regression validation remains pending. General custom
fragmentation and PDF/UA-2 remain outside this extension's declared subset.

The final font-selection preflight separates option validation from source
face enrichment and consumes the prepared base candidates. This avoids the
temporary candidate list in general styled-font preparation: each
positive source case saves exactly one allocation and 72 bytes, independent
of source length. The twelve-negative fixture saves nine allocations and
424 bytes through earlier option rejection and avoiding unused candidates.
Both pinned targets reproduce these changes with identical PDF bytes, stage
work, source-fragment reports, and all twelve located diagnostic checks.
These fixed selection costs were reviewed before updating the exact baselines.
