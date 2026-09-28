# S6b: uniqueness in lowering, and an allocated-bytes guard

This slice removes the super-linear time that the tables slice
([tables.md](tables.md), "Quadratic object-store time") found in object
lowering. It changes no output byte and no work counter. It adds one piece of
harness evidence, a per-case ceiling on allocated bytes, and builds fixture
executables without the compiler cache.

The tables slice suspected one cause: `KernelObject`'s builder functions
appending to a list reached through the still-live builder record. That
pattern turned out to be harmless on its own. The copying had seven separate
causes, listed below, and a fixture's code also depended on which other
fixtures the harness had built before it.

## How it was measured

- **Allocated bytes.** The test hosts now sum the size of every `roc_alloc`
  and the new size of every `roc_realloc` (`allocated_bytes`). A list copied
  on every append adds one allocation event per append, so the allocation
  count grows linearly and looked plausible. The bytes grow with the square
  of the list and made each copy visible. This metric became the guard
  described below.
- **Stage cutoffs.** A throw-away probe app returned early after each
  pipeline stage (semantics, shaping, lines, pages, text, fragments, scenes,
  and each sub-step of output and structure lowering), so the bytes of each
  stage could be read at 100, 200, and 400 invoice rows.
- **Allocation stacks.** A debug build of the host walked frame pointers on
  every allocation of 4 KiB or more and printed the return addresses. Built
  with `roc build --debug`, the DWARF subprogram entries (procedure hash,
  declaring module, line) named the Roc function that asked for the copy.
  Sizes told which list was copied: `values` (24-byte elements), `depths`
  (8 bytes), and so on.
- **LIR.** `ROC_LIR_DUMP=<name>` printed the pinned compiler's final LIR,
  with reference-count operations, for single procedures.
- **Minimal programs** with no roc-pdf dependency checked each pattern alone,
  in a build from an empty cache and in a second build of the same source
  into the same cache.

Instruction counts come from `perf stat -e instructions:u`. The build is the
pinned `nightly-2026-09-26-d6267b4`, `--opt=dev`, `x64musl`.

## Causes

Causes 1 to 5 were each confirmed by a fix that removed their bytes in the
probe, cause 6 by build-order experiments, and cause 7 was ruled out.

1. **Error-path loop state.** Most lowering loops carried
   `var $error = NoError` (or `$failure`) and wrote
   `Err(e) => { $error = Invalid(e) }` in the arm of the call that consumed
   the builder. On that path the loop exits and the old `$builder` is still
   read afterwards, so it is live across the call. The caller keeps a
   reference and the callee copies every list it appends to, once per
   iteration: once per structure element, page-tree node, resource name,
   parent-tree row, page, content command, graphics state, and form. This is
   correct behaviour for the code as written. Early returns (`?` or
   `return Err(e)`) remove the live reference.
2. **A builder returned beside another list.** Helpers returned
   `Try({ builder, values })`, and the caller passed both fields on
   (`KernelObject.add_array(r.builder, r.values)`). After `?`, the builder's
   lists stayed shared, so the next append copied the object store once per
   element. This is upstream report A. Such helpers now build their array
   themselves and return `{ builder, id }`, or return only the builder while
   the caller derives the value ids (they are consecutive) from
   `KernelObject.counts` taken before the call.
3. **A list updated after `?`.** `place_table` wrote a cell's attributes into
   `placed.nodes` after `placed = place_rich(…)?`, which copied the
   whole-document node list (204 KB at 100 rows) once per cell. That is the
   same defect as 2. `place_rich` now writes the cell's attributes and element
   identifier with the node.
4. **Exact reserves.** `List.reserve` sizes the allocation exactly, and so
   does `List.concat`. `append_all` in `KernelObject`, `KernelEmit`, and
   `KernelDeflate`, and `Pdf.append_pdf_bytes` reserved `source.len()` before
   appending, so every `add_array`, `add_dictionary`, and emitted segment
   reallocated its whole target. `KernelContent.reserve_exact` asked for a
   spare at least as large as the stream on every token, which reallocated
   the stream to twice its size per number written. `KernelPdfText.reserve`
   reserved exactly per token. They now only check the limit; `append`
   grows geometrically. Upstream report C covers `List.concat`.
