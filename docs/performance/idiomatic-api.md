# Idiomatic API: records with defaults

This slice changes the shape of the public API, not what it produces. Every
PDF snapshot, every reference-document PDF, and every gallery PDF is
byte-identical before and after it. It implements two design reviews: the
roc-gui default-record idiom, and an audit of the code against the Roc
language reference.

## Design

### Records with defaults

`Theme`, `Pdf.Options`, `Theme.Scope`, and the configuration of the block
constructors are transparent nominal records (`:=`). Each presentation field
declares its built-in value as a `??` default. A caller writes only the
fields it changes, and `{}` means all defaults:

| Record | Defaults | Required |
| --- | --- | --- |
| `Theme` | `face`, `font_selection`, `body`, `title`, `headings`, `inline`, `link`, `table`, `page_margin`, `paragraph_spacing`, `bullet_indent` | none |
| `Pdf.Options` | `profile ?? Archive`, `page_size ?? A4`, `theme ?? {}`, `fonts ?? BuiltIn`, `chunk_retention ?? ShareUnchangedResources` | none |
| `Theme.Scope` | every role `?? Inherited` | none |
| `Pdf.CustomBlock` | `inset ?? 0`, `panel ?? Scene.Drawing.empty`, `fragmentation ?? Unsplittable` | `name`, `contents`, `size` |
| `Pdf.NumberedList` | `start ?? 1`, `style ?? Decimal` | none |
| `Pdf.TableProps` | `header_rows ?? []`, `footer_rows ?? []`, `row_split ?? KeepRows` | `caption`, `columns`, `body_rows` |
| `Pdf.RegionProps` | `start`, `center`, `end ?? []`, `backdrop ?? NoBackdrop`, `slot_inset ?? 0` | `height` |
| `Pdf.FirstPageTemplateProps`, `Pdf.PageTemplateProps` | `header`, `footer ?? Pdf.no_region`, `gap ?? 0`, `lead ?? Pdf.no_lead` | none |
| `Pdf.DecorationProps` | `above`, `below ?? 0`, `layer ?? Front` | `drawing` |
| `Pdf.FigureProps` | `fit ?? Exact` | `drawing`, `alt`, `caption` |
| `Scene.Label` | `align ?? Start`, `color ?? black` | `text`, `origin`, `size` |
| `Scene.AuthorPathStyle` | `fill ?? AuthorNoFill`, `stroke ?? AuthorNoStroke` | none |

Semantic facts have no defaults: the document title, language, contents,
alternative text, captions, a table's columns and rows, and font validation
limits stay required. `Font.ValidationLimits` is unchanged.

These records replace the setters. The following are removed:

- Theme's 31 `with_*` setters.
- `Options.with_*`.
- `Scope.empty` and `Scope.with_color`.
- `Pdf.with_backdrop` and `Pdf.with_slot_inset`. A region's backdrop and
  slot inset are now `RegionProps` fields.
- `Pdf.spaced_decoration`. Its spacing and layer are now `DecorationProps`
  fields.
- `Pdf.figure_fit`. A figure's fit is now a `FigureProps` field.

Each sub-record that has its own defaults is its own nominal type:
`BodyStyle`, `TitleStyle`, `HeadingStyle`, `Headings`, `InlineRoles`,
`InlineStyle`, `LinkStyle`, `TableStyle`, `BodyFills`, and `PageMargin`. A
partial nested literal is completed from its own type's defaults, so a
partial `title` never takes the body's size.

Inheritance is always an explicit tag and is never read from a missing
value:

- A style's face is `ThemeFace` (the theme's `face`) or `Face(id)`.
- A heading level is `SameAsAll` or `Own(style)`.
- An inline role's color, face, and scale are `Inherited` until set.

The getters that preparation reads (`body_style`, `title_style`,
`heading_level_style`, and `inline_*`) resolve these tags into the unchanged
resolved `TextStyle`, so no kernel stage changed.

A default is a documented construction value, never a fallback.
Constructors only copy their fields. Preparation validates every field, as
before, and rejects an invalid supplied value with a located diagnostic; the
default never replaces it. Changing a `??` default is a reviewed
package-version change. architecture.md records these rules.

### Literal points

`Layout.Unit` gains `from_numeral`, so a bare number literal where a unit is
expected means points: `size: 12.5` is 12,500 units. The conversion reads
the literal's digits exactly in `U128`. A literal with more than three
significant decimal places (`0.0005`), or one outside the `I64` range of
millipoints, is a compile error at the literal. Trailing zeros (`12.5000`)
are accepted. `Unit` still has no arithmetic operators, so overflow remains
an explicit, checked result. The `points` helper that every example
defined is gone.

### Language-reference idioms

