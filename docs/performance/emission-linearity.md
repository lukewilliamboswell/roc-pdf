# S6c: linear emission and the remaining super-linear copies

The allocated-bytes guard added in S6b
([lowering-uniqueness.md](lowering-uniqueness.md)) recorded ceilings for
cases that still copied whole lists once per element: dense content pages,
production-visual forms, scenes, and several accumulators grown with
`List.concat`. This slice removes those copies. It changes no output byte
and no work counter; the exact allocation counts and the allocated-bytes
ceilings are rebaselined.

## How it was measured

- **Every scale pair.** A throw-away script built each fixture that owns a
  scale pair with `roc build --no-cache --opt=dev --target=x64musl`, ran both
  cases of all 56 pairs in `tests/spec.json`, compared each PDF with its
  snapshot, and read `allocated_bytes` from the metrics report and
  instructions from `perf stat -e instructions:u`. Each change below was
  measured this way before it was kept.
- **Allocation stacks.** The S6b frame-walking debug host, and a copy that
  traces every allocation of 512 bytes or more instead of 4 KiB, with the
  binary built by `roc build --debug`. The stack names each Roc procedure by
  its declaring module and line, and consecutive sizes show the shape of a
  copy: a clone is sized exactly (`len + 1`), and geometric growth follows it.
- **LIR.** `ROC_LIR_DUMP=` with an empty value prints the final LIR of every
  procedure. Two throw-away detectors read it: one lists every `incref` of a
  list whose same local then reaches `list_map_prepare_reuse`, `list_reserve`,
  `list_set`, or `list_append_unsafe` before any `decref` (a guaranteed
  clone), and one lists every caller of a specialization (the compiler
  specializes a procedure separately for borrowed and owned arguments).
- **Source detectors.** Two further scripts flag value-producing `if`/`match`
  expressions whose branches reassign an outer `var`, and `match f(…, $v, …)`
  statements with an arm that neither reassigns `$v` nor exits. Most hits
  hold only scalars; the list-holding ones were reviewed by hand.
- **Minimal programs** reproduce two of the causes; see report E of
  [upstream-roc-uniqueness-issue.md](upstream-roc-uniqueness-issue.md).

The build is the pinned `nightly-2026-09-26-d6267b4`, `--opt=dev`, `x64musl`.

## Causes and fixes

1. **A branch value that consumes a reassigned `var`.** When an `if` or
   `match` produces a value and one branch reassigns a `var` while another
   passes it on as the value, the join after the construct carries the `var`
   beside the value. The branch that did not reassign it sets both from the
   same list, with an `incref`, so the call in that branch copies the list.
   `KernelLex.append_decimal` had this shape (`if $scale == 0 {
   append_u64($out, …) } else { $out = …; $out }`), so every whole number
   written into a content stream copied the whole stream. `emit_color` and
   the stroke dash in `KernelContent`, `append_thousandths_unchecked`, and
   `KernelForm.append_color` did the same once per color, stroke, fraction,
   and recipe color. The dense-page ceilings were almost entirely this: in
   `production-visual shared-constant opacity x1000`, 99% of the 335 MB
   traced was `emit_path` and `append_decimal` copying the page. Each branch
   now consumes an immutable binding (`signed = if … else output`), or the
   `var` is reassigned only by statements and read after the construct.
   The pinned compiler copies in this shape with `--opt=speed` as well
   (report E, `branch`).
2. **A consumed `var` kept by one arm.** After `match f($v) { … }`, an arm
   that neither reassigns `$v` nor exits keeps the old value live across
   the call. The buffered emission loops in `KernelEmit` and
   `KernelDeflate` ended on `Done => { $done = True }`, so `Encoder.next`
   received a shared encoder and copied its object offsets on every object:
   2,786 copies and 42 MB for the invoice at 500 rows. `Done` now returns.
   With `--opt=speed` the pinned compiler does not copy here (report E,
   `flag`). The S6b error-state pattern (`Err(e) => { $error = … }`) is the
   same cause.