5. **Builder copied into a loop-local `var`.** The name and number tree
   emitters assigned `var $inner = $builder` inside a `match` arm while the
   loop's `$builder` stayed live. The child arrays now come from a helper
   that takes the builder as a parameter.
6. **Cross-program procedure reuse.** Built after any other program that
   exercises the object store (`tests/structural_kernel`, or a
   one-line app calling `KernelStructure.build_blank`), the tables fixture
   copied lists that it updates in place when built alone, whatever the
   source pattern. The pinned compiler reuses cached procedures across
   programs, and the harness built all fixtures into one cache. With most of
   the fixes above applied, the x500 invoice still allocated 67.3 GB in
   harness order (67.9 GB before any of them) and 2.6 GB alone. Report B
   reproduces the cache dependence in a single file. The harness now builds
   fixtures with `roc build --no-cache`, which reproduced the standalone
   build exactly and took 50 s for all 51 fixtures (47 s with the shared
   cache).
7. **Nested record update of a still-live builder** (the suspected cause).
   In a single program this did not copy. The `KernelObject` rewrite (every
   operation takes its builder apart once and builds its result record once)
   is kept because it is simpler and removed intermediate builders, but it
   was not the cause.

## Fix pattern

The rules now in `AGENTS.md`:

- Thread an accumulator (list, builder, or store) only through calls that
  consume it. Never keep it live on another path, as in
  `Err(e) => { $error = … }` loop state or `Err(_) => $acc` fallbacks. Use
  `?` or `return Err(e)`.
- Do not return an accumulator beside another refcounted value in a `Try`
  that the caller then splits. Let the helper finish the aggregate
  (`add_*_array` returning `{ builder, id }`), or return the accumulator
  alone and derive dense ids from counts taken before the call.
- Do not update a list the caller received through `?`. Move the update into
  the producing call.
- Grow accumulators with `append` only. `List.reserve` and `List.concat` are
  for one-shot sizing when the final size is known.

## Scaling

Invoice xN (`tests/tables`) and keep groups xN (`tests/layout_policies`),
fixtures built with `--no-cache` from the tree before and after this slice.
Instructions and allocated bytes are deterministic.

| Case | Instructions before | Instructions after | Allocated bytes before | Allocated bytes after | Allocations before → after |
| --- | ---: | ---: | ---: | ---: | --- |
| invoice x50 | 3.94 G | 3.68 G | 1.03 GB | 0.163 GB | 100,900 → 77,955 |
| invoice x100 | 6.53 G | 5.80 G | 2.59 GB | 0.318 GB | 180,104 → 136,823 |
| invoice x200 | 12.32 G | 10.02 G | 7.42 GB | 0.645 GB | 338,355 → 254,328 |
| invoice x400 | 26.44 G | 18.49 G | 23.83 GB | 1.33 GB | 656,466 → 490,491 |
| invoice x500 | 34.76 G | 22.73 G | 35.35 GB | 1.68 GB | 815,362 → 608,498 |
| groups x50 | 2.76 G | 2.68 G | 0.343 GB | 0.058 GB | 65,879 → 52,145 |
| groups x100 | 4.76 G | 4.53 G | 0.978 GB | 0.116 GB | 128,672 → 101,233 |
| groups x250 | 11.30 G | 10.19 G | 4.74 GB | 0.307 GB | 321,088 → 252,448 |
| groups x500 | 23.58 G | 19.62 G | 17.15 GB | 0.648 GB | 641,905 → 504,449 |

Per doubling of the invoice (100 → 200 → 400), instructions grew 1.89× and
2.15× before and 1.73× and 1.85× after; bytes 2.86× and 3.21× before and
2.03× and 2.06× after. From 400 to 500 rows (1.25×), bytes grew 1.48× before
and 1.26× after. Groups x250 → x500 grew bytes 3.62× before and 2.11× after,
and instructions 2.09× before and 1.93× after. Both families now scale
linearly.

