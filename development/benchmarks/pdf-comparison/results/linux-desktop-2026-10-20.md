# PDF comparison trial: Linux desktop, 2026-10-20

Contributor evidence for the [PDF comparison trial](../README.md). Two full
runs (all three cache states, five runtime samples per build) on the same
machine, one before and one after the nightly 10-18 upgrade and allocation
sweep. Diagnostic only; there are no numeric acceptance targets.

## Runs

| | Run 01 (2026-10-19) | Run 02 (2026-10-20) |
| --- | --- | --- |
| Roc compiler | `nightly-2026-10-14-38a3029` | `nightly-2026-10-18-1df370f` |
| roc-pdf package | base of `0db12cc` (harness commit on the 10-14 main) | `23432ec` (allocation sweep plus the Balanced default: DEFLATE level 6, previously 10) |
| roc-deflate | 0.4.0-rc2 | 0.4.0-rc4 |
| unicode | 4.2.0 | 4.3.0 |
| basic-cli | 0.26.0-rc2 | 0.26.0-rc2 |
| Harness sources | identical (same `sources_sha256`) | identical |

Shared environment, from both manifests:

- AMD Ryzen 7 9700X (8 cores, 16 logical CPUs), 32.7 GB RAM.
- Linux 7.0.0-38-generic x86_64, glibc 2.39.
- Go `go1.26.5 linux/amd64`, fpdf v0.9.0.
- Python 3.12.3, ReportLab 4.4.10, Pillow 13.0.0, charset-normalizer 3.5.2
  (pre-provisioned venv passed with `--existing-python`).
- Workload and font hashes identical (`workload_sha256 ad3ffe86…`,
  `font_sha256 ee0c414a…`).

Raw `summary.md`, `results.json` and `manifest.json` were produced in local
workspaces `pdf-comparison-linux-desktop-01` and `-02`; they are not committed.
Retained failed attempts: 0 in both runs.

## Sample counts

Build and script (`roc run`, `python report.py`) rows are **n=1** per cache
state. Compiled-binary runtime rows are **n=5** medians. Treat single-sample
differences of a few percent as noise.

## What changed between runs

Run 02 changes both the compiler and the package at once. Any change in
`roc build` time or `roc run` wall time therefore mixes compiler and package
effects and cannot be attributed to either alone. The compiled-runtime stage
timings come from the application's own monotonic timers inside the built
executable, so they isolate the package (as compiled by each nightly).

### Compiled runtime (n=5 medians, first cache state, ms)

| Stage | Roc run 01 | Roc run 02 | Go run 02 |
| --- | ---: | ---: | ---: |
| font setup | 0.957 | 0.809 | 0.788 |
| prepare (layout, validation, planning) | 1.514 | 1.350 | — |
| emit | 2.869 | 0.672 | 1.280 |
| write | 0.029 | 0.031 | 0.025 |
| application total | 5.726 | 2.835 | 2.107 |
| external wall | 6.00 | 3.04 | 2.76 |
| PDF bytes | 14950 | 15212 | 12790 |
| executable bytes | 12000688 | 11304384 | 4428331 |

Emission fell from 2.87 ms to 0.67 ms and the application total from 5.73 ms
to 2.84 ms. External wall time is now about 3.0 ms against Go's about 2.75 ms
(Go is 2.74 ms in run 01 and 2.75 to 2.90 ms across run 02's states). The
unchanged and edited states agree within about 0.3 ms. Go's stages are not
equivalent work (fpdf's emit includes subsetting and finalization); compare
totals. The Roc PDF grew by 262 bytes because Balanced uses DEFLATE level 6
rather than the previous level 10. The Roc output keeps its Archive profile
(tagged PDF 2.0 with the PDF/A-4 claim); ReportLab and fpdf outputs make no
equivalent claim.

Peak RSS of the Roc executable: 36.0 MiB (run 01), 35.3 MiB (run 02); Go 24.7 MiB.

### Source to PDF (`roc run`, dev backend, n=1, ms)

| Cache state | Run 01 wall | Run 02 wall | Run 01 application | Run 02 application |
| --- | ---: | ---: | ---: | ---: |
| first | 10469 | 15969 | 83.2 | 45.6 |
| unchanged | 7794 | 8218 | 87.8 | 45.7 |
| edited | 7784 | 8345 | 79.2 | 47.7 |

The in-process application time roughly halved (emit 52 → 10 ms). Wall time is
dominated by compilation and rose, most visibly on the first, empty-cache
invocation; this mixes the compiler change with the package change. Python
ReportLab ran in 67 to 144 ms (run 02; its 144 ms first state was mostly
imports, 123 ms, against 67 ms in run 01).

### Source to executable (`roc build`, n=1)

| Cache state | Run 01 wall s | Run 02 wall s | Run 01 peak RSS GiB | Run 02 peak RSS GiB |
| --- | ---: | ---: | ---: | ---: |
| first | 78.3 | 94.7 | 11.4 | 13.3 |
| unchanged | 77.4 | 97.5 | 13.2 | 14.8 |
| edited | 76.7 | 97.2 | 13.2 | 14.6 |

Speed-optimized builds became about 20 s slower and use about 1.5 to 2 GiB more
peak RSS; again compiler and package effects are mixed. Go builds took 2.0 s
first, 19 ms unchanged and 93 to 99 ms edited in both runs.
