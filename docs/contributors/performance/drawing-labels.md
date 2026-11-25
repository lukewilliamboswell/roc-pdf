# Text labels inside drawings

`Scene.Drawing.text` adds a single line whose baseline is aligned to its
drawing-local origin. `Start` begins at the anchor, `Center` centers on it, and
`End` ends there. `Scene.Drawing.text_in` selects an inline role's style face,
falling back to the body face when the theme does not assign that role a face.

## Ownership and stage contract

1. Normalization applies group translation to each boxed `FlowText` command.
   The baseline, origin, and size contribute to the drawing bounds. The
   horizontal extent is proved after shaping.
2. Semantic planning reserves the graphic anchor followed by one text occurrence
   per intrinsic label in the Figure's content spine. The occurrences have an
   exact source and Unicode range in a separate interned source bank. The
   Figure's authored alternative description and Caption retain their roles.
3. After pagination, `KernelFacadeLabels` positions the labels from each
   drawing's placed origin and applied scale. For style faces, shaping selects
   the output instance of each role's face, including faces requested only by
   labels. It checks script, single-scalar clusters, and coverage per source and
   face. It shapes each label whole and uses its exact advance to align the run
   and prove it lies within the drawing.
4. `KernelFacadeText` appends the label runs per page. Each Figure label run
   names its prepared occurrence and gets a layout fragment like other real
   text. The graphic anchor and label fragments lower in authored order under
   the same Figure, independently of paint order. A custom-block panel's label
   is `Decoration` artifact text. Its source follows the furniture sources.

A label that exceeds the drawing bounds reports `layout.drawing_label_bounds`.
Labels on decorations, in furniture drawings, and under an ordered font
policy are rejected. Decorations paint after page text, furniture draws its
text through its own path, and the ordered policy does not supply a single
label face. A drawing with no labels skips the label shaping and placement
stage.

## Evidence

The `flow figures labels x10` and `x50` cases check each chart's ordered
Figure labels, the labels on the scaled bay plan, and the custom-block panel
artifact. The independent checker resolves each Figure's children through
the ParentTree and decodes their exact Unicode using the shown font's
`ToUnicode` map. It also checks that the panel's label is an artifact. The ownership mutation
swaps a label with its figure's caption text in both structure indexes while
preserving the page content. The focused checker rejects the misplaced label.
The cases exercise width, script, coverage, empty label, unsupported drawing
and ordered policy rejections.

The `flow figures label faces x10` and `x50` cases use three Font resources.
The regions use the body face, the ticks use the `Code` face, and the title
“Café” appears in both the `Strong` and body faces. No flow text uses either
role face. The checker verifies both exact Unicode order and selected faces
by Figure label. The cases also exercise missing label-face coverage.

Label preparation and placement visit the drawing commands and label text
linearly. Label pieces are sorted once by page and authored index, then
merged into the page text runs. The focused cases pin deterministic work
and allocation evidence in `tests/spec.json`.
