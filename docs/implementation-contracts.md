# Versioned Implementation Contracts

[architecture.md](../architecture.md) owns enduring package, stage, ownership,
conformance, determinism, and performance decisions. This record preserves the
binding representation and repository-harness details used to implement those
decisions. The [roadmap](../feature-roadmap.md) owns capability availability and
evidence; inclusion here does not establish a public capability.

These contracts were extracted from the architecture without changing their
requirements. Revisions require an explicit design decision, affected
allocation/work and byte evidence, and updates to the normative ledger or
architecture when their boundaries change. Compiler- or feature-caused baseline
changes follow the existing review protocol; this record is not permission to
regenerate evidence mechanically.

## Emission representation

`SealedPdfPlan` is an exact compact replayable plan, not a fully materialized
recursive PDF tree or a collection of precompressed byte blobs. Every object
and indirect stream-length object is assigned before emission. Object IDs
follow emission order so offsets append to a dense list rather than update a
map. Ordinary stream lengths use indirect objects emitted immediately after
their streams. A generated stream payload is already held whole in the
sealed plan's payload store; the encoder compresses it whole at its stream's
transition into one owned buffer, emits it as one generated segment, releases
the source payload at its last use, and records the compressed length for the
following length object.

DEFLATE goes through one private seam, `KernelDeflate`, whose single call into
the pinned pure-Roc `roc-deflate` package (a libdeflate port) compresses at a
fixed package-versioned level. The seam owns the zlib framing (header and
Adler-32 trailer), accepts preflighted input and checked limits, proves a
conservative output bound before a plan escapes (the dependency's stored-block
bound plus six framing bytes), checks the emitted length against it, and
reports deterministic work (streams, input bytes, and emitted bytes). The
independent Python checker uses zlib only as a test-time decompression oracle
over the emitted PDF bytes. Changing the dependency version or the level is a
byte-contract change reviewed like any other; it cannot weaken these
contracts or change emitted bytes silently.

The initial xref stream is unfiltered, covers the complete contiguous object
range, and uses `/W [1 8 2]`; its direct length is therefore 11 bytes per entry
with checked multiplication. The encoder retains `U64` offsets proportional to
object count. Any alternative compressed or replay/counting strategy is a
separately specified capability. Sealing proves exact counts where possible
and safe upper bounds for lexical output, compression, offsets, and configured
output budgets so the infallible encoder cannot discover overflow or limit
failures.

The encoder is an explicit state machine, not a stored iterator closure. It
consumes one state and returns its successor plus a coarse output segment. A
segment is either a generated, independently owned bounded-capacity buffer or
an exact range of validated resource bytes that are already in their final PDF
representation. The public `List(U8)` for the latter may be a Roc seamless
slice, avoiding a payload copy. Generated PDF syntax, transformed image data,
font subsets, and DEFLATE output are never presented as slices of mutable
accumulators or oversized internal arenas. Retaining an old encoder state is
valid but forfeits the unique-state fast path.

The package never coalesces shareable resources into one whole-document byte
arena, and package-created shareable resources use separate reference-counted
allocations. A caller-supplied resource may itself already be a seamless slice
of a larger caller allocation; sharing it can retain that actual backing
allocation, not merely the visible resource range. The encoder releases its
own resource reference immediately after its final emitted range; any remaining
lifetime is then caused by caller-retained chunks. Chunked output has an
explicit retention policy: the default shares unchanged resources for the
ordinary consume-and-release streaming path, while an owned-chunk mode copies
such ranges into bounded buffers when predictable retained memory is more
important than avoiding the copy. Both policies emit identical bytes.

Buffered output drives the same lower-level emission transition into one unique
byte accumulator, reserving only an exact known size. When the final size is
not exact, the accumulator follows one deterministic bounded-growth policy; a
loose validated worst-case bound is never used as a requested allocation size.
It does not first build a `List(List(U8))` and concatenate it. Resource ranges
are copied directly into this final contiguous result, because `to_bytes`
cannot both return one allocation and preserve zero-copy resource sharing. The
public chunk wrapper either returns a permitted seamless resource slice or
supplies a fresh bounded buffer to the transition. A high-level chunk
entrypoint may expose the validated encoder, while one-shot byte sources that
cannot be replayed or fully validated are not accepted as resources.

## Repository fixture protocol

Repository file and directory names must not collide under case-insensitive
comparison. The contract preflight checks Git's path inventory on every host,
including Linux, so a macOS checkout cannot silently replace a fixture module
with a differently cased app root. App and module names must be distinct beyond
capitalization.

Evidence applications are ordinary apps under capability-named directories in
`tests/`. Internal evidence imports the local `all.roc` root, while public API
fixtures import `main.roc`. Test-only fixture modules live beside the apps that
share them rather than in `package/`. Related cases with one fixture pipeline
use one family app root and a deterministically ordered, versioned JSONL case
file. The app decodes exactly one JSON argument into a closed typed case union;
unknown tags, malformed fields, and unsupported schema versions are explicit
failures. The harness builds each family root once, then may execute its rows in
parallel. Genuinely different application/package boundaries may still use
multiple named roots in one capability directory.

Case manifests declare their ordered structural validators explicitly by
stable allowlisted ID. Numeric dimensions are evidence inputs, not implicit
validator selectors, and source paths or directory names never choose semantic
checks. Preflight checker self-tests are likewise an ordered manifest list.
Python registries bind those IDs to project-owned callables and scripts without
allowing manifest data to import or execute arbitrary code.

Exact allocation baselines and allocated-bytes ceilings are measured from a
cold Roc cache, in the full harness order that CI runs, with fixture
executables built by `roc build --no-cache`. The pinned compiler produces
different code for identical source when it reuses procedures cached by other
programs: a program built against procedures compiled for another fixture can
copy a list that the same program built alone updates in place, even though
bytes and work counters are identical. Building fixtures without the cache
makes each case's allocation evidence independent of build order and cache
state. A reproduction of the cache dependence is recorded in
[upstream-roc-uniqueness-issue.md](performance/upstream-roc-uniqueness-issue.md)
(B). A case's
static PDF/A-4 claim is declared by its `pdfa4` validator; Standard-only
snapshots must never declare PDF/A identification, and
`scripts/check_pdfa4.py` enforces both directions.

## Scope decisions (2026-09-28)

The maintainer refocused the project's goals on correctness to stop gates from
accumulating evidence that does not affect whether generated PDFs are right.
[architecture.md](../architecture.md), the [roadmap](../feature-roadmap.md),
and `AGENTS.md` now state that:

- Performance evidence exists to catch super-linear or exponential blow-ups
  that would make the package unusable. Exact per-case Roc allocation counts,
  deterministic work counters, and the pinned-compiler re-baseline protocol
  remain mandatory and unchanged; every scalable feature carries at least one
  small/large scale pair proving linear or `n log n` work growth.
- There are no numeric latency, peak-memory, throughput, output-size, or
  benchmark product targets, and no controlled timing or memory jobs. Copied
  bytes, ARC counts, retained bytes, peak RSS, and timing are recorded only
  where existing instrumentation reports them.
- Human reader and assistive-technology review, expert review, and assessor
  sign-off are optional recorded protocols that do not block Gate 6, Gate 7,
  or later closure. Human-verifiable requirements remain recorded as author
  obligations, and the package still never claims to certify semantic quality.
- Machine-verifiable conformance (veraPDF profiles, PDF/UA-2 and PDF/A-4
  ledger rules, structural checks, and atomic negative twins), determinism,
  ownership, and no-fallback invariants are unchanged.
