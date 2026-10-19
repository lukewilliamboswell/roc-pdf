# PDF generation comparison trial

Compare the complete scripting experience, then compare compiled applications
with build and execution shown separately. This optional development experiment
does not change any production dependency, capability claim, allocation baseline,
snapshot or performance acceptance requirement. It is a trial design and runnable
harness, not a general ranking of languages or PDF libraries.

## Workload and comparisons

`workload.json` is the common source for a one-page operations report: a title,
three wrapped paragraphs, a captioned four-row table and a footer. Preparation
generates constants for all three languages from that file. Each program reads
the same `package/RocPdfSans-Regular.ttf` at runtime and embeds its selected
font data in its output. The font's existing provenance and license remain in
the repository's asset manifest. Font loading/registration is measured.

All pages are exactly 595 × 842 points, with 50-point side/top content margins,
an 18-point title, 11/15-point body text, and a 9-point footer. A single regular
face is intentional. The layout implementations are idiomatic approximations,
not pixel-identical templates. Roc uses semantic flow blocks and a native table;
ReportLab uses Platypus flowables and a table; Go wraps paragraphs and positions
the small, single-line table cells with fpdf. The Go example does not implement
general table layout or pagination.

| Track | Program | Measured command |
| --- | --- | --- |
| Source → PDF | Python + ReportLab | `python report.py` |
| Source → PDF | Roc + basic-cli + roc-pdf | `roc run main.roc` (default dev backend) |
| Source → executable | Roc | `roc build main.roc --output=report` (default speed optimization) |
| Source → executable | Go + fpdf | `go build -o report .` |
| Executable → PDF | Roc or Go | `./report` |

The Roc facade keeps its default `Archive` profile: tagged PDF 2.0 with its
static PDF/A-4 claim, embedded subset, Unicode mappings and color profile.
ReportLab and fpdf produce ordinary PDFs with embedded TrueType fonts; they do
not supply equivalent tagging or archival conformance. The harness records
`pdfinfo`/`pdffonts` output rather than treating these different output contracts
as identical. Passing this trial's checks establishes the workload, not full
PDF conformance. No PDF/UA claim is made.

## Run

Prerequisites: the compiler in `.roc-version`, Go 1.21 or later, Python 3.11 or
later (required by the pinned Pillow), and Poppler's
`pdfinfo`, `pdftotext` and `pdffonts`. This POSIX harness supports macOS and Linux.
It requires no Python measurement dependencies. The target virtual environment
uses the versions pinned in `requirements.txt`; Go uses `go.mod` and `go.sum`.
The exact compiler/interpreter versions and executable paths are recorded.

First provision the Roc URLs in `package/main.roc` and `main.roc.in` and their
transitive dependencies in Roc's package cache. Preparation copies only those
immutable packages into the workspace. `--roc-packages` selects a different
provisioned package cache. Missing dependencies fail preparation explicitly.

The pinned compiler can provision those packages without compiling or running
the example:

```sh
/path/to/pinned/roc deps examples/furniture-typography/main.roc
```

From the repository root:

```sh
python3 development/benchmarks/pdf-comparison/trial.py prepare \
  .roc-pdf-tmp/pdf-comparison-01 --roc /path/to/pinned/roc

python3 development/benchmarks/pdf-comparison/trial.py run \
  .roc-pdf-tmp/pdf-comparison-01
```

Preparation creates an isolated Python environment, installs the pinned Python
dependencies, downloads the pinned Go modules, copies the shared font and
generates authoring constants. Its wall time and commands are recorded separately
in `manifest.json`. Installed toolchains are assumed; their installation is not
measured. Roc package acquisition is already complete at this point: preparation
time is not an all-language clean-install comparison.
`--existing-python --python /path/to/venv/bin/python` can reuse an
already provisioned environment; its actual dependency versions are recorded.

All trial commands run serially and Go module downloads are disabled during
measurement. Roc packages are already copied before any trial. Compiler caches
are private to each track. The package checkout is a local Roc dependency, so
package download time is excluded for every language. The source/import and
font hashes are retained in the manifest; changing production package sources
after preparation is an error.

For a smoke run with one build/source invocation and one binary execution per
language:

```sh
python3 development/benchmarks/pdf-comparison/trial.py run \
  .roc-pdf-tmp/pdf-comparison-01 --states first --runtime-samples 1
```

`--tracks script` / `--tracks compiled` and `--languages python roc go` select
subsets. Resume the same workspace with the same `--runtime-samples` to complete
remaining states; completed samples are skipped. A second concurrent run in one
workspace is rejected. Default per-command timeout is 30 minutes; timeout or
failure retains diagnostics and the sample is excluded from summaries. Prepare
a fresh workspace after a failed first build if its compiler cache was populated.

## Cache and source-edit scenarios

Each track/language has three sequential scenarios:

1. **First:** installed dependencies, empty track-specific compilation cache and
   no application bytecode. This is not a cold filesystem or cold machine.
