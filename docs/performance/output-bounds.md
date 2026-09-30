# structural-kernel structural output bounds

> **Current layout.** Since the output-size work every plan's stored bound is
> computed by `KernelOutputBound.calculate` over the sealed objects under the
> object-stream layout; see "Object-stream layout bound" below. The formula
> in the next sections remains the checked pre-allocation guard for blank
> plans.

## Scope

The current `KernelStructure.Plan` represents one through 1,048,576 blank
pages, an evidence-only one-page unchanged-stream variant, and an evidence-only
one-page generated compressed-stream variant. Its lowerer computes and stores a
checked byte bound before allocating the object stores. `KernelEmit` carries
that scalar through every state and checks each transition against it as an
internal invariant. Therefore an accepted plan cannot discover a size-bound
error after returning output.

The bound for this plan kind is:

```text
4096 + 1024 * page_count + payload_bytes
```

Both the multiplication and additions use checked `U64` operations. Blank
plans use zero payload bytes; at the maximum accepted page count their bound is
1,073,745,920 bytes. The unchanged-stream plan adds the exact unfiltered byte
length. The generated-stream plan adds its checked compressor bound.

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

The unchanged unfiltered stream omits `/FlateDecode`, so the blank-plan syntax
allowance remains conservative and its exact payload length is the only added
term. For non-empty generated input of `m` bytes split into
`b = ceil(m / 65535)` blocks, `KernelDeflate` proves and adds
`6 + ceil((9m + 349b) / 8)`. Nine bits per input byte covers literal-only
encoding, 349 bits per block covers the dynamic declaration, header,
end-of-block symbol, and rounding allowance, and six bytes cover the zlib
header and Adler-32 trailer. Input, multiplication, addition, and total-output
limits are checked before the plan escapes.

This proof otherwise depends on the current structural representation, fixed
fanout, fixed-width xref format, and DEFLATE byte policy. Changing any of those
requires reviewing the constants rather than accepting a snapshot or
allocation change mechanically.

## Executable evidence

Focused Roc tests assert the bound at the maximum accepted page count and
compare the stored plan bound with actual 4,096-page emission. Other focused
tests reject compression-limit and arithmetic failures before emission and
assert that actual multi-block compressed output stays within its stored bound.
The optimized scenarios independently record the exact 1,084,927-byte balanced
page output and 2,527-byte generated-stream output.

A separate counting sink starts above `2^32`, records an object offset, advances
without allocating the represented bytes, and verifies the exact 11-byte xref
entry. It also rejects `U64` position overflow. This proves that offset
accounting and fixed-width serialization remain 64-bit beyond 4 GiB without a
multi-gigabyte fixture allocation.

## Object-stream layout bound

`KernelOutputBound.calculate` walks the sealed objects once in plan order and
applies the same partition as emission (`KernelFileLayout`):

- A stream object is bounded as a top-level object, exactly as before: its
  header, dictionary value bound with the generated `/Filter` and `/Length`
  entries, framing, and payload bound (a DEFLATE bound for generated
  payloads).
- Every other object is bounded as an object-stream member: its value bound
  (or the digits of its stream's payload bound for a length object) plus 43
  bytes for its header pair (two numbers of at most 20 digits, two spaces)
  and newline.
- Each object stream closed by the partition (every 400 members, and the last
  partial batch) adds the DEFLATE bound of its members plus the header's
  newline, and 256 bytes of framing: its object header, a dictionary with at
  most three 20-digit numbers, and the stream keywords.
- The cross-reference stream adds the DEFLATE bound of 12 bytes per row (a
  predictor byte, the type, at most eight offset bytes, and two index bytes)
  over every object including zero, the object streams, and itself, plus 512
  bytes of dictionary and the `startxref` trailer with the digits of the
  running bound.

The DEFLATE bound is the dependency's stored-block bound (five bytes per
5,000-byte block beyond the input, at least one block) plus six zlib framing
bytes, so every term is an upper bound of what emission writes whatever the
compressor finds. Every addition and multiplication is checked. The emitter
still compares its position with the stored bound at every segment.
