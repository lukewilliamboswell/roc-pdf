import KernelObject

## The file layout facts that emission and the output bound share.
##
## Streams and objects consisting solely of a reference stay top-level.
## Other sealed objects fill FlateDecode object streams in plan order
## (ISO 32000-2 §7.5.7). Each stream holds at most
## `max_objects_per_stream` members, the last one partly. The object streams
## take the object numbers after the planned objects, in order, and the
## cross-reference stream takes the number after them. The partition depends
## only on the plan's object order and kinds, so it is fixed before emission
## and never on byte sizes.
##
## ISO 32000-2 7.5.7 keeps stream objects, objects with a nonzero generation,
## the encryption dictionary, the Length of an object stream, and an object
## consisting solely of a reference out of object streams. The package writes
## generation-zero objects without encryption, keeps every stream top-level,
## and gives object streams and the cross-reference stream direct lengths.
KernelFileLayout :: [].{

	## Members per object stream.
	max_objects_per_stream : U64
	max_objects_per_stream = 400

	StoredPlacement : [ObjectMember, TopLevelReference(KernelObject.ObjectId), TopLevelStream(KernelObject.StreamId)]

	stored_placement : KernelObject.Value -> StoredPlacement
	stored_placement = |value| match value {
		Reference(object) => TopLevelReference(object)
		Stream(stream) => TopLevelStream(stream)
		_ => ObjectMember
	}

	## Whether a sealed object is stored in an object stream.
	compressible : KernelObject.Store, KernelObject.Object -> Bool
	compressible = |store, object| match object.content {
		LengthOf(_) => True
		Stored(value_id) => match store.values.get(KernelObject.ValueId.index(value_id)) {
			Ok(value) => match stored_placement(value) {
				ObjectMember => True
				_ => False
			}
			Err(OutOfBounds) => True
		}
	}

	## The number of compressible objects in a store.
	compressible_count : KernelObject.Store -> U64
	compressible_count = |store| {
		var $count = 0
		var $index = 0
		while $index < store.objects.len() {
			match store.objects.get($index) {
				Ok(object) => if KernelFileLayout.compressible(store, object) {
					$count = $count + 1
				}
				Err(OutOfBounds) => {}
			}
			$index = $index + 1
		}
		$count
	}

	## Object streams needed for `compressible` objects.
	stream_count : U64 -> U64
	stream_count = |members| if (members == 0) 0 else U64.div_by(members - 1, KernelFileLayout.max_objects_per_stream) + 1

	## Emission keeps one `U64` per planned object for the cross-reference
	## stream: a file offset for a top-level object, or this marker with the
	## object stream ordinal and member index for a compressed one.
	compressed_entry : U64, U64 -> U64
	compressed_entry = |stream, member| CompressedSlot.pack(stream, member)

	is_compressed_entry : U64 -> Bool
	is_compressed_entry = |entry| CompressedSlot.marker_bits(entry) != 0

	compressed_stream : U64 -> U64
	compressed_stream = |entry| CompressedSlot.stream(entry)

	compressed_member : U64 -> U64
	compressed_member = |entry| CompressedSlot.member(entry)

	## The high bit tags compressed slots. The next 47 bits hold the stream
	## ordinal, and the low 16 bits hold the member index. These expressions
	## are shared by the concrete operations and the arithmetic proofs.
	CompressedSlot :: [].{
		pack = |stream_index, member_index| stream_index.shl_wrap(16).bitwise_or(0x8000000000000000).bitwise_or(member_index)
		marker_bits = |entry| entry.bitwise_and(0x8000000000000000)
		stream = |entry| entry.bitwise_and(0x7FFFFFFFFFFFFFFF).shr_wrap(16)
		member = |entry| entry.bitwise_and(0xFFFF)
	}

	## Bytes needed to write `value` big-endian, at least one.
	byte_width : U64 -> U64
	byte_width = |value| {
		var $width = 1
		var $rest = value.shr_wrap(8)
		while $rest > 0 {
			$width = $width + 1
			$rest = $rest.shr_wrap(8)
		}
		$width
	}
}

expect KernelFileLayout.stream_count(0) == 0 and
	KernelFileLayout.stream_count(1) == 1 and
		KernelFileLayout.stream_count(400) == 1 and
			KernelFileLayout.stream_count(401) == 2

expect {
	entry = KernelFileLayout.compressed_entry(3, 199)
	KernelFileLayout.is_compressed_entry(entry) and
		KernelFileLayout.compressed_stream(entry) == 3 and
			KernelFileLayout.compressed_member(entry) == 199 and
				!KernelFileLayout.is_compressed_entry(4096)
}

expect KernelFileLayout.byte_width(0) == 1 and
	KernelFileLayout.byte_width(255) == 1 and
		KernelFileLayout.byte_width(256) == 2 and
			KernelFileLayout.byte_width(4294967296) == 5
