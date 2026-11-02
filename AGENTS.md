# AGENTS

- Keep `docs/` and the root README user-facing: explain supported behavior,
  runnable usage, limits, diagnostics, and migration steps. Introduce features
  by the task they solve, not by issue numbers, delivery gates, or compiler work.
- Put contributor workflows, design reviews, implementation history, performance
  baselines, validator reports, and integration/closure records in `development/`.
  Keep capability planning in `feature-roadmap.md` and enduring decisions in
  `architecture.md`. Preserve evidence and repair links when moving records;
  do not remove required evidence to simplify user documentation.
- Public release notes describe user-visible changes and migration impact.
  Keep branch names, agent coordination, commit-by-commit narratives, and gate
  checklists out of user guides and release notes. Technical details belong in
  a user guide only when they help someone use the supported API.
- Keep the README and evergreen guides release-neutral. Avoid repeated current
  or upcoming version labels and install pins; link release notes for exact
  package/compiler pins and release-specific migration. Derive publication
  version labels from build metadata.
- Read `architecture.md` and `feature-roadmap.md` before making changes in this
  repository.
- Treat `architecture.md` as the enduring source of truth for package scope,
  public boundaries, compiler stages, typed invariants, ownership, storage,
  accessibility, conformance, deterministic emission, and performance design.
- Treat `feature-roadmap.md` as the capability and evidence boundary. Implement
  features in dependency-gate order, and do not claim a capability until its
  gate evidence is satisfied.
- Keep this a pure Roc, generation-only PDF 2.0 package. Do not introduce PDF
  reading, legacy-format constraints, native production dependencies, silent
  fallback behavior, conformance downgrade, font substitution, outlining, or
  rasterization as recovery.
- Preserve the architecture's explicit stage contracts. Later stages must
  consume facts produced by earlier stages rather than infer semantics,
  ownership, reading order, resource identity, or conformance from incidental
  data.
- Use current Roc syntax and keep the high-level `Pdf` facade as the primary
  user experience. Advanced integration must not leak PDF object internals into
  the common path.
- Correctness comes first. Performance evidence exists to catch super-linear
  or exponential blow-ups: exact Roc allocation counts and deterministic work
  counters remain mandatory, and scalable features carry small/large scale
  pairs, but there are no numeric product performance targets or required
  timing/memory jobs. Human reader and assistive-technology review is optional
  and never blocks gate closure; machine-verifiable conformance does not relax.
- Treat performance as part of every feature slice's design and completion
  evidence. Review ownership, ARC/uniqueness, dense storage, traversal choice,
  caching, copying, seamless-slice retention, worst-case complexity, and error
  bounds before fixing a representation.
- Run affected tests through `./scripts/test.py`. Every focused case must keep
  its exact Roc allocation count and deterministic work evidence under the
  pinned build, and must stay within 10% of its recorded allocated bytes. Do
  not mechanically accept allocation-count, allocated-bytes, or PDF snapshot
  changes; explain and review their architectural cause first.
- Keep accumulators uniquely owned. Do not thread a growing list or builder
  through a `Try` that the caller then updates, keep it live on an error path
  (`Err(e) => { $error = … }` loop state), return it beside another list, or
  grow it with `List.reserve`/`List.concat`/`Str.concat` (all size exactly).
  After a call that consumes an accumulator `var`, every path must reassign
  it or leave the loop with `return`: a `Done => { $done = True }` arm keeps
  the old value live across the call. Do not reassign an accumulator `var`
  inside the branches of an `if` or `match` that produces a value (including
  a function's tail expression), and do not read a record or projection
  after the call that grows one of its lists. See
  `development/performance/lowering-uniqueness.md` and
  `development/performance/emission-linearity.md`.
- If a proposed change alters an enduring architectural decision or roadmap
  capability boundary, update the corresponding document in the same change.
  Do not use an implementation workaround to avoid resolving the conflict.
