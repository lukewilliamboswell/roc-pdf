# Property fuzz targets

These targets use the content-addressed `roc-fuzz` 0.2.1 release platform. They
are evidence-only applications: the production package remains pure Roc and does
not expose its private stage facts through the public facade. They are
software-quality tests for correctness, determinism, bounded error handling, and
invariant preservation; they do not make or test a security claim.

Build and smoke-test them from the repository root:

```sh
roc build --fuzz fuzz/font_inspector_mutation.roc
roc build --fuzz fuzz/font_inspector_repair.roc
roc build --fuzz fuzz/font_subset_roundtrip.roc
roc build --fuzz fuzz/jpeg_inspector_mutation.roc
roc build --fuzz fuzz/facade_output_equivalence.roc

./font_inspector_mutation run .roc-fuzz/font-inspector-seeds \
  --runs=1000 --max-input-size=524288 --timeout=5 --memory-limit=2048
./font_inspector_repair run .roc-fuzz/font-repair-corpus \
  --runs=1000 --max-input-size=512 --timeout=5 --memory-limit=2048
./font_subset_roundtrip run .roc-fuzz/corpus \
  --runs=1000 --max-input-size=512 --timeout=5 --memory-limit=2048
./jpeg_inspector_mutation run .roc-fuzz/jpeg-corpus \
  --runs=1000 --max-input-size=65536 --timeout=5 --memory-limit=2048
```

## Targets

`font_inspector_mutation` passes every fuzzer byte directly to the bounded
TrueType inspector. Typed inspection errors are ordinary outcomes. Successful
inspections must preserve independently checked table, loca, coverage, glyph,
component, and deterministic-work facts.

`font_inspector_repair` edits table payload bytes and then independently
restores the per-table and whole-font checksums. This exists because raw
mutation cannot reach past the inspector's two checksum gates: measured on the
`font_inspector_mutation` binary, a valid font reaches 330 edges, the same font
with one flipped byte reaches 45, and that same flip with checksums repaired
reaches 330 again. Without repair, the loca, glyf, cmap, OS/2, and name parsers
are effectively unreachable and only the directory layer is exercised. The
checksum arithmetic is reimplemented in the property rather than reused from
`KernelFont`, so the two implementations act as independent oracles.

`font_subset_roundtrip` generates bounded glyph choices and a retained-glyph
budget against five already-inspected text-layout fixtures. Typed planning failures
are ordinary outcomes. Successful plans must be deterministic, produce
byte-identical subsets on repetition, re-inspect successfully, preserve metrics
and cmap intent, and rewrite composite dependencies to subset glyphs. Glyph
choices and the retained budget are sized against the widest fixture, which has
1376 glyphs; a `U8` choice could select only its first 256 glyphs and a budget
capped at 96 rejected every large subset before it was built.

`jpeg_inspector_mutation` passes every fuzzer byte to the bounded JPEG
inspector. Accepted images must yield a sanitized stream: framed by SOI/EOI,
never longer than its source, carrying no application or comment segment, with
a resolved orientation and dimensions and work counters inside the declared
limits. This inspector has no checksum gate, so raw mutation reaches its
parsers directly.

`facade_output_equivalence` drives the public facade over generated typed
documents and checks the enduring output contracts: identical inputs produce
identical bytes, the buffered and chunked encoders agree byte for byte, the
chunk retention policy changes allocation only, and a rejected document is
rejected the same way every time. The LLVM compiler defect that previously
blocked this target was fixed upstream by Roc commit `47a14ba38c` and is
included in the pinned nightly.

## Corpora

Keep long-lived corpora under the ignored `.roc-fuzz/` directory. The raw-input
inspector corpus can be seeded directly with the valid font files in
`vendor/fonts/` and `tests/assets/`. The structured targets are
generator-encoded, so inspect hand-authored seeds with their `show` command
before retaining them.

Minimized reproductions are retained as `fuzz_seed` assets under
`tests/assets/` with provenance, and promoted to atomic regression tests beside
the code they exercise.
