# Arabic and Latin supplier invoice

Run `roc main.roc` here to write `arabic-invoice.pdf`.

The invoice registers packaged Inter Regular and the included static
IBM Plex Sans Arabic Regular, in that order, and enables
`Theme.international_text: ArabicLatin`. The supplier name `شركة السلام` and
its reference `AE-118` share a line. The payment paragraph's logical text
is `المبلغ المستحق AED 2,400.00`. The name and amount are painted in their
resolved directions and extracted in authored order. Arabic spans use
`Pdf.in_language("ar", ...)`.

Keep each Arabic word in one inline span. Pointed text, presentation forms,
joining controls and styling boundaries inside an Arabic word are outside
the supported repertoire. Preparation reports these at the authored block.
