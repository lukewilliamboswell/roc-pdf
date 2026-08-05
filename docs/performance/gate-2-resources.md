# Gate 2 color and image resources

`KernelColor` validates dense color-space identities and bounds ICC bytes,
profiles, tag records, and spaces before exposing an opaque plan. ICC header
and tag-table fields are read directly from packed bytes; tag relationships use
scalar ranges into profile storage.

`KernelImage` validates packed grayscale/RGB raster planes with checked
dimension, stride, multiplication, color-component, and exact decoded-length
rules. Pixel and alpha planes remain packed byte lists. The normalized store
reuses each validated raster payload and scene placements carry only image IDs.

Both plans expose deterministic byte, row, profile, tag, space, and resource
work counters. JPEG marker inspection and sanitation is the next bounded
resource slice; encoded input currently fails explicitly rather than crossing
the normalized resource boundary.
