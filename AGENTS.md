# AGENTS

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
- Treat performance as part of every feature slice's design and completion
  evidence. Review ownership, ARC/uniqueness, dense storage, traversal choice,
  caching, copying, seamless-slice retention, worst-case complexity, and error
  bounds before fixing a representation.
- Run affected tests through `./scripts/test.py`. Every focused case must keep
  its exact Roc allocation count and deterministic work evidence under the
  pinned build. Do not mechanically accept allocation-count or PDF snapshot
  changes; explain and review their architectural cause first.
- If a proposed change alters an enduring architectural decision or roadmap
  capability boundary, update the corresponding document in the same change.
  Do not use an implementation workaround to avoid resolving the conflict.
