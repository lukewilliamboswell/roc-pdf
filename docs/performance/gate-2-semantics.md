# Gate 2 semantic normalization

`KernelSemantics` consumes the flat semantic stores and produces the exact
occurrence-to-fragment reverse index required by tagged lowering. It counts
fragments per occurrence, computes dense prefix starts, and fills one compact
fragment-ID buffer. It does not comparison-sort fragments or copy fragment
records.

The semantic graph is traversed from the one PDF 2.0 `Document` root with an
explicit worklist. Ownership marks prove that nodes, mixed content-spine
entries, occurrences, contextual artifacts, and attributes are each reached
exactly once. Semantic depth is budgeted without using the host call stack.

The deterministic work record separates namespace, occurrence, fragment,
counting, prefix, reverse-write, node, content, and attribute visits. The
optimized Gate 2 fixture will pin allocations and these counters at its Roc
measurement boundary before the capability is declared complete.