- `is_eq : _` and `to_hash : _` on every opaque ID, `Layout.Unit`,
  `Font.Script`, and `Semantics.Range`, and `is_eq : _` on `Profile`,
  `PageSize`, and `ChunkRetention`. With these, `.index() == .index()`,
  `.raw() == .raw()`, and `KernelObject.ObjectId.is_eq(a, b)` become `==`.
  The helpers `range_equal`, `ranges_equal`, `text_range(s)_equal`,
  `work_equal`, `facts_equal`, and `key_equal` are gone. Two helpers keep
  their hand-written comparison because they compare external data:
  `paragraph_equal` (its body is now `==` on its fields) and
  `logical_key_equal`. Comparisons between different ID types keep their
  explicit `.index()`.
- The cell modifiers are now methods on `Document.Cell`:
  `Pdf.header_cell(Row, label).spanning(4).shaded(tint)`. Drawings use
  `Scene.Drawing.empty.rectangle(rect, color)`, and `Scene.drawing({})`,
  `Scene.path({})`, and `Scene.rectangle` are removed.
- `Pdf.Error` gains `to_inspect`, which renders each diagnostic as
  `code at path: message`. This output is for people, not a contract.
- `Font.Script` gains `from_quote`, so `scripts: ["Latn"]` is checked at
  compile time by the same rule that registration applies. `as_str` is
  renamed `to_str`.
- 1,410 `##` lines directly above an `expect`, `var`, `if`, or `import` are
  now `#`, and `Bool.True`/`Bool.False` are written `True`/`False`.
- The audit's "don't change" list is respected:
  - indexed loops
  - accumulator shapes
  - no arithmetic on `Unit`
  - no `Dict` or `Set` in the kernel
  - the hand-written diagnostic strings
  - the free `to_bytes_with` and `prepare` functions
  - `list_at`

### Diagnostic paths

| Code | Before | After |
| --- | --- | --- |
| `text.inline_scale` | `theme.inline_scale.<role>` | `theme.inline.<role>.scale` |
| `text.link_underline` | `theme.link_underline` | `theme.link.underline` |

`document.figure_fit` now reports only a `ScaleToFit` floor above 100.
Applying a fit to a block that is not a figure can no longer be written.

## Before and after: examples/product-brief

Before, the theme was built in two steps. A base theme read three styles out
of `Theme.default` and chained 16 setters. A `with_faces` helper then read
the styles again to swap in faces:

```roc
base_theme = {
    body = Theme.body_style(Theme.default)
    heading = Theme.heading_style(Theme.default)
    title = Theme.title_style(Theme.default)
    Theme.default
        .with_body_style({ ..body, color: charcoal, size: points(11), leading: points(16) })
        .with_heading_style({ ..heading, color: forest, size: points(17), leading: points(22) })
        .with_title_style({ ..title, color: forest, size: points(40), leading: points(46) })
        .with_page_margin({ top: points(40), right: points(54), bottom: points(40), left: points(54) })
        .with_table_header_fill(meadow)
        .with_table_rule(Rule({ color: leaf, width: points(1) }))
        # ... ten more setters
}
with_faces = |base, faces| {
    title = Theme.title_style(base)
    heading = Theme.heading_style(base)
    base.with_font(faces.regular)
        .with_title_style({ ..title, font: faces.bold })
        .with_heading_style({ ..heading, font: faces.bold })
        .with_inline_font(Strong, faces.bold)
        .with_inline_font(Code, faces.mono)
        .with_inline_scale(Code, 90)
}
options = Pdf.Options.default.with_theme(with_faces(base_theme, fonts)).with_page_size(Letter).with_font_registry(fonts.registry)
accent = Theme.Scope.empty.with_color(Strong, forest).with_color(Quote, forest)
Pdf.shaded(tint, Pdf.spanning(4, Pdf.header_cell(Row, label)))
```

After, the theme is one record that names only what differs from the
built-in values:

```roc
theme = |faces| {
    face: faces.regular,
    body: { color: charcoal, size: 11, leading: 16 },
    title: { color: forest, face: Face(faces.bold), size: 40, leading: 46 },
    headings: { all: { color: forest, face: Face(faces.bold), size: 17, leading: 22 } },
    inline: {
        strong: { font: Face(faces.bold) },
        code: { color: Themed(rust), font: Face(faces.mono), scale: Percent(90) },
    },
    page_margin: { top: 40, right: 54, bottom: 40, left: 54 },
    table: { header_fill: Fill(meadow), rule: Rule({ color: leaf, width: 1 }) },
}
options : Pdf.Options
options = { theme: theme(fonts), page_size: Letter, fonts: Registered(fonts.registry) }
accent = { strong: Themed(forest), quote: Themed(forest) }
Pdf.header_cell(Row, label).spanning(4).shaded(tint)
```

