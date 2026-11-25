# Testing and fixture development

Run all checks through the Python test driver:

```sh
./scripts/test.py
```

Set `ROC` to use a specific compiler executable, `--jobs N` to override the
hardware-aware worker count, or `--verbose` to mirror the detailed log:

```sh
ROC=/path/to/roc ./scripts/test.py --jobs 8 --verbose
```

The driver applies `roc fmt --check` to the validation inventory in
`tests/spec.json`, type-checks every root in it and runs every `expect`, builds
each fixture group application once (see [Family fixtures and fixture
groups](#family-fixtures-and-fixture-groups)), and executes independent
evidence cases in parallel, one process per case. Fixture builds obey
`toolchain.max_build_workers` and run as many at once as available memory
allows at 7 GB each; validation tasks share a memory budget of 4 GB per root
and 6 GB per group application. Logs are written under `.roc-pdf-tmp/logs/`.

To iterate on one group or case without the preflight and validation phases:

```sh
./scripts/test.py --quick --group layout
./scripts/test.py --quick --case "tables invoice x50" --compare-baselines
```

The Zig build installs the ordinary host into `tests/platform/targets/`
and the retention host into `tests/retention_platform/targets/`. It also
builds the static PIE startup object from the pinned Zig distribution's musl
sources and installs it into both Linux target directories, alongside the
retained libc archive. Each platform's `inputs_dir` stays
inside its own directory, as required by the pinned compiler.

Every `roc check`, `roc test`, or `roc build` re-checks the whole package
(about 4 s and 4 GB per root), so the driver plans validation to give each
root exactly one compiler invocation (`plan_validation` in `scripts/test.py`):

- `package/all.roc` is tested; it exposes every package module, so it runs
  every package `expect`. `package/main.roc` is checked.
- An application root's `roc test` would re-run every package `expect` too,
  so application roots are tested only for the expects in their own file and
  in the same-directory modules they import: every root whose own file has
  expects is tested, then, per directory, the fewest roots whose local import
  closures reach the remaining expect-bearing modules. A group application's
  closure also follows its package edges into its family packages, whose
  expects its `roc test` runs; the families' own `package.roc` files are not
  roots.
- `roc test` and `roc build` report the same errors and warnings as `roc
  check`, with the same exit codes, so a tested root is not also checked, and
  a fixture root that no test needs is checked by its evidence build.
- Every other root (examples, fuzz targets, platforms) gets one `roc check`.
- `roc fmt --check` runs as one batch of files per worker.

The detailed log records the plan (`PLAN test <root> (checks it and runs
expects in ...)`, `PLAN check <root>`, `PLAN <root>: checked by its fixture
build`). A failing `expect` names its own file and line, and the driver adds
the test root and every module that root covers. A new expect-bearing module
needs no registration, but it is only run if some root imports it: a module
that no root reaches is not tested. See [fixture planning](performance/test-suite-speed.md) for the validation strategy.

## Allocation baselines

Integration cases use the dev backend with explicit lambda-set specialization
(`toolchain.roc_specialization: "yes"`) and require exact PDF snapshots,
dimensions, allocation baselines, deterministic work counters, retention
contracts, and explicit structural validators. Review allocation changes with:

```sh
./scripts/test.py --compare-baselines
```

The [fixture equivalence contract](performance/fixture-grouping.md#equivalence-evidence)
retains compile-time generation for structural blank and the static PDF/A-4
blank/fixed-figure cases, including the Standard twin. Their emitted bytes and
work records are explicit module values; the payload-less case inputs and
scenario identities remain unchanged. Report, navigation, caller-font and
chunked fixtures continue to measure runtime work. A separate runtime variant
needs its own input and scenario identity rather than replacing static coverage.

After reviewing an intentional PDF change, update snapshots with:

```sh
./scripts/test.py --update-snapshots
```

Snapshot updates still require the exact allocation and work-counter baselines
in the same run. An allocation event is a call to `roc_alloc` or `roc_realloc`;
host setup, teardown, and family-case JSON decoding are outside the
`before_fixture_main` measurement boundary.

The test hosts report metrics protocol 2:

```text
ROC_METRICS protocol=2 allocations=N allocated_bytes=B work=W1,W2,...
```

`allocated_bytes` sums the size of every `roc_alloc` and the new size of every
`roc_realloc` inside the same boundary. It is deterministic for the pinned dev
backend. Each case records it per target beside `allocations`, and the harness
fails a case whose allocated bytes exceed the recorded value by more than 10%
(`ALLOCATED_BYTES_CEILING_TENTHS` in `scripts/test.py`). The ceiling exists to
catch quadratic copying: a list copied on every append adds one allocation
event per append, so the exact count grows linearly and can look reasonable,
while the copied bytes grow with the square of the list. Decreases and drift
inside the ceiling pass; a reviewed rebaseline lowers the recorded value. The
ceiling is checked wherever allocation baselines are (`--allocation-baselines`,
`--compare-baselines`, `--update-snapshots`), and from the same cold cache.
`--baseline-report` lists every case whose allocations, allocated bytes, or
work differ exactly, so a rebaseline can also lower ceilings that did not
fail.

Fixture executables are built with
`roc build --opt=dev --specialize=yes --no-cache`. With the cache, the
pinned compiler reused package procedures compiled for an earlier fixture
program in later ones, and a later program could then copy lists that it
updates in place when built alone: a case's allocation count and allocated
bytes depended on which fixtures were built before it and on the local cache
(`docs/contributors/performance/lowering-uniqueness.md`). Without the cache each fixture
compiles exactly as a standalone `roc build --no-cache --opt=dev --specialize=yes` does, so a
case can be reproduced outside the harness. The flag works around
roc-lang/roc#11826 and should be removed once that is fixed. Validation (`roc
check`, `roc test`) still uses the cache. Still measure a delta you intend to review from a
cold cache, as CI does, by running the full suite against an empty cache
directory:

```sh
XDG_CACHE_HOME="$PWD/.roc-pdf-tmp/cold-cache" ./scripts/test.py \
    --compare-baselines --baseline-report .roc-pdf-tmp/baselines.json
```

`--baseline-report` (with `--compare-baselines` or `--update-snapshots`) writes
each differing case's expected and observed metrics as JSON for review. It
never edits `tests/spec.json`: accepting a delta remains a deliberate, recorded
change with an identified cause.

CI runs this complete comparison and retains the report and detailed logs for
each target, including failed runs. It still fails when any allocation or work
baseline differs, and functional, byte and structural checks remain mandatory.
Collecting the complete set of differences makes a compiler transition
reviewable without repeatedly rerunning the suite for its next mismatch.

The [accepted compiler/dependency profile](performance/toolchain-profile.md)
records current native provenance, controlled comparisons and reviewed outliers.

## Static PDF/A-4 lanes

Every `Archive` snapshot declares the `pdfa4` validator
(`scripts/check_pdfa4_structure.py`), which re-derives the static profile
facts from the bytes. The external lanes run on demand, after
`scripts/provision_extended_tools.py` has laid down veraPDF, MuPDF, and the
vendored upstream corpus:

```sh
python3 scripts/check_pdfa4.py --cases           # Archive snapshots: zero failed checks
python3 scripts/check_pdfa4.py --standard-cases  # Standard snapshots: only deliberate omissions
python3 scripts/check_pdfa4.py --corpus          # upstream veraPDF PDF/A-4 corpus verdicts
python3 scripts/check_archive_renderers.py --pdfium-renderer PATH --mutool PATH
```

The veraPDF lane always passes the explicit `--flavour 4`. Parser warnings or
task exceptions in package output are failures. Corpus validator defects may
only be recorded in `conformance/verapdf-exceptions.json`, with an upstream
reference. The ledger must map every rule of the pinned profile
(`conformance/verapdf-pdfa4-rules.json`, extracted from the vendored
installer) exactly once; `scripts/check_contracts.py` enforces this.

## Designing correctness oracles

Follow the [testing chapter](../testing.adoc#designing-correctness-oracles)
to choose a production contract, derive an independent oracle, and validate it
with a targeted mutation.

## State models and arithmetic proofs

`./scripts/test.py` runs the document suite's Model and Solve modules as
ordinary Roc expectations. Run them together with the pinned compiler:

```sh
roc test fuzz/document_suite.roc --no-cache
```

Keep each oracle's expectations and helpers in its own module imported by
the suite. Register generated properties in the suite's `Fuzz.suite` list
so the smoke and campaign harness can select them by name. Run both the
deterministic expectations and the optimized fuzz build after changing the
suite's imports. The optimized build checks the imported modules too.

The builder model checks every sequence of up to three appends from its
13 authored operations. It compares normalized leaves, metadata and builder
counts with an independent list model after each operation. Its goals cover
mixed batches, empty and populated lists, and links with destination headings.
The public builder contract checks that heading level 9 produces the same
located diagnostic through both authoring paths.

The xref proof uses the same packing and extraction expressions as the
emitter. It proves the 47-bit stream ordinal and 16-bit member index round-trip
and distinguishes compressed slots from offsets below the high-bit marker.
A concrete maximum-value check exercises the emitter's U64 helpers.

| Contract | Oracle and scope |
| --- | --- |
| First-page breaking | `fuzz/PageBreakModel.roc` exhausts up to three blocks of measured unit rows across four frame heights. It enumerates fitting legal cuts and compares the chosen prefix and ordered relaxations or exact failure. Geometry, shaping, and continuation policy have separate fixture coverage. |
| Scoped continuation | `fuzz/ContinuationPaginationModel.roc` partitions a guarded paragraph or padded source over declared opening and continuation frames. It checks measured and concrete layouts for frame selection, exact row coverage, ownership, geometry, and ordered relaxations, including a return to the default frame or entry to an adjacent scope. |
| Reference wrapping | `fuzz/ReferenceWrapModel.roc` checks up to four measured items. It sums independent partitions for intrinsic widths and enumerates legal line ends for wrapping, including mandatory breaks, held cuts, and fixed-width reference atoms. A separate builder-authored fixture checks I64 overflow in both measurement and wrapping. |
| Canonical resource graphs | `fuzz/ResourceGraphModel.roc` derives identity by byte rank in one forced collision bucket, grows reachability as a set, and selects the smallest ready node by recomputing the ready set. It compares dictionaries, direct dependencies, order, and diagnostics. Three-resource cases distinguish direct from transitive dependencies, ready priority after an insertion, and a cycle reached after a partial schedule. |
| Structure containment through Part and Div | `fuzz/GroupingContainmentModel.roc` compares typed paths with an ancestor walk. It checks mixed chains, physical diagnostic locations, and the effect of an intervening ordinary role. The byte checker exercises nested and mixed grouping twins. |
| Explicit table headers | `fuzz/TableHeaderModel.roc` rescans 1,008 authored grids for exact headers on each cell and compares the typed relationships and identifiers. The byte checker verifies the emitted attributes and resolves their targets. |
| Content operator scopes | `fuzz/ContentScopeModel.roc` exhausts 16 one-page scenes with up to three transforms, optional prepared ActualText and two sibling paint orders. It compares the scope sequence in the serialized content bytes with the authored scene and checks it with one typed stack. |
| Wrapped link regions | `fuzz/LinkRegionModel.roc` groups authored placements by Link and page. A unit-grid oracle checks the exact active area and distinct quadrilaterals across style boundaries, wrap, and page continuation. It compares the enclosing rectangle, keyboard order, and the semantic annotation occurrences that supply OBJR ownership. |
| Page-label range selection | `fuzz/PageLabelModel.roc` compares 1,177 histories with a linear authored-range lookup and independent format examples. It checks resets, UTF-8 budgets and empty labels. A serialized regression verifies the largest representable start. |
| Outline visibility | `fuzz/OutlineModel.roc` derives parents from authored depths and counts visibility from the authored open flags. It exhausts forests with up to five entries and checks signed counts and every sibling and parent link. |
| Appearance transparency | `fuzz/AppearanceTransparencyModel.roc` compares 48 typed form chains using the page selected by an annotation and the authored transparent operation. Navigation fixtures separately verify a missing blending-space error and the emitted page group. |
| Stream sealing | The [stream-pair model](performance/sealed-plan.md#bounded-stream-pair-model) compares builder histories with a ledger of ownership, object order, references, and last payload use. |
| Page-tree child spans | `fuzz/PageTreeProof.roc` proves that one level's fixed-fanout partition covers every child exactly once through the structural page cap. It uses the scalar terms from production, then walks concrete shapes at fanout boundaries and the cap to check dense offsets. |
| Dense-store spans | `fuzz/DenseSpanProof.roc` proves endpoint validation across all U64 inputs and checks the concrete helper against U128 addition. It then uses a solver-produced wraparound witness to test the actual scene planner and its diagnostic, alongside a valid empty range. |

### Content operator scopes

Scope pairs must nest in last-open, first-close order. Graphics saves and
restores may balance over an ordered page Contents array. Marked content must
close in its physical stream. One synthetic check carries graphics state over
the boundary and another rejects a marked sequence across it. The model also
rejects a balanced sequence that closes a marked scope before the graphics
scope it encloses. [ISO 32000-2:2020+EC3](https://pdfa.org/resource/iso-32000-2/),
[§8.4.2](https://pdf-issues.pdfa.org/32000-2-2020/clause08.html#H8.4.2),
[§14.6.1](https://pdf-issues.pdfa.org/32000-2-2020/clause14.html#H14.6.1),
[ISO-approved correction #302](https://github.com/pdf-association/pdf-issues/issues/302).

The emitted check observes `KernelContent.Plan` bytes before PDF object
packaging. The current writer emits one stream per page in this path and keeps
each text object within it. Its graphics scopes wrap complete text objects.
The rule that graphics save and restore inside a text object also preserve
both text matrices is outside this emitted model. Compatibility sections and
operand semantics are outside its observed operator set. The stack allows text
state changes outside a text object, while the emitted trace checks where the
current writer places them. Positioning and showing text require an open
text object. [ISO 32000-2:2020 §§9.3–9.4 and EC3](https://pdfa.org/resource/iso-32000-2/).

## Property fuzz targets

The bounded property targets in `fuzz/` are evidence-only applications on the
content-addressed `roc-fuzz` platform. `./scripts/test.py` formats every
`fuzz/*.roc` source and chooses the fewest application roots that exercise
every module's `expect`s. A separate lane runs the generated properties
against their example inputs and corpora. It has two modes.

The smoke mode is the default and is what every pull request runs:

```sh
./scripts/fuzz.py            # or: blueprint run fuzz
```

It builds two shared suites with `roc build --fuzz --specialize=yes --no-cache` for libFuzzer
coverage instrumentation, then invokes each property independently through
`--target`. It replays the target's seed corpus and up to 64 further inputs
from a fixed seed, with `--time=1` capping the workload at one second per
target. Suites build in parallel (`--jobs`, by default as many 6 GB builds as
memory allows) and run one at a time. Its purpose is that every target keeps building and its property keeps
executing between campaigns; it makes no claim about search coverage.

The campaign mode is the bounded search, 2000 executions per target by default:

```sh
./scripts/fuzz.py --mode campaign                        # or: blueprint run fuzz-campaign
./scripts/fuzz.py --mode campaign --targets jpeg_inspector_mutation --runs 200000
```

Pull requests run the smoke mode in the `Fuzz smoke` job of `ci.yml`, beside
the test job. `.github/workflows/fuzz.yml` runs the campaign daily and on manual dispatch, on the
default branch only; it never runs on a pull request.

In both modes a crash, a per-input timeout (`--timeout`, 10 s), a memory-limit
breach (`--memory-limit`, 2048 MB), or a target still running at the hard
deadline (60 s for a smoke run, 30 min for a campaign target) fails the lane.
Every selected target still runs, and each target's failing inputs are written
to `.roc-pdf-tmp/fuzz-artifacts/<target>/`, which `fuzz.yml` uploads when the
campaign fails. Reproduce one with `.roc-pdf-tmp/fuzz/<target> replay <input>`.

Seed corpora are copied into the ignored `.roc-pdf-tmp/fuzz-corpus/` before a
run, because libFuzzer writes newly interesting inputs back into the directory
it is given and must never own tracked files. The JPEG corpus is tracked under
`tests/assets/jpeg-fuzz-corpus/` and regenerated by
`scripts/build_jpeg_fuzz_corpus.py`; the font targets are seeded from the faces
in `vendor/fonts/` and `tests/assets/`.

A target's corpus is what decides whether its property is exercised at all. An
inspector reached only by raw byte mutation will spend an entire campaign in
its reject paths unless valid inputs are seeded, leaving the accept-path
invariants unevaluated.

Minimized reproductions are retained as `fuzz_seed` assets under `tests/assets/`
with provenance, and promoted to atomic regression tests beside the code they
exercise.

## Family fixtures and fixture groups

Every evidence case belongs to a case family. The only exception is the
retention probe, which runs on its own platform. A family is a local package
in its own directory under `tests/`:

- `package.roc` exposes `Cases`. Public-surface families depend on
  `package/main.roc` and internal evidence families on `package/all.roc`;
  one directory, and one program, never mixes the two.
- `Cases.roc` holds the family's closed `Case` tag union and its `run`
  dispatch.
- `cases.jsonl` is a deterministically ordered file. Each schema-version-1
  row has exactly `name`, `schema_version`, and `case`.
- `Fixture.roc` and any other modules hold the shared scenario pipeline.

Families run in fixture groups. `tests/groups/<group>.roc` is generated from
`tests/spec.json`, and the driver refuses a stale or unlisted copy. It
decodes one argv envelope,
`{"case":{"<FamilyTag>":<row case>},"schema_version":2}`, into the union of
its families' `Case` types and checks that it round-trips canonically.
Malformed or unknown cases fail explicitly. It then resets the allocation
counters and calls the family's `run`. The family tag is the PascalCase of
the family name. Each case still runs in its own process. The harness
builds each group once.

To add a family case:

1. Add its typed case tag and fields to the family's `Cases.roc` and
   implement the scenario through the shared fixture pipeline. Pass runtime
   guards as typed fields (for example `context : U64`). A payload-less
   case, or a constant computed in a `match` arm, can be evaluated at
   compile time and measure nothing. A JSON-decoded `Str` field does not
   allocate like an argv string; see
   [fixture grouping](performance/fixture-grouping.md).
2. Add one ordered row to `cases.jsonl`.
3. Add the matching case to `tests/spec.json` with its `family`, snapshot,
   dimensions, work counters, allocation baseline, retention contract, and
   ordered `validators` list. The snapshot lives in the family directory.

To add a family:

1. Create `tests/<family>/package.roc`, `Cases.roc` and `cases.jsonl`.
2. Add `{"name": "<family>", "group": "<group>"}` to `families`.
3. Run `./scripts/test.py --write-groups`.
4. Keep each group's build under 7 GB peak RSS. Facade families cost 5 to
   6 GB alone and kernel families 2.5 to 3 GB. Check with
   `/usr/bin/time -v roc build tests/groups/<group>.roc --opt=dev --specialize=yes --no-cache`.

Before landing a change to group membership, run the equivalence modes on
the affected groups from an empty `XDG_CACHE_HOME`. Each must report no
exact difference:

```sh
./scripts/test.py --quick --group <group> --compare-baselines --baseline-report group.json
./scripts/test.py --quick --group <group> --isolate --compare-baselines --baseline-report isolate.json
./scripts/test.py --quick --group <group> --group-mode perturb --compare-baselines --jobs 2
./scripts/test.py --quick --group <group> --group-mode inject --compare-baselines
```

`--group-mode inject` must pass with exactly one extra allocation in every
grouped case. `./scripts/test.py --list-groups` lists the groups and their
families.

The harness requires a one-to-one match between JSONL rows and spec cases.

Validator, preflight, and post-update IDs are resolved through the allowlisted
registry in `scripts/harness_validators.py`. Unknown or duplicate IDs are
schema errors; routing is never inferred from filenames, directories, or
dimension flags.

The test-only Zig platform supports macOS AArch64 and Linux x86-64. It derives
from `roc-platform-template-zig` and retains the upstream notice in
`tests/platform/NOTICE`.
