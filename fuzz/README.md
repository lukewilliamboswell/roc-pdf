# Gate 3 property targets

These two targets use the content-addressed `roc-fuzz` 0.2.1 release platform.
They are evidence-only applications: the production package remains pure Roc
and does not expose its private font-stage facts through the public facade.
They are software-quality tests for correctness, determinism, bounded error
handling, and invariant preservation; they do not make or test a security
claim.

Build and smoke-test them from the repository root:

```sh
roc build --fuzz fuzz/font_inspector_mutation.roc
roc build --fuzz fuzz/font_subset_roundtrip.roc
./font_inspector_mutation run fuzz/corpus/font_inspector_mutation \
  --runs=1000 --max-input-size=524288 --timeout=5 --memory-limit=2048
./font_subset_roundtrip run fuzz/corpus/font_subset_roundtrip \
  --runs=1000 --max-input-size=128 --timeout=5 --memory-limit=2048
```

`font_inspector_mutation` passes every fuzzer byte directly to the bounded
TrueType inspector. Typed inspection errors are ordinary outcomes. Successful
inspections must preserve independently checked table, loca, coverage, glyph,
component, and deterministic-work facts.

`font_subset_roundtrip` generates bounded glyph choices and a retained-glyph
budget against five already-inspected Gate 3 fixtures. Typed planning failures
are ordinary outcomes. Successful plans must be deterministic, produce
byte-identical subsets on repetition, re-inspect successfully, preserve
metrics and cmap intent, and rewrite composite dependencies to subset glyphs.

Keep long-lived corpora below `fuzz/corpus/`. The raw-input inspector corpus can
be seeded directly with the valid font files in `vendor/fonts/` and
`tests/assets/`; the structured subset target's corpus is generator-encoded, so
inspect hand-authored seeds with its `show` command before retaining them.
