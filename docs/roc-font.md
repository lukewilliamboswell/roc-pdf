# Use Inter and Fira Code in PDFs

`RocFont` supplies static PDF instances of the sans and mono fonts distributed
by roc-font. Register them once and reuse the registry and theme:

```roc
import pdf.Font
import pdf.Pdf
import pdf.RocFont

faces = RocFont.register(Font.Registry.empty, Font.ValidationLimits.default)?
options : Pdf.Options
options = {
    fonts: Registered(faces.registry),
    theme: RocFont.theme(faces, {}),
}
```

The preset uses Inter Regular for body text, Inter Bold for titles, the shared
heading style and strong text, and Fira Code Regular for inline code. Pass
`faces.source_code` explicitly as `Pdf.source_block`'s `face`. Existing
per-level heading overrides are preserved. Sizes, leading, colors and spacing
come from the theme supplied to `RocFont.theme`. The preset selects
`StyleFaces`, replacing any ordered font policy in that theme.

Inter uses optical size 14 and weights 400/700; Fira Code uses weight 400.
Measurement and embedding use these same static instances. Latin shaping is
supported; possessing glyphs for other scripts does not enable their shaping.
Both families cover `⌘K`. Missing glyphs remain errors before bytes are returned.

Emphasis inherits its surrounding face. No italic is synthesized: register a
genuine italic font and set `theme.inline.emphasis.font` explicitly. Custom
fonts use the existing `Font.Registry.register` API, and the adapter can append
to that registry. Merriweather and automatic serif fallback are not included.

`RocFont.licenses` contains the two OFL notices. Include these when distributing
the font assets with your application. The reproducible asset recipe and pins
are recorded in [the integration record](../development/roc-font.md).

The existing single-face default remains available. Selecting this preset
changes glyph metrics, line breaks, pagination and PDF bytes; downstream apps
with explicit font registration must select it explicitly.
