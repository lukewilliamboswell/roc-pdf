# Packaged roc-font families

Current assets come from roc-font [0.1.0-rc4](https://github.com/lukewilliamboswell/roc-font/releases/tag/0.1.0-rc4).
The exact published bundle is
`3Es9Gca6KTySYDqcDPHwVqpAqJk6KwT9G4xkcLoYaSsx.tar.zst`, SHA-256
`0b2705f8c4ebff64ffe2fd79ef0b335fc84561693e121fa48d1e88ae2407350c`.
All ten retained TTFs were extracted from that verified bundle and compared
with rc4's upstream archive/member/digest manifest. They are unchanged, static
files, not generated variable instances. The three OFL notices ship alongside
them. Merriweather retains its Reserved Font Name because its files are unchanged.

`python3 scripts/build_roc_font_instances.py --check` verifies all retained font
and licence bytes offline. Add `--bundle PATH` to compare against the exact
published bundle. `--install --bundle PATH` reproduces those files after checking
the complete bundle's length and digest. This current procedure needs only
Python's standard library and tar/zstd; fontTools remains necessary for unrelated
legacy fixtures, not these default assets.

## Selection, ownership and work

The ordinary facade now resolves exact family/style intent before shaping.
Default body/headings use Inter; explicit serif selects Merriweather; code uses
Fira Code. Strong/emphasis compose to genuine Bold Italic irrespective of nesting
order. Missing styles and coverage reject without fallback. The user guide records
the supported per-family/style/script matrix and the upstream unsupported cases.

The resolver first collects named demands into a fixed ten-slot set, then
registers only demanded packaged faces in canonical order through the ordinary
validated resource boundary. The full payload totals 7,070,508 bytes; the largest
face is 1,198,568 bytes. All fit the unchanged explicit 2 MB public registration
limit. The private legacy helper's former 200 KB limit is replaced for the new
assets. The explicit `RocFont.register` adapter intentionally registers all ten
once; reusing its registry/family mappings does not register them again.

Registration consumes one registry, extracts each scalar handle before its next
append, and retains the original immutable byte allocation and inspection facts.
Inline style flags propagate once through normalized preorder parents; no per-leaf
ancestry walk is required. A dense face-to-candidate map avoids repeated scans
when source blocks introduce many distinct caller fonts. Candidate inspection
stores contain selected faces; final output compacts to painted faces and embeds
only their sanitized subsets. Temporary style/demand tables do not enter sealed
PDF plans. Each stage retains its own explicit facts rather than identifying a
family by a PostScript name, glyph ID or insertion accident.

Deterministic resolver counters are `packaged_inspections`,
`registered_font_bytes`, `inline_visits`, `source_visits` and
`copied_input_bytes`. The last counts resource-input copies and remains zero;
new subset bytes are distinct output work. Inline/source counters cover every
resolution traversal, including dense exact-face materialization. The default
asset migration deliberately changes applicable facade measurements, pagination,
font programs, snapshot bytes and allocations. The integration review records
these causes before any evidence baseline is updated.

Facade layout-work probes consume the same resolved family/style facts as their
public outputs. Custom-block evidence measures selected-font line layout and
pagination; final report facts independently cover fragments and placements.
It does not substitute the legacy regression face or lower colored panels
without document intent facts. Replacing its former legacy-face TextReady probe
changes that fixture's measurement boundary, so both targets must be measured
again before allocation baselines are accepted.

## Source metadata and exact angles

Inspection now retains source post angle/fixed-pitch facts and validates
head/OS2 Bold/Italic style-link consistency. The subset post header preserves
the exact original angle and fixed-pitch value; head/OS2 style declarations are
copied unchanged. Descriptor style facts are resolved before canonical resource
identity. Italic/Oblique and FixedPitch flags follow those retained facts.
Positive OS/2 family-class/PANOSE declarations set Serif; unknown/conflicting
classification never consults a name. All supplied rc4 faces have unclassified
serif metadata (family-class zero; Merriweather/Fira PANOSE all zero; Inter
PANOSE family 2 with serif-style zero), so the package does not invent that flag.

The source Inter italic angle is exactly `-616038/65536` degrees and
Merriweather's is `-511180/65536`; neither is an integer. A separate bounded
signed-16.16 number primitive emits these exact finite decimals without floating
point or rounding. Unit witnesses cover the full signed endpoints, sub-unit
angles, canonical zero and an independent Oblique flag. Source formats follow
the primary [post](https://learn.microsoft.com/en-us/typography/opentype/spec/post),
[head](https://learn.microsoft.com/en-us/typography/opentype/spec/head), and
[OS/2](https://learn.microsoft.com/en-us/typography/opentype/spec/os2) definitions.

Canonical font-leaf recipe schema 2 explicitly changes its angle field from
integer degrees to raw signed 16.16. The unchanged eight-byte width adds no
recipe bytes or traversal work, but the new version changes resource/file
identities even for upright zero-angle faces. It does not change those faces'
metrics or the source-digest/glyph-closure subset-tag procedure. Exact style
metadata and larger inspection records are deliberate migration causes, not
automatically accepted baseline drift.
The [existing-fixture review](performance/rc4-existing-fixtures.md) isolates the
runtime 32-byte subset `post` header allocation and expanded inline inspection
storage. Its direct subset control does not resolve a descriptor, so the extra
allocation must not be described as solely a per-face descriptor record.

## Downstream handoff

Adoption in roc-automation remains separately owned by
[roc-automation #98](https://github.com/lukewilliamboswell/roc-automation/issues/98).
Its current renderer explicitly registers four Inter faces, a generated serif
heading face and Source Code Pro. A dependency URL update alone leaves those
assets active.

The concrete tested 0.3.0 candidate is recorded in the
[artifact review](release-artifacts-rc4-review.json): source commit
`c08a3f81e21a2641bcdb9b786f381c6a5e59398e`, bundle
`C3YnjBMeN7A9ar7F5seM73coSTkYLSksTD2BNikQEVSP.tar.zst`, SHA-256
`83e4ca7077ca2bb561d39f944ea23e7bc13ffa3a9c78637ea63e9d68674dfaa4`.
Its destination is
`https://github.com/lukewilliamboswell/roc-pdf/releases/download/0.3.0/C3YnjBMeN7A9ar7F5seM73coSTkYLSksTD2BNikQEVSP.tar.zst`;
that URL becomes available only upon an actual release. The #98 owner must
verify the published bytes against this tested pin, then apply the registrations,
notices and layout regression checks below.

The downstream change must pin the tested roc-pdf release bundle and digest,
replace those local PDF registrations with `RocFont.register` and its family
mappings, select the `Available` face from `faces.serif.bold` explicitly for its existing serif headings,
and retain its sizes, colours, margins, spacing and code scaling. Use the new
source face tags, replace PDF font notices with `RocFont.licenses`, and remove
superseded PDF-only assets, generation inputs and cache/release packaging entries.
HTML font selection stays independent. The release handoff must include the
actual published roc-pdf package URL/digest; this PR does not publish a release
or claim downstream adoption.

Downstream regression acceptance covers exact body/inline/source Command-K
extraction and visible geometry, genuine emphasis/combined styles, unchanged
atomic missing-character/style failures, original PDF bytes in conformance
oracles, and deterministic output from repeated builds. Run the renderer's
preparation/HTML expects and `tools/roc-docs/tests/test_cli.py` suite against the
pinned bundle, retaining the raw extraction/render reports. This is an explicit
consumer work item; current roc-pdf package evidence does not close it by proxy.

## Historical rc3 preset evidence

The following record describes the earlier 0.2.0 preset and its original
compiler/run evidence. Its source bytes, pins and generation recipe remain
retained; the numbers below are historical, not rc4 baselines.

Source selection is roc-font commit `8befe25ddd8cc65adadea77631704fe78b3e2b20`
(0.1.0-rc3). Exact upstream archive/member/digest and license pins are retained
in `vendor/fonts/roc-font/rc3-upstream-pins.json`. Only the Inter and Fira Code
source assets are retained. Both permit modified font redistribution under
OFL-1.1 without Reserved Font Names; licenses ship in `package/fonts/`.

`vendor/fonts/roc-font/build_rc3_instances.py` with fontTools 4.61.1 materializes every
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
