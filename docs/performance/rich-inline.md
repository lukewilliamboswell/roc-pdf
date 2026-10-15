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

**Namespaces (reference-documents closure).** `Code` and `Quote` are PDF 1.7
standard structure types: ISO 32000-2 14.8.6 does not define them in the
PDF 2.0 namespace, and PDF/UA-2 8.2.4 requires every element to belong to
(or be role mapped to) a standard namespace. veraPDF 1.30.2 PDF/UA-2
therefore reported `http://iso.org/pdf2/ssn:/Quote` (and `Code`) as
unmapped. Their nodes are now in a second namespace, the PDF 1.7 standard
namespace `http://iso.org/pdf/ssn` (`Pdf17`, namespace index 1), which the
facade declares only when a `Code` or `Quote` node exists. The kernel
accepts that namespace only at index 1 and only for those two roles
(`KernelSemantics.role_namespace`); every other role stays PDF 2.0, so no
`/RoleMap` is needed. The five snapshots holding `Code` or `Quote` gain one
`Namespace` object (+157 to +164 bytes, +8 to +13 allocations; work
unchanged); `check_structure_semantics.py` checks each element's namespace
against its role, with two twins.

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

## Shared sources with different face splits

Identical text interns to one source (`KernelFacadeSources`), so a table
cell `10` and a strong cell `10`, or a plain and a strong paragraph with the
same text, share a source. Under role faces those occurrences need
different font splits, but `KernelShape.shape_selected_batch` required every
group over one source to carry the identical split and rejected the second
with `SelectedRequestInvalid({ reason: SplitMismatch })`, which the facade
reported as `UnsupportedAuthoringContent`. The release notes hit it with a
strong `—` beside a plain `—` in the compatibility table.

The shaper now treats a group's split as that group's fact. The first
group over a source defines its primary split, as before. A later group is
compared cluster by cluster with the primary split while it agrees; at its
first differing cluster it copies the primary split (whose earlier clusters
it matched) and records its own fonts from there. When such a group
completes, its split becomes a variant with its own glyph template, built
once from that group's clusters in pass two, and every request of the group
reads that template in pass three. Variants are not deduplicated against
each other: a differing group costs exactly its own cluster count in
template work, so the total stays linear in the requested clusters instead
of comparing every variant with every other. Identical splits (the common
case) allocate nothing new: the variant list and the per-request variant
index stay empty until a split first differs, so every existing case keeps
its allocation count, allocated bytes, work, and snapshot. The pass-three
consistency check that each template glyph's font is the request's font is
kept as an internal invariant. The ordered-policy path is unchanged: it
selects once per unique source, so its occurrences share one split by
construction.

