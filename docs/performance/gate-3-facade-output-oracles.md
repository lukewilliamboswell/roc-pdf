# Gate 3 facade-output oracle boundary

This document records the evidence boundary for the first real high-level
`Pdf` facade output. It does not close any Gate 3 capability.

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
  explicitly checked per-renderer ink bounds and tolerances, with their
  geometry checked against each other separately. Glyph-edge antialiasing
  coverage is renderer-specific evidence, not a reason to widen a shared
  pixel-count tolerance.

`scripts/check_gate3_facade_output.py` carries these assertions without
hard-coding object IDs, subset digest, width sequence, content layout, or
allocation totals. The core fixture supplies those facts through the emitted
PDF and the authored expected text. Its checker self-test uses the existing
visible-text fixture and rejects independent same-length changes to a
`ToUnicode` row, `/Identity-H`, and embedded-font length.

The public one-import fixture now exercises this input through
`Pdf.to_bytes`. It remains outside `tests/spec.json` until its snapshot and
exact dev-backend allocation record can join the separately reviewed baseline
update. The fixture's direct structural invocation establishes this boundary
without silently accepting that pending allocation delta. When it is promoted,
the harness must invoke this checker after snapshot comparison and pin renderer
metrics from the original bytes. Those values are properties of the facade
pipeline; they are not inherited from the synthetic visible-text case.

The facade case has an implementation-owned atomic negative twin: an authored
page artifact is rejected as unsupported with no `List(U8)` result. Mutating
output bytes remains only the independent checker self-test and is not a
substitute for that typed failure evidence.
