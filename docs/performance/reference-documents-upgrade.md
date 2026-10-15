# Reference documents upgrade

This slice implements `reference-documents-v12` of
[docs/reference-documents.md](../reference-documents.md): the tax invoice,
business report, and business letter move from the built-in RocPdfSans face
to vendored OFL faces with real Bold and Italic and are restyled to match
the rest of the gallery. It also closes the deferred items of the idiomatic
API audit ([idiomatic-api.md](idiomatic-api.md)), tidies the test fixtures,
fixes a quadratic allocation in multi-face output that the new references
exposed, and rebaselines the allocated-bytes drifts left by earlier slices.

## The references

| Reference | Faces | Changes |
| --- | --- | --- |
| Tax invoice | Source Sans 3 Regular, Bold | Logo over a navy and brass masthead rule; continuation header inset above a hairline and footer below one; striped details table with navy row headers; items table with white-on-navy column headers, striped hairline-ruled rows, and totals on a brass tint. Two pages instead of three. |
| Business report | Source Sans 3 Regular, Bold, Italic; Source Code Pro Regular | Navy cover band with the reversed mark; running header and footer over hairlines; callout labels in `Strong` with a navy accent bar; Figure 1 with real drawing labels (axis values, bar values, region names, unit, labelled legend) instead of seven-segment digits and unlabelled swatches; a generated 966 × 520 JPEG for Figure 2 (`scripts/build_report_photo.py`) instead of a 128 × 69 one; shaded and ruled tables, Table 2's shares widened so supplier names fit one line. Four pages instead of five. |
| Business letter | Literata Regular, Bold, Italic | Mark above a navy and brass letterhead rule; the sender's address in slate through `Pdf.scoped`; footer and continuation header on hairlines; the enclosure title in `Em`; a shaded, ruled schedule. Three pages, as before. |

The fonts are byte-identical copies of the files already vendored for the
operations handbook and field guide (same upstream archives and digests),
stored beside each example and recorded in `assets/provenance.json`. The
fixture modules import the same files, so `tests/reference_documents` still
produces the gallery PDFs byte for byte. Each fixture registers its faces at
run time through the case's runtime zero (`max_bytes: 2000000 + guard`), so
no registration is evaluated at compile time.

Every adverse variant keeps its outcome; where a variant depended on the old
face's metrics it was re-measured and the amendment is recorded in the
contract: page fields (50, 60, 62, and 12 pt), INV-A5's 36 rows, REP-A1's
620 pt and REP-A2's 420 pt spacers, REP-A6b's 710 thousandths, and longer
INV-A1 and LET-A1 lines so they still wrap. REP-A5's ordered policy cannot
set drawing labels (`text.drawing_label_policy`), so it places Figure 1
without labels; its alternative text and caption are unchanged.

## Defect: quadratic bytes in multi-face output

The first run of the new invoice scale pair showed allocated bytes growing
18.5× for 10× the rows while allocation counts stayed linear (rows
100/200/300/400: 121, 283, 500, 774 MB). Removing theme features one at a
time isolated it to a second output font: with only the regular face the
growth was linear. A `gdb` trace of every `roc_alloc`/`roc_realloc` above
30 kB at 200 rows attributed 97 MB to one site,
`KernelFacadeOutput.build_multi_plan` line 196: each run's glyph usages
were appended to a per-font list read out of `$usages_per_font` while the
outer list still held it, so every append copied the font's whole usage
list. The list is now taken out (`list_set(..., [])`) before it grows,
following [lowering-uniqueness.md](lowering-uniqueness.md). Bytes no longer
change; the same rows now allocate 91, 171, 253, 334 MB.

The defect predates this slice and affected every document with more than
one output font (all gallery examples with a Bold face). The cases it moves
are rebaselined below.

## Evidence

- `tests/reference_documents`: 21 cases, the 24 rejections unchanged in
  code and paths, snapshots regenerated and reviewed page by page with
  MuPDF 1.28.2 at 100 dpi.
