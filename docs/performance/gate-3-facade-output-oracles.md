# Gate 3 facade-output oracle boundary

This document records the evidence boundary prepared for the first real
high-level `Pdf` facade output. It does not claim that output exists or close
any Gate 3 capability.

The input case is one authored paragraph with the built-in theme and a
`Standard` profile. The core slice must provide a deterministic nonblank PDF,
an exact snapshot, and a checked-in scenario record before it can join the
ordinary test suite. Its positive evidence must establish all of these facts
from the original emitted bytes:

- exactly one tagged A4 page with an owned text content stream, balanced
  fragment marked content and text objects, `/StructParents`, and `/Tabs /S`;
- exactly one page Type 0 `/Identity-H` resource with one CIDFontType2
  descendant, an unfiltered identity `CIDToGIDMap`, and a complete `ToUnicode`
  mapping for every painted CID;
- direct reconstruction of the semantic source string from content CIDs and
  `ToUnicode`, plus independent PDFBox 3.0.8 extraction of the exact UTF-8
  string;
- an embedded TrueType-flavoured `FontFile2` whose declared `/Length1` equals
  the decoded stream, with one deterministic subset identity shared by all
  three PDF font dictionaries; and
- independent PDFBox and PDFium 72-dpi rendering within newly measured,
  explicitly checked ink bounds and tolerances.

`scripts/check_gate3_facade_output.py` carries these assertions without
hard-coding object IDs, subset digest, width sequence, content layout, or
allocation totals. The core fixture supplies those facts through the emitted
PDF and the authored expected text. Its checker self-test uses the existing
visible-text fixture and rejects independent same-length changes to a
`ToUnicode` row, `/Identity-H`, and embedded-font length.

When the line-layout dependency is fixed, the integration change must add the
facade-output fixture to `tests/spec.json`, give it the reviewed exact
allocation and deterministic-work record, and invoke this checker from the
test harness after snapshot comparison. It must also pin renderer metrics from
the new original bytes. Those values must be reviewed as properties of the
facade pipeline; they are not inherited from the synthetic visible-text case.

The facade case still needs its implementation-owned atomic negative twin
(invalid input or violated stage invariant, stable diagnostic, and no emitted
PDF). Mutating output bytes is only the independent checker self-test and is
not a substitute for that typed failure evidence.