2. **Unchanged:** repeat the exact source command with the normal caches and
   existing executable left in place. Reusing an existing correct executable is
   a valid result of a normal unchanged build.
3. **Edited:** change only the visible revision text from A to B in the generated
   source constants, retaining the previous executable. The changed text has a
   different length to avoid Python's timestamp-plus-size bytecode invalidation
   ambiguity. Keep compiler caches.

Each source command/build is measured once per scenario. Each successful build
is followed by five separately launched executions by default (including the
first execution, without discarded warmups). Their medians and raw samples are
reported. The cache-state label on a binary execution describes its preceding
build, not a claim that the executable or filesystem is cold. For repeatable
first-use distributions, prepare and run multiple fresh workspaces; do not
silently flush the user's global caches. A quiet-machine run later can use the
same commands and increase `--runtime-samples`.

## Timing and memory boundaries

`results.json` retains every sample, command, working directory, exit status,
timeout, raw stdout/stderr paths, wall time, user/system CPU time, OS `wait4`
maximum RSS, PDF/executable sizes and checks. `summary.md` reports medians and
pairs each build with its first subsequent execution. Build and run wall/CPU
times can be added. Their peak memory values cannot be added.

External wall time covers launch through process exit. It includes compilation
for `roc run`, imports for Python, all document work, write/close, metric output,
runtime shutdown and a small harness overhead. Monotonic application timers
separately report:

| Program | Available internal stages |
| --- | --- |
| Roc | font read/registration; authoring; `Pdf.prepare` (layout, validation and planning); emission; write/close |
| Python | imports; font read/registration; authoring; combined Platypus layout/generation; write/close |
| Go | font read/registration and PDF context setup; authoring/layout/painting; serialization; write/close |

Stage durations must sum exactly to the reported application duration. Individual
stages are not equivalent work across libraries: neither Platypus nor fpdf is
forced into a fictitious Roc compiler-stage split. In particular, fpdf's final
output step still does font subsetting and document finalization. Compare full
application totals before interpreting individual stages.

`outside_application_ns` is external wall time minus that sample's application
duration. For `roc run` it includes compilation, runtime startup and teardown;
for binaries it includes startup and teardown; for Python it also includes work
before the first script timestamp. It is **not** labelled pure startup or pure
compilation. A build command supplies the separate source-to-executable measure.
No compiler-internal parsing/optimization/linking times are invented.

RSS is the native `wait4.ru_maxrss` value (bytes on macOS, KiB converted to bytes
on Linux). It is not cumulative allocation, stage-specific live memory, or
simultaneous aggregate process-tree RSS. On Linux it is the largest process
high-water value among the command and its waited-for descendants; platform
accounting for build children varies. CPU times use the same OS child-resource
accounting and can include waited-for compiler descendants. Thus retain the OS
and scope when comparing builds, and do not claim that one compiler's entire
process tree fits in its reported RSS figure. The harness does not poll process
tables or add a profiler to short executions. Fonts are runtime files, so their
size is recorded separately from executable size; an executable alone is not
the complete deployment payload.

File output uses ordinary buffered write and close, **without fsync**. Bytes
have reached the OS, not necessarily durable storage. Generation returns a full
in-memory PDF before the timed write in all three programs. Validators run only
after the measured command exits.

## Correctness and evidence

Every generated PDF must have one page, the expected dimensions, all report
paragraphs/cells/revision/footer extractable, and every listed font embedded.
Reported size must equal written size. A source edit that fails to appear in
the PDF fails the trial. The harness removes stale output before invocation,
retains each validated original PDF and records its digest. Roc outputs for
identical report inputs must also agree byte-for-byte across modes and reruns.
Failed commands,
missing metrics, inconsistent stage sums, missing executables and malformed or
incomplete PDFs never enter the success summary.

This is separate from `scripts/test.py`'s exact Roc allocation/work baselines.
There is no allocator instrumentation in these basic-cli/Python/Go processes,
so the trial makes no allocation-count comparison. A production source change
still requires the repository's affected tests and architectural review.

Implementation references: [ReportLab flowables](https://docs.reportlab.com/reportlab/userguide/ch5_platypus/),
[ReportLab font registration](https://docs.reportlab.com/reportlab/userguide/ch3_fonts/),
[fpdf API](https://pkg.go.dev/github.com/go-pdf/fpdf@v0.9.0),
[fpdf v0.9.0 release](https://github.com/go-pdf/fpdf/releases/tag/v0.9.0).
The pinned fpdf repository is archived; it is a reproducible conventional Go
comparison, not a recommendation to adopt it for a new production application.

The Linux resource-accounting scope is described in
[getrusage(2)](https://man7.org/linux/man-pages/man2/getrusage.2.html).

The harness failure-path checks do not need PDF libraries:

```sh
python3 development/benchmarks/pdf-comparison/test_trial.py
```
