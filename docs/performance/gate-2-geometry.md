# Gate 2 page and analytical geometry slice

## Representation and coordinate model

Prepared pages carry resolved media, crop, bleed, trim, and art boxes plus one
closed quarter-turn rotation. Coordinates use PDF user space with a bottom-left
origin and upward Y axis. One point is exactly 1,000 `Layout.Unit` values.
Affine matrix coefficients are signed fixed-point thousandths; translations
use layout units. Transform multiplication uses checked `I64` arithmetic and
half-even rounding at the single division boundary.

Paths are dense records over one flat segment arena. Cubics store two controls
and an endpoint; rectangles remain one fixed-shape segment rather than four
duplicated line records. Dash lengths occupy one flat scalar arena. Commands
refer to paths, images, text runs, and child spans by dense scalar identity;
they do not retain payload copies or recursive command lists.

## Validation, work, and ownership

Every resolved box must have positive dimensions and checked endpoints. Crop
must be contained by media; bleed, trim, and art must each be contained by
crop. Validation performs five box checks, four containment checks, and twenty
coordinate checks per page, with no geometry-dependent allocation.

Analytical point transforms have constant work and allocate no collections.
Overflow is a typed failure rather than wrapped geometry. Later path and scene
validation consumes these page and path arenas directly with indexed loops and
records its own per-segment and per-command work before the representation is
accepted as the million-command path.

The prepared scene owns each path segment and dash scalar once. Placements and
commands carry scalar IDs or ranges, so repeated drawing and resource reuse do
not duplicate geometric or image payloads.