3. **Error loop state, again.** S6b converted the object-store loops. 64
   further loops in 20 modules recorded a failure in `$error` or
   `$failure` and kept looping, keeping their accumulators live: the
   opacity walk passed the 65,536-entry value index and the per-command
   state arrays to `walk_opacity` once per page group, scene and semantic
   validation copied their ownership marks once per mark,
   `KernelPdfFont.add_widths` copied the object store once per glyph width
   (81 copies of 1.8 MB for the invoice's one font, and a cost of fonts
   times document size), and resource-object, form-structure, resource-use,
   seal, index, and tagged lowering copied builders or counts per element.
   The error arms now return. In the converted loops a set error ended the
   iteration's remaining checks (they sit in `else` branches or behind
   `$error == NoError` guards), so the error returned is the first one
   recorded, as before, and every negative case reports the same error.
   Loops whose error arms follow no call that consumes an accumulator
   (`KernelEmit` and `KernelStructure` overflow checks, `KernelOutline`'s
   entry validation, KernelForm's missing blending space) are unchanged.
4. **Exact-size concatenation.** `List.concat`, `Str.concat`, and
   `List.reserve` size their result exactly. KernelForm grew the identity
   payload (font subsets, JPEG and ICC bytes, form and pattern recipes) and
   the recipes with `concat`, so every leaf reallocated the whole payload;
   table header associations grew once per data cell; destination names and
   URIs once per destination and link; list item blocks once per item; and
   a rich paragraph's segment text once per leaf. They now append
   element-wise, and a segment joins its leaf texts once
   (`Str.join_with`). `KernelXmp` concatenates into a buffer reserved to the
   exact packet size, which does not reallocate, and stays as it is.
5. **Loop exits and multi-list arms.** In `KernelFacadeScenes`, the page
   loop ran one inner loop over a page's text placements and a second over
   its table rules, both appending to `$commands`, `$groups`, and
   `$page_groups`. The LIR packed the first loop's exit state into a struct,
   read the three lists out of it with an `incref` each, and the second
   loop's entry `list_map_prepare_reuse` copied them before the struct was
   released: once per page, 43.6 MB for the invoice at 500 rows. One loop
   per page now paints the placements and then the rules. A figure image was
   appended inside a value-producing `match` behind `?` exits; the first
   rewrite, a statement `match` that still reassigned both lists behind the
   `?` exits, copied them once per placement (4.6 GB at 500 rows), so the
   image command is now built by a `match` that reassigns nothing and
   appended by a separate one. Neither shape reduced to a small program.
6. **Reads after the growing call.** `emit_object` read the plan store
   (`store`, `object`) after recording the object's offset, which kept the
   encoder live, and the compiler called the borrowed specialization of the
   offset append; the object is now serialized first. KernelForm read
   `$state.form_occurrences.len()` after passing `$state` to
   `collect_range_uses`, which then copied the state per page group. Records
   whose fields are appended to (`encoder_with_offset`,
   `encoder_with_stream_length`, `CountingSink.mark_object`) are taken apart
   before the append.

The emission helpers in `KernelContent` also return the stream alone; the
counts they returned beside it are derived from the command. That shape was
not a cause here, but it removes a record that could keep the stream live.

The S6b open issue about `emit_commands` blamed an unsplit
sixteen-variable loop join. The copies were in the helpers it called
(cause 1), and `emit_commands` itself does not copy.

`AGENTS.md` now states causes 1, 2, and 6 beside the S6b rules.

## Scaling

Every scale pair in the suite, measured from the tree before this slice
(`d1f8265`) and after it. "Ratio" is the large case's allocated bytes (or
instructions) divided by the small case's; the scale column gives the input
ratio. Allocated bytes and instructions are deterministic, and the
standalone `--no-cache` builds reproduced the harness's recorded allocation
counts and bytes exactly.