Wall time for x500, three runs each on an idle machine: the invoice took
11.5–11.6 s in harness order before this slice, 6.7–7.0 s built alone before,
and 2.76–2.79 s after. Groups took 5.9–6.0 s, 4.2–4.4 s, and 2.31–2.38 s.

In harness order (all fixtures in one cache), which is what the tables slice
measured, the same tree before this slice took 4.25, 7.52, 15.8, 39.7, and
55.2 G instructions for invoice 50, 100, 200, 400, and 500 rows (110,221 to
897,797 allocations, and 1.47 GB and 67.9 GB allocated at x50 and x500).
Groups x50 and x500 took 2.83 and 27.5 G. The tables slice's 14.1, 37.2, and
111 G were measured in yet another cache state. With `--no-cache` the harness now measures the standalone
figures above.

Where the bytes went, per invoice stage at 100 / 200 / 400 rows, before this
slice's fixes (the `KernelObject` rewrite alone changed nothing):

| Stage | Before (MB) | Cause |
| --- | --- | --- |
| Semantic planning | 57.7 / 213 / 821 | 3 (`place_table` node writes) |
| Content lowering | 1,325 / 2,683 | 4 (reallocation per token); 1 (per command group); a per-token copy remains, see open issues |
| Tagged objects: structure elements | 1,000 / 3,880 | 1, 2 (`add_k_items`), 4 (`append_all`) |
| Tagged objects: parent tree | 7.6 / 28 | 1, 2 |
| Page objects | 15 / 51 / 186 | 1, 2 |
| IDTree | 2.4 / 6.4 | 2, 5 |

After the fixes, the structure elements take 2.5, 4.5, and 7.9 MB, the
parent tree 0.26 and 0.75 MB, page objects 2.6, 5.3, and 10.5 MB, the IDTree
0.64, 1.8, and 3.6 MB, and semantic planning 2.7, 5.4, and 13.7 MB. The whole
invoice at 100 rows now allocates 318 MB, against 1,325 MB for content
lowering alone before.

## The allocated-bytes guard

Metrics protocol 2 adds `allocated_bytes` to the host report, and every case
records it per target beside `allocations`. `scripts/test.py` fails a case
whose allocated bytes exceed the recorded value by more than 10%
(`ALLOCATED_BYTES_CEILING_TENTHS = 11`). Decreases pass. `--baseline-report`
lists every exact difference, so a reviewed rebaseline can lower ceilings.
The self-test checks that one byte over the ceiling fails, that the ceiling
itself and half the recorded value pass, and that the check is skipped when
allocation baselines are not checked.

Why this design:

- **Deterministic.** With `--no-cache` builds, the bytes are a function of
  source and host allocator requests, not of timing or the system allocator.
  Every repeated measurement in this slice reproduced exactly.
- **Catches the failure that exact counts missed.** A per-append copy is
  quadratic in bytes and linear in events.
- **A ceiling, not equality.** Exact byte equality would add a second exact
  number to review on every representation change, and small drift carries
  no risk. A 10% ceiling on every case passes routine changes and fails a
  blow-up at any scale where it matters.
- **Every case, not only scale pairs.** A dense page is quadratic in its own
  size. The guard found such cases outside any scale pair (see open issues).
- **Checked with allocation baselines.** The ceiling is enforced wherever
  exact allocation counts are (`--allocation-baselines`, which Linux CI runs,
  `--compare-baselines`, and `--update-snapshots`). The recorded values are
  x64musl measurements copied to arm64mac, as the allocation counts are.

## Harness builds without the cache

`build_case_sources` passes `--no-cache`. Allocation evidence no longer
depends on which fixtures were built first, on parallel build order, or on a
developer's cache. A case reproduces with a plain
`roc build --no-cache --opt=dev --target=x64musl` of its fixture. The build
phase took 50 s for 51 fixtures, against 47 s with the shared cache, and the
full suite still runs in about 3.5 minutes at `--jobs 6`. Validation
(`roc check`, `roc test`) still uses the cache.

## Rebaseline

