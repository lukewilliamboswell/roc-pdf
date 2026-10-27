# Destination page references

Use `Pdf.page_reference` inside a rich paragraph or table cell to print the
page containing a named destination. The field reserves its authored width
before pagination, then prints the exact page value in that box. Forward and
backward references use the same destination placement as internal links.

Use `Pdf.contents_entry` for a linked title and a page number aligned at the
right edge of the current content frame:

```roc
Pdf.contents_entry({
    title: [Pdf.strong([Pdf.text("Installation")])],
    reference: { destination: "installation", width: 32 },
    indent: 18,
    leader: Dots,
})
```

Every title line reserves the reference width and a gap of 6 points. `indent`
defaults to zero and shifts all of the title's wrapped lines together without
moving the page-number column. The page number sits beside the final title
line, including when the title continues onto another page. `leader` defaults
to `NoLeader`; `Dots` paints decorative dots between the final title line and
the number column when there is room. Dots are page artifacts, excluded from
selectable text and reading order.

Both the title and number link to `reference.destination`. Supply title text
and inline styling, without nested links or page references. The entry retains
ordinary paragraph/link semantics with one logical space between title and
number. Its reference must use `End` alignment. Empty titles, negative `indent`
or `gap`, and geometry leaving no title width reject before emission. The
exact resolved number must fit the reserved reference width as usual. Heading
collection, numbering, ancestry and entry selection remain caller decisions.

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

See [Composing a technical manual](manual-composition.md) for chapter headers,
numbered instructions and continued callouts. The [authoring guide](authoring.md)
explains font selection, furniture and document options.
