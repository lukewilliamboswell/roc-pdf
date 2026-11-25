import fuzz.Solve
import pdf.KernelFileLayout

XrefSlotProof := [].{}

## All 47-bit stream ordinals and 16-bit member indices fit the tagged slot.
expect Solve.prove_within(
	{
		stream: Solve.u64_in(0, 0x7FFFFFFFFFFF),
		member: Solve.u64_in(0, 0xFFFF),
	}.Solve,
	|input| {
		slot = KernelFileLayout.CompressedSlot.pack(input.stream, input.member)
		Solve.all([
			KernelFileLayout.CompressedSlot.marker_bits(slot).eq(0x8000000000000000),
			KernelFileLayout.CompressedSlot.stream(slot).eq(input.stream),
			KernelFileLayout.CompressedSlot.member(slot).eq(input.member),
		])
	},
	1000,
) == Ok(Proved)

## Offsets in the untagged range always have the marker clear.
expect Solve.prove_within(
	Solve.u64_in(0, 0x7FFFFFFFFFFFFFFF),
	|offset| KernelFileLayout.CompressedSlot.marker_bits(offset).eq(0),
	1000,
) == Ok(Proved)

expect {
	stream = 0x7FFFFFFFFFFF
	member = 0xFFFF
	slot = KernelFileLayout.compressed_entry(stream, member)
	symbolic = KernelFileLayout.CompressedSlot.pack(Solve.Uint.from_u64(stream), Solve.Uint.from_u64(member))
	symbolic.eval() == Ok(slot) and
		KernelFileLayout.is_compressed_entry(slot) and
			KernelFileLayout.compressed_stream(slot) == stream and
				KernelFileLayout.compressed_member(slot) == member and
					!KernelFileLayout.is_compressed_entry(0x7FFFFFFFFFFFFFFF)
}
