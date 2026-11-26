# Coastal field guide

```sh
roc run main.roc
roc run main.roc pocket
```

Both commands write `field-guide.pdf`. The [A4 edition](field-guide.pdf) has
room for the full-size habitat drawings and scientific names in the survey
table. The [pocket edition](field-guide-pocket.pdf) uses a 306 × 468 pt
page (4.25 × 6.5 inches), 20 pt side margins and 22 pt top and bottom margins.
It uses two 252 × 108 pt diagrams, a 252 × 334 pt observation card, and a
narrower survey table. See the [pocket preview](preview-pocket.png).

The pocket edition sets `Preferred` keep-with-next on the plover note.
The note and the observation card exceed one body frame together, so the
card starts on the next page. The preparation report identifies the relaxed
keep. The survey details and counts still occupy one sheet under a required
`Pdf.keep_together`.
