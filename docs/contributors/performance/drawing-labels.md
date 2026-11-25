# Text labels inside drawings

Charts and diagrams in the gallery faked their axis values, tick labels,
and legends with hand-drawn seven-segment digits, because a `Scene.Drawing`
could hold only paths and images. This slice adds bounded, shaped text
labels to drawings.

## API

`Scene.Drawing.text(drawing, { text, origin, size, color, align })` adds one
line of text (`Scene.Label`) whose baseline is aligned to `origin` in
drawing coordinates: `Start` begins there, `Center` centers on it, `End`
ends there. Labels are allowed in figure drawings and custom-block panels.

## Ownership and tagging

Labels are page-artifact text, the architecture's one non-semantic text
source, exactly like page furniture:

- Each label is shaped whole in the body face by the existing shaper, at
  its size times its figure's applied fit scale, so a `ScaleToFit` figure's
  labels scale with its paths.
- Its runs name artifact sources appended after the semantic sources and
  the furniture sources (`KernelFacadeText.Plan.label_sources`,
  `KernelFacadeFragments` attaches them), so every CID has a `ToUnicode`
  entry and the text is searchable and extractable.
- It is painted by a `Decoration` page-artifact group
  (`/Artifact <</Type /Layout>>`), never by a layout fragment, and belongs to
  no structure element.

For a figure this is a deliberate reading of the figure contract: the
`Figure` element's `/Alt` is what assistive technology announces in place
of the figure's content, so the labels are part of the figure's visual
presentation and conveying what they say belongs to the author's existing
`AlternativeTextMeaningful` obligation. Tagging them as real content inside
the `Figure` would add occurrences, fragments, and structure to a leaf the
semantic stage treats as one anchor line, which is Gate 8's vector-scene
integration; the artifact path needs none of that.

Labels are rejected where they cannot be honest: in a decoration
(`layout.decoration_drawing`), because decorations paint after the page's
text and would cover their own labels; in a furniture drawing
(`layout.furniture_drawing`), whose text path is furniture text; and under
an ordered font policy (`text.drawing_label_policy`), which has no single
body face. An empty label, a non-positive size, or an origin below or left
of the drawing is `document.figure_drawing` (or the panel's
`layout.custom_block_drawing`).

## Stage contract

1. **Normalization** (`Document.validate_flow_drawing`) converts each label
   into a boxed `FlowText` command with its group translation applied. The
   label's baseline plus its size joins the drawing's height and its origin
   the width; its advance is unknown until shaping.
2. **Scenes** strip `FlowText` from the flow drawings they paint
   (`without_labels`, which copies a command list only when it holds a
   label), so paths and images paint exactly as before.
3. **Labels** (`KernelFacadeLabels`, new) run after text materialization,
   once positions are facts: a figure is anchored at the first painted run
   of its occurrence (where scenes anchor its drawing) and scaled by its
   applied fit scale; a panel sits at its `PanelPaint`. Label texts intern
   once (`KernelFacadeSources`), every unique source is checked for its
   script (`text.unsupported_script`), single-scalar clusters
   (`text.unsupported_cluster`), and face coverage (`text.coverage_missing`)
   before shaping so a failure names its label, and the labels shape as one
   simple batch. Each run is aligned by its exact advance and must lie
   inside its drawing horizontally and below its top
   (`layout.drawing_label_bounds`, with the extent and the drawing size in
   the message); nothing is clipped, moved, or shrunk.
4. **Text** (`KernelFacadeText.Plan.with_labels`) appends each page's label
   runs after its other runs as `Decoration` artifact runs, with the
   label's color and size as its style.

A document without labels never enters the stage (`has_labels` scans the
figure and panel command lists without allocating) and keeps its plans
untouched, so every existing case keeps its allocation count, allocated
bytes, work, and snapshot.

## Complexity

Figure anchors are one pass over the semantic nodes and one over the final
runs (the occurrence-to-figure table is allocated only when labels exist);
entries, interning, the coverage check, shaping, and placement are linear in
label scalars; pieces are sorted once by page and entry (O(n log n)); and
the text append is linear in runs.

