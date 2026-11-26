# Sequential column flow

Columns use the selected fixed-point page body. The positive widths and
gutter have checked endpoints. A column's nominal line heights fit entirely
inside its frame. Reading and paint follow the authored order through the
first and second columns in each page. ISO 32000-2 §§7.7.3.3, 14.7.2,
14.7.5 and 14.8.2 and ISO 14289-2 §8.2 govern page and tagged-content
ownership. The column order, widths and placement policy are package choices.

One prefix of checked advances per paragraph is shared by its immutable
continuation cursors. Each selected cut advances the cluster cursor and
consumes at least one line. The bounded scout rereads the selected fragment
once for materialization. A split can inspect one line at each of two
proposed continuation positions. The next frame can defer a mandatory keep,
with three attempts sufficient to cover a partial frame and both complete
frame widths. Failed scans return no prepared plan. Line and piece arenas
are consumed by ordinary text materialization. The sealed plan retains no
cursor, measured prefix, or speculative partition.

The pilot article fills columns of unequal width and preserves the same
paragraph across two physical pages. The independent checker matches the
decoded structure text and painted baselines to the authored source and
geometry. Reordering two MCRs or moving a line to the wrong column reaches
the expected failure. The fixture names and inputs are in
`tests/columns/cases.jsonl`. They check the combined and WTPDF declarations
and five located buffered and chunked rejections.

On the pinned x64musl dev backend the 1/10 paragraph scale pair produces
2/18 pages and 38/370 fragments, using exactly 1,040/2,912 allocations and
4,179,757/15,410,555 requested bytes. The device-independent work and
snapshot expectations are declared in `tests/spec.json`. Arm64 execution
remains an integration-run obligation.

`fuzz/ColumnFlowModel.roc` exhausts 73 states with one to twelve words,
one to three lines per column, and both keep policies. Its reference
counts word partitions independently of shaping. It reaches a page
transition, a whole paragraph moved to the wider column, a rescued
widow, and an impossible keep.
