# Composing a technical manual

Use ordinary `Pdf` blocks to combine chapter text, numbered instructions,
tables, callouts and diagrams in one document.

## Print page numbers in a table of contents

Give each chapter a named destination with `Pdf.destination_heading`, then
use `Pdf.page_reference` to print its page number. Wrap the reference in
`Pdf.inline_internal_link` to make it clickable. References reserve a fixed
width; choose enough space for the longest page number or configured label.

See [Destination page references](destination-page-references.md) for a complete
example, numbering options and overflow diagnostics. You author the contents
entries yourself; roc-pdf resolves their page values.

## Give chapters their own headers and opening pages

Wrap a chapter's blocks in `Pdf.page_scope`. Set
`running_label: Label("Installation")` and put `Pdf.running_label` in header
or footer furniture. Use `Pdf.reserved_width` to reserve space for that label.

The scope's `page_templates` property accepts separate `opening` and
`continuation` templates. This lets you use a quiet chapter opener and running
headers on later pages. Scopes start and end on full body-page boundaries and
cannot nest. Author chapter headings, destinations and outlines explicitly.

See [Chapter-aware page scopes](authoring.md#chapter-aware-page-scopes) for
template options, reset behavior and layout limits.

## Keep rich content inside numbered instructions

A `Pdf.list_item` starts with a paragraph. After it, include rich paragraphs,
source blocks, figures, tables, callouts or nested lists. These remain part of
the same numbered item when it continues across pages; the item label prints
once. Lists nest at most four levels.

Use `Pdf.source_block` for code with preserved whitespace. Figures stay with
their captions, and tables use their normal row-continuation and repeated-header
policies. All children use the available item width, including list indentation
and any enclosing callout padding. The [authoring guide](authoring.md#lists) includes
list, source, figure and table examples.

## Continue boxed notes across pages

Use `Pdf.callout` for a box whose height follows its content. By default,
`fragmentation: Lines` allows continuation at supported child boundaries;
each page fragment repeats the panel and padding. Set `Unsplittable` when the
whole note must fit on one page.

Callouts accept paragraphs, lists, source blocks, figures, ordinary tables and
nested callouts. They share a maximum nesting depth of 16 with semantic
containers. Content that cannot fit returns a located diagnostic. See the
[callout example and limits](authoring.md#callouts).

## Add vector diagrams

Place a drawing with `Pdf.figure`, supplying alternative text and an optional
caption. The [prepared vector-diagram example](../examples/vector-diagrams/README.md)
shows how to prepare a constrained Mermaid/SVG flowchart as public Roc drawing
commands with searchable text.

Preparation is separate from PDF generation. The example rejects embedded HTML
labels and unsupported SVG features; it does not provide general SVG or HTML
rendering. Its accepted profile, font requirements and preparation commands
are documented with the example.
