# Fixture grouping

The suite used to build 62 fixture executables, one for each source. It now
builds 12: eleven group applications and the retention probe. The allocation
evidence does not change. All 413 cases keep their exact allocation counts,
allocated bytes, work counters and PDF bytes, and no baseline was
rebaselined. The measurements were taken on `nightly-2026-10-23-18478ff`,
Linux x86_64 (x64musl), with the dev backend and Zig 0.16.0.

## Structure

- **Family packages.** Each case family is a local package in its own test
  directory:
  - `tests/<family>/package.roc` exposes `Cases`.
  - `Cases.roc` holds the closed `Case` union and a `run` dispatch.
  - `cases.jsonl` holds one row per spec case.

  The family package depends on `package/all.roc` or `package/main.roc`
  itself.
- **Group applications.** `tests/groups/<group>.roc` is generated from
  `tests/spec.json` by `scripts/fixture_groups.py`, and the driver refuses a
  stale copy. Each one:
  - wraps its families' `Case` types in one tag union;
  - decodes the argv envelope `{"case":{"<Tag>":<row case>},"schema_version":2}`;
  - checks that the envelope round-trips canonically;
  - calls `Metrics.reset_allocations!()`, then dispatches.
- **One process per case.** The measured window runs from that reset until
  `roc_main` returns.
- **Spec schema 7.**
  - `groups` lists the group names.
  - Each family is `{name, group}`, and its package, JSONL file and tag
    (the PascalCase of its name) follow from the name.
  - A case names its `family`. Only the retention probe keeps `source` and
    `args`.
- **Build flags.** `fixture_build_command()` holds every flag of an evidence
  build.
- **Validation.** It follows package edges from a group application into its
  families. One `roc test` of the group runs the expects in all of its
  family packages, and `tests/*/package.roc` roots are skipped.

Two constraints decided the layout:

- **One package root per program.** A program cannot hold both
  `package/main.roc` and `package/all.roc`: building one that did crashed
  the compiler (exit 139). Public-facade families on `main.roc` therefore
  have their own groups.
- **One package per directory.** The facade apps that shared a directory
  with `all.roc` fixtures moved to their own family directories, together
  with their snapshots:
  - `caller_font_facade`
  - `generated_label_facade`
  - `metadata_facade`
  - `navigation_facade`
  - `structural_blank`

**Retention probe.** The retention probe stays a standalone application. It
runs on its own platform (`tests/retention_platform`), which returns a
different record and has no allocation reset to call, and it is the only
case of its kind.

## Groups

Peak RSS and wall time of `roc build --opt=dev --target=x64musl --no-cache`
for each group, into an empty cache:

| Group | Root | Families | Cases | Peak RSS | Build |
| --- | --- | ---: | ---: | ---: | ---: |
| core | all | 21 | 117 | 4.6 GB | 23 s |
| documents | all | 3 | 42 | 6.8 GB | 20 s |
| interactive | all | 2 | 18 | 6.4 GB | 22 s |
| kernel | all | 6 | 30 | 5.1 GB | 19 s |
| layout | all | 4 | 41 | 6.7 GB | 23 s |
| pages | all | 2 | 28 | 6.8 GB | 32 s |
| structure | all | 3 | 37 | 6.7 GB | 34 s |
| text | all | 2 | 53 | 6.7 GB | 33 s |
| public | main | 4 | 18 | 6.6 GB | 27 s |
| public_fonts | main | 2 | 13 | 5.1 GB | 19 s |
| public_output | main | 3 | 15 | 6.8 GB | 24 s |

A single family built alone peaks at 5.3 to 6.0 GB when it uses the `Pdf`
facade, and at 2.4 to 3.3 GB when it uses only kernel modules. The design
asked for groups under about 6 GB, but no facade family fits that alongside
another one. Groups were therefore split until each build stays under 7 GB:

| Split | Peak RSS before | Peak RSS after |
| --- | ---: | ---: |
| `pages` | 7.8 GB with navigation | 6.9 GB, navigation moved to `structure` |
| `text` | 7.1 GB with the extraction families | 6.8 GB |

The small kernel and font families were merged the other way, into `core`
(21 families, 4.6 GB). The driver now bounds memory itself:

