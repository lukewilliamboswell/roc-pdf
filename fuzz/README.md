# Property fuzz targets

These evidence-only applications check correctness, determinism, bounded errors
and invariants through the content-addressed `roc-fuzz` platform. They do not
make a security claim or add a production dependency to the pure Roc package.

Run all targets with the repository's pinned Roc compiler:

```sh
./scripts/fuzz.py --jobs 1
```

The smoke lane checks every declared example in a fresh supervised process,
compares its exact accepted allocation observations, then requests fixed-seed
coverage exploration with a 64-run cap and a one second exploration budget.
An input already executing may finish later under its invocation deadline;
the separate whole-target deadline remains enforced. A campaign may finish
fewer executions within its budget. Campaigns default to 2,000
executions; select targets and bounds explicitly for a longer search:

```sh
./scripts/fuzz.py --mode campaign --targets jpeg_inspector_mutation --runs 200000 --jobs 1
```

The supervisor enforces invocation deadlines and the exploration worker's RSS
limit. The harness also enforces a whole-target deadline, requires useful
accepted exploration, checks reported provenance and effective controls, and
rejects unbaselined or incomplete example evidence. Compiler warnings are
accepted only under the repository's existing downloaded-package policy.

## Review allocation observations separately

Named examples and saved witnesses live beside each target. New observations
are reviewed before explicit acceptance; verification never accepts changes:

```sh
./scripts/fuzz.py --check-only --jobs 1
# Inspect the printed report directories and review source/ownership causes.
./scripts/fuzz.py --accept-baselines --no-build --jobs 1
./scripts/fuzz.py --no-build --jobs 1
```

`--no-build` requires a matching source/asset closure, compiler, host and binary
digest from the recorded build. It refuses stale executables. The optional
`fuzz-accept` Blueprint task performs the same explicit maintenance action.
Accepted files under `fuzz/baselines/` contain separate host entries for the
`llvm-fuzz` profile; reductions also require review. These observations do not
replace the dev-backend PDF allocation, byte, work or retention contracts in
`tests/spec.json`.

Use `--linux-x64-container IMAGE` to cross-build and exercise the Linux host in
a local container. Reports retain the actual compiler/platform/source identity.
For published CI use, the ordinary workflow executes on a native Linux runner.

## Read reports and retain witnesses

Each invocation prints a fresh directory under `.roc-pdf-tmp/fuzz-artifacts/`.
It contains an invocation record, build logs, each supervisor's `report.json`,
summary and combined child log, original example inputs, observations and any
failure artifacts. CI uploads this evidence on success and failure. The report
keeps outcome, baseline matching, metric validity, trace results and capture
completeness separate; a successful process exit alone is insufficient.

The raw font and JPEG targets copy tracked seeds into ignored writable corpora.
Structured targets preserve their existing entropy generators and reject decoded
values outside their explicit size domains. Source-declared examples are checked
independently of coverage retention. Raw font witnesses use `Fuzz.saved` original
bytes: encoding a large byte list as a typed value would exceed the binary
codec's node budget and would not preserve the original inspector input.

A target's `show`, `replay`, `measure` and `retain` commands inspect inputs and
record reproducible findings. Keep storage-sensitive witnesses as original
bytes; logical encoding preserves values, not capacity, sharing or slices.
Minimized inputs promoted to tracked binary regressions need the usual asset
provenance entry. Existing tracked corpora are never mutated in place.

## Properties

- `font_inspector_mutation`: successful bounded TrueType inspection preserves
  independently checked directory, coverage, glyph, component and work facts.
- `font_inspector_repair`: independent checksum restoration lets bounded table
  edits reach parsers behind the checksum gates. The five-font selector mapping
  is retained.
- `font_subset_roundtrip`: repeated bounded plans/subsets agree, re-inspect,
  preserve source style facts and metrics, and rewrite composite dependencies.
- `jpeg_inspector_mutation`: successful grey/RGB inspection produces a bounded
  sanitized stream with resolved dimensions/orientation and only allowed
  application segments.
- `facade_output_equivalence`: repeatability, buffered/chunked equality, chunk
  ownership invariance, prepared output and transactional rejection agree.
- `facade_structure`: an independent byte-level oracle verifies PDF framing,
  xref/object offsets, stream lengths, references and canonical dictionaries.
- `navigation_property`: generated navigation is deterministic and transactional;
  one-fault scenarios also assert exact typed rejection.
- `registry_property`: registration, explicit policies, cluster selection,
  retained ownership and expected errors satisfy their public contracts.
- `theme_options`: ordinary and extreme themes terminate deterministically,
  preserve buffered/chunked agreement, or reject without partial bytes.

## Profiling aid

`./scripts/profile.py` measures four document and six kernel workloads through
named allocation regions in fresh processes. Its table counts Roc allocation
events (`allocs + reallocs`), while supervisor reports retain all statistics.
PDF lengths/fingerprints are output metadata, independent of allocation counts.
The empty-input executable path runs all workloads; individual selector inputs
isolate each workload. This app deliberately declares no baseline examples and
is replay/measurement tooling, not a coverage campaign or an acceptance gate.

Saved profile comparisons require the same compiler, backend, host, platform
and counting definition. Previous instrumentation records remain separate.

See the [upgrade evidence](../development/roc-fuzz-0.5.0.md) for immutable inputs,
API migration, reviewed initial example observations and validation results.
