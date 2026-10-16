# Preformatted source blocks

Issue #45 requires a distinct whitespace and continuation contract. The
preparation boundary below is implemented; public authoring, measured wrapping,
page continuation and panel evidence remain pending. This record does not
declare the public capability closed or change a conformance claim.

## Source preparation

`KernelSourceText.prepare` owns a single canonical UTF-8 source and a dense
line arena. Each line records exact scalar and byte ranges excluding its LF
separator. LF and CRLF inputs become LF. A bare CR rejects. Indentation,
trailing spaces, consecutive empty lines, and the empty final line following
a terminal LF are retained. Even an empty input has one empty source line.
Tabs either reject or expand to spaces at explicit nonzero scalar-column tab
stops; columns count Unicode scalars rather than UTF-8 bytes. Glyph widths and
grapheme-safe visual breaks belong to subsequent measured layout.

The parser checks input bytes, expanded output bytes and line counts before
growth. Errors retain only a byte offset or bounded scalar details; a partial
source or line arena never escapes. A large tab width cannot bypass the
expanded-output budget.

## Ownership and complexity review

The input is immutable. A uniquely owned output byte buffer grows directly
with appends, and one independently owned line buffer holds scalar records.
The parser never constructs a list of copied line strings or returns an
accumulator through a fallible helper that the caller subsequently grows.
There is no repeated concatenation, speculative scene retention, per-byte
closure, resource payload duplication, or retained slice into an unrelated
combined allocation. Once validated, conversion from UTF-8 transfers the output
buffer into the canonical string.

Worst-case work is O(input bytes + expanded output bytes + lines). Each input
byte is visited once (the LF of a CRLF pair is inspected once and consumed
together), and each expanded tab space is appended once. Dense ranges require
O(lines) storage; the canonical source requires O(expanded bytes). Subsequent
stages must consume the produced ranges and must not split or remeasure all
preceding lines on continuation.

## Phase evidence

The `source_text` harness family measures before source construction and
includes a fixed blank-PDF envelope for the standard fixture protocol. Its
16/160 repetition pair exercises Unicode, CRLF, tabs, empty lines and trailing
spaces, validates every exact line range, and asserts six atomic errors.
The blank PDF is an evidence envelope, not a source-block rendering fixture.

With the pinned `nightly-2026-10-14-38a3029` dev backend, arm64mac and x64musl observations
are 399/407 allocations and 1,254,595/1,317,443 allocated bytes. The variable
work is exactly 192/1,920 input bytes, 224/2,240 output bytes, 49/481 line
writes and range checks, and 64/640 expanded spaces. The eight additional
allocation events are geometric growth of the source and line buffers; the
tenfold input does not copy growing prefixes. Both cases retain six atomic
rejections. The focused cases pass the `scripts/test.py` build/run harness functions
with exact allocation/work equality and independent PDF structure checks on
arm64mac and on cross-compiled x64musl in local `alpine:3.22`. Both targets
match the registered metrics and PDF bytes. Arlington 1.30.2 reports 9,022
passed rules, 286 object checks and zero failures for the envelope.
Full integration-suite validation remains
pending.

## Remaining feature evidence

Public source-block acceptance must additionally prove local registered face,
size, leading and color; preservation of blank lines without synthetic text;
width-aware measured wrapping and explicit oversized-token policy; line-based
page continuation with deterministic first/middle/last panels; artifact
ownership; exact source order across fragments; located impossible keeps; and
ordinary body/furniture typography and paragraph spacing unchanged. It needs
independent structure, extraction, rendering and PDF/A-4 checks, exact
allocation baselines and scale pairs. General custom-block fragmentation and
PDF/UA-2 remain outside the currently declared subset.
