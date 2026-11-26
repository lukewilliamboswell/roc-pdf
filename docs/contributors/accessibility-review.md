# Accessible archival documents

Use this guide to review authoring for the `AccessibleArchive` profile or
add a regression for an accessibility check. The profile writes PDF/A-4 and
PDF/UA-2 declarations. WTPDF 1.0 accessibility is a separate declaration.
Standards support is best effort.

## File and author checks

Inspect the exact PDF returned for the requested profile. For a mechanical
check, cite the standard edition and clause near the implementation or
focused test. Include an accepted authored case and an atomic negative that
isolates the relevant object value or relationship. A rejected document
returns a diagnostic before producing any bytes or chunks. Use the
[test harness](../testing.adoc) to verify snapshots, work, and allocations.
Independent tools are optional for local review.

The [preparation report](reference-documents.md#preparation-report) separates
facts from obligations. Supply title and language, meaningful text alternatives, the intended structure and reading
order, labels and headers, and link purposes through the public authoring
surface. The generated file preserves these choices within the supported
subset. The author is responsible for their accuracy. A report entry locates
the content to review.

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
| `FontEmbeddingRightsConfirmed` | Confirm that each font can legally be embedded in the file for unlimited, universal rendering and that subsetting is permitted. The package checks supported font structure and rejects restricted technical flags where applicable. |

Review the need for an outline even when the report has no
`OutlineMeaningful` record. PDF/UA-2 and WTPDF accessibility recommend an
outline for longer documents and leave the length judgment to the reviewer.

Use the `LanguageAccurate` record to check that each tag names the
actual natural language. The combined profile rejects recognized placeholder
tags and tags starting with the private-use singleton `x`. Check registered
subtags and applicable private agreements as part of language review.
Declare language changes in body text with `Pdf.in_language`. Each standalone
PDF string must use its one inherited language, including alternate
descriptions, expansion text, outline titles and page-label prefixes. The text-string encoder rejects raw escape
introducers.

Use the `StructureMeaningful` and `ArtifactClassificationMeaningful`
records to review styling and layout. Theme, scopes, panels, table fills,
borders, spacing and source highlighting provide presentation in the
combined facade. Express the full meaning of a styled distinction through
authored text, semantic roles or alternatives. For example, put a visible
`Warning.` label inside a tinted callout and use a heading or list to
identify its logical content. A visual property with independent semantic
meaning requires an applicable Layout attribute and is outside the
supported authoring scope.

Page furniture provides page context. Repeated headers
repaint an already tagged table header, and contents-entry leaders supply visual
spacing between tagged labels. A figure's intrinsic vector paint and labels
belong to the Figure. The bounded facade has no constructor for separate
contextual artifacts, such as numbered lines referenced elsewhere.

An optional human or assistive-technology review records the exact source and
PDF digest, tool and version, operating system, tasks, expected result,
observed result and any limitation or follow-up. Preserve raw files and
review outputs in ignored storage or CI artifacts. Use the
[reference document scenarios](reference-documents.md) when reviewing the
invoice, report and letter. WCAG checks such as contrast and cognitive
accessibility have their own scope. File conformance does not certify those
qualities or a reader's behavior.

For independent certification, discuss the use case, scope, funding, and
ownership in [GitHub Issues](https://github.com/lukewilliamboswell/roc-pdf/issues).


## Supplemental associated files

Apply ISO 14289-2:2024 §8.14.1 to each file specification reached through
the catalog's `EmbeddedFiles` tree. Its `Desc` must describe the purpose
of the file. Inspect that judgment and confirm that the document provides
all information a reader needs before marking a file supplemental. Both
checks appear at the file's authoring path in a combined-profile report.

ISO 14289-2 §6.2 and WTPDF §6.2 impose accessibility obligations for files
needed to understand the document. WTPDF §7.2.2 also addresses file-specific
declarations for necessary non-PDF files. The package rejects that dependency
under `AccessibleArchiveWithFiles`. Supply whole-document supplemental data
only. The recommendations in §8.14.2 for associating alternate or
supplemental representations with the applicable structure element belong
to a separate element-level capability.
