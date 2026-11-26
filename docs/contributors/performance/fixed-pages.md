# Fixed-page text and artwork

The [remittance example](../../../examples/remittance-advice/main.roc) places
invoice references and payment amounts on two pre-printed sheet sizes. The
amount paints early on each page and remains last in that page's reading
order. The fixed builder accepts a title, numbered heading, paragraph, rich
paragraph or exact-size figure per placement, with background and overlay rectangles authored
separately. Each placement is confined to one page. Frame fit uses nominal
line boxes and shaped advances.

Fixed normalization validates page sizes, placement frames and a complete
paint permutation per page. It emits dense page spans, authored-order frame
and block rows, a separate paint index, and typed artwork ranges. Geometry
checks the signed origin and positive dimensions before using the proved
`KernelSpan.end_within` predicate for each endpoint. A validated size and
frame therefore bound subsequent baseline arithmetic. The facade's flow
page size and margins contribute no frame geometry.

Shaping and semantic preparation use the ordinary font selection and logical
source arenas. The line builder takes the explicit widths. The positioning
stage checks each block in authored order, then emits positioned lines by
page and paint index. Its per-block physical-run cursor advances monotonically
and visits only runs that can intersect the current line. A line/run overlap
accounts for the corresponding downstream run split. The fit and positioning
passes use O(placements + lines + runs + overlaps) work. Dense lists are
allocated once from checked counts, and fixed geometry holds no copies of
text or font bytes.

The fragment stage preserves each occurrence's logical identity. The scene
stage consumes page sizes and typed artwork ranges directly. It writes the
underlay, semantic content, and overlay in that order. Tagged lowering reads
the semantic spine for `/K` and scene paint order for marked content. The
profile, resource, object-plan, seal, compression, and emission stages are
the same as for flow documents. Preparation reports map the logical block
arena back to `pages[i].placements[j]`.

## Evidence

- `fuzz/FixedPageOrderModel.roc` explores 7,057 states with one to four
  placements, complete and incomplete index lists, and both artifact layers.
  It checks the production normalization result against an independent
  permutation predicate and keeps logical addresses distinct from paint slots.
- `fuzz/DenseSpanProof.roc` proves endpoint acceptance against checked addition
  across U64. The fixed facade tests exercise a flush top/right frame and a
  signed overflow witness through the actual preparation callers.
- `tests/contracts/fixed_positioning.roc` checks wrapped styled text and
  explicit line breaks through shaping, positioning and text materialization.
  The two- and twenty-sheet cases visit 4 and 40 placements, 10 and 100
  lines, and 24 and 240 overlapping or examined runs. They write 10 and 100
  positioned pieces.
- `scripts/check_fixed_pages.py` follows `/K` and decodes stream paint order
  independently. It checks each page's `MediaBox`, Unicode text, glyph geometry,
  `ParentTree`, and classified rectangle geometry. Four isolated mutations
  break semantic order, stream order, frame containment, and artwork order.
  A PDFBox pixel probe checks the overlap of the two artwork layers.
- The two- and twenty-page snapshots alternate the authored sizes and paint
  permutations. The pinned harness checks bytes, allocation counts, work, and
  allocated-byte ceilings on both supported targets. The profile lanes validate
  the original combined output and the separately declared WTPDF case.

| Fixture | PDF bytes | Roc allocations | Requested bytes |
| --- | ---: | ---: | ---: |
| Two sheets | 18,984 | 1,080 | 3,434,525 |
| Twenty sheets | 31,418 | 2,516 | 10,766,942 |
| Two sheets with WTPDF accessibility | 19,251 | 1,081 | 3,436,321 |


## Captioned figures

The [designed brief](../../../examples/designed-brief/Brief.roc) places the
same launch brief on Letter and A4 sheets. The title, key figures, and
captioned figure are authored in reading order. The paint permutation
places the figure first. The figure, caption, and text stay semantic.
The background and accent rectangles are explicit artifacts.

Normalization records a contiguous leaf span for each authored placement
when a caption adds a leaf. Finite paint permutations expand those
spans. The fit stage consumes the drawing's exact bounds, checks the
caption's measured height from the same frame, and commits the drawing
and caption positions for scene lowering. The caption stays next to its
figure under a section, with a separate caption role. The preparation
report preserves the authored placement paths and figure alternatives
and requires author review of reading order and alternative text.

The PDF writer uses ISO 32000-2:2020 with approved corrections
§7.7.3.3 and Table 31 for page boxes, §§14.7.2 and 14.7.5 and Tables
354–355 and 357–359 for structure and content ownership, and §§14.8.2.2
and 14.8.2.5 for artifacts and authored logical order. Caption
containment follows ISO/TS 32005:2023 Table 5. WTPDF §§8.2.3 and
8.3 apply to the independent logical order and artifact paint;
PDF/UA-2 requires review of the figure alternative and reading order.

The independent designed-brief checker verifies exact drawing, glyph
and page geometry, caption ownership and both orders. Reordering the
structure entries to match the physical paint leaves the generic
ownership checks valid and fails the authored-order oracle.

| Figure fixture | PDF bytes | Roc allocations | Requested bytes |
| --- | ---: | ---: | ---: |
| Two sheets | 21,098 | 1,447 | 3,785,035 |
| Twenty sheets | 44,123 | 5,727 | 13,544,768 |
| Atomic authoring rejections | 21,098 | 3,633 | 7,973,907 |

The Letter gallery file and both scale fixtures pass Arlington 1.30.2
and the veraPDF 1.30.2 `4`, `ua2` and `wt1a` profiles. The fixed
placement model checks both text-only and captioned-figure placements
on each completed paint-order history. The fixture suite also replays
an exact drawing-and-caption fit, a one-point drawing in a flush frame,
and seven located rejections through both buffered and chunked entry
points.
The fixed-figure fuzz target replays six named Letter and A4 examples,
including a one-millipoint frame overrun and a caption one point taller
than its available height. The smoke run also varies frame size and
paint order and checks byte and chunk rejection paths.
