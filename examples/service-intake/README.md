# Service intake

Run the app from this directory with the compiler pinned by the repository.

```sh
roc run main.roc
roc run main.roc duplicate-id
```

Open `service-intake.pdf` in a PDF reader with form editing. Type your name
in **Contact name**, then press Tab to move to **Include an inspection
report** (checked), **Service reference** (initially `HF-2041`), and
**Request a site visit** (unchecked). Toggle either checkbox independently.
The `duplicate-id` run reports `form.checkbox.duplicate_id` at
`pages[0].placements[5].field.id` and produces no output file.

The example opts in to `AccessibleForm` for PDF/A-4 and PDF/UA-2 declarations.
Place fields in the intended reading and focus order. Provide a unique ID
using 1–64 ASCII letters, digits, underscores or hyphens, and a visible
label of up to 256 UTF-8 bytes. A document may contain up to 128 fields
across both types. Text fields take a width of 48–1024 points and an initial
value of up to 64 printable ASCII characters that fits the available width.
The embedded 10-point face covers the entire declared repertoire.
Checkboxes use the names `Yes` and `Off` when exporting field data.
Initial appearances and declarations apply to the generated PDF.
Reader-saved copies have their own appearance and metadata.