The line-template cache had the same hidden assumption. `KernelLineLayout`
keyed a logical run's template by (source, first instance, size, width),
documented as complete because "one policy per build makes the physical
split of a source deterministic". With per-occurrence splits it is not: a
plain paragraph and the same text whose second half is strong both begin
with a body-face run, so the second reused the first's line breaks and its
wider strong text overran the right margin (seen in a MuPDF render before
the fix). The logical key now also carries a signature over the exact
physical-run sequence (each run's instance, size, and cluster count) and
the defining run range, and an equal signature is confirmed run by run, so
a collision never shares lines. The probe hash is unchanged (the same base
fields as `hash_key`: source, first instance, size, and width), so documents
with one split per source probe exactly as before. The key stays four words
(source and run count as `U32`, first run, signature, width): a first
version that added the signature and run range to the old fields made each
key eight words, and the key list's growth then reallocated one to four more
times in 47 existing cases (for example `rich inline mixed` went from 18,557
to 18,559 allocations) with no change in work. At four words every existing
case keeps its exact allocation count, allocated bytes, and work.

Evidence, `rich inline shared source faces x10` and `x50`: N table rows
with a plain `10`, a strong `10`, a strong `n/a`, and a plain `n/a`; N
pairs of plain and strong `Revision 10` paragraphs; and one paragraph
twice, plain and with its second half strong. The Noto Sans Mono fixture is
the strong face. Each occurrence paints in its own face and the half-strong
paragraph wraps inside the margin (checked in MuPDF renders); the
rich-inline, structure-semantics, and PDF/A-4 validators pass. Strong text
the strong face does not cover (`Café`) is `text.coverage_missing` at its
inline path, never the body face. The pair is linear: 80 and 360 shaped
runs (7N + 10), 81 and 361 lines, 26,965 and 90,561 allocations, and
8.24 MB and 34.18 MB allocated.

## Inline role scale

A monospace face drawn at the body size looks larger than the body text, so
`Theme.with_inline_scale(theme, role, percent)` paints one inline role at 50
to 100 percent of its paragraph size (`Theme.InlineScale : [Inherited,
Percent(U64)]`); the innermost role with a scale decides, as for faces and
colors. The scaled size is a shaping fact: `KernelFacadeShape` gives the
leaf's request the paragraph size times the percentage, rounded down to a
thousandth of a point, so advances, glyph runs, and the PDF `Tf` size all
carry it and no later stage rescales anything.

A scaled run keeps its line's box. Pagination previously required every
physical run of a logical run, and every cell of a table row, to carry one
size, which it used as the baseline offset. It now requires one leading and
takes the largest run size of the logical run (and the largest cell size
of a row) as the baseline offset, so a paragraph or cell that is all code
sits on a baseline at its code size and mixed text shares the paragraph's
baseline. `KernelLineLayout.logical_bounds` no longer requires equal run
sizes; the line-template key's run signature already includes every run's
size, so a scaled and an unscaled occurrence of one text never share line
breaks.

A scale outside 50 to 100 percent is `text.inline_scale` at
`theme.inline_scale.<role>`, checked before any work. Above 100 percent a
run would need a taller line box than its paragraph's leading, which this
slice does not lay out; below 50 percent is not a useful text size. The
check is a top-level function rather than a closure, so it allocates
nothing on the common path.

Evidence, `rich inline scaled code x10` and `x50`: N paragraphs whose `Code`
runs (one nested in `Strong`) paint in the Noto Sans Mono fixture at 85%, a
paragraph that is all code, and a table row whose command cell is all code
(MuPDF render: shared baselines, the code cell aligned with its row). The
accepted boundaries 50% and 100% and the rejected 49% and 101% are checked
in the same case. The pair is linear: 56 and 256 shaped runs (5N + 6), 26
and 106 lines, 47,683 and 201,608 allocations for five preparations each.
Every existing case keeps its allocation count, allocated bytes, work, and
snapshot: without a scale every request keeps the paragraph size, and the
largest run size of a single-size logical run is that size.

## Link style

Links had no presentation of their own. `Theme.with_link_color(theme,
color)` paints link text (inline links and `Pdf.link` blocks) in a color,
and `Theme.with_link_underline(theme, Underline({ offset, thickness }))`
underlines it (`Theme.LinkStyle`, `Theme.LinkUnderline`).

- **Color** is a shaping-stage paint fact like the inline role colors: a
  `Link` or `InternalLink` inline is one more role in the innermost-themed
  chain, so a themed `Strong` inside a link keeps its own color, and a link
  block's style is the body style with the link color.
- **Underline** is a post-layout decoration. `KernelFacadeFragments`
  already owns the exact link facts (each link's occurrences) and every
  final run's placement, so when the theme asks for an underline it emits
  one filled rectangle per painted line run of a link: from the run's
  baseline start across its glyph advances, `offset` below the baseline,
  `thickness` tall, in the run's fill color. A run that ends its line stops
  before the U+0020 spaces it carries; each space is read through a slice
  of the source (`Str.drop_first_bytes`), never a copy. The rectangles
  join the text plan's decoration rules (`KernelFacadeText.Plan.with_rules`,
  merged in page order after the table rules), and scenes paint them as
  `Decoration` page artifacts like table rules. The underline is
  presentation only: the `Link` element, its text, `/Contents`, annotation
  rectangle, and quadrilaterals are unchanged, and it is not tagged content.
- **Validation.** The offset must be non-negative, the thickness positive,
  and together they must fit in the body leading less the body size, so an
  underline never reaches the next line (`text.link_underline` at
  `theme.link_underline`).

Evidence, `rich inline link style x10` and `x50`: N paragraphs whose inline
URI link (with a nested themed `Strong`) wraps across two lines, and N link
blocks, in blue with a 0.6 pt underline 1.2 pt below the baseline. The new
`link_underlines` checker requires every link quadrilateral on every page to
have a `Layout` artifact rectangle inside its extent and below nothing but
its own line; its self-test rejects the `mixed` snapshot, whose links have
no underline. The MuPDF render shows underlines stopping at the last
visible glyph of each line. The rejections are a negative offset, a zero
thickness, and an underline taller than the 3 pt below the body text. The
pair is linear: 16,961 and 76,682 allocations, 4.16 MB and 20.28 MB. No
existing case changes: without an underline no rule is built, and a
document whose theme has no link color resolves every color as before.

## Scoped inline colors

Inline role colors were theme-wide, so one document could not give a
warning callout an amber `Strong` label and a note callout a teal one.
`Pdf.scoped(scope, blocks)` wraps blocks in a `Theme.Scope`
(`Theme.Scope.empty.with_color(Strong, amber).with_color(Link, amber)`;
roles `Code`, `Emphasis`, `Link`, `Quote`, `Strong`). Inside it, the
innermost scope that colors a role decides that role's color, then the
theme; a role the inner scope leaves inherited keeps the outer scope's.

- **Authoring.** `Document.Block` gains a boxed `Scoped` alternative, so
  the block union keeps its size, and normalization records it as a
  `Scope(U32)` group over `NormalizedAuthoring.scopes`, allocated only
  when a document has a scope. A scope may hold whatever a section may,
  including a custom block; it may not appear among list-item content
  (`semantics.list_item_content`, like the other groups), and an empty
  scope is `semantics.scope_empty`.
- **Semantics and layout.** A scope is transparent: like a keep group it
  has no structure element (its children belong to the nearest semantic
  ancestor), and unlike one it is not a keep, so pagination never sees it.
- **Shaping.** Color resolution takes the leaf's block: each role in the
  inline chain, including link text, asks `role_color`, which walks the
  block's group ancestors for a `Scope` that colors the role and otherwise
  answers the theme. A link block asks the same for its link color. A
  document without scopes never walks its groups, so its preparation is
  unchanged. The walk is bounded by the container depth limit per inline
  ancestor, a constant.

Evidence, `rich inline scoped colors x10` and `x50`: N warning and N note
callouts, each scoped (labels and links amber or teal over a dark-red
theme `Strong` and a blue theme link), a nested scope whose inner `Strong`
is teal while its link keeps the outer amber, and a scoped custom block
(MuPDF render). The fixture plans the same content without scopes and
requires equal semantic node, content, and occurrence writes, so a scope
adds no structure. The rejections are an empty scope and a scope in a list
item. The pair is linear: 61 and 261 node writes (5N + 11), 17,949 and
67,493 allocations. No existing case changes.

### Scoped text color (examples showcase)

Scopes colored only the inline roles and links, so a callout's ordinary
text kept the theme's body color and light text on a dark custom-block
panel was impossible. `Theme.ScopeRole` gains `Text` and `Theme.Scope` a
`text` color. Shaping resolves it through the same scope walk
(`role_color`) as the other roles, as the base color beneath inline role
colors: for plain blocks (paragraphs, headings, list items) in
`block_style`, for rich paragraphs as the paragraph color, and for
generated list labels. A table's themed header colors still take
precedence inside a scoped table. A document without scopes returns
before any walk, so no existing case changes its allocation count; the
wider `Scope` record moves the scoped-colors pair's allocated bytes by
under 0.04%.

Evidence: `rich inline scoped text x10` and `x50`: dark-panel callouts
whose scope paints text near-white, `Strong` amber, and links sky blue,
after a slate-scoped heading, bullet list, and table. The semantic plan
with scopes equals the plan without (nodes, content items, and
occurrences), proving scope stays presentation-only. x10: 11,140
allocations, 1 page; x50: 39,732 allocations (3.6×), 4 pages.

## Code spans keep their words whole (examples showcase)

UAX #14 allows a break after a hyphen that precedes a letter (LB21 forbids
a break before `HY`, not after it), so a callout could end a line at
`--lumen-` and start the next with `indigo`. The package implements the
pinned, untailored UAX #14 boundaries (`KernelUnicode` retains every
boundary with its `Tailorable` or `NonTailorable` authority), and the
architecture's business authoring contract makes unbreakable-token
behavior a typed layout policy, so the tailoring is explicit and scoped
to one semantic role rather than a change to the boundary data:

- **Policy (facade).** Inside a `Code` span, each word (a maximal run of
  scalars other than U+0020) withholds its interior tailorable
  opportunities. Opportunities after the spaces between words stay, so a
  long command still wraps between words. No new public constructor is
  needed: `Pdf.code` is where identifiers are authored. A separate
  `Pdf.no_break` inline was considered and not added, because it would
  need a structure element (an inline element always owns one) for a
  purely presentational fact.
- **Facts.** `KernelFacadeShape.Plan.code_holds` derives a block's holds
  from normalized authoring (the `Code` ancestry of each text leaf) and
  the shaped store (each leaf's physical runs and their source scalars):
  one `CodeHold { run, scalars }` per word that has an interior
  opportunity. Words are found with `Str.split_first`, which slices
  without copying, and byte offsets become scalars through the
  boundaries' byte offsets; a block without `Code` costs one scan of its
  inline records and allocates nothing.
- **Kernel.** `KernelLineLayout.Hold` is a scalar range whose interior
  `Allowed`, `Tailorable` boundaries line selection and measurement treat
  as `Prohibited` (`held_decision`, a binary search over the request's
  holds, borrowed as a range of the batch's list). The kernel gives holds
  no other meaning. `BatchPlan.build_logical_held` lays out a request
  with holds outside the template cache (neither probed nor inserted), so
  an equal request without holds never shares its lines;
  `measure_logical_held` measures table cells, and a cell segment with
  holds bypasses the per-source measurement cache for the same reason.
- **Routing.** A document whose runs are all single takes the one-run
  batch only when no code span holds a word; otherwise it takes the
  logical batch, which applies holds.

A code word wider than its container has no opportunity left, so it is
`layout.unbreakable_token` as any unbreakable token: nothing is squeezed
or broken silently.

Evidence: `rich inline code holds x14` and `x140` move a code identifier
across the line end one letter at a time beside a long spaced command and
a table of hyphenated commands. The fixture lays the document out and
counts lines that end strictly inside a held word (0), and lays out the
same document with every code span written as plain text, whose lines
must end inside the identifier at least once (10 and 100 times): the
positions do reach a hyphen break, and the holds prevent it. It rejects a
code word wider than its 40 pt column (`layout.unbreakable_token`).

| Case | Pages | Allocations | Holds | Lines |
| --- | ---: | ---: | ---: | ---: |
| code holds x14 | 1 | 30,515 | 22 | 38 |
| code holds x140 | 8 | 170,320 | 148 | 290 |

The pair is linear. No gallery PDF and no other snapshot changes: no
existing document ends a line inside a code word. `rich inline scaled code`
x10 and x50 paint `roc build --opt=size` in every paragraph, whose
`--opt=size` holds; they gain 56 and 224 allocations (about two per
paragraph per pipeline, and the fixture runs the pipeline twice: the
block's hold list and the document hold list's growth), with allocated
bytes +0.02%. Every other case keeps its allocation count. Earlier drafts
copied each request's holds out of the batch list and materialized each
code leaf's bytes; both were removed after they added allocations to
documents whose code spans hold nothing.

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
- ~~**A distinct face per inline role**~~ (open-issues slice):
  `Theme.with_inline_font(theme, role, face)` selects a caller-registered
  face for `Code`, `Em`, `Strong`, or `Quote` under style faces. The
  `Styled` font selection shapes every run in its innermost role face (or
  the body face) through `KernelFacadeShape.Plan.build_styled`, and the
  faces some run uses become the output fonts, body first, through the
  multi-font stages of the ordered path; furniture shapes in the body face.
  Under an ordered policy a role face reports `text.inline_font_policy`:
  selection is cached per unique source, so a role face cannot override it
  per occurrence. The `code face` case paints `WMS-7` and `code` in a Noto
  Sans Mono ASCII fixture (`scripts/build_mono_font_fixture.py`) beside the
  packaged face, and its checker pins exactly that text to the monospace
  font.
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
- **Unlocated rich-paragraph failures.** ~~Glyph coverage~~ is located by
  the open-issues slice: on a shaping rejection (single face) or a
  selection or script rejection (ordered policy), `KernelFacadeShape`
  scans each source once for failing clusters and reports the first in
  document order as `UnsupportedText` with its block, text inline, and
  scalars (`text.unsupported_script`, `text.unsupported_cluster`, or
  `text.coverage_missing`). Limit failures of the shaper still map to
  `UnsupportedAuthoringContent({ blocks })`.
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