## Evidence

`flow figures labels x10` and `x50`: N labelled bar charts (region names
centered under the bars, right-aligned tick values, an axis title), a
labelled 600 x 900 pt plan scaled to fit (its "Bay" labels scale with it),
and a custom block with a panel label. MuPDF renders show every label in
place, the scaled labels at their scaled size. The new `drawing_labels`
checker decodes each `Layout` artifact sequence through the font's
`ToUnicode` and requires every label's exact string, and requires that no
label is the whole text of a tagged sequence; its self-test rejects the
unlabelled `sections x10` snapshot. The same case checks seven rejections:
a label wider than its drawing, a Han label (`text.unsupported_script`), an
uncovered Latin label (`ƀ`, `text.coverage_missing`), an empty label, a
labelled decoration, a labelled furniture drawing, and labels under an
ordered policy. The pair is linear: 450 and 2,050 scene commands (40 per
labelled chart plus the plan and callout), 49,617 and 190,842 allocations,
14.83 MB and 54.91 MB. veraPDF PDF/A-4 reports no failure.

## Label faces (examples showcase)

`Scene.Drawing.text_in(drawing, role, label)` sets a label in the face the
theme gives an inline role (`Code`, `Emphasis`, `Quote`, or `Strong`), such
as a bold chart title or a hex value in the code face; `Scene.Drawing.text`
keeps the body face. A role without a face in the theme sets the label in
the body face, as it does inline text.

- **Normalization.** The author command carries the label's face
  (`Scene.LabelFace : [BodyFace, RoleFace(role)]`), and `FlowText` keeps it
  in its boxed record, so the command union's size is unchanged.
- **Face selection is a shaping fact.** Under style faces, output fonts
  are the body face and every role face some run uses. Before this change a
  label face no body run used would have had no output font. Now
  `build_styled_plan` also marks the candidate of every label face
  (`label_candidates`, one scan of the figure and panel commands that
  allocates only for a role-face label), and
  `KernelFacadeShape.Plan.label_instances` gives each role's dense output
  font. Nothing later infers a face.
- **Labels.** `KernelFacadeLabels.Fonts` is the one body font (the
  single-face path, unchanged: every label shapes through
  `shape_simple_batch`) or the style faces' output fonts with each role's
  instance. Under style faces each label is one selected request over its
  whole source in its face's font (`shape_selected_batch`), so identical
  text in two faces is two groups over one interned source with different
  font splits, which the selected batch already supports. Coverage, script,
  and cluster checks run per source and face in the label's own font; a
  gap is `text.coverage_missing` naming the label, with no substitution.
  Runs keep their instance through `KernelFacadeText.Plan.with_labels`, so
  the output fonts subset exactly the glyphs the labels paint.
- **Ordered policies** still report `text.drawing_label_policy`: there is
  no role face to select.

Evidence: `flow figures label faces x10` and `x50`, N charts whose title is
in the `Strong` face (the caller fixture face, which covers only
`CDFPafé`, so the title is "Café"), tick values in the `Code` face (the
monospace fixture), and region names and a small repeat of the title in the
packaged body face. No body text uses either role face. The new
`drawing_label_faces` checker decodes artifact text per font and requires
the names in one font, the title in that font and one other, the ticks in a
third, and neither role font in any tagged text, so both role faces entered
the output through the labels. Its self-test rejects the single-face
`labels x10` snapshot. The case also rejects a `Code` label with `é`,
which the monospace fixture does not cover. x10: 29,118 allocations, 50
body, 10 strong, and 30 code labels, 4 pages; x50: 118,727 allocations, 250,
50, and 150 labels, 17 pages (4.1× for 5×): linear. Every existing case
keeps its allocation count; the labels pair's allocated bytes move by
0.004%. veraPDF PDF/A-4 passes both snapshots.

## Deferred

- Labels under an ordered font policy, which needs the furniture path's
  per-cluster selection and extra-font numbering for label sources.
- Labels in decorations, which needs decorations that paint before text.
- Tagging figure labels as real content inside the `Figure` element.