- `check_reference_documents.py --self-test`: `dc:title`,
  `DisplayDocTitle`, `/MarkInfo`, `/Tabs`, and 45 `/SD` + `/D` pairs
  resolved to their headings (the heading-line bound is now the report's
  21 pt H1 leading).
- `check_structure_extraction.py`: PDFBox and the byte-level checker agree
  on every reference snapshot.
- veraPDF PDF/A-4 and Arlington through the harness validators, and on the
  gallery PDFs.

### Scale pairs

| Workload | Pages | Fragments | Allocations | Allocated bytes |
| --- | --- | --- | --- | --- |
| Invoice rows 50 / 500 | 3 / 21 | 376 / 3,415 (9.08×) | 48,627 / 357,554 (7.35×) | 53.5 / 421.2 MB (7.88×) |
| Report sections 10 / 100 | 4 / 37 | 241 / 2,401 (9.96×) | 39,822 / 324,152 (8.14×) | 48.1 / 440.1 MB (9.15×) |
| Letter paragraphs 20 / 200 | 5 / 31 | 191 / 1,361 (7.13×) | 39,065 / 240,044 (6.14×) | 35.2 / 202.3 MB (5.75×) |

## Reviewed rebaseline

One cold run (`--compare-baselines`, a fresh `XDG_CACHE_HOME`, 4 workers)
reported 54 cases; every other case and every PDF byte matched. Each move is
explained here; no work counter moved outside the reference family.

| Cases | Allocations | Allocated bytes | Cause |
| --- | --- | --- | --- |
| The 21 reference cases | new | new | The new faces, themes, and documents (scenario revision `-v12`; pages and work counters change with the composition). |
| Multi-face scale pairs: flow figures label faces x10/x50, rich inline heading faces, scaled code, and shared source faces x10/x50, page templates ordered policy | −142 to −2,369 | −2.6% to −33% | The multi-face usage-list fix: the larger member of each pair moves most, as a quadratic term should. |
| Other multi-face cases (rich inline code face, ordered spans, text-layout multi-face retention and output, built-in face through a registry) | −1 to −150 | −16 to −296 kB | Same fix, small documents. |
| Page templates, custom block, flow figures, and tables fixtures | −40 to +1 | −12 kB to +120 B | The fixture tidy and `Pdf.DocumentProps`: literal points instead of `points(n)` calls and documents built in one record. An A/B build of `page templates backdrops x3` with the package's `.raw()` comparisons restored measured identical allocations, so the ordering rewrite is allocation-neutral. |
| flow figures labels x10/x50 | −5 | +384 / +2,944 | Pre-existing drift (+1,000 / +3,560 at clean HEAD), bisected to 5552b35 "Set drawing labels in inline role faces": each label carries a boxed face choice. |
| tables ruled grid x40/x400 | 0 | +368 each | Pre-existing: the transparent `Theme` record of 6d490cd is 368 bytes larger per heap copy (recorded in idiomatic-api.md). |
| text-layout multi-face missing coverage and undeclared script negatives | 0 | +8 each | Pre-existing since before f622e7d (the baseline dates from 4ef77cd); the intervening theme-field commits grow the one themed document. Older commits fail the pinned compiler's formatter, so the bisection stops at f622e7d. |

The pre-existing drifts of clean HEAD (flow labels +1,000/+3,560,
reference rejections +6,312 of which +1,152 came from e28bab5's column rule
and frame fields, +768 from 20179e8, and +4,416 from 6d490cd's theme
record, the multi-face negatives +8, rich inline code face −3, and tables
+368) were bisected over clean commits with the harness and are absorbed in
this rebaseline with the causes above; none is a defect.

## Deferred and open

- The report's first two pages end with white space, because Figure 1 and
  Figure 2 do not fit below the preceding content and move whole with
  their captions.
- Table header cells have no face option, so column headers are set in the
  regular face (white on navy in the invoice).
- `Err(e) => Err(e)` pyramids (audit B7) remain.
