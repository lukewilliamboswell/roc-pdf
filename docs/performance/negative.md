# tagged-visual atomic negative evidence

## Transactional boundary

Every runtime negative below is rejected while building an opaque geometry,
scene, semantic, tagged, color, image, resource-use, or content plan. Object
identity assignment and emission accept only those opaque plans, so a rejected
input cannot expose a partial object store or PDF byte prefix. Error tags and
their scalar diagnostic fields are exact Roc test expectations.

Non-finite operands have a stronger boundary: page coordinates, affine
coefficients, colors, dimensions, and path operands use opaque integer or
fixed-point types. NaN and infinity have no representation at this API. The
runtime twin for the remaining numeric failure mode is checked `I64` overflow,
which returns `CoordinateOverflow` before a geometry plan escapes.

| Required negative | Evidence and stable rejection |
| --- | --- |
| Unbalanced or invalid geometry | `KernelScene` rejects overlapping command ranges with `DuplicateOwnership`, orphan commands with `Orphaned`, invalid path order with `InvalidPathOrder`, and excessive explicit graphics depth with `LimitExceeded(GraphicsDepth)`; traversal is iterative. |
| Non-finite or overflowing operands | Non-finite values are unrepresentable; `KernelGeometry` returns `CoordinateOverflow` for checked transform overflow. |
| Invalid page boxes | `KernelGeometry` returns exact `NonPositiveBox` and `BoxOutside` errors before page lowering. |
| Invalid image dimensions or channels | `KernelImage` returns `InvalidDimensions` before stride arithmetic and `ColorComponentMismatch` before resource planning; `KernelResourceUse` independently checks scene/color/image agreement. |
| Malformed JPEG | Segment-length, truncated-marker, table, scan, component, and EXIF/orientation checks return bounded `InvalidJpegSegment`, `InvalidJpegMarker`, `UnsupportedJpegComponents`, `InvalidExif`, or `OrientationRequiresTransform` errors. |
| Invalid semantic, content-stream, or fragment identity | `KernelSemantics` tests exact `NonDenseIdentity` and `IndexOutOfRange` failures before reverse-index writes or ParentTree planning. |
| Orphan or duplicate MCID ownership | MCIDs are derived only after `DuplicateFragmentOwnership`, `OrphanFragment`, and `OccurrenceHasNoFragments` checks. The independent emitted-PDF checker rejects a changed MCID. |
| Missing or wrong ParentTree entry | Counts and prefix sums create every row from sealed marked references. The independent checker replaces the one ParentTree value and requires rejection. |
| Unowned meaningful content | `KernelTagged` rejects semantic fragments painted as page artifacts and logical occurrences without a painted fragment. |
| Page/contextual Artifact confusion | `KernelTagged` proves page artifacts acquire no MCID; `KernelSemantics` rejects Artifact-owned attributes on ordinary nodes; the independent checker rejects a contextual Artifact attached outside its exact semantic parent. |

## Emitted negative twins

`check_tagged_visual.py` begins from the retained valid PDF and applies five length-
preserving mutations: mixed `/K` reordering, wrong ParentTree ownership, an
orphan MCID, a wrong page `StructParents` key, and a contextual Artifact with
the wrong parent. Each must fail the normalized structure checker. Existing
structural-kernel structural negatives separately prove that offsets, lengths, xref,
DEFLATE, identifiers, and EOF corruption are rejected.
