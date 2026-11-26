# Fillable text fields

The explicit `AccessibleForm` profile emits PDF/A-4 and PDF/UA-2 for labelled,
single-line fixed-page fields. The optional WTPDF accessibility declaration
uses the same form constraints. The writer checks the bytes it generates.
A reader owns subsequent user edits, appearances and saves.

## Writer checks

| Requirement | Evidence |
| --- | --- |
| ISO 32000-2:2020+EC3 §§12.5.5, 12.5.6.19, 12.7.2–12.7.4 and 12.7.5.3 | Each field has one editable text widget, a unique terminal field name, a plain initial value, and one normal appearance. The local and AcroForm default appearances use `Ftx` at 10 points. The decoder matches the appearance's text and resources to the authored value and checks the full 95-character ASCII range using the embedded program's cmap and horizontal metrics. |
| ISO 19005-4:2020 §§6.2.10 and 6.3–6.4 | The form has an embedded editable font and explicit normal appearances. Widgets print and remain visible. The writer omits `NeedAppearances` and excludes actions, rich values and external programs from the policy. |
| ISO 14289-2:2024 §§8.9.3.3, 8.10.1, 8.10.2 and 8.10.3.3, WTPDF 1.0 corresponding clauses, and ISO/TS 32005:2023 Table 5 | Every widget has one `Form` owner and OBJR via ParentTree. The direct `Lbl` child holds its decoded visible label, and `TU` carries the accessible field context. Ordered `Form` nodes and ordered page-local annotations preserve authored focus with `/Tabs /S`. The package admits only plain text and omits `RV`. |

The five field PDFs pass Arlington 1.30.2 and veraPDF 1.30.2 explicit `4` and
`ua2`. The WTPDF fixture also passes `wt1a`. The independent field decoder
rejects a different valid value in the appearance while Arlington and
veraPDF `4` and `ua2` accept the same mutation. It also rejects a read-only
flag and a changed field context. Poppler 26.07.0 at 96 dpi renders a blank
text interior and produces 296 nonwhite pixels in the matching interior of
the prefilled field.

The owning-facade model explores 170 states and 169 steps through depth
four with three witnesses. It checks authored label ownership, pages,
placement order and duplicate rejection for reordered, blank and prefilled
inputs, including a page boundary. The independent PDF decoder checks
values and appearances when an emitted fixture is read. Solve checks the
48-point geometry within the bounded page domain. The owning-facade
rejection fixture runs boundary widths, invalid values, duplicate IDs, the
128-field boundary, and incompatible profiles through both buffered and
chunked preparation. Omitted, explicit blank, and empty prefilled inputs
produce byte-identical files.

## Allocation and work

The field registry validates bounded UTF-8 strings and stably sorts
bounded IDs once. Widgets follow authored page order, so lowering and
checking scan the annotation plan without a field-by-page Cartesian pass.
Fixed page geometry shares checked span arithmetic. All appearances
reference one complete editable font program, shared with buffered and
chunked emission, and bounded label/value inputs keep field-local work
finite. The field rejects the 129th registered field before lowering.

| Fields | Pages | Roc dev allocations | Allocated bytes | Emitted chunks | PDF bytes |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | 1 | 2,036 | 13,117,573 | 46 | 91,543 |
| 42 | 7 | 9,493 | 40,861,463 | 178 | 108,303 |

The fixture pins exact allocations and deterministic counters with the
pinned dev compiler, and compares shared prepared chunks with buffered
bytes. Retained generated PDFs include references to one editable font
program per document regardless of field count. See
[`tests/spec.json`](../../../tests/spec.json) for the cross-target evidence
contract.
