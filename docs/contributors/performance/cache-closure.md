# text-layout bounded-cache closure record

This record aggregates the closure-level evidence for every cache kind the
roadmap declares for text-layout — font parsing/coverage, shaping, measurement,
and hyphenation — plus the source intern table those caches key on. Each
kind names its exact key, its bounded retention, and its registered hit/miss
and unique-versus-shared evidence. Nothing below claims a cross-document or
cross-process cache; every cache lives inside one build over immutable
inputs.

## Font parsing — `Font.ParseKey { resource }`

Parsing happens exactly once per registered resource:
`Font.Registry.register` runs `KernelFont.inspect` at registration and
retains the inspection beside the resource; `prepared_face` returns the
retained result and never reparses. `caller-font-retention.md` and
the two-face `shared-registry` mode of
`multiface-public-facade.md` prove one retained payload and one
inspection per face across two complete public outputs
(`copied_input_bytes = 0`), and the `unique-registries` controls prove the
contrasting shape: independent caller allocations double every dimension.
Retention is bounded by the registry's registered resources; no eviction is
needed because the registry is an immutable value the caller owns.

## Coverage — `Font.CoverageKey { face }`

Coverage spans are built once per face at registration into the registry's
flat `coverage_spans` store; selection performs read-only span visits.
`FontEvidence.multi_face_probe_scale` (x1000/x10000) measures
`coverage_span_visits = 4N` against the 8-span two-face total with exact
linearity and zero span writes after registration, and
`FacadeEvidence.ordered_facade` shows the facade performs those visits
once per unique source (15 visits at any repetition count).

## Selection plan — `Font.PlanKey { language, policy, script, source, source_range }`

The facade realizes the plan-cache identity through source interning: the
ordered path calls `Font.Registry.plan` exactly once per unique
`Semantics.TextSourceId` under the build's single policy and language, and
every occurrence of that source reuses the completed `FaceRange` split.
`ordered_facade` measures `planned_sources = 1` with constant selection work
across 1,000 and 10,000 occurrences of one source. Because one policy and
one language hold per build, the interned source identity subsumes the full
`PlanKey`; no cross-document plan cache is claimed, and the shape boundary
additionally rejects any occurrence of a source whose split differs from
the first (`SelectedRequestInvalid(SplitMismatch)`).

## Shaping — per-`(source, font)` glyph templates

`KernelShape.shape_simple_batch` walks each unique source once and reuses
the per-scalar glyph/width template for every request
(the `facade-batch-shaping-v1` scale rows registered in
`tests/spec.json` and reviewed in `facade-shaping.md`). The ordered
`shape_selected_batch` generalizes the same shape: one walk per unique
source resolves the planner-assigned dense font per cluster, so
`metric_reads` stays 3 for the three-cluster source at any repetition count
(`ordered_facade` x1000/x10000). Templates are flat buffers bounded by the
interned source count and freed with the batch.

## Measurement — `BatchKey { instance, size, source, width }`

The line-layout template cache keys measured line selections on the exact
instance, size, source, and width. The `facade-cached-line-layout-v1`
scale rows registered in `tests/spec.json` and reviewed in
`facade-line-layout.md` prove hit/miss behaviour for the single-face
path; the logical multi-face batch keeps `BatchKey` complete because one
policy per build makes each source's physical split deterministic, and
`ordered_facade`
measures 1 template with `cache_hits = N − 1` (999 and 9,999) across face
boundaries. The open-addressed table is bounded by `max_table_slots` and
`max_key_probes`, and both scales report the identical table capacity
behaviour.

## Source intern table

`KernelFacadeSources` hashes each authored input once, retains one `Str`
and one Unicode analysis per unique source, and resolves repeats through
the bounded probe table (the `facade-source-cache-v1` shared and
unique scale rows registered in `tests/spec.json` and reviewed in
`facade-source-cache.md`, with `adjacent_hits` for the common
repeated-input fast path). This is the identity every cache above keys on.

## Hyphenation — inapplicable

Automatic hyphenation is not claimed at text-layout: no language pattern set is
accepted, `soft-hyphen.md` records that only explicit caller-selected
opportunities exist, and the roadmap conditions any future hyphenation cache
on explicitly supported pattern assets. The hyphenation cache row is
therefore explicitly classified inapplicable rather than silently omitted
(closure-readiness audit row: bounded caches).
