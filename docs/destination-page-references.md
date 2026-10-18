# Destination page references

Use `Pdf.page_reference` inside a rich paragraph or table cell to print the
page containing a named destination. The field reserves its authored width
before pagination, then prints the exact page value in that box. Forward and
backward references use the same destination placement as internal links.

```roc
contents = [
    Pdf.rich_paragraph([
        Pdf.text("Installation ··· "),
        Pdf.inline_internal_link(
            [Pdf.page_reference({ destination: "installation", width: 36 })],
            "installation",
        ),
    ]),
    Pdf.page_break,
    Pdf.destination_heading("installation", 1, "Installation"),
]

document = Pdf.document({ title: "Guide", language: "en", contents })
bytes = Pdf.to_bytes(document)?
```

A reference prints the physical page number by default, starting at 1.
`numbering: PageLabel` uses the target page's configured `page_labels` range,
including its prefix and restarted number. For example, a range beginning at
physical index 1 with `prefix: "A-"`, `style: LettersUpper` and
`start_number: 27` prints `A-AA` there. PDF alphabetic labels repeat letters
(`AA`, `BB`, …); generated list labels use their own numbering rules.

`width` is required and uses the same point units as other facade geometry.
`align` accepts `Start`, `Center`, or `End` and defaults to `End`. The box
advance stays fixed even when the label is shorter. No padding characters are
inserted into the document's text. The resolved value inherits its surrounding
font, emphasis, language, scale and leading, and normal font coverage rules
apply. A reference creates no link by itself; wrap it in
`Pdf.inline_internal_link` when a clickable page number is wanted.

References may be the only content of a paragraph, table cell, link, or an
authored line-break segment. They compose with rich paragraphs in numbered
list items and callouts. Table intrinsic measurement includes the reserved
width, and a reference atom never splits across lines.

Use `Pdf.page_label` in furniture to display each current page's configured
label, matching `PageLabel` references. It can be placed inside
`Pdf.reserved_width` like other page fields:

```roc
footer = Pdf.region({
    height: 16,
    center: [Pdf.furniture_text([
        Pdf.reserved_width(60, End, [Pdf.page_label]),
    ])],
})
```

Body references require an existing destination, a positive width, a nonempty
resolved label, and enough width for the exact resolved glyphs. Label output
is bounded to 128 UTF-8 bytes. Violations return located diagnostics before
PDF emission; values are never abbreviated or scaled to make them fit.
`Pdf.page_reference` is for body rich text; furniture accepts the current-page
field `Pdf.page_label` instead. An explicitly unnumbered page with an empty
prefix paints no label in furniture and cannot be the value of a `PageLabel`
body reference.

The dedicated [fixture family](../tests/destination_references/Fixture.roc)
checks printed TOC numbers, named destinations, reference-only cells and
links, nested list/callout ownership, inherited fonts, and atomic rejection.
Its [PDF oracle](../scripts/check_destination_references.py) derives expected
values from the emitted destinations and `/PageLabels`.
[Performance evidence](performance/destination-page-references.md) records
stage contracts, exact allocation counts and deterministic work.
