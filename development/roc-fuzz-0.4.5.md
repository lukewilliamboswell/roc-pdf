# roc-fuzz compatibility review and upgrade

## Decision and immutable inputs

Move the ten evidence-only application headers from roc-fuzz 0.4.3 to
[0.4.5](https://github.com/lukewilliamboswell/roc-fuzz/releases/tag/0.4.5).
The platform API and corpus interpretation are unchanged. The production package,
`.roc-version`, dev-backend allocation baselines and deterministic work contracts
do not change with this tooling upgrade.

| Input | Identity |
| --- | --- |
| Release source | `375234847fafcace4189cac207f3ba00c66d53b5` |
| Bundle | `D4YgxZeGd6MqK1wA17xERBocQHnVff3c8UNmDcvGeF7J.tar.zst` |
| Bundle bytes | 1,949,365 |
| Bundle SHA-256 | `ce7066483b56d837116f8c37180331bb34833c4fb6477a45e0e78625a69fed85` |
| Tested package compiler | `nightly-2026-10-28-bad769b` |

The downloaded release bytes were hashed independently and matched the GitHub
release asset digest. The bundle includes native inputs for `arm64mac` and
`x64musl`; no native production dependency is introduced.

[0.4.4](https://github.com/lukewilliamboswell/roc-fuzz/releases/tag/0.4.4)
introduced additive allocator counters, regenerated host ABI bindings and saved
out-of-memory failures. Version 0.4.5 reuses that platform bundle and updates the
published examples. The existing 0.4.3 PR smoke run also passed under the package
pin, so this review does not claim a reproduced compatibility blocker.

## Probe evidence

An isolated application built against the verified extracted platform with the
pinned compiler and `roc build --fuzz --no-cache`: zero errors and warnings.
It allocates an exactly preallocated byte list, appends each input byte and one
trailing byte, and measures the operation using both the old `measure_allocs!`
API and the additive `measure_alloc_counts!` API. Both returned the same value
and one allocation. Both returned lists remain live through the observations.

For the four-byte input `seed`, `TARGET measure INPUT` emitted:

```json
{"format":"roc-fuzz-allocs/1","label":"probe-region","allocs":1,"reallocs":0,"deallocs":0,"requested_bytes":13}
```

`TARGET replay INPUT` passed. A bounded eight-run exploration also passed and
grew coverage using the existing option spellings:

```sh
TARGET run CORPUS --runs=8 --time=1 --max-input-size=64 \
  --timeout=1 --memory-limit=256 --artifact-dir=ARTIFACTS --seed=1
```

The first probe incorrectly assumed that a previously returned, now-unused list
would not be released inside the next process-counter observation. Its assertion
failed, and the runner saved the exact crashing input with replay instructions.
Keeping both results live made the intended measurement boundary explicit and
passed. This was a probe ownership assumption, not a platform failure. The normal
run accepted the timeout and RSS controls; this small probe did not deliberately
exhaust memory or test a nonterminating property.

## Repository validation

The runner retains the existing nine-target inventory, copied seed corpora,
64-run/one-second smoke bounds, 2,000-run campaign default, per-input timeout,
memory bound, process deadline and failure-artifact contract. The profiling aid
keeps its old measurement API and remains an iteration aid, not gate evidence.

The subset round-trip property additionally checks equality of all validated
source/subset style facts. A successful subset and a changed-angle negative
witness exercise that oracle without changing generators or corpus interpretation.

Full native smoke, the profiling aid and Linux CI verification are pending.
Do not interpret the isolated probe as validation of the complete PDF target set.

## Separate follow-up: 0.5.0 and font coverage

Latest release [0.5.0](https://github.com/lukewilliamboswell/roc-fuzz/releases/tag/0.5.0)
is a deliberate migration, not a URL-only update. It requires declared examples,
encoder/parser derivations for nominal inputs, named measurements instead of
the current profiling API, and supervised report/baseline handling. Decoded inputs
also need explicit domain validation where current generator bounds supply the
only limit. Existing retained inputs and storage-sensitive witnesses must keep
their recorded interpretation; verification must never accept baselines implicitly.

The current raw-font target omits `package/fonts/` and limits input and inspection
to 512 KiB. The rc4 Merriweather files exceed 1 MiB, which also exceeds 0.5.0's
friendly raw-input limit. A separately scoped default-font repair/subset target
can exercise those full static files using compact edit/glyph selections. Keep
the existing five-font generator mapping intact rather than silently remapping
old corpus inputs. The independent default-font fixtures already cover genuine
source/subset style metadata; this follow-up adds fuzz reach, not a new claim of
font or PDF conformance.