| Pair | Scale | Bytes before (MB) | Ratio before | Bytes after (MB) | Ratio after | Instr. ratio before | Instr. ratio after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| layout policies adversarial heading chain | x50 → x500 (10×) | 8.07 → 78.58 | 9.7× | 3.51 → 28.64 | 8.2× | 3.2× | 3.2× |
| layout policies keep groups and lists | x50 → x500 (10×) | 57.53 → 647.55 | 11.3× | 13.86 → 129.40 | 9.3× | 7.3× | 7.3× |
| placeholder PDF | x1 → x4 (4×) | 0.00 → 0.00 | 1.0× | 0.00 → 0.00 | 1.0× | 1.0× | 1.1× |
| production-visual artifact form repeated | x100 → x1000 (10×) | 3.10 → 149.21 | 48.1× | 1.26 → 2.18 | 1.7× | 4.6× | 4.1× |
| production-visual dense resource dependency graph | x100 → x1000 (10×) | 0.81 → 9.81 | 12.0× | 0.81 → 9.81 | 12.1× | 10.5× | 10.5× |
| production-visual distinct font subsets | x8 → x64 (8×) | 5.14 → 90.77 | 17.7× | 4.16 → 25.54 | 6.1× | 4.7× | 4.7× |
| production-visual distinct image emission | x8 → x64 (8×) | 5.06 → 38.80 | 7.7× | 4.91 → 35.23 | 7.2× | 4.3× | 4.3× |
| production-visual distinct mask forms | x8 → x64 (8×) | 6.62 → 50.19 | 7.6× | 5.95 → 46.50 | 7.8× | 4.3× | 4.3× |
| production-visual distinct opacity states | x100 → x1000 (10×) | 7.01 → 378.25 | 53.9× | 2.23 → 23.56 | 10.6× | 8.9× | 8.7× |
| production-visual distinct patterns | x8 → x64 (8×) | 5.21 → 43.07 | 8.3× | 5.15 → 41.34 | 8.0× | 5.1× | 5.1× |
| production-visual distinct shadings | x8 → x64 (8×) | 0.94 → 3.91 | 4.2× | 0.83 → 2.20 | 2.7× | 4.1× | 4.1× |
| production-visual duplicate image collapse | x8 → x64 (8×) | 1.22 → 1.72 | 1.4× | 1.20 → 1.55 | 1.3× | 2.9× | 2.9× |
| production-visual equivalent authored fonts collapse | x8 → x64 (8×) | 1.82 → 21.36 | 11.7× | 1.65 → 7.00 | 4.2× | 3.9× | 4.0× |
| production-visual font-leaf forced digest collisions | x8 → x64 (8×) | 1.93 → 16.80 | 8.7× | 1.92 → 16.79 | 8.7× | 2.3× | 2.3× |
| production-visual forced digest-collision bucket | x100 → x1000 (10×) | 0.20 → 2.25 | 11.2× | 0.20 → 2.25 | 11.2× | 10.0× | 10.0× |
| production-visual mask chain | x2 → x4 (2×) | 2.92 → 4.12 | 1.4× | 2.35 → 3.54 | 1.5× | 1.2× | 1.2× |
| production-visual metadata title scaling | x64 → x256 (4×) | 0.79 → 0.80 | 1.0× | 0.75 → 0.76 | 1.0× | 1.0× | 1.0× |
| production-visual navigation annotations | x8 → x64 (8×) | 1.07 → 8.98 | 8.4× | 0.91 → 2.87 | 3.1× | 4.8× | 4.7× |
| production-visual navigation destination names | x8 → x40 (5×) | 0.87 → 2.80 | 3.2× | 0.80 → 1.38 | 1.7× | 2.5× | 2.5× |
| production-visual nested form DAG | x8 → x32 (4×) | 7.78 → 24.78 | 3.2× | 7.68 → 24.13 | 3.1× | 2.7× | 2.7× |
| production-visual nested opacity chain | x16 → x64 (4×) | 1.93 → 2.52 | 1.3× | 1.33 → 1.78 | 1.3× | 2.0× | 2.0× |
| production-visual pattern cell commands | x16 → x64 (4×) | 1.29 → 2.43 | 1.9× | 1.21 → 1.24 | 1.0× | 1.6× | 1.6× |
| production-visual per-form opacity | x8 → x32 (4×) | 6.46 → 22.30 | 3.5× | 5.85 → 21.30 | 3.6× | 2.1× | 2.1× |
| production-visual resource dependency chain | x100 → x1000 (10×) | 0.44 → 5.16 | 11.6× | 0.44 → 5.16 | 11.7× | 10.1× | 10.1× |
| production-visual resource dependency fan | x100 → x1000 (10×) | 0.44 → 5.16 | 11.6× | 0.44 → 5.16 | 11.7× | 10.2× | 10.2× |
| production-visual shading stops | x16 → x64 (4×) | 1.09 → 4.01 | 3.7× | 0.83 → 1.39 | 1.7× | 2.2× | 2.2× |
| production-visual shared font subset | x100 → x1000 (10×) | 11.03 → 850.01 | 77.1× | 2.46 → 20.56 | 8.4× | 3.8× | 3.6× |
| production-visual shared intent profile | x16 → x64 (4×) | 2.19 → 20.63 | 9.4× | 1.25 → 3.60 | 2.9× | 3.6× | 3.7× |
| production-visual shared mask reuse | x100 → x1000 (10×) | 6.36 → 337.08 | 53.0× | 1.91 → 3.29 | 1.7× | 4.3× | 3.7× |
| production-visual shared pattern | x100 → x1000 (10×) | 3.81 → 203.58 | 53.5× | 1.25 → 1.94 | 1.5× | 4.9× | 4.3× |
| production-visual shared shading | x100 → x1000 (10×) | 2.96 → 168.65 | 57.1× | 0.81 → 2.08 | 2.6× | 3.8× | 3.4× |
| production-visual shared-constant opacity | x100 → x1000 (10×) | 5.77 → 336.50 | 58.3× | 1.34 → 2.72 | 2.0× | 4.6× | 3.9× |
| rich inline paragraphs | x10 → x100 (10×) | 155.04 → 2,676.88 | 17.3× | 9.58 → 87.41 | 9.1× | 6.2× | 6.1× |
| semantic foundation sections | x10 → x100 (10×) | 11.62 → 119.84 | 10.3× | 3.87 → 29.53 | 7.6× | 5.3× | 5.3× |
| static PDF/A-4 archived navigation links | x8 → x64 (8×) | 3.42 → 16.60 | 4.9× | 1.71 → 5.37 | 3.1× | 1.8× | 1.7× |
| structural-kernel bulk lexical values | x2048 → x4096 (2×) | 696.10 → 696.31 | 1.0× | 11.47 → 11.68 | 1.0× | 1.0× | 1.0× |
| tables invoice | x50 → x500 (10×) | 163.18 → 1,679.44 | 10.3× | 21.36 → 158.09 | 7.4× | 6.2× | 6.1× |
| text-layout Unicode analysis | x1000 → x10000 (10×) | 2.12 → 19.21 | 9.1× | 2.12 → 19.21 | 9.1× | 10.0× | 10.0× |
| text-layout adversarial ordered font selection | x1000 → x10000 (10×) | 0.20 → 1.72 | 8.8× | 0.20 → 1.72 | 8.8× | 3.4× | 3.4× |
| text-layout compact-builder authoring normalization | x1000 → x10000 (10×) | 0.41 → 4.79 | 11.7× | 0.41 → 4.79 | 11.7× | 7.2× | 7.3× |
| text-layout facade batch shaping | x1000 → x10000 (10×) | 2.22 → 20.47 | 9.2× | 2.22 → 20.47 | 9.2× | 2.9× | 2.8× |
| text-layout facade cached line layout | x1000 → x10000 (10×) | 2.42 → 22.58 | 9.3× | 2.42 → 22.58 | 9.3× | 3.2× | 3.1× |
| text-layout facade fragment arena | x1000 → x10000 (10×) | 1.71 → 17.23 | 10.1× | 1.71 → 17.23 | 10.1× | 9.7× | 9.7× |
| text-layout facade fragment prepared-input control | x1000 → x10000 (10×) | 1.54 → 15.55 | 10.1× | 1.54 → 15.55 | 10.1× | 9.4× | 9.4× |
| text-layout facade row pagination | x1000 → x10000 (10×) | 3.12 → 29.17 | 9.4× | 3.12 → 29.17 | 9.4× | 3.7× | 3.6× |
| text-layout facade scene arena | x1000 → x10000 (10×) | 0.74 → 7.29 | 9.9× | 0.74 → 7.29 | 9.9× | 8.4× | 9.2× |
| text-layout facade scene prepared-input control | x1000 → x10000 (10×) | 0.11 → 0.99 | 9.4× | 0.11 → 0.99 | 9.4× | 4.8× | 5.0× |
| text-layout facade semantic planning | x1000 → x10000 (10×) | 1.16 → 12.28 | 10.6× | 1.16 → 12.28 | 10.6× | 9.6× | 9.6× |
| text-layout facade text materialization | x1000 → x10000 (10×) | 2.62 → 26.14 | 10.0× | 2.62 → 26.14 | 10.0× | 9.8× | 9.8× |
| text-layout facade text prepared-input control | x1000 → x10000 (10×) | 1.27 → 12.69 | 10.0× | 1.27 → 12.69 | 10.0× | 8.7× | 8.8× |
| text-layout ordered multi-face facade scale | x1000 → x10000 (10×) | 3.93 → 41.67 | 10.6× | 3.93 → 41.67 | 10.6× | 9.0× | 9.0× |
| text-layout shaped-cluster line selection | x1000 → x10000 (10×) | 1.81 → 18.04 | 9.9× | 1.81 → 18.04 | 9.9× | 9.8× | 9.8× |
| text-layout shared facade source cache | x1000 → x10000 (10×) | 0.06 → 0.59 | 10.3× | 0.06 → 0.59 | 10.4× | 7.6× | 7.7× |
| text-layout simple-list authoring normalization | x1000 → x10000 (10×) | 0.52 → 5.47 | 10.5× | 0.52 → 5.47 | 10.5× | 8.2× | 8.3× |
| text-layout single-column pagination | x1000 → x10000 (10×) | 1.80 → 15.80 | 8.8× | 1.80 → 15.80 | 8.8× | 9.7× | 9.8× |
| text-layout unique facade source cache | x1000 → x10000 (10×) | 2.08 → 28.82 | 13.8× | 2.08 → 28.82 | 13.8× | 10.5× | 10.5× |

