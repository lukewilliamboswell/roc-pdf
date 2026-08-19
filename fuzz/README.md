# Property fuzz targets

These targets use the content-addressed `roc-fuzz` 0.2.1 release platform. They
are evidence-only applications: the production package remains pure Roc and does
not expose its private stage facts through the public facade. They are
software-quality tests for correctness, determinism, bounded error handling, and
invariant preservation; they do not make or test a security claim.

Build and run every target through the harness:

```sh
./scripts/fuzz.py
```

That builds each target with `roc build --fuzz` and runs a bounded campaign
against its seed corpus, failing on a crash, a timeout, or a memory-limit
breach. `--targets NAME` (repeatable) selects one and `--runs N` lengthens the
campaign:

```sh
./scripts/fuzz.py --targets jpeg_inspector_mutation --runs 200000
```

`./scripts/test.py` separately applies `roc fmt --check`, `roc check`, and
`roc test` to every source here, which runs the `expect`s each target retains.
Those expects are the regression floor: they pin concrete inputs and hold even
when no campaign runs.

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
never longer than its source, carrying a resolved orientation and dimensions and
work counters inside the declared limits, and retaining an application segment
only when it is the JFIF `APP0` or Adobe `APP14` that `KernelImage` deliberately
copies through for pixel density and colour transform. Every other application
segment, an Exif `APP1` above all, and every comment segment must be stripped.
Each input is inspected under both a calibrated-grey and an sRGB space, because
the inspector matches a frame's component count against its declared space and a
single-space store would send every three-component image down the reject path.

`facade_output_equivalence` drives the public facade over generated typed
documents and checks the enduring output contracts: identical inputs produce
identical bytes, the buffered and chunked encoders agree byte for byte, the
chunk retention policy changes allocation only, and a rejected document is
rejected the same way every time.

`facade_structure` checks that emitted bytes are a structurally valid PDF, which
the equivalence target cannot: comparing output to itself passes even if the
output is not a PDF at all. Its oracle re-derives structure from the bytes,
driving `startxref` to the cross-reference stream to the object offsets, and
verifies framing, `/Size == xref + 1`, `/Length == Size * 11`, the free-object
head, offsets landing on their own object headers, contiguous object tiling,
stream `/Length` adjacency, reference resolution, delimiter balance, and
canonical sorted dictionary keys. It imports no package module at all, so a
disagreement between the emitter and the oracle surfaces instead of cancelling
out.

`navigation_property` drives the authored navigation surface. The five
validation stages run in a fixed order and mask each other, so the free-form
property asserts only what survives that: a document seals to the same bytes or
the same typed error every time, and a rejection is transactional through both
entrypoints. A separate single-fault table injects exactly one navigation fault
into a valid base authoring and asserts the exact variant and location. Limits
come from `KernelNavigation.standard_limit_values` rather than being restated,
so the property cannot drift from the value the pipeline enforces.

`registry_property` drives the public `Font.Registry` boundary over repeated
registrations and explicit policies, which the font targets skip by calling
`KernelFont` directly. It checks dense identity across the parallel stores, the
implicit single-face policy each registration creates, exact tiling of the
coverage and script buffers, pure-append growth, round-trips through
`policy_faces`, the `index == len` boundaries, the unconditional zero-copy claim,
and face-range tiling with coalesced adjacent instances. Its plan oracle
reimplements selection rather than reusing the planner.

`theme_options` drives the theme and options surface, whose layout units are
unvalidated raw `I64` values feeding pagination directly. It maps each knob onto
a ladder of magnitudes — zero, negative, degenerate, ordinary, page-sized, and
±2^62 — across both page sizes and all three profiles, and requires determinism,
buffered and chunked agreement, and termination.

## Corpora

The JPEG corpus is tracked under `tests/assets/jpeg-fuzz-corpus/` with asset
provenance and is regenerated by `scripts/build_jpeg_fuzz_corpus.py`. The
font targets are seeded from the faces in `vendor/fonts/` and `tests/assets/`.
`scripts/fuzz.py` copies a seed corpus into the ignored
`.roc-pdf-tmp/fuzz-corpus/` before every run, because libFuzzer writes newly
interesting inputs back into the directory it is given and must never own
tracked files. Longer-lived accumulated corpora belong under the ignored
`.roc-fuzz/`.

A corpus is what decides whether a property is exercised at all. The JPEG
accept-path invariants were unevaluated for as long as no valid JPEG was
checked in: raw mutation never synthesised one, so every execution took the
reject path while the target reported success. A target whose success arm is a
typed rejection cannot tell you that its interesting half ever ran, so pair a
replayed seed with positive evidence that the accept path was reached.

The structured targets are generator-encoded, so inspect hand-authored seeds
with their `show` command before retaining them. That command is also how to
check a generator is not starving itself: fields are decoded in declaration
order out of an input whose length libFuzzer raises only slowly, so a field
placed behind a string- or list-carrying one receives no entropy and decodes to
one repeated exhausted byte. Declare the cheap selectors first and the content
last, and confirm with `show` that a retained corpus really varies the fields
the target exists to vary.

Minimized reproductions are retained as `fuzz_seed` assets under
`tests/assets/` with provenance, and promoted to atomic regression tests beside
the code they exercise.
