# Tax invoice

```sh
roc run main.roc
roc run main.roc split
roc run main.roc keep
```

The ordinary [invoice](tax-invoice.pdf) uses `KeepRows`. The `split` command
adds a long description to the existing installation service at level 5
and chooses `SplitRows`. It writes `tax-invoice.pdf`, shown in the
[split-row snapshot](tax-invoice-split.pdf) and [preview](preview-split.png).
Its console report names the one authored row on pages 3 and 4.
The visual column headers repeat, and the three totals stay together.

The `keep` command tries the same long description with `KeepRows`. It
returns `layout.oversize_row` at `contents[4].contents[1].table.body_rows[30]`
before opening the output file. The ordinary layout and both policy
choices use the same registered Source Sans family and local assets.
