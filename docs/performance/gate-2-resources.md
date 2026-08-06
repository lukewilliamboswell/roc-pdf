# Gate 2 color and image resources

`KernelColor` validates dense color-space identities and bounds ICC bytes,
profiles, tag records, and spaces before exposing an opaque plan. ICC header
and tag-table fields are read directly from packed bytes; tag relationships use
scalar ranges into profile storage.

`KernelImage` validates packed grayscale/RGB raster planes with checked
dimension, stride, multiplication, color-component, and exact decoded-length
rules. Pixel and alpha planes remain packed byte lists. The normalized store
reuses each validated raster payload and scene placements carry only image IDs.

JPEG preparation scans bounded marker segments and entropy ranges iteratively,
checks frame dimensions, component tables, quantization and Huffman table
shapes, scan headers, JFIF/Adobe metadata, and TIFF/EXIF orientation. Relevant
decoder metadata is retained; comments, unrelated application segments, ICC
duplicates, and EXIF bytes are omitted from one compact sanitized payload.
Orientations requiring a pixel transform are rejected unless the caller has
provided display-ready input.

`KernelResourceUse` joins the checked scene, color, and image plans. It rejects
cardinality drift, color-channel/component mismatches, and orphan normalized
resources before lowering. Dense per-resource counters record direct path and
image dependencies; repeated placements increment only a scalar image-use
counter and continue to reference one inspected payload.

The join traverses the command arena and image descriptor store once. Updating
unique dense count lists has no payload-sized copies, and the result retains no
second image, ICC, raster, or JPEG byte list. The plans expose deterministic
byte, row, marker, profile, tag, space, command, placement, and reuse work
counters.
