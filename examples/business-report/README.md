# Quarterly operations report

Run each command from this directory. Successful runs write `business-report.pdf`.

```sh
roc run main.roc
roc run main.roc report
roc run main.roc report-budget
roc run main.roc report-tiny
roc run main.roc heat-map
roc run main.roc heat-exact
roc run main.roc heat-high-floor
```

The ordinary [report PDF](business-report.pdf) includes a measured custom
callout, figures with alternative text and captions, and a supplier table
whose header repeats. `report` prints authored locations, figure pages and
alternatives, the document language, repeated headers, and author checks,
using `Pdf.prepare_with_report`. It emits the same bytes from the prepared
value. `report-budget` supplies a 700-entry limit in place of the default
65,536 entries. Both use the default 4 MiB text limit. `report-tiny` reliably
returns `report.budget_exceeded` before opening the output file.

`heat-map` adds a packed RGB figure generated from 32 sample counts and uses
the same preparation report. It supplies a text key, alternative text and
caption. The 660 × 330 pt drawing is wider than the 483 pt body. With a
65% minimum it fits, and the report prints the applied 73.1% scale.
See the [heat map PDF](business-report-heat-map.pdf) and [preview](preview-heat-map.png).

`heat-exact` requests `Exact` for the same drawing. `heat-high-floor` supplies
a 90% minimum. Both return `document.figure_oversize` at
`contents[7].contents[2]`. When the drawing cannot fit at the requested
minimum, preparation reports the needed scale and keeps the previous file.

The bundled fonts and photograph have their notices and source records in
[asset provenance](../../assets/provenance.json).
