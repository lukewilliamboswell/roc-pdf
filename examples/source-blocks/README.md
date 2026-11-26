# Paint source highlights without changing source text

```sh
roc run main.roc
roc run main.roc plain
roc run main.roc bad-range
```

The first two commands write `source-blocks.pdf`. Compare the
[highlighted export](source-blocks.pdf) with the
[plain export](source-blocks-plain.pdf). The code has its own monospace family
and background. Both exports preserve the same selectable YAML, expanded
tab in the comment, spacing and page breaks.

The app derives a short list of half-open UTF-8 ranges from the recipe's
source pieces. It colors the opening comment, the complete accented value
`café`, and a storage value that wraps onto another visual line. Range
coordinates refer to the original text before tab expansion or wrapping.
`bad-range` puts the start inside the two-byte `é`. It reports
`source.foreground_range` at `contents[2]` without opening the output.
