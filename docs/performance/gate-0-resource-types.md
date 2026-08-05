# Gate 0 color, ICC, and image resource type slice

## Scope

This define-only slice establishes validated ICC/color and packed raster/JPEG
resource boundaries. It does not parse ICC or JPEG, decode pixels, transform
orientation, compress data, place images, or emit PDF objects.

## Representation and ownership

- ICC bytes are owned once per profile. Parsed tag records carry ranges into
  that allocation; color spaces, output intent, and blend space carry scalar
  profile or space IDs.
- Component counts are a closed typed union. The initial contract can represent
  grayscale and RGB, not untyped component arrays or silently accepted CMYK.
- Raster color and optional alpha planes are packed byte buffers with checked
  dimensions and row strides. There is no list allocation per pixel.
- Validated JPEG bytes remain one encoded allocation. Dimension, component,
  color-space, and orientation evidence are fixed-shape facts beside it.
- Repeated scene placements carry one `Image.Id`; Scene no longer owns a second
  image identity. Theme and Scene likewise consume `Color.Value` rather than
  duplicate color unions.

## Complexity and lifetime

ICC inspection is linear in profile bytes, tags, and checked tag edges. JPEG
inspection is linear in encoded bytes and marker count. Raster validation,
alpha separation, filtering, and transformation are linear in checked pixel
bytes and rows. Exact work records separate these dimensions.

Inspectors use direct indexed loops over bounded byte ranges. They reject
overflow, overlap, unsupported components, invalid dimensions, and conflicting
orientation before constructing a trusted resource. Input and transformed
planes are consumed or released at the earliest phase boundary; an executable
implementation may not retain whole encoded, decoded, separated, filtered, and
compressed copies simultaneously.

No resource stores a closure, iterator, semantic owner, placement, alternative
text, or eventual PDF object number. Returned seamless encoded-resource slices
remain governed by the explicit chunk-retention policy.

## Failure policy

Unsupported color, prohibited profile facts, malformed binary input, excessive
work, and orientation conflicts are errors. There is no assumed profile,
metadata passthrough, rasterization recovery, or conversion fallback.

## Gate evidence

`examples/advanced_resource_contract.roc` compiles one retained ICC profile,
a packed RGB raster, and explicit JPEG orientation evidence. Runtime positive,
atomic negative, fuzz, allocation, copied-byte, and retention evidence belongs
to the gates implementing these inspectors.
