# Explicit chapter scopes (#50)

`Pdf.page_scope` is a layout wrapper with fixed opening and continuation
frames and an explicit short running label or reset. It adds no semantic
container. Headings, destinations and outline entries stay authored content.
Entry and exit start full body pages when necessary; coincident boundaries
coalesce. A scope at the body start may use the document's semantic lead on
physical page zero. An opening frame that cannot place its first required
unit rejects rather than emitting an empty opener. Scopes cannot nest or
appear inside list/callout/table/figure/lead content, and required keeps
cannot cross their boundaries.

Normalization stores dense scope records. Static furniture validation builds
each authored template once and indexes its region span. The flat paginator
advances a monotonic scope cursor at accepted page starts and records the
selected frame and opening/continuation context. Text placement, repeated
table headers, panels, reports and furniture consume those committed facts.
Resolved running text cannot alter the body frame or trigger geometry
inference. Scope-specific geometry lookup for figures uses an indexed range
search, and repeated furniture visits only the selected template's regions.
There is no per-page scan of all scopes or all template regions.

Scopes and templates remain immutable shared inputs. Growing template,
region, text and accepted-page arenas are uniquely owned during construction;
continuations hold scalar positions, not copies of remaining authored
content. Running strings are formatted and shaped under the existing
bounded furniture rules. Static labels, exact font/style/language and field
reservations determine furniture source reuse. Empty/reset labels emit no
text source or glyph; whole-document page and total fields keep their meaning.

The `tests/page_templates` family records these native baselines:

| Case | Pages | Roc allocations | Allocated bytes | Scope visits | Region visits |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2 chapters | 6 | 93,012 | 50,101,969 | 10 | 18 |
| 20 chapters | 42 | 866,711 | 469,042,045 | 82 | 126 |
| No document template | 3 | 48,286 | 27,495,591 | 5 | 6 |
| Explicit label reset | 4 | 49,748 | 28,576,016 | 6 | 12 |
| Six atomic rejections | 1 accepted control | 3,569 | 4,842,968 | — | — |

The 2/20 pair places 4/40 scoped pages and 2/20 opening pages. Exact scope
visits are `2 * scopes + accepted pages`, including both entry/exit boundary
processing. Region visits grow with accepted pages, not the product of
pages and templates. The tenfold authoring increase grows allocations
9.32 times and allocated bytes 9.36 times; fixed front/ending pages account
for the smaller page factor. Exact allocation/work and the existing 10%
requested-byte guard remain registered for every focused case.

`check_chapter_templates.py` derives chapter starts from actual structured
H1 marked content. It checks no omitted/duplicated paragraphs, no blank
boundary pages, exact artifact running labels and global fields, reset and
unscoped restoration, and body glyphs within each declared frame. Reserialized
header-classification mutations must reject. Six public negatives cover empty
and nested scopes, a scope in a list item, an unusable opening frame, and both
sides of required keeps crossing scope boundaries. Rejections emit no PDF.

The [combined technical manual](technical-manual.md) extends the evidence to
nested panels, source, prepared vector figures and continued tables inside
scopes, with destination-page references and a reference in repeated table
header artifacts. Its independent geometry oracle, PDF/A-4 validation and
whole-file PDFBox/MuPDF lanes pass on native output. The complete integrated
harness and cross-target equality remain pending; provisional x64musl schema
fields are not observed evidence, and no new PDF/UA-2 claim is made.