The pairs that grew faster than their scale now grow at or below it:

- **Dense content pages.** The shared-resource pairs (constant opacity,
  mask, shading, pattern, artifact form) went from 48–58× per tenfold scale
  to 1.5–2.6×: their thousand draws sit on one page, and the page is no
  longer copied per token. `shared font subset` went from 77× (850 MB at
  x1000) to 8.4× (20.6 MB), `distinct opacity states` from 54× to 10.6×.
- **Fonts.** `distinct font subsets` went from 17.7× to 6.1× per eightfold
  scale (the object store is no longer copied per glyph width, nor the
  identity payload per font leaf), and `equivalent authored fonts
  collapse` from 11.7× to 4.2×.
- **Documents.** `rich inline paragraphs` went from 17.3× (2.68 GB at x100)
  to 9.1× (87 MB), the invoice from 1.68 GB to 158 MB at 500 rows (7.4× per
  tenfold), keep groups from 648 MB to 129 MB at x500, and
  `shared intent profile` from 9.4× to 2.9× per fourfold scale.

Pairs that stay slightly above their scale factor are unchanged by this
slice and are not copies. The resource-graph pairs (11.2–12.1× per tenfold
scale) grow their allocation count 8.8× and their instructions 10.1×; the
extra bytes are the geometric capacity steps of lists sized in thousands.
`unique facade source cache` (13.8×) interns sources whose text gets longer
with N, and `compact-builder authoring normalization` (11.7×) allocates 121
and 147 times in total.

