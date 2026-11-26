# Pilot findings

Run the report from this directory with the repository's pinned compiler.

```sh
roc run main.roc
```

The 456 × 228 pt sheets use 24 pt margins. The first column is 206 pt
wide, the gutter is 16 pt, and the second column is 186 pt wide. The
article starts under the title on page one. The right column resumes
with “collected the largest share”, and the first line on page two
starts with “minute hold”, completing “two-minute” across the page
boundary. The tagged reading order contains the full paragraph once.

```sh
roc run main.roc -- keep-together
```

The same paragraph cannot fit wholly in either column and yields
`layout.columns.keep_conflict` at `contents[0].contents[1]`.
Preparation runs before opening the output file.
