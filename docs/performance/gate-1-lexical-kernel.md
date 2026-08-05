# Gate 1 canonical lexical-kernel slice

## Scope and status

`KernelLex` is a private package module for canonical PDF lexical values. This
slice implements positive and atomic-negative unit behavior for booleans,
null, signed and unsigned integers, exact finite decimals, names, byte strings,
and Unicode text strings. Every direct value also crosses the flat object
store, sealing, and the shared value emitter in one exact integration check.

## Representation and validation

- A real is an opaque signed `I64` coefficient plus a decimal scale from zero
  through nine. No floating-point value or host formatter crosses the boundary.
- A name owns its validated source bytes once. Null bytes are rejected with an
  exact source index; delimiters, whitespace, `#`, and non-ASCII bytes use
  uppercase `#XX` escapes during emission.
- Byte strings use uppercase hexadecimal syntax. Text strings accept Roc `Str`,
  store its UTF-8 bytes once in the object plan, and emit uppercase hexadecimal
  UTF-16BE with a BOM, including surrogate pairs for non-BMP scalars. Malformed
  UTF-8 cannot inhabit `Str`; repeated emission never reconverts the string.
- The object plan stores names and strings once and refers to them by dense IDs
  or ranges. This slice does not introduce a recursive token tree.

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

## Ownership and executable evidence

Fixed-keyword standalone helpers start from an exactly sized output list;
variable-width standalone helpers start empty for unit-test convenience.
Production append entrypoints consume the preflighted unique accumulator
supplied by the sealed emitter; a shared accumulator is not part of this
consumption-shaped hot-path contract. The boolean writer selects scalar bytes
before mutating the list, so control flow does not cause an ARC copy. Planned
text retains one UTF-8 byte list and does not allocate a conversion for every
emission.

The optimized scaling fixture appends nine canonical values per bundle: both
booleans, null, `I64.lowest`, `U64.highest`, a normalized real, an escaped name,
a byte string, and a non-BMP text string. At 2,048 bundles it emits 18,432
tokens and 206,848 bytes; at 4,096 bundles it emits 36,864 tokens and 413,696
bytes. Both runs record exactly 113,797 whole-fixture allocations, only four
above the unchanged 4,096-page path. Doubling tokens, source bytes, emitted
bytes, and byte visits therefore adds no allocation. The byte checksums are
1,416,541,943,808 and 5,666,285,907,968 respectively.

The all-value integration check stores and seals null, boolean, integer, real,
name, byte string, text string, reference, array, and dictionary values, then
compares their shared emitter output exactly. Allocation or work baseline
changes require a representation/ARC review rather than regeneration.