Instructions barely moved, because a copy is one `memcpy`: the invoice at
500 rows took 22.73 G before and 22.22 G after, rich inline x100 13.54 G and
12.95 G, and `shared font subset x1000` 2.44 G and 2.25 G. `distinct font
subsets x64` rose from 7.87 G to 7.96 G (+1.1%), because the identity
payload now appends font subset bytes one at a time instead of with one
`memcpy` per leaf. The instruction ratios were already linear.

## Rebaseline

Protocol: an empty `XDG_CACHE_HOME`, the full harness in order,
`--compare-baselines --baseline-report --jobs 6`, review, then the report
applied to both targets.

Six of the seven compare runs, and one of the two final
`--allocation-baselines` runs, stopped in the validation phase on a
transient compiler crash in `roc check tests/authoring/authoring.roc` (five
SIGSEGVs, a stack overflow, and a `guarded list invalidated:
monotype.Type.Store.declared_fields` panic). The crash is not caused by
this slice: `roc check package/main.roc` followed by `roc check
tests/authoring/authoring.roc` into one fresh cache crashed in 2 of 7 tries
on this tree and 3 of 8 on its parent, and the harness's first 24 checks
(6 in parallel) crashed it in 2 of 3 and 3 of 3. Each check passes on its
own. The seventh compare run reached every case: all 257 snapshots are
byte-identical and every validator passed. After the report was applied,
the final `--allocation-baselines` run from an empty cache passed all 257
cases.

