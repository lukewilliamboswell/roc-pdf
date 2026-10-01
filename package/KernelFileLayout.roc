import KernelObject

## The file layout facts that emission and the output bound share.
##
## Stream objects are top-level indirect objects. Every other sealed object is
## stored in a FlateDecode object stream (ISO 32000-2 7.5.7): in plan order,
## the compressible objects fill object streams of at most
## `max_objects_per_stream` members, the last one partly. The object streams
## take the object numbers after the planned objects, in order, and the
## cross-reference stream takes the number after them. The partition depends
## only on the plan's object order and kinds, so it is fixed before emission
## and never on byte sizes.
##
## ISO 32000-2 7.5.7 keeps stream objects, objects with a nonzero generation,
## the encryption dictionary, and the Length of an object stream out of object
## streams. The package writes only generation-zero objects, never encrypts,
## keeps every stream top-level, and gives object streams and the
## cross-reference stream direct lengths, so every non-stream object may be
## compressed.
KernelFileLayout :: [].{

	## Members per object stream.
	max_objects_per_stream : U64
	max_objects_per_stream = 400

	## Whether a sealed object is stored in an object stream.
	compressible : KernelObject.Store, KernelObject.Object -> Bool
	compressible = |store, object| match object.content {
		LengthOf(_) => True
		Stored(value_id) => match store.values.get(KernelObject.ValueId.index(value_id)) {
			Ok(Stream(_)) => False
			_ => True
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
	stream_count = |members| if members == 0 0 else U64.div_by(members - 1, KernelFileLayout.max_objects_per_stream) + 1

	## Emission keeps one `U64` per planned object for the cross-reference
	## stream: a file offset for a top-level object, or this marker with the
	## object stream ordinal and member index for a compressed one.
	compressed_entry : U64, U64 -> U64
	compressed_entry = |stream, member| compressed_marker.bitwise_or(stream.shl_wrap(16)).bitwise_or(member)

	is_compressed_entry : U64 -> Bool
	is_compressed_entry = |entry| entry.bitwise_and(compressed_marker) != 0

	compressed_stream : U64 -> U64
	compressed_stream = |entry| entry.bitwise_and(compressed_marker - 1).shr_wrap(16)

	compressed_member : U64 -> U64
	compressed_member = |entry| entry.bitwise_and(0xFFFF)

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

compressed_marker : U64
compressed_marker = 0x8000000000000000

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
