# Gate 2 content lowering

`KernelContent` consumes the opaque tagged plan and writes deterministic PDF
content bytes from typed scene commands. Fragment groups receive `/P` marked
content with lowering-assigned MCIDs; page artifacts receive explicit Artifact
properties. Paths, clipping, transforms, grayscale/RGB paint, stroke state,
dash arrays, and image placements lower without exposing raw operators.

Gate 2 currently admits one page content stream per page. The semantic and
tagged stores retain content-stream identities for later multi-stream and Form
XObject slices, but this lowerer rejects a different cardinality rather than
guessing page or artifact stream ownership.

Command traversal uses a dense explicit frame buffer, so graphics nesting does
not consume the host call stack and source paint order is preserved. The frame
buffer grows with maximum graphics depth, not command count. Each command and
path segment is visited once.

Each page owns one growing byte buffer. Canonical integers and fixed-point
decimals append directly into that unique buffer after an exact lexical-length
check; they do not allocate a temporary byte list per number. Resource names
contain only dense IDs, and repeated image placements never copy image bytes.
The total content-byte limit is reduced after each completed page so a later
page cannot allocate beyond the remaining document budget.

The work record exposes exact bytes, command/group visits, path segments,
balanced graphics-state pairs, image placements, and fragment/artifact marked
groups. The optimized million-command fixture records exactly one million
command visits and image placements, a maximum frame depth of one, 29,000,023
content bytes, and 129 total Roc allocations while reusing one image payload.
