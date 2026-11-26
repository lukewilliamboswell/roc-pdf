# Fixed-page text and artwork

The [remittance example](../../../examples/remittance-advice/main.roc) places
invoice references and payment amounts on two pre-printed sheet sizes. The
amount paints early on each page and remains last in that page's reading
order. The fixed builder accepts a title, numbered heading, paragraph or rich
paragraph per placement, with background and overlay rectangles authored
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
