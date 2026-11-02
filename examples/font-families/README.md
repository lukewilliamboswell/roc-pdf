# Built-in font families

Run `roc main.roc` in this directory to write `font-families.pdf`. The example
selects all ten packaged static faces through the public facade: Inter body,
headings and genuine emphasis, a Merriweather quotation in four styles, and
Fira Code inline/source text in Regular and Bold. It loads no local font files
and needs no registry setup.

Family/style selection is explicit; nested strong/emphasis selects Bold Italic
in either order. Command-K uses exact U+2318 text in sans/mono roles. A serif
occurrence containing that character would reject, as would requested mono
italic. The [font guide](../../docs/roc-font.md) explains these limits and
caller font mappings. The package retains each original font, licence and
provenance pin, and `RocFont.licenses` exposes the three family notices for
applications distributing font assets.