- **Bytes.** No snapshot changed. The gallery examples rebuild
  byte-identically (`scripts/check_gallery.py`).
- **Work counters.** No work counter changed in any case.
- **Allocations.** 246 cases decreased and 11 were unchanged; none
  increased. The total over all cases fell from 4,718,208 to 4,242,691
  (−10.1%). Per case the change ranged from −51.4% to 0.0%, with a median
  of −8.5%.
- **Allocated bytes.** The total fell from 15.59 GB to 2.14 GB (−86.2%).
  Per case the change ranged from −99.2% to +0.1%, with a median of −5.1%.
  One case rose: `production-visual font-leaf atomic negatives`, by 2,390
  bytes (+0.1%) with 64 fewer allocations. A zero-threshold allocation trace
  of that case against the parent commit puts it in KernelForm (+27.8 KB,
  +60 allocations), whose identity payload now grows geometrically from 64
  bytes by single appends where `concat` had sized each small document's
  payload exactly; lexical, object, and emission allocations fell by more.
  The ceiling is 10% above the recorded value, and the cost stays linear.

| Family | Cases | Allocations min | median | max | Bytes min | median | max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| actual_text | 21 | -11.4% | -8.0% | -0.3% | -10.6% | -3.4% | -0.1% |
| archive | 13 | -15.0% | -6.5% | -3.3% | -85.9% | -50.0% | -1.4% |
| authoring | 22 | -8.8% | -2.9% | -0.0% | -0.6% | -0.0% | -0.0% |
| bidi | 1 | -0.9% | -0.9% | -0.9% | -0.2% | -0.2% | -0.2% |
| caller_font | 4 | -12.2% | -12.0% | -11.9% | -12.6% | -12.6% | -8.5% |
| color_images | 8 | -19.6% | -12.7% | -8.4% | -10.3% | -5.7% | -1.5% |
| containers | 5 | -6.8% | -4.7% | -3.9% | -75.4% | -54.6% | -7.9% |
| facade_fragments | 7 | -11.0% | -6.5% | -5.9% | -2.5% | -0.0% | -0.0% |
| facade_output | 2 | -5.9% | -3.3% | -0.6% | -10.9% | -5.5% | -0.1% |
| facade_scenes | 5 | -9.9% | -9.1% | -8.6% | -3.0% | -0.0% | -0.0% |
| facade_text | 4 | -9.0% | -8.3% | -7.7% | -0.0% | -0.0% | -0.0% |
| font | 6 | -7.2% | -0.7% | -0.1% | -2.7% | -0.2% | -0.0% |
| font_leaves | 13 | -24.7% | -7.3% | -1.0% | -97.6% | -9.3% | 0.1% |
| font_subsetting | 1 | -0.7% | -0.7% | -0.7% | -0.1% | -0.1% | -0.1% |
| form_text | 1 | -8.3% | -8.3% | -8.3% | -4.2% | -4.2% | -4.2% |
| forms | 9 | -46.8% | -17.4% | -12.2% | -98.5% | -1.5% | -0.8% |
| generated_label | 2 | -7.5% | -6.8% | -6.1% | -12.8% | -7.9% | -3.0% |
| layout_policies | 9 | -8.6% | -6.4% | -1.3% | -80.0% | -56.6% | -4.7% |
| metadata | 12 | -21.9% | -11.4% | -4.1% | -82.6% | -5.1% | -4.9% |
| multiface_facade | 3 | -11.7% | -11.4% | -11.4% | -9.8% | -9.7% | -9.7% |
| navigation | 17 | -46.0% | -22.0% | -1.5% | -80.6% | -8.5% | -0.7% |
| pdf_facade | 4 | -6.3% | -5.4% | -4.7% | -13.1% | -10.7% | -9.4% |
| pdf_font | 1 | -1.5% | -1.5% | -1.5% | -1.7% | -1.7% | -1.7% |
| resource_graph | 11 | -1.5% | -0.5% | -0.1% | -0.7% | -0.1% | -0.0% |
| rich_inline | 5 | -12.4% | -9.6% | -1.8% | -96.7% | -78.9% | -6.1% |
| shading_patterns | 16 | -51.4% | -19.3% | -14.1% | -99.0% | -27.4% | -1.2% |
| shaping | 1 | -0.7% | -0.7% | -0.7% | -0.1% | -0.1% | -0.1% |
| soft_masks | 10 | -48.2% | -15.1% | -10.6% | -99.0% | -16.9% | -7.3% |
| structural_kernel | 7 | -35.8% | -35.8% | -4.7% | -98.4% | -98.3% | -1.2% |
| tables | 7 | -11.7% | -9.3% | -0.9% | -90.6% | -76.6% | -0.9% |
| tagged_visual | 2 | -15.0% | -11.1% | -7.3% | -2.1% | -1.1% | -0.0% |
| transparency | 12 | -48.6% | -15.9% | -6.6% | -99.2% | -35.3% | -4.5% |
| unicode_analysis | 2 | -5.4% | -5.1% | -4.9% | -0.0% | -0.0% | -0.0% |
| unicode_vectors | 2 | -10.0% | -8.2% | -6.5% | -4.2% | -3.8% | -3.3% |
| visible_text | 1 | -5.3% | -5.3% | -5.3% | -6.1% | -6.1% | -6.1% |