To derive a theme from another, spread the sub-record you change:
`{ ..base, body: { ..base.body, leading: 16 } }`. A partial nested literal
such as `{ ..base, body: { leading: 16 } }` is completed from `BodyStyle`'s
defaults, not from `base`. This is intended language behaviour.

## Evidence

### PDF bytes

The full `./scripts/test.py --jobs 6` suite was run from a cold cache after
every step: the derived equality, the literal units, the Theme record with
wrapper setters, the props constructors, method chaining, and the port with
setter removal. Each run passed every snapshot and structural validator, so
no fixture or reference-document PDF changed. `scripts/check_gallery.py`
regenerates all ten gallery PDFs byte-identically in both plain and bundle
mode.

### Baseline moves

The defaults add no allocations: no allocation count changed through the
equality, literal, Theme, Options, props, and chaining steps. A literal
default is a compile-time constant, and a record update of a nominal record
copies an inline aggregate.

| Case | Allocations | Allocated bytes | Cause |
| --- | ---: | ---: | --- |
| tables ruled grid x40, x400 | unchanged | +368 each | The theme record is larger. Each level holds a `SameAsAll`/`Own(style)` choice and each style a face choice, which adds 368 bytes to each heap copy of a theme. The increase is the same at x40 and x400, so it does not scale with the document. It is within the ceiling and not rebaselined. |
| reference variant rejections | unchanged | +6,312 | Twelve themed documents at +368 each, plus diagnostic messages that name fields instead of removed setters (24 bytes shorter). |
| rich inline code face | unchanged | −3 | The `text.inline_font_policy` message no longer names a removed setter. |
| semantic foundation container atomic negatives | 9,717 → 10,741 | 10,794,851 → 11,064,908 | The negative that applied `figure_fit` to a paragraph cannot be written any more. The check now uses a nested figure whose `ScaleToFit` floor is above 100, which keeps the five rejections and the `document.figure_fit` code. That runs semantic validation of a figure drawing where the old check rejected at the authoring stage. Rebaselined in spec.json. |
| flow figures atomic negatives | 16,909 → 17,940 | 8,371,891 → 8,642,269 | Same cause: the non-figure case became a sectioned figure with a floor of 255, keeping 14 rejections. Rebaselined. |

The page-template negatives first moved by +2 allocations, because inline
region literals rebuilt their slot lists. Spreading one shared
`RegionProps` (`{ ..header_props, backdrop: Backdrop(tall) }`) returned them
to their exact baselines.

Five allocated-bytes differences predate this slice. A standalone
`--no-cache` build of the clean branch head measures the same values:

- flow figures labels x10: +1,000
- flow figures labels x50: +3,560
- reference variant rejections: +1,920
- the two multi-face atomic negatives: +8 each

They are within the ceiling and left for a reviewed rebaseline.

## Compiler issues

- roc-lang/roc#11922 (already filed): a `??` default cannot name a sibling
  by its bare name. Theme's defaults write `Theme.black`, with a
  `TODO(roc-lang/roc#11922)` comment.
- roc-lang/roc#11946 (filed in this slice): `roc build` crashes while
  lowering nested `??` defaults when a nominal record built at runtime omits
  a field whose own type has defaults.
  - The pinned build segfaults. A debug build of d1b254f577 panics in
    `defaultedFieldValueAtCell` with "instantiation unified a tag union with
    a non-tag-union type". It was reduced to four small package modules on
    the compiler repository's own test platform.
  - `tests/pdf_facade/pdf_facade_chunks.roc` hit it with
    `Pdf.Options.{ chunk_retention: retention }`. It now writes
    `{ ..Pdf.Options.default, chunk_retention: retention }`, with a TODO
    citing the issue.
- A partial nested literal takes the inner type's defaults and does not
  merge with a base. This is intended behaviour. authoring.md documents the
  spread pattern. A Theme expect checks that every nested field default
  equals its type's `X.{}` and that a partial literal resets the omitted
  fields.

## Deferred

- `Layout.Unit` ordering methods (`is_lt` and the others) and rewriting the
  internal `.raw() <` comparisons (audit B5).
- Flattening the `Err(e) => Err(e)` pyramids with `?` (audit B7), which
  needs allocation evidence for each site.
- `from_quote` for `"#RRGGBB"` colors (audit A9).
- Document-level navigation props (`with_outline`, `with_page_templates`,
  `with_created`, `with_modified`, and `with_page_labels` stay methods), and
  defaults on `ReportBudget`.
- The test fixtures were converted mechanically. Many still write explicit
  `Layout.Unit.points(n)` and spell out default-valued fields. Only the
  examples were polished to the idiom.
