# Title and heading faces and per-level heading styles

This slice closes two authoring gaps found while rewriting the gallery:
titles and headings could not use a bold (or any other registered) face,
and every heading level shared one style, so `H1` and `H2` looked the same.

## API

- `Theme.HeadingLevel : [H1, H2, H3, H4, H5, H6]` and
  `Theme.with_heading_level_style(theme, level, style)` replace one level's
  complete text style: face, size, leading, and color.
  `Theme.heading_level_style(theme, level)` reads it.
- `Theme.with_heading_style` still sets all six levels, and
  `with_heading_color` recolors all six. `Theme.heading_style` returns the
  level-1 style. `Theme.with_font` sets the face of the body, the title, and
  every heading level, as before.
- `Theme.with_title_style` and the heading styles accept any face of the
  options' font registry. The level is typed, so no setter can name a level
  the document model does not have.

## Stage contract

Face selection stays a facade fact decided before shaping.
`Pdf.selected_fonts` takes the single-face path only when the title, every
heading level, and every inline role use the body face. Otherwise it takes
the style-face path: the candidate faces are the body face, then each
distinct title and heading face (title, then `H1` to `H6`), then each
distinct inline role face, each prepared once from the registry. A face the
registry does not hold is `InvalidFontResource(UnknownFace)`; with the
packaged face alone there is no second face, so any other face is unknown.

`KernelFacadeShape.build_styled` first checks that every block's style face
is a candidate (`UnsupportedThemeFace` otherwise, a stage precondition the
facade already guarantees), then assigns each plain block's body request its
style face's candidate; generated list labels and rich paragraphs keep the
body face, and a rich text leaf still takes its innermost role face. Only
faces some run uses become output fonts, body first, through the existing
multi-font stages. Nothing downstream infers a face: the run's instance is
the selection fact.

`KernelFacadeShape.style_for` resolves a heading's style from its level. A
level outside 1 to 6 never reaches shaping: semantic planning rejects it as
`UnsupportedHeadingLevel`.

Under an ordered font policy every cluster takes the first policy face that
covers it, so a title or heading face cannot apply. It was previously
ignored silently; it is now `text.block_font_policy`, parallel to the
existing `text.inline_font_policy`. A heading whose text its face does not
cover is `text.coverage_missing` located at the heading; no face is
substituted.

The single-face path's face check compared every style face with face
index 0, which assumed the body face was the first registered face.
Registering a bold face before the regular face and selecting the regular
face as the body face was therefore `UnsupportedThemeFace`. The check now
compares with the theme's body face.

The furniture stage had the same assumption: with a single face it
rejected furniture text unless the body face had registry index 0
(`UnsupportedThemeFace`), so a document with page templates whose body face
was registered second could not render its headers and footers. The single
face handed to furniture is the theme's body face by construction, so the
check is removed; a `Pdf.roc` expect registers the built-in face twice,
selects the second as the body face, and renders a page-number footer.

## Ownership and complexity

`HeadingStyles` is a record of six `TextStyle` values inside the opaque
theme, not a list, so a theme allocates nothing new. Candidate lookup scans
at most eight block faces and four role faces per plain block (a constant),
so the styled preparation stays linear in blocks. The faces list is built
once per preparation.

## Evidence

- A `Theme` expect: one level's style changes without touching the others.
- `rich inline heading faces x10` and `x50`: a title and N sections of a
  level-1 heading, a level-2 heading, and a paragraph. The title and
  level-1 headings take the Noto Sans Mono fixture at 17 pt in blue; level-2
  headings keep the built-in body face at 12 pt (checked in a MuPDF render).
  The rich-inline, structure-semantics, and PDF/A-4 validators pass. The
  rejections are an unregistered heading face (`InvalidFontResource`), a
  heading face under an ordered policy (`text.block_font_policy`), and a
  heading `Café` the monospace face does not cover (`text.coverage_missing`
  at `contents[1]`). The pair is linear: 31 and 151 shaped runs (3N + 1),
  41 and 201 lines, 26,077 and 113,969 allocations, and 5.59 MB and 28.93
  MB allocated.
- Every existing case keeps its allocation count, work, and snapshot: the
  default theme's six heading styles equal its former heading style, and a
  theme whose title and headings use the body face takes the single-face
  path exactly as before. The candidate list is built only when a title or
  heading face differs from the body face; a first version that always
  built it added one to three allocations to the four existing role-face
  cases, and that was removed.
- One allocated-bytes change: `reference variant rejections` grows by
  3,840 bytes (110,710,018 to 110,713,858) with the same allocation count.
  The theme now holds six heading styles instead of one, 160 more bytes per
  theme value, and the growth is exactly 160 bytes for each of the case's 24
  rejected variants, consistent with one heap-held theme copy per variant.
  It is inside the 10% ceiling and the recorded value is updated.
