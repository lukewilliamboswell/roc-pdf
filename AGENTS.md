# AGENTS

- Keep the root README and user chapters focused on using the package.
  Explain supported behavior, runnable usage, limits and migration by task.
  Put contributor workflows in their own manual chapters and supporting
  implementation contracts under `docs/contributors/`.
  Document supported behavior in its manual chapter and enduring decisions in
  `docs/architecture.adoc`. Preserve executable baselines, provenance, licenses
  and fixture checks. Keep completed integration records in Git.
- Keep generated run reports, before/after dumps, review screenshots, and one-off
  review JSON/XML in ignored `.roc-pdf-tmp/` directories or CI artifacts.
  Commit executable baselines, provenance, and lockfiles. Keep an evidence
  summary or link to a historical run only when it helps a current task or
  explains an active constraint. Leave completed investigations and one-off
  benchmark results in Git history or ignored output.
- Public release notes describe user-visible changes and migration impact.
  Keep branch names, agent coordination, commit-by-commit narratives, and gate
  checklists out of user guides and release notes. Technical details belong in
  a user guide only when they help someone use the supported API.
- Keep the README and evergreen guides release-neutral. Avoid repeated current
  or upcoming version labels and install pins; link release notes for exact
  package/compiler pins and release-specific migration. Derive publication
  version labels from build metadata.
- Read `docs/architecture.adoc` and the affected manual chapters before making
  changes in this repository.
- Treat `docs/architecture.adoc` as the enduring source of truth for package scope,
  public boundaries, compiler stages, typed invariants, ownership, storage,
  accessibility, conformance, deterministic emission, and performance design.
- Describe supported behavior and its limits in the owning authoring chapter.
  Use the evidence requirements in `docs/testing.adoc` when changing a
  capability.
- Keep this a pure Roc, generation-only PDF 2.0 package. Do not introduce PDF
  reading, legacy-format constraints, native production dependencies, silent
  fallback behavior, conformance downgrade, font substitution, outlining, or
  rasterization as recovery.
- Support PDF standards on a best-effort basis. Cite applicable editions,
  clauses and errata beside implementations and focused tests. Keep licensed
  standards and audit material in ignored local directories. Prefer executable
  invariants and a few authored seeds for generated cases. Use project-owned
  fixtures and checks in CI and keep independent PDF validators and readers
  opt-in local tools. Describe the emitted declarations and the checks actually
  exercised. Discuss separately scoped and funded certification, including
  ownership, in GitHub Issues.
- Preserve the architecture's explicit stage contracts. Later stages must
  consume facts produced by earlier stages rather than infer semantics,
  ownership, reading order, resource identity, or conformance from incidental
  data.
- Use current Roc syntax and keep the high-level `Pdf` facade as the primary
  user experience. Advanced integration must not leak PDF object internals into
  the common path.
- Use the pinned Weaver release to parse user-facing arguments in Roc
  applications.
- Give every operational work, memory, and size limit on a public path a
  sensible finite default and a caller override. Prefer the operation's
  existing public configuration record, with omitted fields keeping their
  defaults. Carry the selected limits through all affected stages. Document
  what each limit bounds and test exhaustion and success with an override.
  Enforce format requirements, representation limits, and correctness
  invariants for every configuration.
- Correctness comes first. Performance evidence exists to catch super-linear
  or exponential blow-ups. Measure Roc allocations and deterministic work,
  enforce allocation ceilings, and give scalable features small/large scale
  pairs, but there are no numeric product performance targets or required
  timing/memory jobs. Human reader and assistive-technology review is optional.
- Treat performance as part of every feature slice's design and completion
  evidence. Review ownership, ARC/uniqueness, dense storage, traversal choice,
  caching, copying, seamless-slice retention, worst-case complexity, and error
  bounds before fixing a representation.
- Run affected tests through `./scripts/test.py`. Enforce the native allocation
  ceiling and exact deterministic work under the pinned build. Keep allocated
  bytes at or below 110% of the recorded reference. Use repeatable improvements
  to tighten ceilings. Explain the architectural cause before raising a
  ceiling or changing work counters or PDF snapshots.
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
  `docs/contributors/performance/lowering-uniqueness.adoc` and
  `docs/contributors/performance/emission-linearity.adoc`.
- If a proposed change alters an enduring architectural decision or supported
  capability boundary, update the owning manual chapter in the same change.
  Do not use an implementation workaround to avoid resolving the conflict.

## Documentation

Documentation serves current users and contributors. Every paragraph must help a
current task; delete obsolete or duplicated material. Keep implementation history
in Git, unfinished work in issues, and release changes in release records. Preserve
required public anchors without explaining their history. Follow the
[shared documentation guidance](https://lukewilliamboswell.github.io/roc-automation/documentation.html#keep-documentation-current).

Author each manual chapter once as a top-level `docs/*.adoc` source and include
it once in `docs/index.adoc`. Keep release records in `docs/releases/`, include
upcoming changes in the development manual, and link to published versions.
The pinned shared `roc-docs` renderer builds HTML, PDF, and Markdown from those
sources. Keep generated formats in ignored build output and give durable
published links explicit anchors. Keep repository entry points short and link
to the relevant chapter.
Link new gallery previews from their example directories to keep the manual's
embedded figure payload within the renderer's budget.
