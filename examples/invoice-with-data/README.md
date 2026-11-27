# Invoice with associated data

Run the example from this directory using the compiler pinned by the
repository.

```sh
roc run main.roc
roc run main.roc archive-only
roc run main.roc reject-static
```

Open `invoice-with-data.pdf` in a reader with an Attachments panel. Save
`invoice.xml` from that panel and compare it byte for byte with the source
file. The document has PDF/A-4f and PDF/UA-2 declarations. The
`archive-only` run writes `invoice-with-data-archive.pdf` with a PDF/A-4f
declaration. The `reject-static` run returns `attachment.profile` before it
opens the output file.

This invoices two items from the tax invoice example. The XML contains the
invoice number, a breakdown of the items, and totals. The invoice itself
contains all billing and payment information. The application marks the XML
`Supplemental` and supplies the bytes, filename, MIME type, UTC modification
time, `Data` relationship and purpose description. The package checks the
attachment metadata, sizes and document associations. The application owns
the XML format and facts.

The invoice and its synthetic XML data are covered by the repository's
[UPL-1.0 license](../../LICENSE). The generated PDF uses the packaged Inter
face, which is distributed under the SIL Open Font License. This example
demonstrates embedding. E-invoicing formats such as Factur-X specify their
own document profile, XML, metadata and filename requirements.
