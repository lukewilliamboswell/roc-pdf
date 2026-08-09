# Gate 3 logical-to-physical facade run boundary

This representation-only slice replaces the facade's incidental assumption
that one logical authoring occurrence equals one `Text.RunId` with the typed
`KernelFacadeShape.LogicalRun` record. Its `physical` range is allocated by
shaping and is retained with each block through line planning, pagination, and
final text materialization. A later multi-face shaping slice can therefore
select ordered physical runs for one grapheme sequence without any later stage
recovering font ownership from glyph IDs, output order, or an adjacent run ID.

The current built-in facade remains intentionally single-physical-run: the
line and final-text stages validate `physical.length() == 1` explicitly. A
wider range is an atomic `InvalidRun` error before line materialization or PDF
planning; it is not truncated, coalesced, or silently assigned to the first
face. `KernelFacadeLines` includes the focused two-run negative for the stable
block/run diagnostic.

On the pinned local dev backend (`release-fast-64c9d73d`, x64musl), the
existing public staged-output success remains 1,422 allocations with work
`[1,1,1,1,1,1,1,2,32,24,8692,32,2,1048,20,12397]`; the public `Pdf` facade
success remains 1,423 allocations with work `[12397]`; and the existing
line-run-limit atomic negative remains 98 allocations with work `[1,667]`.
The PDF snapshot and deterministic counters are unchanged. The record is a
representation/ownership review only: full multi-face line layout and public
output remain a separate Gate 3 slice, and this does not claim Gate 3 closure.
