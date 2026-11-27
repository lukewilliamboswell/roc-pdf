# Dispatch audit log

Run from this directory with the compiler named in [the checkout pin](../../.roc-version).

```sh
roc run main.roc
roc run main.roc archive
roc run main.roc standard
roc run main.roc invalid
```

The first three commands write `audit-log.pdf` with the same 72 audit lines.
The default declares PDF/A-4 and PDF/UA-2. The explicit `archive` choice
declares PDF/A-4, and `standard` emits PDF 2.0 without either declaration.
The sample outputs are [default](audit-log.pdf), [Archive](audit-log-archive.pdf),
and [Standard](audit-log-standard.pdf). All three share the [preview](preview.png).

`invalid` reports `semantics.heading_level` at `contents[1]` and exits with
status 1. Preparation happens before the application opens the output file,
so a file from an earlier run survives.

Use `Document.builder` for compact text authoring. The example appends three
application-owned batches using `add_paragraphs`, finishes the builder, and
emits through `Pdf`. For rich blocks such as charts and tables, see the
[telemetry export](../chunked-export/README.md).
