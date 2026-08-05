# Gate 1 canonical lexical-kernel slice

## Scope and status

`KernelLex` is a private package module for canonical PDF lexical values. This
slice implements positive and atomic-negative unit behavior for booleans,
null, signed and unsigned integers, exact finite decimals, names, byte strings,
and Unicode text strings. The ledger remains `partial` until the optimized
sealed-plan pipeline, independent parser, and allocation scenarios exercise
these paths together.

## Representation and validation

- A real is an opaque signed `I64` coefficient plus a decimal scale from zero
  through nine. No floating-point value or host formatter crosses the boundary.
- A name owns its validated source bytes once. Null bytes are rejected with an
  exact source index; delimiters, whitespace, `#`, and non-ASCII bytes use
  uppercase `#XX` escapes during emission.
- Byte strings use uppercase hexadecimal syntax. Text strings accept Roc `Str`
  and emit uppercase hexadecimal UTF-16BE with a BOM, including surrogate pairs
  for non-BMP scalars. Malformed UTF-8 cannot inhabit `Str`.
- The object plan will store names and strings once and refer to them by dense
  IDs or ranges. This slice does not introduce a recursive token tree.

## Traversal and complexity

All input and output passes are direct indexed `while` loops. There is no
`Iter(U8)`, token list, per-digit string, locale lookup, map iteration, or
recursive traversal.

- Integer work is bounded by 20 decimal digits and constant auxiliary state.
- Decimal normalization is bounded by nine fractional digits; rendering is
  bounded by the integer width plus that fixed scale.
- Name and byte-string work is linear in source bytes and emits at most three
  or two bytes respectively per source byte, plus delimiters.
- Text work is linear in UTF-8 bytes and emitted UTF-16 code units. It retains
  no intermediate scalar or UTF-16 list.

The production append entrypoints consume and return one output list. Fixed
keywords append their bytes directly and never allocate a temporary `Str`.
When the sealed emitter supplies a unique accumulator with proven capacity,
digits, escapes, and code units require no allocation per token or byte.

## Ownership and evidence still required

Standalone rendering helpers intentionally start from an empty output list for
unit tests. Gate 1 completion will add pinned optimized cases for unique and
shared accumulators, exact allocation and ARC shape, byte visits, copied bytes,
output-limit failures, and integrated object emission. A measured regression
will require representation review rather than baseline regeneration.
