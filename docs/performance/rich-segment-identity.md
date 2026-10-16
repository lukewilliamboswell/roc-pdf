# Explicit rich-text segment occurrence identity

Issue #44 exposed a resource/placement identity collision: equal adjacent
explicit-break segments intern to the same source. Source equality therefore
cannot reset shaping cursors or decide where mandatory lines begin. Resetting
only the cluster cursor would still merge segments in line layout and pages.

Each facade run's existing dense metadata now carries `segment`, the first
semantic leaf occurrence of its explicit-break segment. Preparation assigns it
from normalized authored break records; all leaves and physical face splits of
that segment retain it. Unicode analysis and ordered face selection still
intern and cache exact source text. Shaping and selection cursors reset at the
segment occurrence boundary. Line requests, code holds, table measurement, ordinary pagination,
and table-cell rows consume that explicit identity.

The representation adds one scalar per existing run metadata record, with no
new buffer or allocation per occurrence. No source bytes, Unicode analysis,
shaped glyphs, or builder accumulators are duplicated to encode identity.
Break lookup uses binary search over paragraph-ordered break records, followed
by one forward cursor per paragraph; its bound is O(p log b + leaves + breaks).
Physical expansion and segment grouping remain linear in the run count. Text
and source buffers retain the same ownership and lifetime as before.

The `rich inline repeated [ordered] segments x10/x50` cases exercise adjacent
repeated text, code, spaces only, existing trailing spaces, several leaves per
segment, a repeated nonadjacent source, and repeated code in table cells.
Both the single-face and ordered-selection paths have a scale pair. Each
single-face unit must produce exactly 22 measured lines; an ordered unit also
repeats three multi-leaf Latin/Han lines on two faces, for 25 lines. This
advances and resets the physical face-selection cursor across equal segments. One additional semantic planning
pass records source-input, unique-source/scalar, and hash-scalar work, proving
that repeated segments keep shared Unicode analysis across the scale pair. The independent rich-inline
checker decodes the emitted CID strings through ToUnicode and groups their
absolute text baselines on each page: it requires every exact visual line in
authored order, including spaces and table text. The ordinary structure checker
also proves ownership and logical/paint order agreement, and the archive
validator checks the emitted bytes.

Allocation and work results are recorded in `tests/spec.json` under the pinned
compiler. Existing fixtures retain their exact output and work; the scalar
metadata addition permits a reviewed linear allocated-byte increase within the
existing 10% guard.

Pinned arm64mac evidence (dev backend, `--no-cache`):

| Path / units | Allocations | Allocated bytes | Lines | Unique sources / scalars |
| --- | ---: | ---: | ---: | ---: |
| segments x10 | 37,204 | 23,385,211 | 220 | 14 / 115 |
| segments x50 | 166,201 | 111,467,330 | 1,100 | 14 / 115 |
| ordered segments x10 | 45,938 | 31,619,813 | 250 | 16 / 122 |
| ordered segments x50 | 203,414 | 144,557,491 | 1,250 | 16 / 122 |

The existing mixed-inline fixture retains 13,145 allocations, its exact PDF,
and every work counter; allocated bytes increase from 9,067,485 to 9,070,029
(+2,544, about 0.03%), from the extra scalar in dense run metadata. The existing
explicit-breaks fixture likewise retains its allocation count, PDF, and work.
The independent checker rejects a mutation that collapses the first two
repeated segments onto one baseline, in addition to its existing structure,
Unicode, and role mutation twins.