Review of the distribution:

- **Sources.** Every removed event is a copy or a reallocation named in the
  causes above: numbers and colors in content streams, offsets in emission,
  marks in validation, builders in font, resource, and form lowering, and
  exact-size concatenations.
- **Largest decreases.** The transparency, soft-mask, shading, and forms
  families (up to −51.4% of allocations and −99.2% of bytes) draw many
  elements on one page and walked the opacity arena once per group.
  `structural_kernel` fell 35.8% and 98% of its bytes: its lexical and
  index plans write many whole numbers through `append_decimal`, which
  copied the output each time (the `bulk lexical values` pair allocated
  696 MB and now 11.5 MB).
- **Unchanged cases.** `placeholder PDF` x1 and x4, `structural-kernel
  blank PDF` and its two DEFLATE cases, and six text-layout atomic
  negatives stop before any changed code.
- **Checked by subsystem.** The invoice, rich inline, transparency, font
  leaves, emission, and resource-graph cases were traced before and after
  (above); the negative families (`*atomic negatives`) report the same
  errors, since their snapshots are unchanged.

## Open issues

- **Chunked output in callers' loops.** A caller that drains
  `Pdf.next_chunk` with a `Done => { $done = True }` flag loop keeps the old
  encoder live and, with `--opt=dev`, copies its object offsets once per
  object (cause 2). The archive and facade chunk fixtures use that loop, and
  `examples/chunked_export.roc` grows its output with `bytes.concat(chunk)`.
  Their documents are small and have no scale pair. The package cannot
  prevent the copy; the public documentation of chunked output should show
  a loop that returns from `Done`.
- **Per-form use state.** KernelForm allocates a fresh `marks` list of all
  resource nodes for every page and every form in use collection, which is
  proportional to forms times nodes (a few hundred bytes per form at the
  largest scale pairs).
- **Remaining error state.** The overflow checks in `KernelEmit` and
  `KernelStructure`, `KernelOutline`'s entry validation, and KernelForm's
  missing blending check keep `$error`-style state, but no error arm follows
  a call that consumes an accumulator, so they do not copy.
- **Value-producing constructs over scalars.** The source detector still
  lists value-producing `if`/`match` expressions that reassign scalar
  `var`s (counters, cursors). They copy nothing today, but the rule in
  `AGENTS.md` covers any list or builder added to them later.
- **Upstream.** Report E of the draft
  [upstream-roc-uniqueness-issue.md](upstream-roc-uniqueness-issue.md)
  reproduces causes 1 and 2 in a small program. Causes 5 and 6 did not
  reduce and are described there under "Not reproduced". The draft is for
  the maintainer to review and file.