Protocol: a snapshot of the tree, an empty `XDG_CACHE_HOME`, the full
harness in order, `--compare-baselines --baseline-report --jobs 6`, then the
report applied to both targets. The reviewed run passed every case: all 257
snapshots are byte-identical and every validator passed. Two of the seven
full-suite runs in this slice failed on a transient compiler segfault in
`roc check tests/authoring/authoring.roc` (fault addresses `0x211a` and
`0x0`), the same failure the tables slice saw once in four runs. Each rerun
passed. The final `--allocation-baselines` gate from an empty cache passed
all 257 cases.

- **Bytes.** No snapshot changed. The gallery examples rebuild
  byte-identically (`scripts/check_gallery.py`).
- **Work counters.** No work counter changed in any case.
- **Allocations.** 252 cases decreased, 4 were unchanged, and none
  increased. The total over all cases fell from 6,640,817 to 4,718,208
  (−29.0%). Per case the change ranged from −63.2% to 0.0%, with a median of
  −21.5%.
- **Allocated bytes.** Recorded for the first time. They range from 24 bytes
  to 2.68 GB (`rich inline paragraphs x100`), with a median of 2.6 MB.
  `structural-kernel blank PDF` allocates nothing inside its boundary and
  records 0.

| Family | Cases | Min | Median | Max |
| --- | ---: | ---: | ---: | ---: |
| actual_text | 21 | −41.3% | −21.3% | −1.0% |
| archive | 13 | −39.7% | −19.9% | −11.5% |
| authoring | 22 | −20.0% | −6.9% | −0.0% |
| bidi | 1 | −2.5% | −2.5% | −2.5% |
| caller_font | 5 | −37.2% | −35.6% | −5.3% |
| color_images | 8 | −27.3% | −25.5% | −11.5% |
| containers | 5 | −24.1% | −17.2% | −16.1% |
| facade_fragments | 7 | −16.0% | −15.5% | −10.4% |
| facade_output | 2 | −17.9% | −9.8% | −1.8% |
| facade_scenes | 5 | −22.0% | −20.6% | −19.8% |
| facade_text | 4 | −20.4% | −19.1% | −18.0% |
| font | 6 | −17.1% | −1.9% | −0.2% |
| font_leaves | 13 | −48.5% | −28.3% | −6.9% |
| font_subsetting | 1 | −1.8% | −1.8% | −1.8% |
| form_text | 1 | −29.6% | −29.6% | −29.6% |
| forms | 9 | −45.0% | −33.0% | −16.9% |
| generated_label | 2 | −25.3% | −19.2% | −13.2% |
| layout_policies | 9 | −27.2% | −22.4% | −5.7% |
| metadata | 12 | −35.6% | −30.9% | −13.8% |
| multiface_facade | 7 | −38.5% | −2.5% | 0.0% |
| navigation | 17 | −57.8% | −45.3% | −6.2% |
| pdf_facade | 5 | −19.0% | −17.9% | 0.0% |
| pdf_font | 1 | −10.0% | −10.0% | −10.0% |
| placeholder | 2 | 0.0% | 0.0% | 0.0% |
| resource_graph | 11 | −4.2% | −1.4% | −0.2% |
| rich_inline | 5 | −38.7% | −35.1% | −7.6% |
| shading_patterns | 16 | −44.9% | −37.4% | −18.5% |
| shaping | 1 | −2.0% | −2.0% | −2.0% |
| soft_masks | 10 | −35.0% | −31.1% | −17.7% |
| structural_kernel | 9 | −63.2% | −63.2% | −11.9% |
| tables | 7 | −34.0% | −28.4% | −1.8% |
| tagged_visual | 2 | −41.4% | −33.1% | −24.8% |
| transparency | 12 | −35.1% | −32.0% | −16.3% |
| unicode_analysis | 2 | −13.4% | −12.8% | −12.2% |
| unicode_vectors | 2 | −22.2% | −18.9% | −15.6% |
| visible_text | 1 | −20.6% | −20.6% | −20.6% |

Review of the distribution:

