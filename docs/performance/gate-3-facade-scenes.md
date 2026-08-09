# Gate 3 facade page scenes and text ownership

The facade scene stage consumes final page/run placement facts, final per-run
styles, final text, and the fragment-attached semantic plan. It writes the flat
scene arena that later PDF content lowering consumes; it does not recover page,
reading-order, occurrence, fragment, or resource identity from coordinates.

Every final run becomes one fragment-owned group containing a root `Transform`
and one child `DrawText`. The transform carries the accepted baseline, while
the run stays in local text coordinates. Group ID, fragment ID, and run ID are
dense and equal for this facade path. Each page's paint-order range references
those groups in the already accepted placement order. Page boxes use the exact
requested size, the package's bottom-left/upward coordinate model, and zero
rotation.

The stage validates its generated calibrated-gray store through `KernelColor`,
the command/group/page arena through `KernelScene`, semantic paint ownership
through `KernelTagged`, and exact run/fragment occurrence and source coverage
through `KernelTextOwnership`. The successful plan retains only the validated
color and ownership plans plus compact work counters, not the input layout or
an alternate scene copy.

Gate 3 currently accepts only exact sRGB black from facade styles and prepares
it as calibrated gray black. Other theme colors return `UnsupportedColor`.
This is an explicit capability boundary, not a conversion fallback: packaged
ICCBased sRGB and broader color support belong to Gate 4.

## Complexity and ownership

For `p` pages and `r` final runs, arena construction is `O(p + r)` time. It
allocates exact-capacity flat buffers for `2r` commands, `r` groups, `r` page
paint edges, and `p` pages, plus one fixed calibrated-gray resource store. No
recursive draw tree or allocation-per-command representation is created.

The hot loop consumes unique accumulators and performs one placement visit,
one color check, two command writes, one group write, and one page-edge write
per run. Downstream scene validation is iterative at graphics depth two. The
ownership join uses the existing count/prefix/write arrays and visits every run
and fragment exactly once.

## Evidence

`tests/gate3_facade_scenes` uses matched prepared-input controls around the
flat arena boundary:

| Scenario | Control allocations | Arena allocations | Delta | Pages | Commands | Groups |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 occurrences | 65 | 70 | +5 | 32 | 4,000 | 2,000 |
| 10,000 occurrences | 69 | 74 | +5 | 313 | 40,000 | 20,000 |

The constant five-allocation delta corresponds to the command, group,
page-edge, page, and calibrated-gray store buffers; it does not grow per scene
node. Work scales by ten for runs, placements, commands, groups, edges, and
color checks. Atomic negative evidence covers non-black source color, a
non-positive page size, a group limit, and a placement/page mismatch.

The composed fixture creates six fragments and six final runs across three
occurrences. It proves twelve command visits, six group/run/fragment writes,
six occurrence-range checks, and six text fragments through the full color,
scene, tagging, and ownership path.

These allocation fixtures emit a blank 667-byte PDF solely as the deterministic
measurement carrier. They do not claim public facade rendering. The subsequent
font-resource and `Pdf.to_bytes` composition slice must emit and independently
inspect a visible, searchable, nonblank document.
