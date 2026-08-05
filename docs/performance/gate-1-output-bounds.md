# Gate 1 structural output bounds

## Scope

The current `KernelStructure.Plan` represents one through 1,048,576 blank
pages. Its lowerer computes and stores a checked byte bound before allocating
the object stores. `KernelEmit` carries that scalar through every state and
checks each transition against it as an internal invariant. Therefore an
accepted plan cannot discover a size-bound error after returning output.

The bound for this plan kind is:

```text
4096 + 1024 * page_count
```

Both the multiplication and addition use checked `U64` operations. At the
maximum accepted page count the bound is 1,073,745,920 bytes. Future plan kinds
with unchanged resources or non-empty compressed streams must add their own
checked payload and compression bounds before they can enter the same sealed
plan.

## Derivation

Let `p` be the page count and `n` the number of page-tree nodes. The fixed
fanout-32, left-packed shape has `n <= p`: the one-page case has one node; for
larger inputs the first node level is at most half the page count and every
higher non-singleton level is at most half the preceding level.

The maximum accepted plan consequently has at most `1 + n + 3p` sealed
objects: one catalog, `n` page-tree nodes, and one page, stream, and indirect
length object per page. Including the xref-stream object, every object number,
page count, and xref size has at most seven decimal digits. The whole-file
bound itself has ten digits.

The serializer's conservative component bounds are:

| Component | Bound |
| --- | ---: |
| One page dictionary, empty DEFLATE stream, and length object | 384 bytes |
| One fanout-32 page-tree object, including 32 maximum-width references | 512 bytes |
| One fixed-width `[1 8 2]` xref entry | 11 bytes |

Pages and their possible tree node therefore consume at most `896p` bytes.
The xref stream has at most `3 + n + 3p <= 3 + 4p` entries, contributing at
most `44p + 33` bytes. Their combined variable contribution is at most
`940p + 33`, below the declared `1024p` term. The 4,096-byte fixed allowance
covers the header and binary marker, catalog, xref object header and
dictionary (including both 32-byte identifiers), stream framing,
`startxref`, EOF marker, and the constant 33 xref bytes with ample margin.

This proof depends on the current blank structural representation, fixed
fanout, fixed-width xref format, and empty eight-byte zlib stream. Changing any
of those requires reviewing the constants rather than accepting a snapshot or
allocation change mechanically.

## Executable evidence

Focused Roc tests assert the bound at the maximum accepted page count and
compare the stored plan bound with actual 4,096-page emission. The optimized
scenario independently records the exact 1,084,927-byte output and every
emitted-byte visit.

A separate counting sink starts above `2^32`, records an object offset, advances
without allocating the represented bytes, and verifies the exact 11-byte xref
entry. It also rejects `U64` position overflow. This proves that offset
accounting and fixed-width serialization remain 64-bit beyond 4 GiB without a
multi-gigabyte fixture allocation.