- **Sources.** Every removed event is a copy or a reallocation that the
  fixes removed. An exact `List.reserve` in `append_all` reallocated once per
  array and dictionary, and each copy of a shared list is one allocation. The
  `--no-cache` builds also remove the cross-fixture reuse that had added
  copies. That is why cases that do not lower objects (`authoring`,
  `unicode_*`, `facade_*`) also fell: before, they were built against
  procedures cached by earlier fixtures.
- **Largest decreases.** The structural-kernel plans (−63.2%) are almost
  entirely object-store operations: page trees, balanced indexes, and
  dictionaries. Every `add_array` and `add_dictionary` had reallocated
  through `append_all`, and the page-tree and page loops copied the store per
  node. The navigation (−57.8%), `font_leaves` (−48.5%), and `forms`
  (−45.0%) outliers lower many small dictionaries and resource entries, the
  same shapes.
- **Unchanged cases.** `placeholder PDF x1` and `x4` and two text-layout
  atomic negatives stop before lowering. The resource-graph cases (−0.2% to
  −4.2%) plan resources without an object store.
- **Sampled per subsystem.** Tables and layout policies (the scale pairs
  above), structural kernel (page trees), transparency and font leaves
  (traced: content emission and `KernelFormStructure`), and rich inline
  (traced: content emission) were checked by stage probes or allocation
  stacks. Their remaining costs are the open issues below.

## When the upstream defects are fixed

- **Keep regardless:** the early returns (cause 1 is the code's own
  liveness), the removed exact reserves (cause 4; `List.reserve` is exact by
  design), the tree helpers (cause 5), and the `KernelObject` rewrite. They
  are simpler than what they replaced.
- **Revertible, but no reason to:** the builder-only and `add_*_array`
  helpers (cause 2) and the cell attributes written in `place_rich` (cause
  3) work around report A. Reverting them after a fix would bring back the
  old shapes with no gain.
- **Revisit:** `--no-cache` fixture builds (cause 6). Once report B is fixed,
  cached and uncached builds should produce identical programs, and the
  harness could use the cache again for speed. The guard would detect any
  difference.

## Open issues

The guard's first run exposed super-linear allocation outside the invoice
path. The ceilings record these values, so they cannot get worse, but they
are not fixed here:

- **Content streams on dense pages.** Content emission still copies the
  page stream about once per emitted token (allocation stacks through
  `emit_text`, `append_bytes`, and `KernelLex.append_u64`). The LIR of
  `KernelContent.emit_commands` carries the loop's sixteen variables in an
  aggregate join parameter that the pinned compiler did not split, and each
  iteration increments the stream field it reads from that aggregate. The
  compiler's own `scalarize_joins` comment names this as the shape that
  turns in-place updates into copies. The cost is linear in pages and
  quadratic in one page's content. The recorded ceilings show it:
  `production-visual shared font subset` x100 → x1000 grows 11 MB → 850 MB
  (77×), `distinct opacity states` 7.0 → 378 MB (54×), `shared mask reuse`
  and `shared-constant opacity` about 53× and 58×, and `artifact form
  repeated` 48×. A minimal program did not reproduce the unsplit join.
- **Production-visual forms.** `KernelForm`, `KernelResourceGraph`,
  `KernelTextOwnership`, and `KernelFontLeaf` still use `$failure` loop state
  (cause 1; 124 references). Some loops also test `$failure` in conditions,
  so they need manual conversion. `KernelFormStructure`'s were converted
  here.
- **Rich inline paragraphs** x10 → x100 grows 17× in bytes, mostly in content
  emission (above). **Scenes** and **fragments** grow quadratically with
  pages but stay small (45 MB and 9 MB at 400 invoice rows):
  `KernelFacadeScenes` copies `$commands` and `$groups` once per page. The
  cause was not isolated.
- **`List.concat` accumulators** remain in `KernelForm` (payload digests),
  `KernelXmp`, `KernelNavigation` (name and URI bytes), `Document`
  (normalized blocks), and `KernelResourceGraph`, each bounded by its input
  size.
- **Users' builds** can still hit report B when a cache holds procedures
  from another program. The package cannot prevent this.
- **Upstream:** the report draft
  [upstream-roc-uniqueness-issue.md](upstream-roc-uniqueness-issue.md) is for
  the maintainer to review and file.
