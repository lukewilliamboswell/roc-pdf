# Gate 6 rich inline content and nested language

This slice (S4) implements `reference-documents-v3`. It makes
`Pdf.rich_paragraph` and its inline constructors executable: emphasis,
strong, code, quotation, URI and internal inline links, nested language
spans, and abbreviation expansions. A rich paragraph is shaped, broken, and
painted as one paragraph text with per-run theme colors, and every inline
keeps its own PDF 2.0 structure element. It closes no Gate 6 capability as a
whole and makes no PDF/UA-2 claim: `PdfUa2` stays `defined_only`.

## Scope and non-goals

In scope:

- public `Pdf.Inline` with `Pdf.text`, `Pdf.emphasis`, `Pdf.strong`,
  `Pdf.code`, `Pdf.quote`, `Pdf.inline_link`, `Pdf.inline_internal_link`,
  `Pdf.in_language`, and `Pdf.expansion`, and
  `Pdf.rich_paragraph : List(Pdf.Inline) -> Document.Block`, replacing the
  `Str` placeholder;
- `P > (Em | Strong | Code | Quote | Link | Span)*` structure with arbitrary
  legal inline nesting up to 8 inline elements, `/Lang` on language spans, and
  `/E` on expansion spans;
- inline link annotations over wrapped text;
- theme colors for the inline roles;
- stable, located diagnostics for every inline rejection;
- an independent logical-text checker and a harness family.

