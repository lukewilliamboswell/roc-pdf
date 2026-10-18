# Prepared vector diagrams

Run the public example from this directory with `roc main.roc`. It reads
checked-in Roc commands and the exact Inter font bytes, then writes
`vector-diagrams.pdf`. PDF generation uses only public pure Roc APIs. Node,
Mermaid, a browser, SVG parsing and resource acquisition are absent from that
runtime.

The source is `preparation/diagram.mmd`: a real Mermaid flowchart with curved
connectors, arrowheads, translated rectangular nodes, a multiline label and
“Café”. The prepared SVG deliberately adds margins around a nonzero viewBox
origin. `PreparedDiagram.roc` is its generated public `Scene.Drawing` program;
`Diagram.roc` registers the exact same font bytes and supplies `Pdf.figure`'s
alternative text and visible caption. Searchable labels are `Decoration`
artifact text. The figure's Alt text must still explain its meaning.

## Explicit authoring-time preparation

Use Node **23.9.0** and run these commands in `preparation/`:

```sh
npm ci
node prepare.mjs
node test.mjs
```

`npm ci` is an explicit provisioning step. The lock pins Mermaid CLI 11.16.0,
its actual Mermaid renderer 11.17.2, Puppeteer 25.14.0 and all transitive
packages. Puppeteer supplies Chrome **155.0.8059.79**, checked before use.
The exporter loads `Inter-Regular.ttf` as `VectorInter`, renders the source
through that pinned Mermaid distribution with HTML labels disabled, resolves
computed styles and transforms in the browser, and writes the SVG, resolved
fixed-point facts, generated Roc module, source reference PNG and digest
provenance. Repeat preparation must reproduce those facts. Review any changed
source, pin, geometry, label, image or PDF before accepting new evidence.

An existing SVG can also be checked and exported:

```sh
node prepare.mjs --svg input.svg ../PreparedDiagram.roc
```

The SVG must use the profile below and the exact `VectorInter` regular face.
The exporter blocks browser resource requests; it does not fetch referenced
fonts, images or styles. `VECTOR_CHROME` may select a provisioned executable
only if it reports the exact pinned browser version. Ordinary repository CI
uses the checked-in artifacts and never installs or falls back to these tools.

## Accepted profile

This is a constrained recipe for prepared flowcharts, not arbitrary SVG or
HTML support. The browser resolves CSS; the exporter proves that the visible
result fits the following public drawing vocabulary:

- SVG/group translations and positive uniform scales; a positive viewBox;
  96 CSS pixels per inch, converted to points and rounded once to millipoints.
  An explicit white background preserves the entire viewBox and its margins.
- Solid sRGB nonzero fills and solid strokes with butt caps, miter joins and
  miter limit 10. Zero-gap dash patterns are solid. No opacity or effects.
- Rectangles without rounded corners, lines, polygons and polylines; relative
  or absolute M/L/H/V/C/S/Q/T/Z paths. Quadratics become exact cubics before
  final fixed-point rounding. Arcs, circles and ellipses reject.
- Local path-based start/end arrow markers on one open subpath with automatic tangent orientation,
  uniform viewBox scaling and visible overflow. Their geometry is expanded;
  no private PDF operator or transform group is required.
- Horizontal, plain regular Inter text, ASCII plus U+00E9 “é”, without kerning,
  ligatures, per-character positioning, decorations or font substitution.
  Whitespace is single interior U+0020 spaces; source and browser character
  counts must agree. Multiline text is explicit tspan rows. Same-style word spans inside a row
  remain one searchable label. Each line retains its start/center/end anchor.
  Other text coverage needs a separately evidenced profile.
- Labels must remain above all overlapping geometry. Figure drawings paint
  labels after paths; incompatible source paint order rejects.

Visible HTML labels (`foreignObject`), referenced filters/gradients/clips/masks,
external inputs, animation, unsupported text/geometry/transforms and invalid
bounds produce located `vector.*` errors before the Roc module is written.
Unused filter and gradient definitions are permitted. The original consumer's
HTML-label SVG is a retained negative witness, never silently converted.
Input is bounded to 1 MB, 10,000 elements, depth 48 and one million paint-order
comparisons. Roc independently validates the emitted drawing, exact font
coverage and final shaped label bounds; preparation cannot bypass those checks.

## Evidence and provenance

`tests/vector_diagrams` exercises one, ten and fifty public figures with exact
allocation, allocated-byte and deterministic command/page/fragment evidence.
The offline checker decodes exact label text through `ToUnicode`, proves
artifact versus Figure/caption ownership and compares the source Chrome raster
with independent PDFBox output. The preparation test exercises rejected HTML,
effects, external resources, bad paths/transforms, text presentation and Unicode,
plus deterministic conversion and unused definitions.

Inter Regular is the unmodified Inter 4.1 release asset (OFL-1.1), identical to
this repository's product-brief font; see `fonts/Inter-OFL.txt` and the central
asset manifest. The HTML-label negative comes from Luke Boswell's roc-automation
manual, copyright 2026 Luke Boswell, under UPL-1.0:
<https://lukewilliamboswell.github.io/roc-automation/diag-mermaid-md5-332f3e2cc13154f0257848fa9f290595.svg>.
It was retained from the consumer worktree at the issue's reviewed revision;
its digest and source revision are recorded beside the fixture. Neither
preparation nor these rendering tests establishes a PDF/UA claim.
