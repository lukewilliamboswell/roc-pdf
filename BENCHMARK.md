# Running the PDF comparison benchmark

This guide runs the PDF generation comparison locally: the same one-page
report produced by roc-pdf, Python with ReportLab, and Go with fpdf. It covers
setup and commands only. The trial design, what each number measures and how
to interpret it are in
[`development/benchmarks/pdf-comparison/README.md`](development/benchmarks/pdf-comparison/README.md).

The harness supports Linux and macOS. Run every command from the repository
root.

## Prerequisites

- **Roc**: the exact nightly named in [`.roc-version`](.roc-version). Download
  the archive for your platform from
  `https://github.com/roc-lang/nightlies/releases/tag/<tag>`, or with
  `gh release download <tag> -R roc-lang/nightlies`. The harness refuses any
  other compiler version, so a `roc` built from source or another nightly will
  not work. Use an absolute path to the binary.
- **Go** 1.21 or later.
- **Python** 3.11 or later (the pinned Pillow requires it).
- **Poppler**: `pdfinfo`, `pdftotext` and `pdffonts` on `PATH` (the
  `poppler-utils` package on Debian/Ubuntu, `poppler` on Homebrew).

The benchmark always measures the package in this checkout's `package/`
directory.

```sh
export ROC=/absolute/path/to/roc   # the nightly from .roc-version
$ROC version                        # must print the tag in .roc-version
```

## 1. Provision Roc packages

Preparation copies the Roc packages it needs from Roc's package cache
(`~/.cache/roc/packages` by default) and fails if any are missing. Download
them once with `roc deps`, which fetches the basic-cli platform and the
package's dependencies without compiling anything:

```sh
$ROC deps examples/furniture-typography/main.roc
```

Use `prepare --roc-packages DIR` if your package cache is somewhere else.

## 2. Prepare a workspace

`prepare` creates a fresh workspace (the directory must not exist yet). It
creates a Python virtual environment with the pinned ReportLab dependencies,
downloads the pinned Go modules, copies the font and generates each program's
source.

```sh
python3 development/benchmarks/pdf-comparison/trial.py prepare \
  .roc-pdf-tmp/pdf-comparison-01 --roc "$ROC"
```

`--roc` defaults to `$ROC`, and `--go` defaults to `go` on `PATH`.

### Without `python3-venv`

Some Linux distributions ship Python without the `venv`/`ensurepip` module, so
the default preparation fails. Create a venv without pip, install the pinned
requirements into it with the host pip, then tell `prepare` to use it as is:

```sh
python3 -m venv --without-pip .roc-pdf-tmp/reportlab-venv
python3 -m pip --python .roc-pdf-tmp/reportlab-venv/bin/python install \
  -r development/benchmarks/pdf-comparison/requirements.txt

python3 development/benchmarks/pdf-comparison/trial.py prepare \
  .roc-pdf-tmp/pdf-comparison-01 --roc "$ROC" \
  --existing-python --python .roc-pdf-tmp/reportlab-venv/bin/python
```

`pip --python` needs pip 22.3 or later. The installed versions are recorded in
the workspace manifest.

## 3. Run

Quick smoke run (one build or script invocation and one execution per
language), in a separately prepared workspace:

```sh
python3 development/benchmarks/pdf-comparison/trial.py run \
  .roc-pdf-tmp/pdf-comparison-smoke --states first --runtime-samples 1
```

Full run (first, unchanged and edited cache states; five executions after each
build):

```sh
python3 development/benchmarks/pdf-comparison/trial.py run \
  .roc-pdf-tmp/pdf-comparison-01
```

A workspace keeps the `--runtime-samples` value it was first run with, so the
smoke and full runs need separate workspaces.
`--tracks script` or `--tracks compiled`, and `--languages` with any of
`python roc go`, select subsets.

## Results

Everything lands in the workspace:

- `summary.md`: median wall time, CPU time, peak RSS, PDF and executable sizes,
  and per-stage application timings.
- `results.json`: every sample, command, exit status and raw timing.
- `manifest.json`: machine, tool versions and paths, and source and font
  hashes.
- `logs/` and `artifacts/`: raw stdout/stderr and each validated PDF.

**Resume**: if a run is interrupted, rerun the same `run` command with the same
`--runtime-samples`. Completed samples are skipped. Only one run per workspace
can be active. If the first Roc build fails after populating its cache,
prepare a fresh workspace rather than resuming.

## Practical notes

- The Roc `roc build` (speed-optimized) step takes about 95 seconds and peaks
  around 15 GB RSS. It runs three times in a full run. Close other memory-heavy
  work, and do not run the repository test suite or a second trial alongside
  it.
- A full run takes several minutes; `roc run` also compiles on every
  invocation.
- Measurements are serial and offline: Go module downloads are disabled during
  `run`, and every compiler cache is private to the workspace. Your global
  caches are not touched.
- Results are diagnostic. Build and script rows have one sample each, so treat
  small differences there as noise. Recorded runs are kept in
  [`development/benchmarks/pdf-comparison/results/`](development/benchmarks/pdf-comparison/results/).
