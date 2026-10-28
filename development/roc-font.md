# roc-font static PDF instances

Source selection is roc-font commit `8befe25ddd8cc65adadea77631704fe78b3e2b20`
(0.1.0-rc3). Exact upstream archive/member/digest and license pins are retained
in `vendor/fonts/roc-font/upstream-pins.json`. Only the Inter and Fira Code
source assets are retained. Both permit modified font redistribution under
OFL-1.1 without Reserved Font Names; licenses ship in `package/fonts/`.

`scripts/build_roc_font_instances.py` with fontTools 4.61.1 materializes every
axis: Inter opsz=14,wght=400/700 and Fira Code wght=400. `--check` regenerates
and compares exact bytes. These are full coverage static instances, not runtime
variable-font support. roc-font PR #11 is not a prerequisite: PDF facts and
variable outlines alone do not provide a static sfnt byte export.

The adapter uses the existing validated caller-resource boundary. Each face is
inspected once at registration; subsequent preparation consumes those retained
facts. Resource bytes are immutable byte imports, not copied by the adapter.
Three fixed registrations have bounded work proportional to total input size,
with no document-size-dependent registry growth or captured resource closures.
The registry accumulator is consumed sequentially. No new growing-list loops
or fallback policies are introduced. Applications should reuse the registry.

The default remains unchanged in this slice, avoiding an incidental rewrite of
existing layout and allocation evidence. Replacing it is permitted by the user
but requires deliberate default-registry and source-face API work and a reviewed
snapshot migration; the preset provides the integration independently.

The caller-font facade fixture checks body, inline and source `⌘K`, bold, and
atomic missing-glyph rejection. The existing scalable font/planning/subsetting cases remain the scale evidence
for this fixed three-registration adapter; no new scalable algorithm is added.

## Reviewed initial evidence

Pinned nightly-2026-10-27-de79a0f dev backend, x64musl, Zig 0.16.0
ReleaseFast platform: 1,076 Roc allocations, 4,737,468 allocated bytes;
resources/faces/instances each 3. This is a new fixture baseline, encompassing
three full static face inspections, successful three-face PDF generation and
an atomic negative preparation with the retained registry. No existing baseline
or snapshot is changed. The arm64 baseline uses the repository's shared expected
counts; execution here verifies x64musl only.

The 10,526-byte fixture passes PDF/A validation. PDFBox 3.0.8 and Poppler extract
exact `Body ⌘K`, `Inline ⌘K Bold`, and `Source ⌘K`; PDFBox rendering paints three
visible rows at page geometry. `scripts/check_roc_font.py` is registered with the
harness preflight and post-update checks. The bundle consumer verifies all three
static byte payloads and both upstream license digests, then compiles and runs
the public facade from the served bundle. The instance recipe regenerates exact
bytes. All 52 Roc validation tasks pass.

Final verification: `ROC=/tmp/roc-pdf-pinned
ZIG=/tmp/zig-x86_64-linux-0.16.0/zig ./scripts/test.py --allocation-baselines`
completed successfully on 2026-10-29: 418 evidence cases, all exact allocation
and deterministic work checks passing. Existing snapshots and baselines remain
unchanged. `scripts/test_bundle_consumer.py` passes with the pinned Roc and Zig
0.16.0 on PATH, and `scripts/build_roc_font_instances.py --check` passes.

Release verification on nightly-2026-10-28-bad769b repeats the focused case
with identical PDF bytes, 1,076 allocations and unchanged work/byte counts.

The harness requires the retained PDFBox extraction/rendering oracle.
`python3 scripts/check_roc_font.py --poppler` additionally checks Poppler
extraction when that separately installed tool is explicitly requested.