Not in scope: `Pdf.line_break`, `page_number`, `total_pages`, and
`reserved_width` (see [Open issues](#open-issues)); a distinct face, size, or
leading per inline role; generated quotation marks; inline content in
headings, list items, captions, or table cells; marked-content `/Lang`.

## Authoring and normalization

`Document.Inline` is a recursive nominal union. `Document.Block` gains
`RichParagraph(List(Document.Inline))`.

Normalization lowers each rich paragraph into the dense preorder
`NormalizedAuthoring.inlines` arena with an explicit frame stack, so authored
nesting never becomes Roc call depth. Each `NormalizedInline` records its
kind, parent, authored position, depth, direct child count, element ordinal,
the ordinals of the text leaves below it, the offset of its children in the
paragraph's content spine, and its nearest enclosing `in_language` span.
`code` and `expansion` become an element with one text leaf. The paragraph's
own span record (`NormalizedRich`: arena span, child, element, and leaf
counts, and authored position) lives in the `rich_paragraphs` side arena,
and its block kind names it by index, so plain blocks keep their compact
normalized kind.

The paragraph's normalized `text` is the concatenation of its leaves in
logical order, built once with an exact-capacity `Str` (or shared unchanged
when the paragraph has one leaf). Each leaf records its exact byte range of
that text. The paragraph is therefore **one interned source**: Unicode
analysis, line-break opportunities, script itemization, and grapheme
segmentation are computed over the whole paragraph, so UAX #14 sees the text
on both sides of every inline boundary.

## Semantic planning

`KernelFacadeSemantics` validates a rich paragraph's span in preorder before
any store is built; the first failure in authored order wins:

| Code | Family | Cause |
| --- | --- | --- |
| `semantics.inline_empty` | `InvalidRelationship` | The paragraph has no text leaf; an inline text, code, or expansion is empty; an element holds no text; an expansion's expanded text is empty |
| `semantics.link_text_empty` | `InvalidRelationship` | A link holds no text |
| `semantics.nested_link` | `InvalidRelationship` | A link has a link ancestor (a parent-chain walk bounded by the depth limit) |
| `semantics.inline_depth` | `BudgetExceeded` | More than 8 nested inline elements |
| `semantics.language_tag` | `InvalidLanguage` | An `in_language` tag fails `KernelSemantics.language_tag_valid`, the predicate graph validation applies to `/Lang` |
| `semantics.link_uri` | `InvalidRelationship` | An inline URI fails `KernelNavigation.check_uri`, the grammar annotation validation applies later |

It then plans one `P` node, one node per inline element in preorder (roles
`Em`, `Strong`, `Code`, `Quote`, `Link`, and `Span`), and one content
occurrence per text leaf. The paragraph reserves a contiguous content-spine
span of one slot per inline record, and each record is written at its
parent's precomputed spine offset plus its authored position, so every node
owns exactly one contiguous span in authored order without a sort.

Each leaf occurrence names an exact sub-range of the paragraph source. The
leaf's scalar range comes from the source's dense per-scalar boundary facts
with one forward cursor per paragraph. An expansion's node owns one
`ExpandedText` property, lowered as `/E` by the existing node lowering. A
language span's node carries `Language(tag)`; the existing lowering emits
`/Lang` only where it differs from the inherited language.

**Why node-level `/Lang` suffices.** A leaf occurrence carries the language of
its nearest `in_language` span, which is exactly the effective language of
the node that owns it: every language change creates a `Span` that owns all
of its text. ISO 32000-2 14.9.2 gives marked content the language of its
structure element, so no marked-content sequence ever differs from its
owner, and marked-content `/Lang` is never needed. This is a construction
fact of facade planning; the kernel graph validator does not re-derive
occurrence languages.

Inline links produce link records with a dense occurrence range: the text
leaves below the link, which are contiguous in leaf order.

## Shaping, lines, pages, and text

A document without a rich paragraph takes the exact previous whole-source
preparation. A document with one takes a ranged preparation in which every
request carries its exact cluster range of its source, the occurrence's
natural language, and the occurrence's origin in the source.

- **Single face.** Ranged requests shape through the selected batch shaper
  with the one resolved face, so each occurrence shapes exactly its own
  clusters. `KernelShape.SelectedBatchRequest` carries a per-request
  `language`, which becomes the run's language fact; runs in different
  languages of one supported script shape together. The selected shaper's
  coverage groups are full passes over a source, which a rich paragraph's
  consecutive occurrences form.
- **Ordered policy.** Coverage selection still runs once per unique source
  (the paragraph). Each occurrence's cluster range is intersected with the
  source's face/script segments with one forward cursor per logical run.
- **Scripts.** Before shaping, each leaf's overlapped itemization runs must be
  Latin, Common, or Inherited (single face) or also Han (ordered); otherwise
  the paragraph rejects as `text.unsupported_script`, naming the leaf. A leaf
  boundary inside a multi-scalar grapheme cluster rejects as
  `text.unsupported_cluster`.
- **Styles.** Every leaf paints in the paragraph's face, size, and leading.
  Its color is the innermost themed inline role around it
  (`Theme.with_emphasis_color`, `with_strong_color`, `with_code_color`,
  `with_quote_color`), else the paragraph color. The package ships one
  regular face and produces no synthetic bold or oblique; a distinct face per
  role is an open text-matrix row.
- **Lines.** The rich paragraph is one logical run over its physical
  per-occurrence runs, measured by the existing logical line batch. Line
  selection needs only clusters, advances, and the shared size, so
  `KernelLineLayout` no longer requires one occurrence per logical request.
  The template cache key (source, first instance, size, width) remains
  complete because widths depend only on the per-source face split and the
  paragraph size.
- **Pages.** Pagination requires only equal size and leading across a
  logical run's physical runs; colors are paint facts.
- **Text.** The materializer splits each line into one final run per
  overlapped occurrence run and rebases every final run and cluster from
  source coordinates to its occurrence (`KernelFacadeShape.Origins`), the
  occurrence-relative contract of the final text store, fragments, and
  lowering. `WholeSources` states that no rebasing is needed.

## Link annotations

An inline link keeps the facade contract: one annotation per page its text
is painted on, with the page's painted line boxes as quadrilaterals and their
union as the rectangle. Adjacent runs of one link on one line (a link
containing emphasis) extend that line's quadrilateral instead of adding one,
so each painted line contributes exactly one quad. A link that wraps across a
line break has one quad per line; across a page break, one annotation per
page. Each link box now uses its own run's leading (see the rebaseline below).

## Ownership, copying, retention, and complexity

- **Normalization** is O(inline records + text bytes) per paragraph: one frame
  stack and one exact-capacity text concatenation.
- **Planning** is O(records) for validation, spine placement, and node and
  occurrence writes, plus O(scalars) for byte-to-scalar conversion; link
  ancestry and color resolution walk parent chains bounded by the depth
  limit (8).
- **Shaping preparation** is O(requests + graphemes + script runs) per
  paragraph with forward cursors; the ordered expansion is O(requests +
  segments) per logical run.
- **Lines, pages, text, and fragments** keep their existing bounds; the link
  owner map is one flat pass over the links' occurrence ranges.
- **Retention**: the inline arena lives in the normalized authoring value,
  shares the authored leaf strings, and is released with it; nothing new is
  retained past preparation. Plain documents allocate no ranges or origins.
- **Diagnostics** rebuild the normalized arenas only on the rejection path to
  reconstruct the authored path.

## Evidence

**Package expects.** `KernelFacadeSemantics`: exact roles, spine spans,
occurrence scalar and byte sub-ranges, span languages, and ownership of a
nested rich paragraph; empty, nested-link, language, URI, blank, and depth
rejections. `Pdf`: every inline role, `/Lang`, `/E`, and a link annotation in
public output; nested-link and empty-inline rejections with their paths.

**Harness family** `tests/rich_inline` (`rich-inline-v1`, pinned
`nightly-2026-09-26-d6267b4`, cold cache, full harness order):

| Case | Pages | Allocations | Work |
| --- | ---: | ---: | --- |
| mixed styles, links, languages, and expansions | 1 | 27,430 | 34 nodes, 16 inline elements, 40 occurrences, 17 lines, 43 final runs, 2 link annotations |
| paragraphs x10 | 1 | 67,780 | 92 nodes, 80 inline elements, 171 occurrences, 21 lines, 181 final runs, 10 link annotations |
| paragraphs x100 | 6 | 635,809 | 902 nodes, 800 inline elements, 1,701 occurrences, 201 lines, 1,801 final runs, 100 link annotations |
| ordered multi-face spans | 1 | 3,788 | 5 nodes, 3 inline elements, 3 shaped runs on two faces, 1 line |
| inline atomic negatives | 1 | 18,460 | 12 rejections, 8-deep boundary accepted |

The mixed case colors `Strong`, `Em`, and `Code` through the theme, places
French spans (one inside a `Quote`), two expansions, and a three-deep
`Em > Strong > Code` nesting inside a section beside a bulleted list and a
plain paragraph, links `section 3, Operations` (plain text and `Em`, one
merged quadrilateral) to a destination heading, and wraps a URI link
containing `Strong` over three lines (one annotation, three
quadrilaterals). The ordered case shapes `Café` (`fr`), `中` (`zh-Hans`),
and `PDF` (`Em`) through a caller Latin and Han policy.

The negatives are an empty rich paragraph, an empty text leaf, an empty
`strong`, an empty link, a link inside emphasis inside a link, 9-deep
emphasis, the tag `fr_CA`, the URI `harbourfinch example`, a Greek span, a
combining acute accent split from its base letter, and an empty `strong`
inside a section. Each returns its stable code and exact inline path and no
bytes; an inline internal link to an unknown destination stays the typed
`InvalidNavigation(UnknownDestinationName)`, and 8-deep emphasis is accepted.

**Linear scale pair.** From x10 to x100 (10× the rich paragraphs, each with
eight inline elements and a link), nodes grow 9.8×, inline elements and
leaves 10×, content-spine writes 9.9×, shaped runs 9.9×, lines 9.6×, final
runs and fragments 9.9×, link annotations 10×, and allocations 9.4×. All are
within the linear bound.

**Independent checker.** `scripts/check_rich_inline.py` (validator and
preflight `rich_inline`) decodes every shown CID through its font's embedded
`/ToUnicode` CMap and walks the structure tree in `/K` order. For each
document it requires that the logical text in structure order equals the
text in content-stream (paint) order, that every inline element owns text,
that `/E` appears only on `Span`, that every `Link` owns at least one OBJR
(with paired `/SD` and `/D` for internal links), and the dimension counts of
inline elements and link annotations. Its self-test pins the rendered inline
structure of the mixed and ordered snapshots, for example

```text
P: Our oak supplier [Span Lang=fr:Atelier Beaulieu] puts it simply: [Quote:[Span Lang=fr:« Le bois ne ment pas. »]] Read
   [Link (uri https://harbourfinch.example/sustainability):our published sustainability commitments, including the
   [Strong:2026 timber audit] and its appendix] before the next review.
```

and rejects four mutation twins for their intended reasons: structure order
swapped against paint order, a `Link` without an OBJR, `/E` on a non-`Span`
role, and a font without `/ToUnicode` mappings. `--pdfbox-extraction`
compares PDFBox 3.0.8 extraction of the mixed snapshot with its exact
expected lines.

**External lanes.** veraPDF PDF/A-4 `--cases` passes all 29 Archive
snapshots, including the five rich-inline snapshots, with zero failed
checks; `--standard-cases` fails only the deliberate omissions. Arlington
`--cases` passes on every snapshot and gallery example. PDFBox 3.0.8
extracts the mixed snapshot's exact expected lines. The gallery is
unchanged and `check_gallery.py` passes.

## Reviewed rebaselines

Every delta below comes from a cold-cache, full-order run. Each cause was
confirmed by a cold-cache, full-order A/B run that differs only in the named
change.

**Bytes: 3 snapshots.** `archive_navigation`, `archive_navigation_64`, and
`archive_navigation_standard` each change one link annotation: its `/Rect`
and `/QuadPoints` bottom rises by 4 pt (for example `452` to `456`), plus
the dependent trailer `/ID`; lengths are unchanged. The facade link box took
its leading from the style indexed by the run's *occurrence* id, which after
a multi-line block named an unrelated 18 pt heading run; it now uses the
painted run's own 14 pt body leading. Annotations have no appearance, so
rendering is unchanged. No other snapshot or gallery PDF changed.

**Allocations: one case.** Ordered multi-face scale x1000 goes from 320 to
319. `KernelShape.SelectedBatchRequest` gains the per-request `language`, so
the unreserved selected-request list (3,000 physical runs) takes one fewer
byte-size-dependent growth step at this size and the same number at 10,000
(x10000 is unchanged). The A/B without the field restores 320.

**No per-document or per-run cost.** Two intermediate regressions were found
and removed during review:

- **+2 per shaping request** in every facade document (batch shaping x10000
  went from 1,308 to 21,319). Threading the ranged request buffers through
  the shared block loop made the request and style lists non-unique, so
  every append copied. Documents without rich paragraphs now take the
  unchanged whole-source preparation. Ranged documents are prepared in a
  separate function whose per-block helpers take the buffers as separate
  arguments.
- **−1 at 10,000 blocks** in six authoring cases. Carrying the rich record
  inline in `NormalizedBlockKind` grew every normalized block by 16 bytes and
  changed the blocks list's growth steps. The records now live in the
  `rich_paragraphs` side arena and blocks name them by index, so plain blocks
  keep their compact kind.

**Work counters.** No existing work counter changed.

**Transient compiler crash.** The pinned compiler did not segfault in any of
this slice's seven full and two early-stopped parallel harness runs.

## Readiness dimensions

| Dimension | Status |
| --- | --- |
| Backend | Executable: ranged shaping, logical lines over occurrence runs, occurrence rebasing, and inline link annotations, with allocation and work evidence |
| Facade | Executable for `Pdf.rich_paragraph` and the inline constructors with stable located diagnostics |
| Advanced integration | `Document.NormalizedInline` arena; no separately authored consumer |
| Conformance | Inline roles, `/Lang` spans, `/E`, and inline link annotations pass PDF/A-4, Arlington, and the structure and rich-inline checkers; ledger row `ROC-PDF-PDF20-INLINE-SEMANTICS`; `PdfUa2` stays `defined_only` |
| Reader and AT behavior | Not performed (optional) |

## Open issues

- **`Pdf.line_break`** and the furniture-only inlines are not executable. A
  line break needs a mandatory break inside one paragraph source without a
  painted glyph and without a cache identity collision between paragraphs
  that differ only in break positions. The invoice and letter address blocks
  that use `⏎` depend on it.
- **A distinct face per inline role** (a monospace `Code`, an italic `Em`) is
  not selectable; inline roles change only color. This is a required
  text-matrix row, and it needs per-style multi-font output on the
  single-face path.
- **Inline content elsewhere.** Headings, list items, captions, and table
  cells still take plain strings.
- **Ordered selection language.** Coverage selection runs once per paragraph
  source with the document language. A span's language does not influence
  face selection, because the convenience planner has no language-sensitive
  selection. REP-A5's spaces around a Han span still reject through the
  open Common-run row (`Café 中 PDF` reports `UnsupportedBuiltInShaping`),
  so the ordered fixture uses `Café中PDF`.
- **Occurrence languages** are a facade construction fact. The kernel graph
  validator does not re-derive them against their owning element, and no
  marked-content `/Lang` exists.
- **Unlocated rich-paragraph failures.** Glyph coverage on the single-face
  path and limit failures still map to the unlocated
  `UnsupportedAuthoringContent({ blocks })`. Only the inline-specific
  failures above carry a path.
- **Diagnostic placement.** A leaf boundary inside a multi-scalar cluster is
  reported on the first leaf whose boundary falls inside it, which is the
  leaf before the split.
- **Pre-existing lowering facts, unchanged.** Every MCID-bearing sequence
  uses the `/P` marked-content tag regardless of its owner's role. A link's
  line box includes the painted trailing space before a soft break.
- **Roc quirk.** On the pinned compiler, a `var` reassigned inside a `match`
  that is itself a function argument lost the reassignment: an expansion
  property vanished and planning crashed. Statement-form reassignment is
  used instead.
