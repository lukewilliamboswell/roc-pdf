# Accessible archival documents

Use this protocol when changing the combined profile, adding a supported
feature or reviewing a document for an accessibility claim. The
[conformance ledger](../../conformance/ledger.json) holds the stable
requirement IDs, external test IDs, evidence paths and unresolved requirements.
The [normative baseline](../../conformance/normative-baseline.json) identifies
the reviewed editions and the exact errata revision.

## File and author checks

Review the exact PDF returned for the requested profile. Run Arlington and the
independent object and file checks on that file, then run veraPDF with explicit
`4` and `ua2` profiles. When the caller requests the WTPDF accessibility
declaration, also run explicit `wt1a` against the same bytes and inspect the
declaration separately. WTPDF reuse has separate requirements and evidence.

For each machine-verifiable rule, use an accepted authored case and an atomic
negative. A source negative must receive a located diagnostic before delivery
and produce no bytes or chunks. A lowered-file negative should change one
relevant object value or relationship while keeping the parser, unrelated
structure and applicable oracle inputs valid. Inspect the failing rule and
object rather than accepting an arbitrary error. Run the pinned
[test harness](../testing.adoc) for affected paths, including deterministic
work, exact Roc allocations, allocated bytes and cross-target output.

The [preparation report](reference-documents.md#preparation-report) separates
facts from obligations. Supply title and language, meaningful text alternatives, the intended structure and reading
order, labels and headers, and link purposes through the public authoring
surface. The generated file preserves these choices within the supported
subset. The author is responsible for their accuracy. Where a required
obligation has no corresponding supported report observation, record it as
open in the ledger before closing the profile. A report entry records what to
review and where. It cannot discharge the obligation.

Review the following against source content and the preparation report.
Choose the applicable records based on the document's features.

| Report obligations | What the author or reviewer checks |
| --- | --- |
| `DocumentTitleAccurate`, `LanguageAccurate` | The metadata title identifies the document, whether or not there is a visible title. The default and scoped languages fit the prose, inline language changes and human-readable strings, including alternatives, captions, link descriptions, outlines and labels. |
| `StructureMeaningful`, `ReadingOrderMeaningful` | The structure reflects the type and level of each item and follows a coherent reading order. Review the title, headings, sections, quotations, paragraphs, emphasized text, code, lists and rich list items. A paginated unit stays one logical unit. Review meaning across boundaries in continued tables, source blocks and callouts. |
| `ArtifactClassificationMeaningful`, `StructureMeaningful` | Identify meaningful content separately from decoration, furniture, repeats and contextual artifacts. Check that relevant grouping, layout attributes and order convey the author’s intent, even when paint order and structure order differ. |
| `AlternativeTextMeaningful`, `ExpansionAccurate`, `TextEquivalentAccurate` | Evaluate the purpose and scope of each figure alternative, including labelled drawings and chart data. Check the caption association. Review text equivalents, replacements and expansions for fidelity, and verify that source blocks preserve the intended text and whitespace. |
| `StructureMeaningful`, `TableHeadersMeaningful` | Check that numbering, labels, header descriptions and cell relationships are meaningful. Repeated visual table headers do not add separate semantic headers. |
| `LinkPurposeMeaningful`, `AnnotationOrderMeaningful` | Link and annotation descriptions provide enough context to identify their purpose. Check corresponding visible text, logical and focus order, and target on each fragment of a continued link. Check that distinct targets remain distinguishable. |
| `OutlineMeaningful`, `PageLabelsAccurate`, `LinkPurposeMeaningful` | Check that the outline and authored table of contents identify their intended logical sections. Check page labels, shown page numbers and cross-references against what a reader perceives. |
| `FontEmbeddingRightsConfirmed` | Confirm that each selected font can be embedded and subsetted for the intended distribution. The package checks supported font structure and rejects restricted technical flags where applicable. |

An optional human or assistive-technology review records the exact source and
PDF digest, tool and version, operating system, tasks, expected result,
observed result and any limitation or follow-up. Preserve raw files and
review outputs in ignored storage or CI artifacts. Use the
[reference document scenarios](reference-documents.md) when reviewing the
invoice, report and letter. WCAG checks such as contrast and cognitive
accessibility have their own scope. File conformance does not certify those
qualities or a reader's behavior.

## Clause inventory

Use the published PDF/UA-2 edition and ISO/TS 32005 for normative decisions.
The PDF Association publishes the WTPDF accessibility text and an informative
Table 5 workbook. They help review shared provisions and applicable
containment. The veraPDF catalogs cover the corresponding executable machine
rules. The catalogs do not cover every normative clause and passing them
cannot resolve author-dependent requirements.

The PDF/UA-2 preview includes the file requirements through 8.13.2. The
ISO/TS 32005 preview includes the textual clauses through 7.2 and the legend
and beginning of Table 5. Direct review of PDF/UA-2 clauses 8.13.3–8.14 and
the complete normative Table 5 remains open pending access to the sponsored
ISO copies. The pinned errata and the WTPDF accessibility provisions were
checked separately. See the ledger's
`ROC-PDF-PDFUA2-ISO-TEXT-RECONCILIATION` for this open confirmation.
[PDF/UA-2](https://pdfa.org/iso-14289-2-pdfua-2/) ·
[ISO/TS 32005](https://pdfa.org/resource/iso-32005/) ·
[ISO/TS 32005 preview](https://cdn.standards.iteh.ai/samples/45878/b574c2cc0cc94e7986f66b148550bd7d/ISO-TS-32005-2023.pdf) ·
[WTPDF 1.0](https://pdfa.org/download-area/specifications/Well-Tagged-PDF-WTPDF-1.0.pdf) ·
[ISO/TS 32005 informative matrix](https://pdfa.org/resource/iso-ts-32005-hierarchical-inclusion-rules/)

### ISO 14289-2:2024 and WTPDF accessibility

| PDF/UA-2 clause | Review against the combined subset |
| --- | --- |
| 1–4, 6.1, 7, 8.1 | Scope, dependencies, terms, notation, access principles and general file requirements guide this audit. The programmatic PDF/UA-2 identification belongs to clause 5. Separate author claims through PDF Declarations are governed by the declaration mechanism. No additional author-declared standards are implied. |
| 5, 6.2 | Inspect XMP part and revision, explicit claims and catalog MarkInfo. Reject incorrect metadata in the emitted-file controls. No embedded files are accepted. |
| 8.2.1–8.2.4 | Check parent and child object relationships, authored logical order, real content classification, intact logical units through fragmentation, coherent ordered artifacts, and the standard namespaces. Custom mappings and additional namespaces are outside this subset. |
| 8.2.5.1–8.2.5.7 | Check a single PDF 2.0 Document root and appropriate roles for parts, sections and divisions. DocumentFragment denotes external origin. The public facade excludes article and block-quotation constructors. No inferred role based on style or coordinates is adequate. |
| 8.2.5.8 | Authored contents entries presented as a table of contents require TOC and TOCI, each item's semantic target through Ref, and artifact leaders. This applies to explicit authored entries as well as generated contents. |
| 8.2.5.9–8.2.5.10 | Authoring excludes side content and custom role mappings to NonStruct. A bounded callout in the main flow is not a sidebar. |
| 8.2.5.11–8.2.5.13 | Preserve paragraph identity and specific numbered headings. Appropriate heading level is an author obligation. The facade's heading progression policy is an authoring restriction. Titles are distinct from headings and from XMP title. |
| 8.2.5.14–8.2.5.15 | Footnotes, endnotes and Sub-based subdivisions are outside the supported combined vocabulary. |
| 8.2.5.16–8.2.5.20 | Check label ownership, language/attribute spans, quotation and emphasis intent, and distinct targets for distinct links. A single logical link can own multiple annotations across lines and pages. |
| 8.2.5.21–8.2.5.24 | General annotation structures, form field semantics, ruby and warichu are outside this subset. Link has its own semantics. |
| 8.2.5.25 | Check Lbl, LBody and ListNumbering against the authored list. Pagination keeps one logical L and LI rather than creating new lists. Continuation of one distinct authored list from another and its extra attributes are outside the subset. |
| 8.2.5.26 | Check the regular table and row-group grid, scope and header membership, including ID resolution, column spans and paginated repeated headers. More general row span and complex span combinations remain outside this subset. |
| 8.2.5.27–8.2.5.28 | Check caption placement and association, full Figure paint ownership, and the authored alternative. The bounded vector adapter follows the same Figure contract as images. |
| 8.2.5.29–8.2.5.31 | Mathematical and scientific formula structures, MathML, indexes and bibliography semantics are outside the subset. |
| 8.2.5.32–8.2.5.33 | Code retains its source semantics and text, including when wrapped or coloured. Artifact structure follows 8.3. |
| 8.2.6.1–8.2.6.3 | Check selected semantic layout, table, list and artifact attributes, including placement and nondefault values that carry meaning. PrintField attributes are outside the static business-document scope. |
| 8.2.6.4 | ARIA/DPUB-ARIA authoring and namespace-owned custom attributes are outside the subset. |
| 8.3.1–8.3.2 | Check explicit artifact marking and appropriate types and subtypes. Content meaningful only within a structural context requires a contextual Artifact. Test accepted page furniture, repeated table headers, callout panels, decoration, drawing-label and source-paint paths for the applicable ownership. |
| 8.4.1–8.4.4 | Check programmatically obtainable Unicode, alternatives, PUA restrictions and effective language throughout the file. Language switches within human-readable strings need explicit encoding or an author contract that restricts those strings to their inherited language. |
| 8.4.5.1–8.4.5.9 | Check font type, embedded CID fonts, used glyphs, CIDToGIDMap, widths, Unicode maps and absence of .notdef. Simple PDF fonts and arbitrary encoding CMaps are outside the subset. |
| 8.5.1–8.5.2 | Check authored text alternatives for nontext content and equivalent ActualText when nontext paint needs to be consumed as text. |
| 8.6–8.8 | Human-readable strings exclude PUA. Optional content is outside the subset. Internal links and outline actions identify a structure destination under the pinned PDF 2.0 errata. |
| 8.9.1–8.9.4 | Link is the supported annotation type. Check visible flags, whole object references in the structure tree, contiguous logical content, target, viewable bounds, association, tab order and compatibility of descriptions. Non-link annotation families are outside the subset. |
| 8.10.1–8.10.4 | Interactive widgets and non-interactive authoring of semantic form fields are outside the subset. Reusable Form XObjects only supply visual paint. |
| 8.11.1–8.11.2 | Check XMP title and catalog viewer title preference independently of visible headings or other displayed text. |
| 8.12.1–8.12.4 | Check authored outlines and page labels, including agreement with visually rendered custom page numbering. Article threads are outside the subset. |
| 8.13.1–8.13.3 | GoTo and URI are the supported actions. ECMAScript and coordinate-dependent URI `IsMap` are outside the subset. |
| 8.14.1–8.14.2 | Embedded and associated files are outside StaticPdfA4 and the combined subset. |
| Annexes A–B | Declaration and attribute examples are informative. |
| WTPDF 6.1.3 and PDF Declarations 7–8 | Check the explicit accessibility declaration and the URI corrected by erratum #395. Separately check the PDF/UA identification schema under UA clause 5. |
| WTPDF 8.2.5.11 erratum #589 | Corrects an informative cross-reference to the real-content examples. |

### ISO/TS 32005:2023

| Clause | Review against the combined subset |
| --- | --- |
| 1–3 | Scope, dependencies and namespace terminology guide the review. |
| 4 | The optional ISO/TS 32005 declaration is distinct from the PDF/UA-2 identification and WTPDF accessibility declaration. |
| 5.1 | The emitted PDF header specifies version 2.0. |
| 5.2 | The PDF 1.7-only exception does not apply because this subset has an explicit PDF 2.0 Document root. |
| 5.3–5.4 | Roles shared by both standard namespaces use PDF 2.0. Roles unique to PDF 2.0 explicitly use that namespace. |
| 5.5.1–5.5.2.3 | The admitted unique PDF 1.7 roles follow the meanings and grouping or inline constraints of Tables 2 and 3. For an authored flat TOC, use a TOC with TOCI children and use Caption for descriptive text within it. |
| 5.6 | The bounded role set has explicit standard namespaces and no custom role map. |
| 6.1–6.2 | Check supported table, list, artifact and layout attribute owners against the role and attribute definitions. Standard owner eligibility follows the attribute definition independently of which standard namespace owns the role. |
| 6.3 | Namespace-owned custom attributes remain excluded. |
| 7.1–7.2 | Check each admitted parent/child pair, direct content item, cardinality and any applicable position constraint. The ledger maps the shared veraPDF Table 5 rules as one maintained group, with distinct evidence for the package's accepted roles and exclusions. Erratum #336 affects Code with Sub, and erratum #440 affects WP with Figure. Neither pair is currently supported because Sub and WP are unavailable. |

A captioned figure uses a dedicated `Sect` whose entire content is the figure
and its caption, in that order. This makes the caption the last child of the
structure element enclosing the captioned content. The object check requires
that exact relationship and rejects a transparent `Part` in its place.
[ISO 32000-2 caption semantics](https://pdf-issues.pdfa.org/32000-2-2020/clause14.html) ·
[PDF 2.0 HTML derivation, section 4.3.5.2](https://pdfa.org/download-area/specifications/Deriving_HTML_from_PDF.pdf)

The exact errata revision in the normative baseline contains resolved
ISO/TS 32005, WTPDF and PDF Declarations corrections. Do not treat proposals
published after that revision as requirements for the pinned profile. The
navigation errata for intra-document actions and named destinations are
tracked by `ROC-PDF-PDF20-GOTO-D-DESTINATION` and
`ROC-PDF-PDF20-NAMED-DESTINATION-SD` in the ledger.
