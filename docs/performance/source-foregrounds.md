# Source foreground ranges

Issue #47 adds optional original-input UTF-8 foreground ranges to
`Pdf.source_block`, independent of language tokenization. This extends the
existing bounded Gate 6 source contract; no PDF/UA-2 claim is added.

## Representation and ownership review

`Pdf.SourceForeground` is `{ start : U64, end : U64, color : Color.SourceValue }`.
The default is an empty list. Validation rejects empty/reversed, out-of-bounds,
overlapping/unsorted and non-grapheme endpoints. The pinned Unicode extended
cluster iterator walks the original input once alongside a forward endpoint
cursor. This makes CRLF indivisible and rejects UTF-8 continuation-byte and
combining-sequence splits before shaping. Supported foregrounds use the
existing facade sRGB RGB channel policy; unsupported channel models reject
at the original range, even if only a newline would consume the colour.

The normalization byte walk maps validated endpoints as it emits canonical
bytes. Tabs propagate a range's colour across their expanded spaces. CRLF
maps to LF. No original source, per-byte mapping table, substring, token text
or payload closure is retained. Canonical ranges occupy one global dense
`source_foregrounds` arena, with a span per source. The 100,000-range cumulative
bound is checked before growth; exhaustion retains no partial output and
prevents later sources from materializing. Source input/output/line budgets
remain independently enforced.

Shaping and line/page layout consume the exact same requests whether ranges
exist or not. `KernelFacadeText.Plan.with_source_foregrounds` consumes accepted
layout. An explicit semantic-owner index maps real source-line occurrences
to their source and canonical byte origin; interned text identity is never
used as placement identity. One cursor per source visits canonical foregrounds
monotonically through visual wraps and pages. Each source cluster is visited
once. Splitting retains the existing glyph, glyph-index and cluster arenas;
only fixed run spans, styles and placements are built. Positions advance by
accepted glyph advances, retaining offsets. Subsequent fragment, ownership,
font, colour and sealed-plan validation use their existing contracts. Tokens
create no semantic nodes; real line occurrence identities remain unchanged.

Worst-case normalization is O(input bytes + expanded bytes + original
clusters + ranges); retained mapping is O(ranges). Paint subdivision is
O(runs + logical rows + occurrences + source clusters + ranges), with O(occurrences + sources
+ paint pieces) temporary/index storage. Run/placement limits are checked
before every new piece. Accumulators stay uniquely owned; no growing list
passes through a fallible helper that its caller then extends. There are no
new payload copies, caches, native dependencies or language dependencies.

## Evidence

The public `source_blocks` family adds colour/plain pairs for original tabs,
CRLF, indentation, trailing spaces, consecutive/final blank lines and accented
Latin; a long URL/string plus a range spanning newlines and two pages; 180 and
1,800 token ranges across 60/600 rows; and identical interned source in two
placements with independent foregrounds/defaults. Twelve located atomic
negative cases cover invalid byte/range/cluster and unsupported colour input.
Normalization units also cover exact endpoint mapping and range exhaustion.

The independent Python oracle reconstructs the canonical source and every
painted character's colour directly from original UTF-8 offsets. It decodes
actual CIDs through embedded ToUnicode maps, inspects profile-based colour
operators and semantic order, and compares every glyph position, font size,
page, panel rectangle and semantic role against the plain twin. Monochrome
mutation twins must fail. Actual shape metric reads and line/page candidate
visits are identical within every colour/plain pair. Paint counters record
retained ranges, visited source clusters and range-cursor advances.

MuPDF 1.28.2's default text extractor repeats the parent Code `ActualText`
once per marked-content piece, including the plain control: the two real lines
produce two copies, and their seven colour pieces produce seven copies. The
minimal original PDFs and raw default extraction are retained by reader mode.
The source's parent `ActualText` and once-each real line occurrences are the
existing #45 contract; neither colour painting nor a serializer workaround
changes them. The independent CID/ToUnicode and semantic oracle and PDFBox
extract each character once. MuPDF's separately declared
`-O ignore-actualtext` glyph/ToUnicode extraction must also recover each
character once and in order; default MuPDF extraction is recorded as a reader
limitation, not a passing logical-extraction claim. Rendering uses the original
PDF unchanged.