- **Builds.** Parallel fixture builds are bounded by available memory at
  7 GB each.
- **Validation.** Tasks share a memory budget, 4 GB per root and 6 GB per
  group application. A group's `roc test` peaks at up to 5.5 GB, and six
  together exhausted a 30 GB machine.

## Equivalence evidence

Every step ran from an empty `XDG_CACHE_HOME` and compared exact
differences (`--compare-baselines --baseline-report`):

| Run | Cases | Exact differences |
| --- | ---: | ---: |
| committed groups | 412 | 0 |
| `--isolate` (each family alone in a generated group app) | 412 | 0 |
| `--group-mode perturb` (each group plus the next group on the same root) | 412 | 0 |
| `--group-mode inject` (one known allocation inside the window) | 412 | every case exactly +1 allocation |
| full suite, `--compare-baselines` | 413 | 0 |

Before each argv application was removed, it was compared case by case with
its converted family. The comparison covered exit status, PDF bytes, and the
`ROC_METRICS` line (allocations, allocated bytes, work). Three conversions
first differed. Each was traced and fixed in the fixture; none was
rebaselined:

- **`placeholder`.** The argv app evaluated `Fixture.placeholder_pdf(0)` at
  compile time, so the bytes were static data. Inside a `match` arm of
  `Cases.run`, the same call ran at run time and cost one more allocation
  (439 bytes). The bytes are now a top-level constant in `Cases.roc`.
- **`archive` negatives.** A title passed as a JSON `Str` field points into
  the decoded input buffer, so `Str.to_utf8` on it does not allocate. The
  short argv string was stored inline in the `Str` value, and converting it
  did allocate (11 more allocations). The case now selects its title from a
  `context` guard, as the navigation negatives do.
- **`pdf_facade` image figure.** A payload-less variant let the compiler
  evaluate the figure document at compile time: 0 allocations instead of
  615. A `context` guard restores the run-time evaluation.

The two failure modes to watch for in a typed case are a `Str` field where
an argv string was used, and a payload-less case where a runtime guard was
used.

Two existing cases measure compile-time-evaluated documents, before and
after grouping:

- `structural-kernel blank PDF` records 0 allocations;
- the static PDF/A-4 blank and figures cases record 1 allocation.

## Suite time

Local, `./scripts/test.py --compare-baselines --jobs 6`, empty cache, on a
30 GB machine with about 22 GB available:

| Phase | 62 executables | 12 executables |
| --- | ---: | ---: |
| Preflight self-tests | 22 s | 32 s |
| Validation (fmt, check, test) and the Zig host | 243 s | 291 s |
| Fixture builds | 422 s (4 jobs) | 233 s (2 jobs by available memory) |
| Case execution | 33 s | 53 s |
| Total | 721 s | 610 s |

**Builds.** Fixture builds take about half as long, even though the memory bound let
only two run at once; most groups build in 20 to 34 s alone.

**Validation.** Validation is now the longest phase, and its cost is mostly
outside the fixtures:

- each `fuzz/*.roc` property root's `roc test` re-runs the roughly 600
  package expects, at 35 to 70 s each;
- the examples' checks take 22 to 33 s each;
- the contract roots take up to 54 s.

It also runs a little slower under the memory budget.

**Case execution.** Executing the cases takes 20 s longer. Each case still
starts its own process, now from a larger executable that decodes a larger
union. The measured window is unaffected, because the reset follows the decode.

## Driver options

- **`--list-groups [--json]`.** Lists the groups, their families and case
  counts.
- **`--write-groups`.** Regenerates `tests/groups/*.roc`.
- **`--group NAME`.** Selects a group's cases. It combines with `--case`.
- **`--quick`.** Builds and runs the selected cases without the preflight
  and validation phases.
- **`--isolate`, or `--group-mode isolate`.** Builds each family alone; this
  is the equivalence oracle.
- **`--group-mode perturb`.** Builds each group with the next group on the
  same root. Run it with `--jobs 2`, because these builds are larger.
- **`--group-mode inject`.** The window self-test: every grouped case must
  report exactly one more allocation than recorded.
