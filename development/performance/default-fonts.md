# Default font family acceptance and work evidence

The `default_fonts` group covers the public facade's packaged family selection,
genuine static styles, automatic source/code fonts, exact style overrides and
atomic missing-style/coverage diagnostics. Its seven initial baselines use Roc
`nightly-2026-10-28-bad769b` with the dev backend and Zig 0.16.0. The arm64mac
and x64musl measurements below are identical, including exact allocation counts,
allocated bytes, work vectors and emitted PDF bytes. The source checkpoint for
these measurements includes the drawing-owner and named-record review fixes.

## Measurement boundary

Measurement starts before fixture construction. Each positive case runs the
public `Pdf.to_bytes_with` pipeline, then independently normalizes the same
document and runs the font resolver to expose its actual deterministic work.
The allocation totals include both operations. The work vector describes the
second resolver pass; it is not presented as the combined traversal count of
the complete fixture. The exact-override case also registers the packaged
caller font set inside the measured window.

`packaged_inspections` counts demanded packaged programs inspected by that
resolver pass. `registered_font_bytes` counts the bytes of those inspected
programs. It does not count unique emitted subset bytes or every font already
present in a caller registry. `inline_visits` and `source_visits` count the
three actual traversals over their respective normalized arenas.
`copied_input_bytes` reports actual registration input copying, which remains
zero in all positive cases.

| Case | Allocations | Allocated bytes | Inspections | Inspected font bytes | Inline visits | Source visits | PDF bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Sans | 2,076 | 11,410,378 | 6 | 2,283,744 | 45 | 3 | 36,834 |
| Serif | 2,040 | 9,927,571 | 6 | 5,395,756 | 45 | 3 | 36,627 |
| Mono | 1,124 | 4,114,710 | 2 | 608,992 | 21 | 3 | 16,822 |
| Exact override | 1,482 | 8,237,601 | 1 | 289,624 | 27 | 0 | 20,558 |
| 10 sections | 2,066 | 10,787,402 | 5 | 1,964,376 | 300 | 30 | 28,848 |
| 100 sections | 5,909 | 24,611,441 | 5 | 1,964,376 | 3,000 | 300 | 45,696 |
| Atomic negatives | 635 | 426,955 | — | — | — | — | 0 |

The negative case asserts ten rejections: eight located failures and two
document-scoped policy failures. Its work vector is exactly `[10, 8, 2, 0]`.
It emits no bytes. The complete named work vectors and both target baselines
are retained in `tests/spec.json`.

## Ownership and complexity review

The resolver uses a fixed set of ten packaged face identities and a bounded
four-role drawing demand table. Demands carry typed style and origin facts.
Each drawing role retains the first requesting owner and label ordinal,
ordered by the normalized authored block index. It retains no drawing payload
or copied text. Figures and custom panels therefore report the actual first
owner even when their storage arenas are traversed separately.

Dense inline/source arenas are traversed a constant number of times. The
10/100 pair increases normalized inline leaves from 100 to 1,000 and sources
from 10 to 100; visits grow exactly tenfold. Inspections and inspected bytes
remain constant at five programs and 1,964,376 bytes. No growing prefix is
copied, no per-section font registry is built, and input-copy work stays zero.
Allocated bytes grow from 10.79 MB to 24.61 MB while the fixed font inspection
cost remains constant. This supports linear content work and storage; it is
not a timing or memory product target.

Accumulator ownership follows the existing normalization and output contracts.
The facade extracts option scalars before consuming its font registry, so a
later parent-record read does not retain the old registry alias. Font program
buffers are transferred into inspected resources without copying their input.
The fixture likewise extracts its theme before consuming options in the
public pipeline. No resolver request retains a slice of a caller's text.

Two reviewed bounded costs are represented in these initial baselines. Real
per-face descriptor metadata requires one 24-byte descriptor record per
emitted face, replacing the previous shared uniform constant. The subsequent
owner/context and named-record changes added a constant 112 allocated bytes
to every positive case, with unchanged allocation counts and PDF bytes. The
constant is the same for 10 and 100 sections; it introduces no per-inline or
per-source allocation event. These are initial observations for the new cases,
not acceptance of unrelated existing-case baseline changes.

## Independent byte evidence

`scripts/check_default_fonts.py` inspects the original emitted bytes through
the existing independent PDF/font parsers. It resolves shown CIDs through each
font's own ToUnicode map, checks the exact selected program set and required
searchable text, and compares selected glyph outlines with the pinned source
program. Composite glyph comparisons preserve their component structure while
allowing only relocated subset glyph IDs and trailing padding.

The oracle checks static TrueType table structure, checksums, resource
ownership, OS/2 weight, head style bits, sanitized post metadata and exact
source glyphs. Descriptor Italic/FixedPitch flags must match the source, and
the emitted italic angle must equal the original signed 16.16 value exactly:
Inter italic is `-616038/65536`, and Merriweather italic is `-511180/65536`.
The subset post table preserves the same angle and fixed-pitch facts. Serif
classification remains source-derived; these pinned programs do not supply a
positive classification that would justify guessing the Serif flag from
their names.

Self-tests prove composite relocation acceptance and changed-outline rejection,
and reject a wrong family, a renamed combined-style program, a zeroed italic
angle, a cleared fixed-pitch descriptor flag and an invented Serif flag. The
six positive snapshots pass this oracle. The checker also validates the ten-program public
font-family gallery; the gallery artifacts are maintained with the examples.

The public fixtures cover both strong/emphasis nesting orders, code plus
strong, code plus emphasis with an explicit exact override, and automatic
source fonts. Missing Fira italic/combined styles, missing Merriweather command
symbol coverage and an unavailable caller family style reject without
fallback. Later-paragraph paths, document-scoped ordered-policy failures,
later-figure paths and an earlier custom panel's first label owner are checked
directly against structured public diagnostics.

## Reproduction

After setting `ROC` and `ZIG` to the pinned tools, strict focused checks run as:

```sh
./scripts/test.py --group default_fonts --quick --allocation-baselines --jobs 1
./scripts/test.py --group default_fonts --quick --allocation-baselines \
  --linux-x64-container sha256:b66e0ce64844f5c6435b0c4bfd965558199ab0f53270846861c979cb1ac29365 --jobs 1
python3 scripts/check_default_fonts.py --self-test
```

The container is the locally pinned amd64 Alpine 3.22 image. Focused case
validators include exact snapshots, the independent font oracle, normalized
plan identity and structural PDF/A-4 checks. Both strict target runs passed all
seven cases, and the independent oracle self-test passed. These commands skip
preflight by design; the normal integration suite owns preflight validation
and full independent conformance-tool evidence.
