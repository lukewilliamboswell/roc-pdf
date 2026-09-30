# Reference business documents

## Purpose and status

This record is the correctness contract for the Gate 6 business-authoring
slices. It fixes three reference documents — a multi-page invoice, a business
report, and a business letter — together with their ordinary content, adverse
variants, expected logical structure, expected appearance, author obligations,
declared text support, layout policy, planned public vocabulary, and scale
workloads. It is step 1 of
[Work following the Gate 4 milestone](../feature-roadmap.md#work-following-the-gate-4-milestone).

Version: **`reference-documents-v10`**.

- It began as a design record. From `reference-documents-v10` every outline,
  adverse variant, and policy below is executable: the three references are
  the gallery programs `examples/tax-invoice/main.roc`,
  `examples/business-report/main.roc`, and `examples/warranty-letter/main.roc`, and
  `tests/reference_documents` prepares each of them and every adverse
  variant (see [the closure record](performance/business-authoring-closure.md)).
  Capability status remains governed by the [roadmap](../feature-roadmap.md)
  and the [authoring guide](authoring.md). It claims no reader behavior.
- Every later Gate 6 slice cites the version it implements. A slice that must
  change an outline, a policy, a diagnostic code, or a planned API name updates
  this record in the same change, increments the version (`-v2`, ...), and adds
  a line to [Change log](#change-log). Implementation may not silently diverge
  from the recorded contract.
- Correctness comes first. Each adverse variant below has exactly one expected
  outcome: an exact policy-defined layout, or a structured error with no PDF
  bytes. Where the exact page on which content lands can only be fixed by the
  first executable snapshot, this record states the invariants that snapshot
  must satisfy; the reviewed break positions are then added here as an
  amendment rather than accepted mechanically.
- Performance evidence for these references consists of the
  [scale workloads](#scale-workloads), which exist only to catch super-linear
  blow-ups in named deterministic work counters and exact allocation counts.
  This record sets no numeric latency, throughput, or memory thresholds. The
  roadmap's [product performance targets](../feature-roadmap.md#product-performance-targets)
  section continues to govern whether such thresholds are later required.
- [Human review tasks](#optional-human-review-tasks) are listed for
  exploratory use and do not block slices recorded against this document.
- The references are authored entirely through the public package surface in
  the eventual release. Private fixture constructors cannot satisfy them.

All sample content is fictional. Harbour & Finch Pty Ltd, its customers and
suppliers, its ABN, bank details, and URLs are invented; domains use the
reserved `.example` top-level domain and telephone numbers use the
`5550 xxxx` range reserved for fictional use. Amounts are in Australian
dollars (AUD) and include 10% GST where stated. The document language is
`en-AU`; each reference contains at least one nested `fr` span.

### Shared conventions

- Page size is A4 (595 × 842 pt). The reference themes use margins of 48 pt top
  and bottom and 56 pt left and right (72 pt left and right for the letter),
  giving body frames of 483 × 746 pt and 451 × 746 pt respectively. Template
  regions are reserved inside the body frame, never in the margins.
- Body text uses the packaged face at 11/14 pt (the built-in theme's body
  style). Headings, captions, table text, and furniture text use exact
  `Theme` styles over the same packaged face unless a variant says otherwise.
  No reference depends on a bold or italic face: the built-in package ships one
  regular face, and synthetic emboldening or obliquing is not produced.
  `Em`, `Strong`, `Code`, and `Quote` are distinguished visually only by
  their theme colors (`Theme.with_emphasis_color`, `with_strong_color`,
  `with_code_color`, `with_quote_color`); an unthemed role paints exactly like
  the text around it. A caller-registered face per inline role (for example
  a monospace face for `Code`) is selectable with `Theme.with_inline_font`
  under style faces (`reference-documents-v8`); under an ordered policy it
  reports `text.inline_font_policy`. The semantic role never depends on that
  presentation.
- Numbers, currency amounts, and dates are caller-formatted strings. The
  package performs no arithmetic, rounding, currency formatting, or total
  verification; correctness of totals is an author obligation.
- "Artifact" means a page-content artifact excluded from the logical structure.
  Everything else listed in a structure tree is semantic and appears in
  logical reading order.
- Structure trees use PDF 2.0 standard roles. `⏎` marks an authored
  `Pdf.line_break` inside one paragraph. `Headers →` lists the header cells a
  data cell's `Headers` attribute references.

## Multi-page invoice

### Authored content

Metadata title: `Tax invoice HF-2026-0417 — Harbour & Finch Pty Ltd`.
Visible title: `Tax invoice`. Created and modified timestamps are authored as
`2026-09-14T00:00:00Z`.

Page templates:

- First page: header region 44 pt holding the Harbour & Finch logo as
  `Pdf.furniture_image` in the start slot (a validated vector drawing, 132 × 44
  pt). Footer region 16 pt: start slot `ABN 00 123 456 789 · Tax invoice
  HF-2026-0417`; end slot `Page N of M` built from `Pdf.page_number` and
  `Pdf.total_pages` inside a `Pdf.reserved_width` of 64 pt, end-aligned. Region
  gap 12 pt. No lead region.
- Continuation pages: header region 16 pt with start slot `Harbour & Finch Pty
  Ltd — Tax invoice HF-2026-0417 (continued)`; the same footer.

Body contents, in order:

1. Supplier block: `Pdf.division` containing
   - `Pdf.rich_paragraph([Pdf.strong([Pdf.text("Harbour & Finch Pty Ltd")])])`
   - `Pdf.rich_paragraph` with `Level 3, 18 Wharf Street⏎Hobart TAS 7000⏎ABN
     00 123 456 789⏎accounts@harbourfinch.example · (03) 5550 0142`.
2. `Pdf.title("Tax invoice")`.
3. Invoice details table (no caption, no header rows, one `Content` column of
   row headers and one `Share(1)` column):

   | Row header (`Row` scope) | Value |
   | --- | --- |
   | Invoice number | HF-2026-0417 |
   | Issue date | 14 September 2026 |
   | Due date | 14 October 2026 |
   | Customer reference | PO 88213 |

4. `Pdf.section` with `Pdf.heading(1, "Bill to")` and one rich paragraph:
   `Northstar Cooperative Ltd⏎Attn: Accounts Payable⏎42 Kestrel
   Parade⏎Fremantle WA 6160`.
5. `Pdf.section` with `Pdf.heading(1, "Items")` and the items table:
   - Caption: `Items supplied under purchase order PO 88213`.
   - Columns: `Code` (`Content`, `Start`), `Description` (`Share(1)`,
     `Start`), `Qty` (`Fixed(36 pt)`, `End`), `Unit price (AUD)`
     (`Fixed(72 pt)`, `End`), `Amount (AUD)` (`Fixed(80 pt)`, `End`).
   - One header row of `Column`-scoped header cells naming the columns.
   - `row_split: KeepRows`.
   - 32 body rows: the eight products below, once for each of the fit-out sites
     `L2`, `L3`, `L4`, `L5` in that order. The code cell is a `Row`-scoped
     header cell holding `<code>/<site>`; the description gains the suffix
     ` (Level 2)` and so on.

     | Code | Description | Qty | Unit price | Amount |
     | --- | --- | --- | --- | --- |
     | HF-DSK-140 | Standing desk frame, twin motor, 1400 mm | 4 | 689.00 | 2,756.00 |
     | HF-TOP-OAK | Tasmanian oak desktop, 1400 × 700 mm, oiled | 4 | 412.50 | 1,650.00 |
     | HF-CHR-ERG | Ergonomic task chair, mesh back, adjustable lumbar support | 6 | 529.00 | 3,174.00 |
     | HF-CAF-ELG | *fr:* Cafetière « Élégance », 1 L, for the staff kitchen | 2 | 64.95 | 129.90 |
     | HF-LMP-LED | LED task lamp, 4000 K, clamp mount | 6 | 118.00 | 708.00 |
     | HF-CBL-TRY | Under-desk cable tray, powder-coated steel | 8 | 36.40 | 291.20 |
     | HF-INS-HRS | Installation labour (hours) | 12 | 95.00 | 1,140.00 |
     | HF-DEL-MET | Metropolitan delivery, Hobart | 1 | 180.00 | 180.00 |

     The product name `Cafetière « Élégance »` is authored as
     `Pdf.in_language("fr", [Pdf.text("Cafetière « Élégance »")])`.
   - Three footer rows, each a `Row`-scoped header cell spanning four columns
     and end-aligned (`Pdf.aligned(End, Pdf.spanning(4, ...))`) and one
     amount cell:
     `Subtotal (excl. GST)` / `40,116.40`; `GST (10%)` / `4,011.64`;
     `Total due (AUD)` / `44,128.04` (the amount wrapped in `Pdf.strong`).
6. `Pdf.section` with `Pdf.heading(1, "Payment")` and two rich paragraphs:
   - `Please pay by 14 October 2026. Bank transfer: BSB 000-000, account
     1234 5678, reference HF-2026-0417.`
   - `You can also ` +
     `Pdf.inline_link([Pdf.text("pay invoice HF-2026-0417 online")],
     "https://pay.harbourfinch.example/invoices/HF-2026-0417")` +
     ` (pay.harbourfinch.example/invoices/HF-2026-0417).` The trailing
     parenthesized address is plain text for printed copies.

A sketch of the items table in the planned vocabulary:

```roc
items = Pdf.table({
    caption: Pdf.caption("Items supplied under purchase order PO 88213"),
    columns: [
        { width: Content, align: Start },
        { width: Share(1), align: Start },
        { width: Fixed(Layout.Unit.points(36)), align: End },
        { width: Fixed(Layout.Unit.points(72)), align: End },
        { width: Fixed(Layout.Unit.points(80)), align: End },
    ],
    header_rows: [
        Pdf.row([
            Pdf.header_cell(Column, [Pdf.text("Code")]),
            Pdf.header_cell(Column, [Pdf.text("Description")]),
            Pdf.header_cell(Column, [Pdf.text("Qty")]),
            Pdf.header_cell(Column, [Pdf.text("Unit price (AUD)")]),
            Pdf.header_cell(Column, [Pdf.text("Amount (AUD)")]),
        ]),
    ],
    body_rows: item_rows,
    footer_rows: [
        Pdf.row([
            Pdf.aligned(End, Pdf.spanning(4, Pdf.header_cell(Row, [Pdf.text("Subtotal (excl. GST)")]))),
            Pdf.cell([Pdf.text("40,116.40")]),
        ]),
        Pdf.row([
            Pdf.aligned(End, Pdf.spanning(4, Pdf.header_cell(Row, [Pdf.text("GST (10%)")]))),
            Pdf.cell([Pdf.text("4,011.64")]),
        ]),
        Pdf.row([
            Pdf.aligned(End, Pdf.spanning(4, Pdf.header_cell(Row, [Pdf.text("Total due (AUD)")]))),
            Pdf.cell([Pdf.strong([Pdf.text("44,128.04")])]),
        ]),
    ],
    row_split: KeepRows,
})
```

### Logical structure and reading order

```text
Document  Lang=en-AU
├─ Div
│  ├─ P ── Strong "Harbour & Finch Pty Ltd"
│  └─ P "Level 3, 18 Wharf Street⏎Hobart TAS 7000⏎ABN …⏎accounts@… · (03) 5550 0142"
├─ Title "Tax invoice"
├─ Table
│  └─ TBody
│     ├─ TR ── TH Scope=Row "Invoice number"      TD "HF-2026-0417"      Headers → that TH
│     ├─ TR ── TH Scope=Row "Issue date"          TD "14 September 2026"
│     ├─ TR ── TH Scope=Row "Due date"            TD "14 October 2026"
│     └─ TR ── TH Scope=Row "Customer reference"  TD "PO 88213"
├─ Sect
│  ├─ H1 "Bill to"
│  └─ P "Northstar Cooperative Ltd⏎Attn: Accounts Payable⏎…⏎Fremantle WA 6160"
├─ Sect
│  ├─ H1 "Items"
│  └─ Table
│     ├─ Caption ── P "Items supplied under purchase order PO 88213"
│     ├─ THead ── TR ── TH Scope=Column ×5
│     ├─ TBody ── TR ×32
│     │  └─ TH Scope=Row "HF-DSK-140/L2"
│     │     TD description   Headers → TH Description, TH row code
│     │        (row HF-CAF-ELG: Span Lang=fr "Cafetière « Élégance »" inside the TD)
│     │     TD qty           Headers → TH Qty, TH row code
│     │     TD unit price    Headers → TH Unit price, TH row code
│     │     TD amount        Headers → TH Amount, TH row code
│     └─ TFoot ── TR ×3
│        └─ TH Scope=Row ColSpan=4 "Subtotal (excl. GST)"
│           TD "40,116.40"   Headers → TH Amount, TH row "Subtotal (excl. GST)"
│           (last row: TD ── Strong "44,128.04")
└─ Sect
   ├─ H1 "Payment"
   ├─ P "Please pay by 14 October 2026. …"
   └─ P "You can also " Link("pay invoice HF-2026-0417 online" + OBJR) " (…)."
```

Every header and data cell carries a generated element ID in the IDTree;
`Headers` associations are derived from declared scopes and never from
geometry. The logical `THead` occurs once, at the table's first fragment.
`TFoot` appears once, after the last body row.

Reading order equals the tree above. The link annotation's keyboard order
follows its `Link` element.

Artifacts: header logo (`Header`), continuation header text (`Header`), footer
ABN text (`Footer`), `Page N of M` (`PageNumber`), header rows repainted on
continuation pages (repeated-table-header pagination artifact), and table
rules (`Decoration`).

### Expected appearance

- Page 1: logo top-left in the 44 pt header region. Supplier block at the top of
  the body, start-aligned; then the title at the title style; then the details
  table as a two-column key/value grid with no rules; `Bill to`; `Items`
  heading; the caption above the items table; the header row with a rule below
  it; body rows.
  Code cells hug their content width; descriptions wrap within the share
  column; numeric columns are end-aligned so decimal points line up because
  every amount has two decimals. Footer: ABN text start-aligned, `Page 1 of M`
  end-aligned inside its reserved width.
- Continuation pages: continuation header text; the items header row repainted
  at the top of the body before the next body row; remaining body rows; on the
  last page the three totals rows (with the total's amount in the strong
  style), then the Payment section.
- Invariants for the ordinary variant: no body row is split (`KeepRows`); the
  three totals rows are on one page together with at least the last body row;
  the Payment heading is not the last line on a page; every page shows
  `Page N of M` with the exact final `M`. With the reference theme the
  ordinary variant is expected to occupy two or three pages; the exact break
  rows are recorded here from the first reviewed snapshot.
- Reviewed break positions (`reference-documents-v10`, MuPDF 1.28.2 render
  of `examples/tax-invoice/tax-invoice.pdf`): three pages. Page 1 holds body rows 1–9
  (through `HF-DSK-140/L3`); page 2 repaints the header row and holds rows
  10–28 (through `HF-CAF-ELG/L5`); page 3 repaints the header row and holds
  rows 29–32, the three totals rows, and the Payment section. No preference
  is relaxed.

### Adverse variants

| ID | Change from ordinary | Policy | Expected outcome |
| --- | --- | --- | --- |
| INV-A1 | Customer name `The Northstar Regional Housing and Community Development Cooperative (Western Australia) Ltd`; every address line ~90 characters; one description 380 characters | defaults | Accepted. Lines wrap at pinned UAX #14 opportunities inside the Bill-to paragraph and the description cell; the affected row grows and, under `KeepRows`, moves whole to the next page if it does not fit. No shrinking, clipping, or truncation. |
| INV-A2a | Code `HF-DSK-140-TASMANIAN-OAK/L2` | defaults | Accepted. The `Content` column widens and the `Share` column absorbs the difference. Amended in `reference-documents-v10` to the column rule of `-v5`: the `Share` column's minimum still fits beside the code's max-content width, so the `Content` column takes that width and the code does not break at its hyphens; descriptions wrap in the narrower share (four pages). |
| INV-A2b | Description contains a 128-hex-digit serial with no break opportunity | defaults | `layout.unbreakable_token` locating the cell and the token's scalar range, reporting the token width and the widest width the column could receive. No bytes. |
| INV-A2c | Fixed columns widened so fixed widths plus every column's min-content exceed the table width | defaults | `layout.table_width` naming the table, the sum of minima, and the available width. No bytes. |
| INV-A3 | 500 body rows (products cycled) | defaults, with an 80 pt `Page N of M` reserved width (`reference-documents-v10`) | Accepted: 24 pages. The header row repeats as an artifact on every continuation page; the logical `THead` and `TFoot` occur once; totals obey the INV-A5 rule. With the ordinary 64 pt reserved width the two-digit total does not fit (`Page 1 of 24` measures 64.598 pt), which is `layout.field_overflow` at `templates.first.footer.end[0].inlines[0].inlines[1]` with no bytes. |
| INV-A4a | One description of 9,000 characters (taller than a continuation page body) | `KeepRows` (default) | `layout.oversize_row` locating the row and reporting its measured height and the largest available body height. No bytes. |
| INV-A4b | As INV-A4a | `SplitRows` | Accepted. The row fragments at line boundaries; each continuation page paints the repeated header then the row's continuation. Cells whose content completed in an earlier fragment paint nothing further; cell rules continue. One `TR`, one `TD` per cell, the long `TD` owning several fragments. |
| INV-A5 | Rows arranged so the last body row fits on page *k* but the three totals rows do not (30 body rows, `reference-documents-v10`; without the totals the 30th row fits on page 2) | defaults | Accepted. The totals group is unsplittable and prefers to carry at least one body row: page *k* ends at the second-last body row; page *k+1* paints the repeated header, the last body row, and the totals. No preference is relaxed. |
| INV-A6a | Customer name contains Arabic `شركة الشمال` | defaults | `text.unsupported_script` locating the paragraph and the Arabic scalar range; the script check precedes coverage so the author sees the fundamental cause. No bytes. |
| INV-A6b | Address contains Han `北京` with the packaged face only | defaults | `text.coverage_missing` locating the scalars. No bytes. No face is substituted. |
| INV-A7a | Items section and Payment section wrapped together in `Pdf.keep_together`, exceeding one page body | defaults | `layout.keep_conflict` naming the keep and its first and last member blocks (`details` `contents[4]`, `contents[4].contents[0].contents[0]`, `contents[4].contents[1].contents[2]`); the message gives their minimum height and the fresh-page body height. No bytes. |
| INV-A7b | `Pdf.page_break` inside a `Pdf.keep_together` (between the Bill-to and Items sections) | defaults | `layout.keep_conflict` naming the explicit break and then the required keep. No bytes. |
| INV-A8 | A body row with five cells plus a `Pdf.spanning(2, ...)` cell (seven grid columns in a five-column table) | defaults | `table.grid_mismatch` naming the row, the declared column count, and the spanned width. No bytes. |
| INV-A9 | A cell declared with a row span | defaults | `table.row_span` (`FeatureUnavailable`, Gate 8). No bytes. |

### Author obligations

- Totals, tax, and every amount are correct; the package does not compute or
  verify them.
- The logo is decorative because the supplier name is present as text. If a
  logo conveyed information not present in text, it would be authored as a
  figure with alternative text instead.
- Each `Row`-scoped code cell identifies its row, and every column header
  describes its column; declared scopes must match the table's meaning.
- Link text states the link's purpose (`pay invoice HF-2026-0417 online`),
  not merely a raw address.
- The `fr` span marks the product name only.
- Visible order in the body matches the intended reading order.

## Business report

### Authored content

Metadata title: `Harbour & Finch quarterly operations report, Q1 FY2027`.
Visible title: `Quarterly operations report`. Created and modified timestamps
are authored as `2026-10-12T00:00:00Z`.

Page templates:

- First page: no header region. Footer region 16 pt: end slot `Page N of M`
  inside a `Pdf.reserved_width` of 64 pt.
- Continuation pages: header region 24 pt with start slot `Quarterly operations
  report · Q1 FY2027` and a full-width 0.5 pt rule as a `Pdf.furniture_image`
  vector drawing at the region's bottom; the same footer. Region gap 12 pt.

Destinations and outline: each section heading is a destination heading
(`summary`, `sales`, `supply-chain`, `freight`, `timber`, `outlook`,
`appendix-a`). `Pdf.with_outline` lists them in document order with depths
matching heading levels and titles equal to the visible heading text.

Body contents, in order:

1. `Pdf.title("Quarterly operations report")`.
2. Rich paragraph: `Q1 FY2027: July to September 2026 · Prepared by the
   Operations team, 12 October 2026`, where `FY2027` is
   `Pdf.expansion("FY2027", "financial year 2027")`.
3. Section `summary`, `H1 "1 Summary"`:
   - Rich paragraph: `Revenue rose ` + strong `5.0%` + ` to AUD 9.22 million,
     led by ` + emphasis `Queensland` + `. Freight costs fell for the second
     quarter; see ` + `Pdf.inline_internal_link([Pdf.text("section 3,
     Supply chain")], "supply-chain")` + `.`
   - Bulleted list of three items; the second item contains a nested bulleted
     list of two items:
     - `On-time delivery reached 96.4%.`
     - `Timber purchasing moved further toward certified sources:`
       - `88% of oak by volume is certified.`
       - `All veneer suppliers are now audited annually.`
     - `Warranty claims fell to 0.6% of units shipped.`
   - A "Key figures" callout through `Pdf.custom_block` (the custom-block seam
     exercise): semantically a `Div` of three paragraphs `Revenue: AUD 9.22 m
     (+5.0%)`, `On-time delivery: 96.4%`, `Certified timber: 88%`; visually a
     tinted rounded panel owned by the block as a decoration artifact.
     Unsplittable, measured by the extension.
4. Section `sales`, `H1 "2 Sales performance"`:
   - Paragraph introducing the table, with
     `Pdf.expansion("GST", "Goods and Services Tax")` in `Revenue is reported
     excluding GST.`
   - Table 1, caption `Table 1. Revenue by region, AUD thousands`; columns
     `Region` (`Content`), `Q1 FY2026`, `Q1 FY2027`, `Change` (each
     `Share(1)`, `End`); `Column`-scoped header row; `Row`-scoped region cells:

     | Region | Q1 FY2026 | Q1 FY2027 | Change |
     | --- | --- | --- | --- |
     | Tasmania | 1,284 | 1,412 | +10.0% |
     | Victoria | 2,905 | 3,118 | +7.3% |
     | New South Wales | 3,462 | 3,390 | −2.1% |
     | Queensland | 1,127 | 1,301 | +15.4% |
     | *footer:* Total | 8,778 | 9,221 | +5.0% |

     Negative values use U+2212 MINUS SIGN.
   - Figure 1: a bounded vector bar chart (paired bars per region, axis, tick
     labels drawn as vector paths) authored as `Pdf.figure` with alternative
     text `Bar chart comparing revenue by region for Q1 FY2026 and Q1 FY2027.
     Queensland grew most, by 15.4%; New South Wales fell by 2.1%. Values are
     given in Table 1.` and caption `Figure 1. Revenue by region, AUD
     thousands`. Drawing bounds 483 × 220 pt.
5. Section `supply-chain`, `H1 "3 Supply chain"`, with one introductory
   paragraph and two subsections:
   - Section `freight`, `H2 "3.1 Freight"`: two paragraphs; one mentions the
     warehouse system code as `Pdf.code("WMS-7")`.
   - Section `timber`, `H2 "3.2 Timber sourcing"`: a paragraph quoting the
     Lyon supplier: `Our partner ` +
     `Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")])` + ` puts it
     simply: ` + `Pdf.quote([Pdf.in_language("fr", [Pdf.text("« Le bois
     demande de la patience. »")])])` + ` (“Timber asks for patience.”)`.
     Then Figure 2: a raster photograph (a caller-supplied sRGB JPEG, 483 ×
     260 pt placement) with alternative text `Stacked Tasmanian oak boards
     air-drying under cover at the Moonah yard.` and caption `Figure 2. Air
     drying at the Moonah yard`.
6. Section `outlook`, `H1 "4 Outlook"`: a paragraph and a numbered list
   (`Decimal`, start 1) of three priorities; the second item contains a nested
   bulleted list of two items. The paragraph links externally with
   `Pdf.inline_link([Pdf.text("our published sustainability commitments")],
   "https://www.harbourfinch.example/sustainability")`.
7. Section `appendix-a`, `H1 "Appendix A. Supplier register"`: a paragraph and
   Table 2, caption `Table 2. Active suppliers at 30 September 2026`, 40 body
   rows, columns `Supplier` (`Row` scope, `Share(3)`), `Location`
   (`Share(2)`), `Category` (`Share(2)`), `Spend (AUD thousands)`
   (`Fixed(80 pt)`, `End`), `Certified` (`Fixed(56 pt)`, `Center`,
   `Yes`/`No`). One row's supplier cell is
   `Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")])`. `KeepRows`. The
   table continues across at least one page break in the ordinary variant.

### Logical structure and reading order

```text
Document  Lang=en-AU
├─ Title "Quarterly operations report"
├─ P "Q1 " Span(E="financial year 2027") "FY2027" ": July to September 2026 · …"
├─ Sect                                   (destination summary)
│  ├─ H1 "1 Summary"
│  ├─ P "Revenue rose " Strong "5.0%" " … led by " Em "Queensland" " … see "
│  │    Link("section 3, Supply chain" + OBJR; /SD → H1 supply-chain) "."
│  ├─ L ListNumbering=Disc
│  │  ├─ LI ── Lbl "•"  LBody ── P
│  │  ├─ LI ── Lbl "•"  LBody ── P, L ── LI ×2 (Lbl, LBody ── P)
│  │  └─ LI ── Lbl "•"  LBody ── P
│  └─ Div                                  (custom block "Key figures")
│     └─ P ×3
├─ Sect                                   (destination sales)
│  ├─ H1 "2 Sales performance"
│  ├─ P "… excluding " Span(E="Goods and Services Tax") "GST" "."
│  ├─ Table
│  │  ├─ Caption ── P "Table 1. Revenue by region, AUD thousands"
│  │  ├─ THead ── TR ── TH Scope=Column ×4
│  │  ├─ TBody ── TR ×4 ── TH Scope=Row, TD ×3 (Headers → column TH, row TH)
│  │  └─ TFoot ── TR ── TH Scope=Row "Total", TD ×3
│  └─ Sect ── Figure Alt="Bar chart comparing …", Caption ── P "Figure 1. …"
├─ Sect                                   (destination supply-chain)
│  ├─ H1 "3 Supply chain"
│  ├─ P
│  ├─ Sect                                (destination freight)
│  │  ├─ H2 "3.1 Freight"
│  │  └─ P ×2 (one containing Code "WMS-7")
│  └─ Sect                                (destination timber)
│     ├─ H2 "3.2 Timber sourcing"
│     ├─ P "Our partner " Span Lang=fr "Atelier Beaulieu" " … "
│     │    Quote ── Span Lang=fr "« Le bois demande de la patience. »" " (…)"
│     └─ Sect ── Figure Alt="Stacked Tasmanian oak boards …", Caption ── P "Figure 2. …"
├─ Sect                                   (destination outlook)
│  ├─ H1 "4 Outlook"
│  ├─ P "… " Link("our published sustainability commitments" + OBJR) "."
│  └─ L ListNumbering=Decimal
│     ├─ LI ── Lbl "1."  LBody ── P
│     ├─ LI ── Lbl "2."  LBody ── P, L ── LI ×2
│     └─ LI ── Lbl "3."  LBody ── P
└─ Sect                                   (destination appendix-a)
   ├─ H1 "Appendix A. Supplier register"
   ├─ P
   └─ Table
      ├─ Caption ── P "Table 2. Active suppliers at 30 September 2026"
      ├─ THead ── TR ── TH Scope=Column ×5
      └─ TBody ── TR ×40 ── TH Scope=Row, TD ×4
```

A captioned figure is a `Sect` holding its `Figure` and then its
`Caption ── P`, with a `CaptionFor` relationship from the caption to the
figure (`reference-documents-v7`, flow-figures slice). The caption is not a
child of the `Figure`, because `/Alt` replaces the figure and its children
for assistive technology, and it is not grouped in a `Div`: veraPDF's
PDF/UA-2 profile treats `Div` and `Part` as transparent for 8.2.5.27 (a
`Caption` is the first or last child of its parent), which would make the
caption a middle child of the section around the figure. An uncaptioned
figure is a bare `Figure`. The visible caption text is therefore exposed
independently of the figure's `/Alt`.

Internal links carry both `/SD` (the heading's structure element) and `/D`
(the post-layout geometry of that heading). Outline entries resolve to the same
destinations. List labels are generated text with presentation evidence.

Artifacts: continuation header text and rule (`Header`), `Page N of M`
(`PageNumber`), repeated table header rows on Table 2's continuation pages,
table rules, and the callout panel background (`Decoration`, owned by the
custom block).

### Expected appearance

- Page 1: title, subtitle paragraph, section 1 with its list (nested list
  indented by the theme's list indent), and the callout panel if it fits
  entirely; otherwise the panel moves to page 2 whole.
- Following pages: section 2 with Table 1 (caption above, a rule below the header row,
  total row after a rule) and Figure 1 with its caption below; section 3 with
  Figure 2; section 4; Appendix A with Table 2 continuing across pages and its
  header row repainted on each continuation page.
- Continuation pages show the header text and rule; every page shows `Page N
  of M` end-aligned in the footer.
- Invariants for the ordinary variant: no heading is the last line on a page
  (heading keep-with-next); every figure stays with its caption; every table
  caption stays with the table's header row and first body row; Table 1 is
  not split in the ordinary variant; paragraphs respect two-line widow and
  orphan minimums unless a relaxation is reported. The exact page
  composition is recorded here from the first reviewed snapshot.
- Reviewed composition (`reference-documents-v10`, MuPDF 1.28.2 render of
  `examples/business-report/business-report.pdf`): five pages. Page 1 holds the title,
  subtitle, section 1 with its list and the callout, and section 2 through
  Table 1 (unsplit); Figure 1 with its caption does not fit below it and
  opens page 2, which continues with section 3 through the paragraph of
  3.2; Figure 2 with its caption opens page 3, followed by section 4 and
  Appendix A with Table 2's caption, header, and rows 1–8; page 4 repaints
  the header and holds rows 9–34; page 5 repaints it and holds rows 35–40.
  No preference is relaxed.

### Adverse variants

| ID | Change from ordinary | Policy | Expected outcome |
| --- | --- | --- | --- |
| REP-A1 | Section 2's heading falls on the last line of a page (`reference-documents-v10`: a page break, a one-line filler paragraph, and a 630 pt spacer before section 2 leave room for the heading but not for a body line; a control proves the heading alone fits) | defaults | Accepted. Heading keep-with-next (preferred, rank R1) moves the heading and at least two lines of the next paragraph to the next page. Not reported as relaxed. |
| REP-A2 | Figure 1 lands where the figure fits but its caption does not (`reference-documents-v10`: a page break, a filler line, and a 430 pt spacer before Figure 1; a control proves the uncaptioned figure fits) | defaults | Accepted. Figure and caption form one unsplittable unit and move together. If a heading precedes it, the heading moves with it (R1). |
| REP-A3 | Table 1 placed so that only two body rows fit (`reference-documents-v10`: a page break, a filler line, and a 580 pt spacer before Table 1) | defaults | Accepted. The table breaks after a whole row; the next page repaints the header row (artifact) before rows 3–4 and the total row. Logical `THead` and `TFoot` occur once. |
| REP-A4 | 100 sections, each after an explicit break (`Page N of M` reaches three digits), with the page number alone in a `Pdf.reserved_width` sized for two digits (16 pt; amended in `reference-documents-v10`: the widest two-digit value, `40`, measures 14.045 pt, so the former 14 pt would already overflow on page 40) | defaults | `layout.field_overflow` naming the footer field (`templates.continuation.footer.end[0].inlines[0].inlines[0]`); the message names page 100, the resolved value `100`, its shaped width, and the reserved width. No bytes. |
| REP-A5 | Font selection switched to an ordered policy of a caller-registered Latin face and a Han face; section 3.2 adds a nested `zh-Hans` span (amended in `reference-documents-v10` to `Pdf.in_language("zh-Hans", [Pdf.text("中")])` between spaces: the test-only Han fixture face covers only U+4E2D) | ordered policy | Accepted: per-cluster face selection, one nested `zh-Hans` span, no substitution. The spaces around the span itemize as Common and take the Latin face (the report's coverage facts show `Zyyy` runs on font 0 and one `Hani` scalar on font 1). |
| REP-A6a | Figure 1's drawing is 600 × 900 pt | `Exact` (default) | `document.figure_oversize` reporting the drawing size and the body frame. No bytes. |
| REP-A6b | As REP-A6a with `Pdf.figure_fit(..., ScaleToFit({ minimum_percent: 50 }))` | scale to fit | Accepted. Uniform scale `min(483/600, available/900)` on a fresh page, reported in the preparation report as an authored fit outcome: 733 thousandths, the continuation frame (682 pt) less the caption line and its spacing being 660 pt (`reference-documents-v10`). |
| REP-A6c | As REP-A6b with `minimum_percent: 90` | scale to fit | `document.figure_oversize` reporting the required scale and the floor. No bytes. |
| REP-A7 | `H1 "3 Supply chain"` followed directly by an `H3` | defaults | `semantics.heading_skip` naming both headings. No bytes. |
| REP-A8 | Internal link to an undeclared destination `risks` | defaults | The existing typed `InvalidNavigation` destination error, locating the link. No bytes. |
| REP-A9 | Figure 2 with empty alternative text | defaults | `document.figure_alternative_empty` locating the figure. No bytes. |
| REP-A10 | The callout extension reports a height larger than the body frame | defaults | `layout.oversize_block` naming the custom block and both heights. No bytes. |

### Author obligations

- Each figure's alternative text conveys what the figure communicates (the
  chart's comparison and extremes), not its appearance alone, and refers to
  Table 1 for exact values.
- Captions identify their figure or table; header cells head their data.
- Heading text and levels reflect the document's actual organization; outline
  titles match headings.
- Internal and external link text states the destination or purpose.
- Nested language spans cover exactly the foreign-language text.
- Abbreviation expansions are accurate.

## Business letter

### Authored content

Metadata title: `Letter to Northstar Cooperative about the warranty extension,
21 September 2026`. There is **no** visible title and no `Title` structure
element; the metadata title is still required and is displayed by readers
through `DisplayDocTitle`. Created and modified timestamps are authored as
`2026-09-21T00:00:00Z`.

Page templates:

- First page: header region 48 pt with the logo (`Pdf.furniture_image`, 140 ×
  48 pt) in the end slot. A **lead region** of 60 pt holds semantic letterhead
  blocks: a rich paragraph `Harbour & Finch Pty Ltd` (strong) and a rich
  paragraph `Level 3, 18 Wharf Street, Hobart TAS 7000⏎(03) 5550 0142 ·
  hello@harbourfinch.example · ABN 00 123 456 789`. Footer region 16 pt with
  centered text `harbourfinch.example`. Region gap 12 pt. First-page body
  height: 746 − 48 − 12 − 60 − 12 − 16 − 12 = 586 pt.
- Continuation pages: header region 16 pt, start slot `Northstar Cooperative
  Ltd · 21 September 2026`, end slot `Page N of M` in a 72 pt reserved width
  (amended in `reference-documents-v6`: in the packaged face at 11 pt,
  `Page 10 of 11`, which LET-A2 requires, measures 66.7 pt and would not fit
  the former 64 pt; `Page 9 of 9` measures 60.0 pt, so the invoice's and
  report's 64 pt suit their one-digit totals).
  No footer. Continuation body height: 746 − 16 − 12 = 718 pt.

Body contents, in order:

1. Paragraph `21 September 2026`.
2. Recipient block: rich paragraph `Ms Priya Raman⏎Operations Manager⏎Northstar
   Cooperative Ltd⏎42 Kestrel Parade⏎Fremantle WA 6160`.
3. `Pdf.spacer(12 pt)`.
4. Paragraph `Dear Ms Raman,`.
5. Rich paragraph `Subject: ` + strong `Extended warranty for your Level 2–5
   fit-out`. (A subject line is a paragraph, not a heading.)
6. Six body paragraphs (approximately 90–120 words each). One mentions `our
   oak supplier ` + `Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")])`
   + ` in Lyon`.
7. Numbered list (`Decimal`) of four warranty terms.
8. Two closing paragraphs.
9. Signature block as one `Pdf.keep_together`: paragraph `Yours sincerely,`,
   `Pdf.spacer(36 pt)` (signature space), paragraph `Tom Finch`, paragraph
   `Director, Harbour & Finch Pty Ltd`.
10. Paragraph `Enclosure: Schedule 1, covered items`.
11. `Pdf.page_break`.
12. `Pdf.section` with `Pdf.heading(1, "Schedule 1. Covered items")` and a
    table (caption `Items covered by the extended warranty`), columns `Code`
    (`Row` scope, `Content`), `Description` (`Share(1)`), `Warranty until`
    (`Fixed(96 pt)`), eight rows for the invoice's products.

The ordinary letter occupies two pages of letter text plus the schedule page
(three pages).

### Logical structure and reading order

```text
Document  Lang=en-AU                       (no Title element)
├─ Div                                      (first-page lead region)
│  ├─ P ── Strong "Harbour & Finch Pty Ltd"
│  └─ P "Level 3, 18 Wharf Street, Hobart TAS 7000⏎(03) 5550 0142 · …"
├─ P "21 September 2026"
├─ P "Ms Priya Raman⏎Operations Manager⏎…⏎Fremantle WA 6160"
├─ P "Dear Ms Raman,"
├─ P "Subject: " Strong "Extended warranty for your Level 2–5 fit-out"
├─ P ×6   (one containing Span Lang=fr "Atelier Beaulieu")
├─ L ListNumbering=Decimal ── LI ×4 (Lbl "1."…"4.", LBody ── P)
├─ P ×2
├─ P "Yours sincerely,"
├─ P "Tom Finch"
├─ P "Director, Harbour & Finch Pty Ltd"
├─ P "Enclosure: Schedule 1, covered items"
└─ Sect
   ├─ H1 "Schedule 1. Covered items"
   └─ Table ── Caption, THead, TBody ── TR ×8
```

The lead region's blocks are semantic and come first in reading order,
because the letterhead identifies the sender. Spacers and page breaks produce
no structure. Artifacts: logo and first-page footer (`Header`, `Footer`),
continuation header text (`Header`), `Page N of M` (`PageNumber`), table
rules.

### Expected appearance

- Page 1: logo top-right; letterhead lines start-aligned in the lead region;
  body begins 12 pt below the lead region with the date, recipient block,
  salutation, subject line, and body paragraphs; centered footer.
- Page 2: continuation header (recipient and date start-aligned, `Page 2 of 3`
  end-aligned); remaining paragraphs, the list, closing, and the unsplit
  signature block with 36 pt of empty space above the signatory's name;
  enclosure line.
- Page 3: continuation header; the schedule heading at the top of the body
  (explicit break); the table.
- Invariants: the signature block is never split; the explicit break always
  starts the schedule on a new page; `Page N of M` is exact.
- Reviewed composition (`reference-documents-v10`, MuPDF 1.28.2 render of
  `examples/warranty-letter/warranty-letter.pdf`): three pages. Page 1 holds the letterhead,
  date, recipient, salutation, subject, and body paragraphs 1–4; page 2
  paragraphs 5–6, the list, the closing paragraphs, the signature block,
  and the enclosure line; page 3 the schedule. The schedule dates read
  `30 Sep 2031` so that each fits the 96 pt column on one line. LET-A2 (60
  body paragraphs) occupies exactly 11 pages.

### Adverse variants

| ID | Change from ordinary | Policy | Expected outcome |
| --- | --- | --- | --- |
| LET-A1 | Recipient name, position, organization, and address lines of 80–110 characters each | defaults | Accepted. Each line wraps inside the recipient paragraph at UAX #14 opportunities; subsequent content moves down. |
| LET-A2 | Ten pages of letter text (60 body paragraphs) | defaults | Accepted. Pages 2–10 use the continuation template with exact `Page N of 11` values (schedule included). |
| LET-A3a | Lead region height 640 pt | defaults | `layout.template_body_space` naming the first-page template, each region height, and the remaining body height (less than one body line). Detected before flow. No bytes. |
| LET-A3b | Letterhead with twelve lines in the 60 pt lead region | defaults | `layout.template_region_overflow` naming the lead region (`templates.first.lead`), with the content and reserved heights in the message. No bytes. |
| LET-A3c | Continuation header slot texts whose combined widths exceed the region width | defaults | `layout.template_region_overflow` naming the region and slots. No bytes. |
| LET-A4 | The ordinary letter (no visible title) under `Archive` and, from Gate 7, `AccessibleArchive` | profile | Accepted. No diagnostic requires a visible title. Gate 6 evidence checks XMP `dc:title` equals the metadata title and the catalog sets `DisplayDocTitle true`. Until Gate 7, `AccessibleArchive` still reports `profile.accessible_archive`. |
| LET-A5 | Empty metadata title | defaults | The existing typed metadata error. No bytes. |
| LET-A6 | Signature block taller than a continuation body (e.g. a 700 pt spacer) | defaults | `layout.keep_conflict` naming the keep group and its first and last members. No bytes. |
| LET-A7 | `Pdf.page_number` used inside a body paragraph | defaults | `document.generated_reference` (`FeatureUnavailable`, Gate 8). Page fields are furniture-only in v1. No bytes. |

### Author obligations

- Letterhead content in the lead region is genuine sender identification;
  purely decorative letterhead graphics go in furniture.
- The metadata title describes the letter; it is not a placeholder.
- The subject line and signature are paragraphs in reading order; spacing
  conveys no meaning.
- The recipient block is the recipient's real address in reading order.

## Declared production text support

This matrix is the facade's declared production text support for this record
(unchanged since `reference-documents-v1`). It distinguishes the one-import
facade from the advanced positioned-run boundary, which has its own closed rows
in the [text-layout closure review](performance/text-layout-closure.md). A row
is supported only when its evidence exists; rows marked **required** are
additions the references need and that Gate 6 slices must close. Each
unsupported row names its stable rejection. No row is satisfied by font
substitution, outlining, rasterization, or dropping text.

| Script or feature | Facade | Advanced boundary | Evidence or diagnostic |
| --- | --- | --- | --- |
| Latin (`Latn`), horizontal LTR, packaged face coverage: Basic Latin, Latin-1 Supplement except U+00AD, Latin Extended-A, general punctuation subset, `€`, `™`, arrows, U+2212 | supported | supported | [public-pdf-facade.md](performance/public-pdf-facade.md), [facade-shaping.md](performance/facade-shaping.md), [facade-line-layout.md](performance/facade-line-layout.md) |
| Latin through one caller-registered face | supported | supported | [caller-font-facade.md](performance/caller-font-facade.md), [caller-font-text.md](performance/caller-font-text.md) |
| Han (`Hani`), horizontal, through a caller-registered face in an ordered policy | supported | supported | [multiface-public-facade.md](performance/multiface-public-facade.md), [cjk-text.md](performance/cjk-text.md) |
| Ordered multi-face per-cluster selection over `{Latn, Hani}` | supported | supported | [multiface-public-facade.md](performance/multiface-public-facade.md), [multiface-font-selection.md](performance/multiface-font-selection.md) |
| Pinned UAX #14 line breaking and UAX #29 grapheme segmentation | supported | supported | [line-layout.md](performance/line-layout.md), [uax-boundary-vectors.md](performance/uax-boundary-vectors.md) |
| Precomposed Latin letters with diacritics (one scalar per cluster) | supported | supported | facade shaping records above |
| Generated list labels | supported | supported | [generated-labels.md](performance/generated-labels.md) |
| Scalars outside the selected faces' coverage | rejected | rejected | `text.coverage_missing`, located at the paragraph or inline with the cluster's scalars |
| Scripts outside `{Latn, Hani}` (e.g. Arabic, Hebrew, Devanagari, Thai) | rejected | per closed row | `text.unsupported_script`, located likewise |
| Right-to-left and bidirectional text | rejected | supported | facade: `text.unsupported_script`; advanced: [rtl-text.md](performance/rtl-text.md) |
| Decomposed combining sequences (multi-scalar clusters) | rejected | supported | facade: `text.unsupported_cluster`; advanced: [combining-text.md](performance/combining-text.md) |
| Supplementary-plane scalars | rejected | supported | facade: `text.coverage_missing` for the packaged face, `text.unsupported_script` otherwise; advanced: [supplementary-text.md](performance/supplementary-text.md) |
| OpenType ligatures (GSUB) | not applied | supported | facade shapes without GSUB, so no ligature is formed and none is claimed; advanced: [fi-ligature.md](performance/fi-ligature.md) |
| Soft hyphen U+00AD | rejected | supported | facade: `text.coverage_missing` (the packaged face does not map U+00AD); advanced: [soft-hyphen.md](performance/soft-hyphen.md) |
| Case transformation | not offered | supported | no facade constructor; advanced: [case-transformation.md](performance/case-transformation.md) |
| Automatic hyphenation | not offered | not offered | no language pattern set is claimed |
| Vertical writing | rejected | rejected | `text.vertical_writing` (Gate 8) |
| Nested language spans within one paragraph (`fr` in `en-AU` through the packaged face; `zh-Hans` in a Latin paragraph through an ordered policy whose faces cover it) | supported | — | [rich-inline.md](performance/rich-inline.md); an unsupported script inside a span rejects as `text.unsupported_script` with its inline path. REP-A5's spaces around a Han span take the Common-run row below |
| Rich inline runs (`Em`, `Strong`, `Code`, `Quote`, `Link`, `Span`) with per-run theme colors in one line, wrapping across inline boundaries | supported | — | [rich-inline.md](performance/rich-inline.md) |
| A distinct caller-registered face per inline role (e.g. monospace `Code`) under style faces | supported | — | [rich-inline.md](performance/rich-inline.md): `Theme.with_inline_font`; the innermost role with a face decides a run's face at the paragraph's size and leading; under an ordered policy `text.inline_font_policy` (`FeatureUnavailable`) |
| Runs whose script stays Common (or Inherited) after itemization, e.g. a cell holding only `1,284` or `+10.0%`, or the spaces in `Café 中 PDF`, under an ordered policy | supported | — | [tables.md](performance/tables.md): each cluster of such a run takes the first face in policy order that covers it, exactly as per-cluster coverage selection does for declared scripts; no script-specific shaping is applied because the convenience shaper applies none. The single-face path is unaffected. |
| Furniture text (headers, footers, page fields) shaped with exact artifact ownership, through the single theme face or an ordered policy | supported | — | [page-templates.md](performance/page-templates.md); under an ordered policy each furniture cluster selects its face exactly as body text does, a furniture-only face becomes an extra output font, and pieces split at face boundaries (`reference-documents-v8`); uncovered or undeclared-script furniture text is `text.coverage_missing` or `text.unsupported_script` at its item path |

The text diagnostics above are located (`reference-documents-v8`): each
names the paragraph, list item, or rich inline that holds the first text in
document order that cannot be shaped, and the failing cluster's scalar range
relative to that text, on both the single-face and ordered-policy paths. Per
cluster, the declared-script check (`{Latn, Hani}` with Common and Inherited)
runs before the cluster check and both before coverage, so an unsupported
script is never reported as a coverage gap. On the single-face path Han is
declared but shaped only through an ordered policy: uncovered Han is
`text.coverage_missing` and covered Han `text.unsupported_script`.
`InvalidFontSelection` remains only for policy construction errors.

## Layout policy vocabulary

This is the contract later Gate 6 slices implement. Every rule has a defined
outcome or a structured error; there is no undocumented recovery mode.

### Regions and containment

- The page body frame is the page minus the theme margins. A page template
  reserves a header region at the top and a footer region at the bottom of the
  body frame, each of fixed authored height, separated from the flow region by
  the template's gap. The first-page template may also reserve a lead region
  below its header. Body flow is confined to the remaining flow region.
- Template validation runs before flow. If a template's flow region is shorter
  than one line of the body style, preparation fails with
  `layout.template_body_space`.
- Lead-region blocks are laid out once, in the lead region's width, as one
  unsplittable unit; exceeding the reserved height fails with
  `layout.template_region_overflow`. They are semantic and precede body
  contents in reading order.
- Header and footer regions each have three slots (`start`, `center`, `end`).
  Each slot holds a vertical stack of furniture items. Each furniture text item
  is exactly one line. If stacked items exceed the region height, or the slot
  contents overlap horizontally, preparation fails with
  `layout.template_region_overflow`.
- (`reference-documents-v6`) A present region reserves a positive height and
  holds at least one furniture item; otherwise `layout.template_region_empty`
  (`no_region` reserves nothing and no gap). A template gap must not be
  negative (`layout.spacer_negative`, path `templates.first.gap`). A
  templated document needs at least one body block
  (`layout.template_body_empty`).
- (`reference-documents-v6`) A header's slot stacks sit on the region's
  bottom edge and a footer's hang from its top edge, beside the body flow;
  items stack top to bottom in authored order. Start items align to the
  body frame's start edge, end items to its end edge, and center items are
  centered on it. A text item is one body-style line (its height is the
  body leading, its baseline one body size below its top); a drawing
  item's size is its drawing's extent.
- (`reference-documents-v6`) On each page, header furniture text paints
  before the body text and footer furniture text after it; furniture
  drawings paint after the page's text and table rules. A furniture line
  holding a page field is a `PageNumber` artifact (`/Subtype /PageNum`);
  every other item takes its region's kind (`/Header` or `/Footer`).
- (`reference-documents-v6`) Widths are proven for every painted page with
  its resolved field values: each reserved width must hold its content, each
  item the body frame's width, and the slots must not overlap. A template
  that paints on no page (the continuation template of a one-page document)
  has only its heights, inlines, and drawings validated.
- Every placed fragment lies inside its container (flow region, table cell, or
  template slot). Content is never clipped, scaled, or dropped to satisfy
  containment.

### Mandatory constraints

Mandatory constraints are never relaxed. A violation or a conflict among them
is an error naming every participating source.

| Constraint | Source | Violation |
| --- | --- | --- |
| Containment | geometry | `layout.oversize_block`, `layout.oversize_row`, `layout.unbreakable_token`, `layout.table_width`, `document.figure_oversize` |
| Reserved template regions | page templates | `layout.template_body_space`, `layout.template_region_overflow` |
| Unsplittable content | lines, headings and titles (theme), figures with captions, custom blocks declaring `Unsplittable`, `Pdf.keep_together` groups, table rows under `KeepRows`, the table footer group, the lead region | `layout.oversize_block`, `layout.oversize_row`, `layout.keep_conflict` |
| Table start | caption + header rows + the first body row's first line are placed together | `layout.keep_conflict` if they cannot fit on a fresh page |
| Required keep | `Pdf.keep_with_next(Required, block)` chains, binding the kept block's end to the next block's first placement unit | `layout.keep_conflict`, also when an explicit break follows or no block follows |
| Explicit page break | `Pdf.page_break` between two flow blocks | strictly inside a `Pdf.keep_together` or after a required keep: `layout.keep_conflict`; first, last, or directly after another break: `layout.page_break_position` |

A block's **first placement unit** is the keep-together group it starts, the
whole block when it is unsplittable, or else its first orphan-minimum lines.
Keeps bind a block to the next block's first placement unit. A page break at
the edge of a `Pdf.keep_together` (its first or last item) does not split the
group and is accepted.
| Field fit | page and total-page fields | `layout.field_overflow` |

A fresh page never receives nothing: if the next unit cannot be placed on an
empty flow region, the result is the error for that unit, never an empty page
or an infinite loop.

### Ranked preferences

Preferences choose among breaks that already satisfy every mandatory
constraint. They are ranked; a higher rank is never sacrificed to satisfy a
lower one.

| Rank | Preference | Default |
| --- | --- | --- |
| R1 | A heading or title keeps with the next block's first placement unit (and that block's orphan minimum) | on (theme) |
| R2 | Author `Pdf.keep_with_next(Preferred, block)`, binding the next block's first placement unit | as authored |
| R3 | The table footer group carries at least one body row onto its page | on (reserved for the table slice) |
| R4 | Orphan minimum: at least *k* lines of a paragraph at the bottom of a page | *k* = 2 (theme) |
| R5 | Widow minimum: at least *k* lines of a paragraph at the top of a page | *k* = 2 (theme) |

Break selection, per page, in a single forward pass:

1. Collect the legal break candidates from the page's first unit up to the
   last position at which placed content still fits and every mandatory
   constraint holds.
2. Score each candidate by the vector (R1 satisfied, ..., R5 satisfied) and
   choose the lexicographically greatest vector.
3. Break ties by choosing the latest candidate (most content on the current
   page). Candidates are distinct positions, so the choice is unique.
4. If the chosen candidate leaves some preference unsatisfied, that
   preference is relaxed for this break. The preparation report records the
   rank, the constraint source, the affected blocks, and the page. A
   relaxation is not an error and cannot mask a mandatory violation.

Content deferred by an earlier break is placed on the next page and is laid
out at most once more; measurements are cached by their complete key.

The scan keeps scalar state only: the page start, the running height, and the
best candidate so far. Required keeps make a candidate illegal; keep-together
groups and unsplittable blocks are atomic units whose inner positions are not
candidates. An explicit page break reachable from the page start ends the page
there; a preference that binds across it (R1 or R2 of the block before it)
cannot hold at that break and is recorded as relaxed. When a fresh page has no
legal candidate, the unit at its start is the error: `layout.oversize_block`
for an unsplittable block, `layout.keep_conflict` for a keep. Each page scans
at most one page of positions past its chosen break, so the candidate visits
grow linearly with the document; there is no backtracking across pages.

### Spacing

- Block spacing before and after comes from the theme and is never relaxed.
- Spacing that would fall at the top of a flow region is suppressed, so a page
  never begins with block spacing. `Pdf.spacer` is authored space: it is kept
  everywhere except as the first placement on a page, where it is suppressed.
  Inside a `Pdf.keep_together`, a spacer moves with its group.
- A spacer adds its height after the flow block before it, on top of that
  block's theme spacing; a spacer before the first block is at the top of the
  first page and therefore suppressed. A negative spacer is
  `layout.spacer_negative`. Consecutive blocks inside one outermost list have
  no paragraph spacing between them.

### Oversize policy

- A unit taller or wider than an empty flow region is rejected by default:
  `layout.oversize_block` for blocks and custom blocks, `layout.oversize_row`
  for rows under `KeepRows`, and `document.figure_oversize` for figures.
- A figure may explicitly select `Pdf.figure_fit(figure, ScaleToFit({
  minimum_percent }))`. The figure (not its caption) is scaled uniformly by the
  largest factor ≤ 1 that fits the flow region width and an empty page's flow
  height together with its caption. A scale below the floor is
  `document.figure_oversize`. The applied scale appears in the preparation
  report. No other content is ever scaled.
- (`reference-documents-v7`) The factor is in thousandths, the largest `s ≤
  1000` with `w·s/1000` within the flow width and `⌈h·s/1000⌉` within the
  flow height less the rest of the figure's unit (the paragraph spacing and
  caption lines, and any decoration above it). Under page templates the flow
  height is the smaller of the first and continuation frames, so the scaled
  unit fits a fresh page of either kind; an `Exact` figure is checked against
  the larger frame, as every other unsplittable unit is. A floor above 100
  is `document.figure_fit`.
- (`reference-documents-v7`) A figure is placed start-aligned at the flow
  edge as one unsplittable unit with its caption (a required keep), the
  paragraph spacing between them; the caption uses the body style.
- (`reference-documents-v7`) A decoration (`Pdf.decoration`) occupies its
  drawing's height immediately above the next flow block and is part of
  that block's first placement unit, so it always lands on the page where
  that block starts and is never separated from it or clipped. It needs a
  following flow block and may not appear in a list item or a lead region
  (`layout.decoration_position`, `semantics.list_item_content`); a
  decoration wider than the flow region or taller than a page's flow region
  is `layout.oversize_block`.

### Unbreakable tokens

Lines break only at pinned UAX #14 opportunities and explicit
`Pdf.line_break`s. A token without an opportunity that is wider than the widest
width its container can receive is `layout.unbreakable_token`. There is no
emergency breaking, character-level wrapping, ellipsis, or overflow in v1.

An explicit line break splits its paragraph into segments, each its own
interned source, so the break is a mandatory line boundary. Its separator is
a U+0020 at the end of the text before it (`reference-documents-v8`), painted
invisibly at the end of the line so extracted and structure-order text keep
the word boundary; text already ending in a space gains none. Otherwise the
break paints no glyph, and two paragraphs that differ only in break positions never share a
line-cache identity. Every segment must hold text:
`semantics.line_break_position` otherwise.

### Lists

Each list has a label column: the theme list indent (`Theme.bullet_indent`),
or, when the list's widest generated label does not fit it, that label's
width plus half the label size (`reference-documents-v8`). A list's items'
blocks are indented by the columns of all enclosing lists, and each item's
generated label is painted start-aligned in its own list's column before its
first paragraph's first line. A label has no break opportunity and is never
shrunk or allowed to overlap its body; a column that leaves its body no width
is `layout.list_label_width`. An item holds paragraphs, rich paragraphs,
and nested lists and begins with a paragraph; lists nest at most four deep.
Labels are `•` for bullet lists, and for numbered lists the number in its
style followed by a full stop (`7.`, `c.`, `iv.`, `XII.`); lower and upper
letters are bijective base 26 (`z.`, `aa.`). Each `L` declares its
`ListNumbering` (`/Disc`, `/Decimal`, `/LowerAlpha`, `/UpperAlpha`,
`/LowerRoman`, or `/UpperRoman`).

### Tables

- Column widths are resolved once per table, before any cell line is
  broken, from measured cell widths: a cell's max-content width is its
  widest line between mandatory breaks and its min-content width its widest
  piece between UAX #14 opportunities (with the trailing space a line would
  carry), both plus the theme's cell padding on each side. A column's
  minimum and maximum are those of its single-column cells; spanning cells
  are checked against their resolved spans afterwards. `Fixed` widths are
  exact; `Content` columns take their max-content width, reduced toward
  their min-content width only as needed, in proportion to each column's
  slack; the remaining width is divided among `Share` columns in proportion
  to their weights, a share below its column's minimum being fixed at that
  minimum and the rest redistributed. Any millipoint remainder is assigned
  left to right. Without `Share` columns a table may be narrower than the
  flow. If fixed widths plus all minima exceed the table width, preparation
  fails with `layout.table_width`; a single column whose minimum exceeds its
  fixed width or the flow width, or a spanning cell whose widest piece
  exceeds its resolved span, is `layout.unbreakable_token`, naming the cell
  and the piece's scalar range.
- Cell content is a sequence of inlines forming one paragraph (explicit line
  breaks included). Cells wrap within their column text width; there is no
  block flow inside cells in v1. A cell must hold text (`table.cell_empty`).
  A cell's lines align by their visible advance (trailing spaces excluded)
  in the alignment of the first column it spans, or in its own alignment
  when authored with `Pdf.aligned(align, cell)` (`reference-documents-v8`); lines start at the top of
  the row.
- Every row's spans must sum to the table's column count, and every span is
  at least one (`table.grid_mismatch`). Column spans are supported; a cell
  declared with `Pdf.row_spanning` is rejected as `table.row_span` until
  Gate 8. A table needs a column and a body row (`table.empty`) and at least
  one header cell (`table.header_missing`).
- A row's height is its tallest cell's line count times the cell leading;
  rows are separated by the theme's row gap. The caption is unsplittable
  and required to keep with the header rows, which are unsplittable and
  required to keep with the first body row's first placement unit, so the
  table start is placed together (`layout.keep_conflict` otherwise).
- `row_split: KeepRows` (default): a row is unsplittable; a row that does not
  fit moves to the next page; a row taller than an empty flow region, after
  the repeated header rows, is `layout.oversize_row`.
- `row_split: SplitRows`: a row may break at a line of its grid: all of a
  row's cells share one leading and start at its top, so every grid line is
  a line boundary of every cell. The largest such position that fits is
  chosen, cells that finished earlier paint nothing further, and the widow
  and orphan minimums apply to the row's grid (its tallest cell).
- Header rows are declared once. On every page where the table continues
  (the page starts at a body or footer row, including a split row's
  continuation), they are repainted at the top of the page as a
  repeated-table-header pagination artifact (`/Artifact <</Type
  /Pagination>>`, the `RepeatedHeader` page-artifact kind): body and footer
  rows reserve the header rows' height, with the gap after them, at the top
  of any page they start or continue on. The logical `THead` is emitted
  once, and no new logical header cells or relationships are invented.
- Footer rows are unsplittable and, when there are several, form one
  required group placed once, after the last body row; the last body row
  keeps with them by preference R3.
- A rule of the theme's color and width is drawn centered in the row gap
  below the last header row (the original and every repainted copy) and
  above the first footer row when a body row precedes it on the page, across
  the table width, as a `Decoration` artifact; it must fit inside the gap
  (`layout.table_rule`). Header-row shading is not offered in v1.
- `Headers` associations are derived from declared scopes, never geometry:
  a data cell references the `Column`- or `Both`-scoped header cells of
  earlier rows in the columns it spans (all header rows, including spanning
  cells), in ascending cell order without repeats, then the `Row`- or
  `Both`-scoped header cells of its own row. Header cells carry no
  `Headers`. Every cell carries a generated element identifier (`c` and its
  one-based cell ordinal in six digits, so identifier order is cell order),
  and each `Headers` entry is also a typed `HeaderFor` relationship; the
  kernel rejects any disagreement between the two.

### Page and total-page fields

Page fields exist only in page-template furniture in v1. `Pdf.page_number` is
the 1-based physical page index; `Pdf.total_pages` is the physical page count;
each is written in the `NumberStyle` it is given (`reference-documents-v6`;
formerly decimal only): `Decimal`, `LowerAlpha`, `UpperAlpha`, `LowerRoman`,
or `UpperRoman`, as list labels are, without the full stop. Page labels
authored with `Pdf.with_page_labels` are unaffected and are the author's
responsibility to keep consistent.

Because template regions have fixed heights, furniture never changes body
pagination. Stabilization therefore follows the architecture's state model
with an exact, fixed outcome:

1. State S0: no resolved references.
2. Pass 1 paginates the body and produces state S1: the page count *M* and each
   page's index.
3. Pass 2 shapes every furniture item using S1's values, verifies its fit,
   and recomputes the state. It must equal S1, so the result is
   `Stable({ passes: 2 })`.
4. Fit proof: a field in a `Pdf.reserved_width(width, align, inlines)` is
   shaped with its resolved value and must fit within `width`; a field without
   a reserved width must fit, with its whole furniture line, within its slot.
   Otherwise the result is `layout.field_overflow`. The value is never
   approximated, abbreviated, or shrunk.
5. The pass budget is fixed at 4 for v1. Exhaustion is `layout.budget_exhausted`
   and repetition of an earlier non-identical state is
   `layout.reference_cycle`. Neither is reachable with furniture-only fields;
   both are exercised through the `Layout.Stabilization` harness with
   synthetic reference systems until flow-affecting references
   (`document.generated_reference`, Gate 8) exist.
6. (`reference-documents-v6`) Pass 2 recomputes its state from the pass-1
   pagination it received. Flow frames are fixed from region heights before
   flow and no pass can change them, so pass 2's state equals S1 by
   construction and the driver confirms it by exact comparison.

### Diagnostic codes

Every code below is stable, identifies the authored location (a compact block
path such as `contents[4].table.body_rows[17].cells[1]` plus an optional scalar
range), and is returned from preparation with no `Prepared` value and no PDF
bytes. Codes marked *new family* use the `Conformance.DiagnosticCode`
alternative `LayoutConstraintViolated`, added by the lists-and-layout-policies
slice (`reference-documents-v4`). Their dotted code rides in the existing
`FeatureReference` field and `details` lists the authored path of every
participating source in a fixed order: a keep conflict names the keep and
then its first and last member, the explicit break, or the block it keeps
with.

| Code | Family | Meaning |
| --- | --- | --- |
| `layout.keep_conflict` | new family | Required keeps, unsplittable groups, table-start units, or explicit breaks cannot be satisfied together |
| `layout.oversize_block` | new family | An unsplittable block or custom block exceeds an empty flow region (a figure reports `document.figure_oversize`) |
| `layout.oversize_row` | new family | A `KeepRows` row exceeds an empty flow region |
| `layout.unbreakable_token` | new family | A token with no break opportunity exceeds its container |
| `layout.table_width` | new family | Fixed widths plus column minima exceed the table width |
| `layout.field_overflow` | new family | A resolved page field does not fit its reserved width or slot |
| `layout.template_body_space` | new family | Template regions leave less than one body line of flow |
| `layout.template_region_overflow` | new family | Lead or furniture content exceeds its region or slots overlap |
| `layout.furniture_inline` | new family | An inline other than text, page fields, or reserved width appears in furniture |
| `layout.template_region_empty` | new family | A region reserves no height or holds no furniture item (`reference-documents-v6`) |
| `layout.template_body_empty` | new family | A document with page templates has no body block (`reference-documents-v6`) |
| `layout.furniture_drawing` | `InvalidRelationship` | A furniture drawing has no command, a group, a non-positive image size, a path that paints nothing, or content below or left of its origin (`reference-documents-v6`) |
| ~~`text.furniture_policy`~~ | — | Retired in `reference-documents-v8`: furniture text is executable under an ordered font policy |
| `text.inline_font_policy` | `FeatureUnavailable` | An inline role face under an ordered font policy (`reference-documents-v8`) |
| `layout.reference_cycle` | `LayoutCycle` | Stabilization repeated an earlier non-identical state |
| `layout.budget_exhausted` | `BudgetExceeded` | Stabilization or layout work budget exhausted |
| `table.grid_mismatch` | `InvalidRelationship` | Row spans do not sum to the column count |
| `table.header_missing` | `InvalidRelationship` | A table declares no header cell |
| `table.row_span` | `FeatureUnavailable` | Row spans (Gate 8) |
| `table.empty` | `InvalidRelationship` | A table declares no column or no body row |
| `table.cell_empty` | `InvalidRelationship` | A table cell holds no text |
| `layout.table_rule` | new family | The theme's table rule is wider than the row gap it is drawn in |
| `document.content_limit` | `BudgetExceeded` | The document crosses a documented facade content bound; `details` names the table or block at which planning crossed it |
| `text.unsupported_script` | `FontCoverageMissing` | Script outside the declared facade set |
| `text.coverage_missing` | `FontCoverageMissing` | No selected face covers a cluster |
| `text.unsupported_cluster` | `FontCoverageMissing` | A multi-scalar cluster reaches the one-scalar convenience shaper |
| `document.figure_oversize` | new family | A figure exceeds the flow region or its fit floor |
| `document.figure_alternative_empty` | `InvalidRelationship` | A figure's alternative text is empty |
| `document.figure_drawing` | `InvalidRelationship` | A figure's drawing has no painting command, a non-positive image size, a path that paints nothing, content below or left of its origin, groups nested more than 8 deep, a clip, opacity, or soft-mask group, or a coordinate beyond 10^9 pt (`reference-documents-v7`) |
| `document.figure_caption_empty` | `InvalidRelationship` | A figure's visible caption is empty (`reference-documents-v7`) |
| `document.figure_fit` | `InvalidRelationship` | `figure_fit` on a block that is not a figure, or a `ScaleToFit` floor above 100 (`reference-documents-v7`) |
| `layout.decoration_drawing` | `InvalidRelationship` | A decoration's drawing is not a valid flow drawing, as for `document.figure_drawing` (`reference-documents-v7`) |
| `layout.decoration_position` | new family | A decoration has no following flow block, or appears in a lead region (`reference-documents-v7`) |
| `semantics.heading_skip` | `InvalidRelationship` | A heading is more than one level deeper than its predecessor |
| `semantics.nested_link` | `InvalidRelationship` | A link contains a link |
| `semantics.link_text_empty` | `InvalidRelationship` | A link has no text content |
| `semantics.link_uri` | `InvalidRelationship` | An `inline_link` URI fails the navigation URI grammar |
| `semantics.language_tag` | `InvalidLanguage` | An `in_language` tag is not a well-formed BCP 47 tag |
| `semantics.inline_empty` | `InvalidRelationship` | A rich paragraph has no text, or an inline text, code, expansion, or element is empty |
| `semantics.inline_depth` | `BudgetExceeded` | Inline elements nest more than 8 levels deep |
| `semantics.container_depth` | `BudgetExceeded` | Parts, sections, and divisions nest more than 16 levels deep |
| `semantics.empty_container` | `InvalidRelationship` | A part, section, or division contains no semantic block |
| `semantics.list_empty` | `InvalidRelationship` | A list has no items |
| `semantics.list_item_empty` | `InvalidRelationship` | A list item has no blocks |
| `semantics.list_item_content` | `InvalidRelationship` | A list item holds a block other than a paragraph, rich paragraph, or list (including a page break or spacer), or does not begin with a paragraph |
| `semantics.list_depth` | `BudgetExceeded` | Lists nest more than 4 deep |
| `semantics.list_numbering` | `InvalidRelationship` | A generated number is not representable: letters or Roman numerals from 0, or Roman numerals beyond 3999 |
| `semantics.line_break_position` | `InvalidRelationship` | A line break begins or ends its paragraph or directly follows another |
| `layout.keep_empty` | new family | A keep holds no laid-out block |
| `layout.page_break_position` | new family | A page break is first or last in the flow, or directly follows another |
| `layout.spacer_negative` | new family | A spacer has a negative height |
| `layout.list_label_width` | new family | A list's widened label column leaves its body no width |
| `layout.custom_block_measure` | new family | A custom block's measured box is not positive, its inset is not positive or leaves no content box, or its laid-out content is taller than its measured height less twice its inset (`reference-documents-v9`) |
| `layout.custom_block_drawing` | `InvalidRelationship` | A custom block's panel is not a valid flow drawing, holds an image, or extends beyond the measured box (`reference-documents-v9`) |
| `semantics.custom_block_content` | `InvalidRelationship` | A custom block holds something other than paragraphs and rich paragraphs (`details`: the block, then the child), or appears in the lead region (`reference-documents-v9`) |
| `semantics.custom_block_name` | `InvalidRelationship` | A custom block's name is empty (`reference-documents-v9`) |
| `report.budget_exceeded` | `BudgetExceeded` | The preparation report would exceed its entry or text-byte budget; no report and no prepared document are returned (`reference-documents-v9`) |

Container diagnostics (from `reference-documents-v2`) carry their dotted code
in the existing `FeatureReference` field and the compact block path of the
offending container, such as `contents[3].contents[0]`, as the diagnostic's
single `details` entry; their location is `Document`. Later codes follow the
same convention. Rich-inline diagnostics (from `reference-documents-v3`)
extend the paragraph's block path with the authored inline positions, such as
`contents[2].inlines[1].inlines[0]`; `text.unsupported_script` and
`text.unsupported_cluster` use it for text inside a rich paragraph.

Existing codes keep their meaning: `document.generated_reference`,
`text.vertical_writing`, `profile.accessible_archive`, and the typed
`InvalidNavigation` and metadata errors (an inline internal link to an
unknown destination is still `InvalidNavigation(UnknownDestinationName)`).
Placeholder codes that Gate 6 retires as its constructors become executable
(`semantics.rich_inline` and `semantics.nested_language`, retired by the
rich-inline slice; `semantics.containers`,
`semantics.text_properties`, `table.simple`, `layout.page_template`) stop
being returned for the supported subset. The template slice
(`reference-documents-v6`) corrects the facade's roadmap label for
`layout.page_template` to Gate 6; no supported construct returns it. A page
field or reserved width in body content reports
`document.generated_reference` (`FeatureUnavailable`) with its inline path,
such as `contents[4].inlines[1]`; furniture diagnostics name template paths
such as `templates.first`, `templates.first.lead`,
`templates.continuation.header`, or
`templates.continuation.footer.end[0].inlines[0].inlines[1]`.

## Planned authoring vocabulary

These are the proposed public names the outlines above use. Later slices may
refine names or shapes, but each refinement updates this section and the
affected outlines. Several current placeholders (`Pdf.rich_paragraph : Str ->
Block`, `Pdf.section : Str -> Block`, `Pdf.simple_table`, `Pdf.page_header`,
`Pdf.page_footer`) are replaced; the migration is recorded in the release
notes of the version that replaces them.

### Inline content

```roc
Inline                    # opaque Pdf.Inline
text : Str -> Inline
emphasis : List(Inline) -> Inline                 # Em
strong : List(Inline) -> Inline                   # Strong
code : Str -> Inline                              # Code
quote : List(Inline) -> Inline                    # Quote; marks are authored text
inline_link : List(Inline), Str -> Inline         # Link + URI annotation
inline_internal_link : List(Inline), Str -> Inline # Link + /SD and /D to a destination name
in_language : Str, List(Inline) -> Inline         # Span with /Lang
expansion : Str, Str -> Inline                    # Span with /E (text, expansion)
line_break : Inline                               # explicit break within a paragraph
page_number : NumberStyle -> Inline               # furniture only
total_pages : NumberStyle -> Inline               # furniture only
reserved_width : Layout.Unit, Align, List(Inline) -> Inline  # furniture only; Align : [Start, End, Center]
rich_paragraph : List(Inline) -> Document.Block
```

`quote` does not generate quotation marks; authors supply them as text so no
generated presentation text is needed. Links may contain other inlines but not
links.

`rich_paragraph`, `text`, `emphasis`, `strong`, `code`, `quote`,
`inline_link`, `inline_internal_link`, `in_language`, and `expansion` are
executable with these names and shapes (rich-inline slice). A rich
paragraph's inlines share one paragraph text: lines break at pinned UAX #14
opportunities computed over the whole paragraph, across inline boundaries.
Inline elements nest at most 8 deep. An inline link becomes one link
annotation per page its text is painted on, with one quadrilateral per
painted line. `line_break`, `page_number`, `total_pages`, and
`reserved_width` are furniture-only. `line_break` is
executable (lists-and-layout-policies slice): it splits the paragraph into
segments, each its own interned source, and must separate text.
`page_number`, `total_pages`, and `reserved_width` are executable in
furniture text (page-templates slice, `reference-documents-v6`); `Pdf.Align`
names the reserved width's alignment type.

### Blocks and grouping

```roc
part : List(Block) -> Block          # Part
section : List(Block) -> Block       # Sect
division : List(Block) -> Block      # Div
bullet_list : List(ListItem) -> Block
numbered_list : { start : U64, style : NumberStyle }, List(ListItem) -> Block
list_item : List(Block) -> ListItem  # nested lists are ordinary blocks
NumberStyle : [Decimal, LowerAlpha, UpperAlpha, LowerRoman, UpperRoman]

page_break : Block
keep_together : List(Block) -> Block           # required; no structure element
keep_with_next : Keep, Block -> Block          # Keep : [Required, Preferred]
spacer : Layout.Unit -> Block                  # layout-only vertical space
```

Existing `title`, `heading`, `paragraph`, `bullets`, `destination_heading`,
`destination_paragraph`, `link`, `internal_link`, `with_outline`, and
`with_page_labels` remain.

`bullet_list`, `numbered_list`, `list_item`, `NumberStyle`, `page_break`,
`keep_together`, `keep_with_next` (with `Keep : [Required, Preferred]`), and
`spacer` are executable with these names and shapes
(lists-and-layout-policies slice, `reference-documents-v4`); see
[Lists](#lists), [Mandatory constraints](#mandatory-constraints), and
[Spacing](#spacing) for their rules. `bullets` also declares
`ListNumbering /Disc`.

`part`, `section`, and `division` are executable (semantic-foundation slice).
Grouping has no layout effect, a container must contain at least one semantic
block, and containers nest at most 16 levels deep; see the container
diagnostics under [Diagnostic codes](#diagnostic-codes).

### Tables

```roc
table : {
    caption : Document.Caption,
    columns : List(Column),
    header_rows : List(Row),
    body_rows : List(Row),
    footer_rows : List(Row),
    row_split : RowSplit,                        # RowSplit : [KeepRows, SplitRows]
} -> Block
Column : { width : [Fixed(Layout.Unit), Share(U16), Content], align : [Start, End, Center] }
row : List(Cell) -> Row
cell : List(Inline) -> Cell                      # TD
header_cell : Scope, List(Inline) -> Cell        # TH; Scope : [Column, Row, Both]
spanning : U16, Cell -> Cell                     # column span only
aligned : Align, Cell -> Cell                    # overrides the first spanned column's alignment
row_spanning : U16, Cell -> Cell                 # represented; rejects as table.row_span
```

These are executable with these names and shapes (tables slice,
`reference-documents-v5`); `Pdf.Column`, `Pdf.Row`, `Pdf.Cell`, `Pdf.Scope`,
and `Pdf.RowSplit` name the types, and `Pdf.simple_table` is retired. Table
presentation is `Theme` policy: `with_table_cell_padding`,
`with_table_row_gap`, `with_table_rule` (`Rule({ color, width })` or
`NoRule`), and `with_table_header_color`; cells paint in the body style.

### Page templates

```roc
with_page_templates : Document, { first : FirstPageTemplate, continuation : PageTemplate } -> Document
first_page_template : {
    header : Region,
    lead : LeadRegion,
    footer : Region,
    gap : Layout.Unit,
} -> FirstPageTemplate
page_template : { header : Region, footer : Region, gap : Layout.Unit } -> PageTemplate
region : { height : Layout.Unit, start : List(Furniture), center : List(Furniture), end : List(Furniture) } -> Region
no_region : Region
lead_region : Layout.Unit, List(Block) -> LeadRegion   # semantic letterhead content
no_lead : LeadRegion
furniture_text : List(Inline) -> Furniture       # one line; Header, Footer, or PageNumber artifact
furniture_image : Scene.Drawing -> Furniture     # Header or Footer artifact
```

Only the first-page template can hold a lead region, so a lead region on a
continuation page is unrepresentable rather than rejected. A document without
`with_page_templates` keeps today's template-free pagination. A furniture text
item containing a page field lowers as a `PageNumber` artifact; other items
take their region's kind. The repeated-table-header artifact kind is
`Scene.PageArtifactKind.RepeatedHeader` (tables slice).

These are executable with these names and shapes (page-templates slice,
`reference-documents-v6`); `Pdf.FirstPageTemplate`, `Pdf.PageTemplate`,
`Pdf.Region`, `Pdf.LeadRegion`, and `Pdf.Furniture` name the types, and the
placeholders `Pdf.page_header` and `Pdf.page_footer` (and the compact
builder's `add_page_header` and `add_page_footer`) are retired. A furniture
drawing holds image commands and solid paths (`Scene.solid_fill`,
`Scene.solid_stroke`, `Scene.rectangle`) in drawing-local coordinates
whose origin is the item's bottom-left corner, y upward; its extent is the
union of its commands from that origin, a stroke extending a path by half
its width on every side. Grouped commands report `layout.furniture_drawing`.
The lead region is a `Div` normalized before the body; its content height
(lines and the spacing between its blocks) must fit its height. A page
break inside it is `layout.page_break_position`, a spacer after its last
block is suppressed with the lead's own trailing spacing, and keeps inside
it are subsumed by its single unit.

### Figures, decorations, and extensions

```roc
figure : Scene.Drawing, Str, Document.Caption -> Block   # existing; bounded vector drawings join
figure_fit : Block, FigureFit -> Block    # FigureFit : [Exact, ScaleToFit({ minimum_percent : U8 })]
decoration : Scene.Drawing -> Block       # in-flow Decoration artifact, occupies space
custom_block : CustomBlock -> Block
Scene.Drawing.group : Scene.Drawing, Layout.Point, Scene.Drawing -> Scene.Drawing
```

`figure`, `figure_fit` (with `Pdf.FigureFit`), `decoration`, and
`Scene.Drawing.group` are executable with these names and shapes
(flow-figures slice, `reference-documents-v7`); `custom_block` is executable
with the shape below (custom-block slice, `reference-documents-v9`). A figure or decoration
drawing holds any number of image commands and solid paths
(`Scene.solid_fill`, `Scene.solid_stroke`, `Scene.rectangle`) and
translated groups (`Scene.Drawing.group`, at most 8 deep) in
drawing-local coordinates whose origin is its bottom-left corner, y
upward, with the furniture drawing's extent rule; a decoration is a
`Decoration` page artifact (`/Artifact <</Type /Layout>>`) painted after the
page's text. `figure_fit` on a non-figure block is rejected.

```roc
CustomBlock : {
    contents : List(Block),          # paragraphs and rich paragraphs only
    fragmentation : [Unsplittable],  # the only v1 value
    inset : Layout.Unit,             # content inset on every side, positive
    name : Str,                      # names the block in diagnostics and the report
    panel : Scene.Drawing,           # solid paths in box-local coordinates, behind the content
    size : Layout.Size,              # the extension's measurement of the block
}
```

The document stays data-only: a custom block is a value, with no handler,
callback, private store, PDF object, or operator. Its contract:

- **Semantics.** Its paragraphs keep their own semantics inside a `Div`
  (`Document > … > Div > P`); the block adds no other element. The panel is a
  `Decoration` artifact (`/Artifact <</Type /Layout>>`) owned by the block.
- **Measurement.** The extension measures the block: `size` is its width and
  height in the flow. The package lays the paragraphs out at `size.width`
  less twice the inset, in the body style with paragraph spacing between
  them, and proves that their height fits `size.height` less twice the inset;
  otherwise `layout.custom_block_measure` reports both heights. Content is
  never clipped or shrunk. The block occupies exactly `size.height`; its
  content starts one inset below its top, start-aligned one inset from its
  left edge.
- **Fragmentation.** `Unsplittable`: the block is one keep-together unit
  that moves whole to the next page (with any decoration above it). A block
  wider than its flow region, or taller than the largest page flow region, is
  `layout.oversize_block` naming the block and both sizes (REP-A10).
- **Paint.** The panel is validated like a figure drawing but holds solid
  paths only (no images) and must lie inside the measured box
  (`layout.custom_block_drawing`). It paints first on its page, behind every
  text line, with its origin at the box's bottom-left corner.
- **Placement.** A custom block is body flow at the block level, including
  inside parts, sections, divisions, and keeps; not in a list item
  (`semantics.list_item_content`), a table, or the lead region
  (`semantics.custom_block_content`). Its content holds no nested group,
  decoration, spacer, or page break.

PDF operators and custom pagination are not exposed; continuation of a
custom block across pages is not offered in v1.

### Preparation report

```roc
prepare_with_report : Document, Options -> Try({ prepared : Prepared, report : Report }, Error)
prepare_with_report_budget : Document, Options, ReportBudget -> Try({ prepared : Prepared, report : Report }, Error)
Report : { facts : ReportFacts, obligations : List(ReportObligation) }
ReportFacts : {
    alternatives : List({ kind : [Alternative, Expansion, Language], path : Str, text : Str }),
    blocks : List({ first_page : U64, fragments : U64, last_page : U64, path : Str, role : Str }),
    coverage : List({ font : U64, path : Str, scalars : U64, script : Str }),
    language : Str,
    outcomes : List(ReportOutcome),
    pages : List({ fragments : U64, page : U64 }),
    title : Str,
}
ReportOutcome : [
    CustomBlockPlaced({ height : Layout.Unit, name : Str, page : U64, path : Str }),
    FigureScale({ fit : [Exact, ScaleToFit], path : Str, scale : U64 }),
    PreferenceRelaxed({ page : U64, path : Str, preference : [AuthorKeep, FooterCarry, HeadingKeep, Orphan, Widow] }),
    RepeatedHeader({ page : U64, path : Str, rows : U64 }),
    RowContinued({ page : U64, path : Str }),
]
ReportObligation : { obligation : [AlternativeTextMeaningful, ExpansionAccurate, LanguageAccurate, LinkPurposeMeaningful, ReadingOrderMeaningful, TableHeadersMeaningful], path : Str }
ReportBudget : { max_entries : U64, max_text_bytes : U64 }
```

These are executable with these names and shapes (custom-block slice,
`reference-documents-v9`). Mechanical facts (`facts`) and human-review
obligations (`obligations`) are separate fields. Every observation carries
the authored path diagnostics use; pages count from 1; `blocks` is the
logical reading order of leaf blocks; a figure scale is in thousandths.
`prepare_with_report` uses a budget of 65,536 entries and 4 MiB of text.
The prepared document is the one `prepare` returns, so its bytes are
identical. `ExpansionAccurate` joins the obligation vocabulary with this
version; `LinkPurposeMeaningful` and `LanguageAccurate` are no longer only
proposed. Obligations are one `ReadingOrderMeaningful` and one
`LanguageAccurate` for the document (path `document`), one
`ReadingOrderMeaningful` per custom block, and one per figure, table, link,
nested language, and expansion.

The report is bounded and read-only. It contains authored locations (block
paths), per-page fragment summaries, logical reading order, authored
alternatives and expansions, author assertions, layout-policy outcomes
(relaxed preferences, applied figure scales, row splits, repeated headers),
selected font and script coverage, and human-review obligations
(`AlternativeTextMeaningful`, `ReadingOrderMeaningful`,
`TableHeadersMeaningful`, and proposed `LinkPurposeMeaningful` and
`LanguageAccurate`). It exposes no PDF object identity and retains no discarded
compiler stage or resource payload. Exceeding the report budget is an explicit
error, never silent omission.

## Scale workloads

These workloads exist only to detect super-linear blow-ups. Each is a pair of
public-API documents differing only in the scaled dimension. Counters are
deterministic, so each fixture records exact values; the assertion is on the
growth class between the pair:

- linear: `c(large) ≤ r · c(small)`, where `r` is the scale ratio;
- `n log n`: `c(large) ≤ r · c(small) · log2(n_large) / log2(n_small)`.

A quadratic regression exceeds either bound by roughly a further factor of
`r`. Exact Roc allocation counts are recorded for both sizes and must satisfy
the linear bound. Counter names below use `Layout.Work` where it already has
the field; new names are introduced by the slice that implements them.

| Workload | Small / large | Counter | Class |
| --- | --- | --- | --- |
| Invoice rows | 50 / 500 body rows | `source_visits`, `candidate_visits`, `continuation_steps`, `materialized_fragments` | linear |
| | | `row_visits`, `cell_measurements`, `column_width_passes` (one per table) | linear |
| | | `repeated_header_paints` ((pages − 1) × header rows) | linear |
| | | `header_association_edges`, structure elements, MCIDs | linear |
| Report sections | 10 / 100 sections, each an `H1`, three paragraphs, one four-row table, one internal link to the next section, and one outline entry (footer reserved width sized for three digits) | `source_visits`, `candidate_visits`, `materialized_fragments`, `reference_visits` | linear |
| | | `outline_entries`, `destinations` | linear |
| | | destination-name resolution `comparison_work` | `n log n` |
| Letter pages | 20 / 200 body paragraphs (6 / 36 pages; amended in `reference-documents-v6` from 1 / 10 pages so the continuation template and two-digit page fields scale) | `lines`, `pages`, `fragments`, furniture items shaped, field resolutions | linear |
| | | stabilization passes | constant (2) |

## Optional human review tasks

These tasks are exploratory and do not block slices recorded against this
document. Human review is optional and never blocks Gate 6 or Gate 7 closure
(see the roadmap). Observations record the reader or assistive technology and its
version, the task, the observed outcome, and any limitation.

- Invoice: using table navigation, locate the amount for `HF-CHR-ERG/L4` and
  hear its column and row headers; find the total due; confirm the repeated
  header rows on continuation pages are not announced as new table rows.
- Invoice and report: follow the payment link and the external link; confirm
  the announced link text states its purpose.
- Report: list and navigate headings; jump to `3.2 Timber sourcing` through
  the outline and through the internal link in the summary.
- Report: understand Figures 1 and 2 through their alternative text and hear
  their captions.
- All: hear the nested French span (`Cafetière « Élégance »`, `Atelier
  Beaulieu`, the quoted sentence) pronounced as French.
- Letter: confirm the reader shows the metadata title, that the letterhead is
  read first, and that page furniture is not read as body text.

## Change log

- `reference-documents-v10`: the reference-documents closure makes the three
  references gallery programs and adds `tests/reference_documents`, which
  prepares them and every adverse variant; records the reviewed break
  positions of the three ordinary documents; amends INV-A2a to the `-v5`
  column rule, INV-A3 and the invoice scale workload to an 80 pt page field
  (the 64 pt field of two-digit totals is a `layout.field_overflow`),
  REP-A4 to a 16 pt two-digit field, REP-A5 to the `中` scalar the Han
  fixture covers, and records the constructions of INV-A5, REP-A1, REP-A2,
  and REP-A3 and the exact scale of REP-A6b; puts `Code` and `Quote` in the
  PDF 1.7 standard structure namespace; makes `semantics.heading_skip`
  executable (`details`: the previous heading, then the skipping one); and
  records that destination headings keep with their next block (R1) and are
  unsplittable like every other heading. Figure 2 is a caller-supplied
  128 × 69 baseline sRGB JPEG.

- `reference-documents-v9`: the custom-block slice makes `custom_block`
  (with `Pdf.CustomBlock`), `prepare_with_report`,
  `prepare_with_report_budget`, `Report`, and `ReportBudget` executable;
  fixes the custom block's data-only shape and its semantic, measurement,
  fragmentation (`Unsplittable`), paint (panel behind text), and placement
  contract; fixes the report's fields, outcome and obligation vocabulary
  (adding `ExpansionAccurate`), and budget; and adds
  `layout.custom_block_measure`, `layout.custom_block_drawing`,
  `semantics.custom_block_content`, `semantics.custom_block_name`, and
  `report.budget_exceeded`.

- `reference-documents-v8`: the open-issues slice makes furniture text
  executable under an ordered font policy and retires
  `text.furniture_policy`; adds `Theme.with_inline_font` (a caller face per
  inline role under style faces) and `text.inline_font_policy`; adds
  `Pdf.aligned` for a cell's own alignment and end-aligns the invoice
  totals labels; widens a list's label column for its widest label and
  narrows `layout.list_label_width` to a column that leaves no body width;
  gives each explicit line break a U+0020 separator at the end of the text
  before it; and locates every remaining coverage failure as
  `text.coverage_missing`, `text.unsupported_script`, or
  `text.unsupported_cluster` (Han is declared on both paths, so uncovered Han
  under the packaged face is a coverage gap).
- `reference-documents-v7`: the flow-figures slice makes vector, grouped,
  and multi-command drawings in `figure`, `figure_fit` with `FigureFit`,
  `decoration`, and `Scene.Drawing.group` executable; records the caption
  structure (`Sect ── Figure, Caption ── P` with `CaptionFor`) and why a
  `Div` is not used; fixes the scale factor's precision, the frame
  `ScaleToFit` fits (the smaller page frame), figure placement, and the
  decoration's placement rule; and adds `document.figure_drawing`,
  `document.figure_caption_empty`, `document.figure_fit`,
  `layout.decoration_drawing`, and `layout.decoration_position`.
- `reference-documents-v6`: the page-templates slice makes
  `with_page_templates`, `first_page_template`, `page_template`, `region`,
  `no_region`, `lead_region`, `no_lead`, `furniture_text`,
  `furniture_image`, `page_number`, `total_pages`, and `reserved_width`
  executable; `page_number` and `total_pages` take a `NumberStyle`; retires
  `Pdf.page_header` and `Pdf.page_footer`; fixes slot-stack alignment, the
  furniture text style, paint order, artifact kinds, furniture drawing
  geometry, per-page width proofs, and the lead region's rules; adds
  `layout.template_region_empty`, `layout.template_body_empty`,
  `layout.furniture_drawing`, and `text.furniture_policy` and names the
  template diagnostic paths; widens the letter's continuation reserved width
  to 72 pt (measured widths recorded above); and amends the letter scale
  workload to 20 / 200 body paragraphs.

- `reference-documents-v5`: the tables slice makes `table`, `row`, `cell`,
  `header_cell`, and `spanning` executable with unchanged names and shapes,
  adds `row_spanning` (represented, rejected as `table.row_span`) and the
  theme's table style, and retires `Pdf.simple_table`; refines the
  column-width algorithm (measured minima and maxima with padding, slack-
  proportional content reduction, share minima, spanning cells checked
  afterwards), states that SplitRows minimums apply to the row's line grid,
  that cells align by their visible advance in their first column's
  alignment, and that header rows repaint as `/Artifact <</Type
  /Pagination>>` (`RepeatedHeader`); replaces header-row shading with rules
  in the invoice and report appearance; adds `table.empty`,
  `table.cell_empty`, `layout.table_rule`, and `document.content_limit`;
  records the facade's content bounds; and marks the Common-run text row
  supported, each cluster taking the first policy face that covers it.
- `reference-documents-v4`: the lists-and-layout-policies slice makes
  `bullet_list`, `numbered_list`, `list_item`, `page_break`, `keep_together`,
  `keep_with_next`, `spacer`, and `line_break` executable with unchanged
  names and shapes; adds the `LayoutConstraintViolated` family with
  `layout.keep_conflict`, `layout.oversize_block`, `layout.keep_empty`,
  `layout.page_break_position`, `layout.spacer_negative`, and
  `layout.list_label_width`, and the list codes `semantics.list_empty`,
  `semantics.list_item_empty`, `semantics.list_item_content`,
  `semantics.list_depth`, `semantics.list_numbering`, and
  `semantics.line_break_position`; defines the first placement unit that
  keeps bind, headings and titles as unsplittable, page-break position rules,
  spacer placement, list geometry and labels, and the page scan's bounded
  look-back; and records that dotted layout codes ride in `FeatureReference`
  with every participating source's path in `details`.
- `reference-documents-v1`: initial record.
- `reference-documents-v3`: the rich-inline slice makes `rich_paragraph`,
  `text`, `emphasis`, `strong`, `code`, `quote`, `inline_link`,
  `inline_internal_link`, `in_language`, and `expansion` executable with
  unchanged names and shapes; defers `line_break`; limits inline presentation
  to theme colors and records a distinct per-role face as a required text
  row; adds `semantics.inline_empty`, `semantics.inline_depth`, and
  `semantics.link_uri`; and extends diagnostic paths with `.inlines[k]`.
- `reference-documents-v2`: the semantic-foundation slice makes `part`,
  `section`, and `division` executable with unchanged names; adds the
  `semantics.container_depth` and `semantics.empty_container` diagnostic codes
  with a 16-level container depth bound; and records that a dotted code rides
  in `FeatureReference` with the compact block path in `details`.