## Measured token scale and review

The pinned `nightly-2026-10-14-38a3029` dev backend and Zig 0.16.0
ReleaseFast host produce matching arm64mac/x64musl PDF bytes and metrics.
The measurement includes authoring construction, registered fonts, public
preparation/report/emission and the existing independently repeated stage-work
probe. The probe uses black paints with the same explicit boundaries; it
never changes shape/line/page inputs or remeasures by token.

| Rows / foreground ranges | Plain allocations / bytes | Coloured allocations / bytes | Paint cluster visits / range advances |
| --- | --- | --- | --- |
| 60 / 180 | 12,622 / 10,552,080 | 29,557 / 15,001,149 | 1,020 / 180 |
| 600 / 1,800 | 74,121 / 49,007,192 | 248,012 / 118,772,395 | 10,200 / 1,800 |

Both styles have exactly 63/603 shaped runs and visual lines, 2/11 pages,
1,086/10,266 metric reads and line-candidate visits, and 63/603 page-candidate
visits. Colour produces 363/3,603 final paint runs instead of 63/603, each
backed by the original cluster/glyph arenas. The extra run styles, placements,
fragment associations, scene commands and lowered text pieces explain its
allocation cost. It does not multiply shaping or measurement by range count.
Tenfold input/ranges give exactly tenfold paint traversal, with geometric
buffer growth and existing bounded downstream tree/compression work. The
measured whole-fixture allocated bytes grow less than tenfold.

The short whitespace/unicode pair uses 5,919/6,220 allocations and
7,273,988/7,509,399 bytes. The long cross-page pair uses 17,903/18,055
allocations and 14,021,267/14,154,359 bytes. The repeated-source pair uses
6,226/6,523 allocations and 7,371,633/7,511,829 bytes. Their glyph geometry,
source and semantic roles are identical in the independent pair oracle.
These are current measured ratchets, not targets to preserve historical
counts.

All 27 source-family cases pass cross-target byte/work checks. All 11 new
snapshots pass veraPDF 1.30.2 explicitly as PDF/A-4 with zero failed checks,
and the digest-pinned Arlington 1.30.2 model with 9,022 rules each and zero
failed checks. The colour/plain originals comprise 10 PDFs and 34 pages;
PDFBox 3.0.8, MuPDF 1.28.2 and PDFium 7988 render every page at A4 geometry,
with per-page purple/blue/green raster assertions. PDFBox extraction and
MuPDF's declared glyph/ToUnicode extraction preserve non-whitespace character
order exactly; the byte oracle separately proves all canonical whitespace.

Backend, facade and the tested Pdf20/StaticPdfA4 subset are closed by these
checks. A lexer or independent pagination callback is inapplicable to this
presentation-only extension. Human reader/AT review was not performed and is
optional. Full integration and the final ratchet review are recorded below
when complete.

## Integration ratchet review

The complete 487-task comparison run passed every validation task, all 57
fixture builds, every PDF snapshot and deterministic work vector. Existing
non-source cases had identical allocations and allocated bytes. All 16
existing source-block cases kept their allocation counts, work and PDF bytes;
their new source presentation list/span metadata costs 80 allocated bytes in
ordinary cases, 272 in the three-placement identity fixture and 848 across
the original atomic-rejection fixture's repeated preparations. These are
reviewed representation costs, measured on both 64-bit targets; existing
source-byte baselines are updated to the observed current values.

The new foreground-rejection fixture's stricter location assertions build
one expected byte/range prefix per rejection: 12 additional allocations and
648 bytes. This is test evidence construction, with unchanged generation,
work and PDF bytes. The ratchet records that cost explicitly. No existing
PDF snapshot changes, no blanket count acceptance and no preservation of
historical counts are involved.
