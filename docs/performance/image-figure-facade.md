# Public image-figure facade

## Boundary

The first executable public figure slice accepts one replayable `Image.Source`
inside one `Scene.Drawing`, a positive placement, non-empty alternative text,
and an optional caption. Normalization assigns dense figure identity once.
Semantics creates the `Figure`, its text property, and its occurrence before
layout; the scene stage consumes those facts and never infers ownership from
coordinates.

The source plane remains one immutable packed byte list. Inspection, hashing,
compression, image-object emission, and placement consume ranges or the shared
list; the authoring layer does not expand pixels into records. The prepared PDF
retains only the validated resource payload and sealed object/content recipes.

## Complexity and ownership

- Normalization and semantic/scene indexing are `O(b + f + o)` for blocks,
  figures, and occurrences, with dense lists and scalar IDs.
- Each figure adds one semantic node, occurrence, source input, text property,
  image resource, scene command, and placement flag. Caption wrapping may add
  fragments but does not duplicate the image payload or paint it twice.
- Image validation and compression remain `O(encoded_bytes + decoded_bytes)`
  under the existing bounded image pipeline. Packed input is retained once;
  final compressed stream bytes are a distinct required output allocation.
- Figure lookup uses an occurrence-indexed dense list produced from the
  validated semantic store, avoiding a run-by-figure scan.
- Arithmetic introduced by figure leading and placement uses checked signed
  operations; resource counts and command budgets use checked unsigned
  operations.

## Focused evidence

`text-layout public image-figure facade output` measures the whole public
facade from authoring construction through contiguous output on the pinned
nightly dev backend. Its 8×4 RGB plane has 96 authored bytes and produces a
one-page 18,772-byte PDF in exactly 2,597 Roc allocations on both recorded
targets. The independent validator decodes the image stream and requires exact
pixel equality, one placement, a semantic `Figure` MCR, and the exact authored
`/Alt` string.

Adding the normalized figure store widens the staged document value carried by
the existing text-only public-facade fixture. Under the pinned dev compiler,
that fixture moves from 1,588 to 1,589 allocations on both recorded targets.
The emitted bytes and deterministic work are unchanged; the single event is
the reviewed fixed representation cost, not per-page or per-block image work.

The existing contract suite supplies atomic negatives for malformed packed
planes, empty alternatives, and vector-only drawings. Existing color-image
fixtures retain the scaled row, hashing, compression, alpha, and JPEG evidence;
the public fixture proves that the facade reaches those already-reviewed
stages without a parallel serializer or fallback.
