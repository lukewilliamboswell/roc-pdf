# Gate 2 tagged plan

`KernelTagged` joins already-validated semantic and scene plans. It walks page
paint ranges once, distinguishes typed page artifacts from fragment-owned
paint, and proves that every meaningful fragment owns exactly one scene group.

MCIDs are assigned in content-stream paint order. Counts and prefix sums create
one dense ParentTree entry range per content stream, while a fragment-indexed
table provides constant-time lookup when semantic `/K` order is materialized.
The two orders remain independent: ParentTree rows follow paint order and
structure kids follow the mixed semantic content spine.

The plan stores scalar IDs and ranges rather than duplicating scene commands,
fragment records, or payload bytes. Its work record counts paint edges,
fragment and artifact groups, occurrence-owner edges, ParentTree prefix/write
steps, and emitted normalized `/K` items. Optimized allocation evidence remains
part of the Gate 2 fixture before the gate is declared complete.
