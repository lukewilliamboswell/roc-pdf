# Choose built-in and caller fonts

Ordinary `Pdf.to_bytes` documents use Inter for body text and headings. Inline
code and source blocks use Fira Code automatically; no files or registry setup
are required:

```roc
import pdf.Pdf

example = Pdf.document({
    title: "A short report",
    language: "en-AU",
    contents: [
        Pdf.paragraph("Body text"),
        Pdf.rich_paragraph([Pdf.strong([Pdf.text("Strong")]), Pdf.emphasis([Pdf.text("Emphasis")])]),
        Pdf.source_block({ text: "answer = 42" }),
    ],
})
bytes = Pdf.to_bytes(example)?
```

To select Merriweather for serif typography, set the theme's family:

```roc
options : Pdf.Options
options = { theme: { family: BuiltIn(Serif) } }
bytes = Pdf.to_bytes_with(example, options)?
```

A family choice selects one exact face for each requested style. Strong text
uses Bold, emphasis uses Italic, and nested strong/emphasis uses Bold Italic in
either nesting order. Titles and headings default to Bold. Code retains its
selected family while applying those style requests. Quote inherits its
surrounding family unless explicitly configured. Sizes, leading, colours and
spacing remain theme settings.

| Family | Regular/Bold | Italic/Bold Italic | Command symbol U+2318 |
| --- | --- | --- | --- |
| Inter 4.1 | Available | Available | Available in all four faces |
| Merriweather 4.009 | Available | Available | Missing in all four faces |
| Fira Code 6.2 | Available | Unavailable | Available in both faces |

The unchanged source character maps contain these per-face repertoires; this
does not extend the single-scalar Latin shaping contract:

| Faces | Mapped scalars per face | Convenience shaping |
| --- | --- | --- |
| Inter Regular/Bold | 2,852 | Single-scalar Latin |
| Inter Italic/Bold Italic | 2,816 | Single-scalar Latin |
| Merriweather Regular/Bold | 1,423 | Single-scalar Latin |
| Merriweather Italic/Bold Italic | 1,422 | Single-scalar Latin |
| Fira Code Regular/Bold | 1,586 | Single-scalar Latin |
| Fira Code Italic/Bold Italic | Unavailable | Rejected |

The package uses the ten unchanged upstream static TTF files published by
roc-font 0.1.0-rc4. Measurement and embedding use the same selected bytes, with
Regular at weight 400 and Bold at 700. No runtime variation axes or font
instancing are involved. Supported convenience shaping remains single-scalar
Latin text; glyph coverage does not add script or combining-mark shaping.
Italic repertoires can differ from upright ones.

Unavailable styles return located `text.style_unavailable` diagnostics naming
the selected family and style. Uncovered characters return located
`text.coverage_missing` diagnostics. For example, serif Command-K text fails,
and emphasis within default code fails because Fira Code has no genuine
italic. No font is substituted and no style is synthesised. These unsupported
requirements are tracked in [roc-font's coverage/style issue](https://github.com/lukewilliamboswell/roc-font/issues/13)
and [Fira Code's italic issue](https://github.com/tonsky/FiraCode/issues/134).

Caller fonts remain explicit. Register bytes with
`registry.register({ bytes, registration, limits })` and pass the returned
registry in `Pdf.Options.fonts`. A theme with `family: FromOptions` uses
`theme.face` as that caller family's Regular face. Requested Bold, Italic and
Bold Italic need an explicit family mapping or matching role override:

```roc
family = {
    regular: regular.face,
    bold: Available(bold.face),
    italic: Available(italic.face),
    bold_italic: Available(bold_italic.face),
}
options : Pdf.Options
options = { fonts: Registered(registry), theme: { family: Registered(family) } }
```

Use `Unavailable` for a missing style. `theme.inline.strong.font`,
`theme.inline.emphasis.font` and `theme.inline.strong_emphasis.font` accept
exact `Face(id)` overrides. A combined request needs its combined face; an
upright or single-style face is never chosen implicitly. Inline family
choices use `Family(BuiltIn(Serif))` or `Family(Registered(family))`.

`theme.source_code` chooses the default source face, independently of the
body and inline code. A source block can override it with `face: Face(id)`
or `face: BuiltIn({ family: Mono, style: Bold })`. Explicit title, heading and
furniture `Face(id)` overrides continue to select registered faces.

`RocFont.register(registry, Font.ValidationLimits.default)` registers all ten
packaged faces once for applications that need reusable family handles;
`RocFont.theme(faces, base)` applies its sans/mono roles while preserving theme
sizes, colours, spacing and per-level heading overrides. The returned `sans`,
`serif` and `mono` records are family mappings. `RocFont.licenses` supplies all
three OFL notices; include them when distributing font assets. Distribution
pins and validation evidence live in [the integration record](../development/roc-font.md).

Changing from the old restricted default or generated rc3 preset changes glyph
metrics, line breaks, pagination and PDF bytes. Review existing layouts after
upgrading. Wrap an existing explicit source handle in `Face(...)`, and add
family mappings or genuine role overrides where custom themes request styles.
Changing a dependency URL does not replace fonts an application registers itself.
