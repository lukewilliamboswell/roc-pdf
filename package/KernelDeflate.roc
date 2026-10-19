import deflate.Deflate

## The package's one DEFLATE seam: zlib framing (RFC 1950) around the pinned
## pure-Roc `roc-deflate` compressor, a port of libdeflate.
##
## `compress_raw` is the only call into the dependency. Everything the
## package relies on is checked here rather than trusted: limits and a
## checked output bound are proven before a plan escapes, the compressed
## length is compared against that bound, and the zlib header and Adler-32
## trailer are package code. The level is an explicit `Level` carried by
## each plan, one of three package-versioned values, so identical input at
## an identical level always produces identical bytes.
KernelDeflate :: [].{

	## A package-versioned libdeflate level. Only the three constructors
	## below exist: `fastest` (1), `balanced` (6), and `smallest` (10, the
	## first near-optimal parsing level).
	## development/performance/output-size.md records the measurements
	## behind each.
	Level :: U64.{
		is_eq : _

		fastest : Level
		fastest = Level.(1)

		balanced : Level
		balanced = Level.(6)

		smallest : Level
		smallest = Level.(10)

		## The libdeflate level number.
		libdeflate : Level -> U64
		libdeflate = |Level.(level)| level

		## The zlib FLG byte (RFC 1950): the FLEVEL libdeflate writes for the
		## level (0 at level 1, 2 at level 6, 3 at level 10) with the FCHECK
		## bits that make the header a multiple of 31.
		zlib_flag : Level -> U8
		zlib_flag = |Level.(level)| if level < 2 {
			1
		} else if level == 6 {
			156
		} else {
			218
		}
	}

	Error : [
		ArithmeticOverflow,
		CompressorFailed,
		InputLimitExceeded({ attempted : U64, limit : U64 }),
		OutputBoundExceeded({ bound : U64, attempted : U64 }),
		OutputLimitExceeded({ attempted : U64, limit : U64 }),
	]

	Limits :: {
		max_input_bytes : U64,
		max_output_bytes : U64,
	}.{
		make : { max_input_bytes : U64, max_output_bytes : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	## Deterministic compression work: streams compressed, bytes read, and
	## bytes emitted, plus the largest single emitted stream.
	Work :: {
		emitted_bytes : U64,
		input_bytes : U64,
		max_chunk_bytes : U64,
		streams : U64,
	}.{
		zero : Work
		zero = Work.{
			emitted_bytes: 0,
			input_bytes: 0,
			max_chunk_bytes: 0,
			streams: 0,
		}

		add : Work, Work -> Try(Work, Error)
		add = |left, right| add_work_totals(left, right)

		emitted_bytes : Work -> U64
		emitted_bytes = |work| work.emitted_bytes

		input_bytes : Work -> U64
		input_bytes = |work| work.input_bytes

		max_chunk_bytes : Work -> U64
		max_chunk_bytes = |work| work.max_chunk_bytes

		streams : Work -> U64
		streams = |work| work.streams
	}

	Plan :: {
		input : List(U8),
		level : Level,
		output_bound : U64,
	}.{
		prepare : List(U8), Level, Limits -> Try(Plan, Error)
		prepare = |input, level, limits| prepare_plan(input, level, limits)

		input_bytes : Plan -> U64
		input_bytes = |plan| plan.input.len()

		level : Plan -> Level
		level = |plan| plan.level

		output_bound : Plan -> U64
		output_bound = |plan| plan.output_bound
	}

	## The checked upper bound of one zlib stream over `input_bytes` bytes at
	## every level: the stored-block bound does not depend on the level.
	output_bound : U64 -> Try(U64, Error)
	output_bound = |input_bytes| compressed_output_bound(input_bytes)

	## Compresses a prepared plan into one complete zlib stream.
	to_bytes : Plan -> Try({ bytes : List(U8), work : Work }, Error)
	to_bytes = |plan| compress_plan(plan)
}

## Inputs above 2^56 bytes are refused before any arithmetic, so every sum
## below stays far from overflow.
max_supported_input : U64
max_supported_input = 72057594037927936

adler_modulus : U64
adler_modulus = 65521

## The canonical empty zlib stream: header, one empty fixed-Huffman final
## block, and the Adler-32 of no bytes.
empty_stream : List(U8)
empty_stream = [120, 156, 3, 0, 0, 0, 0, 1]

prepare_plan : List(U8), KernelDeflate.Level, KernelDeflate.Limits -> Try(KernelDeflate.Plan, KernelDeflate.Error)
prepare_plan = |input, level, limits| {
	input_bytes = input.len()
	if input_bytes > limits.max_input_bytes {
		Err(InputLimitExceeded({ attempted: input_bytes, limit: limits.max_input_bytes }))
	} else {
		bound = compressed_output_bound(input_bytes)?
		if bound > limits.max_output_bytes {
			Err(OutputLimitExceeded({ attempted: bound, limit: limits.max_output_bytes }))
		} else {
			Ok(KernelDeflate.Plan.{ input, level, output_bound: bound })
		}
	}
}

## The dependency's `compress_bound` (all stored blocks, five header bytes
## each) plus the two-byte zlib header and four-byte Adler-32 trailer.
compressed_output_bound : U64 -> Try(U64, KernelDeflate.Error)
compressed_output_bound = |input_bytes| {
	if input_bytes == 0 {
		Ok(empty_stream.len())
	} else if input_bytes > max_supported_input {
		Err(ArithmeticOverflow)
	} else {
		Ok(Deflate.compress_bound(input_bytes) + 6)
	}
}

compress_plan : KernelDeflate.Plan -> Try({ bytes : List(U8), work : KernelDeflate.Work }, KernelDeflate.Error)
compress_plan = |plan| {
	input = plan.input
	if input.is_empty() {
		Ok({ bytes: empty_stream, work: stream_work(0, empty_stream.len()) })
	} else {
		raw = compress_raw(input, plan.level)?
		checksum = adler32(input)
		var $bytes = List.with_capacity(raw.len() + 6)

		## CMF 0x78 (DEFLATE, 32 KiB window) and the level's FLG byte.
		$bytes = $bytes.append(120).append(KernelDeflate.Level.zlib_flag(plan.level))
		$bytes = append_all($bytes, raw)
		$bytes = $bytes
			.append(checksum.shr_wrap(24).to_u8_wrap())
			.append(checksum.shr_wrap(16).to_u8_wrap())
			.append(checksum.shr_wrap(8).to_u8_wrap())
			.append(checksum.to_u8_wrap())
		if $bytes.len() > plan.output_bound {
			Err(OutputBoundExceeded({ bound: plan.output_bound, attempted: $bytes.len() }))
		} else {
			work = stream_work(input.len(), $bytes.len())
			Ok({ bytes: $bytes, work })
		}
	}
}

## The single call into the DEFLATE dependency.
compress_raw : List(U8), KernelDeflate.Level -> Try(List(U8), KernelDeflate.Error)
compress_raw = |input, level| match Deflate.compress(input, KernelDeflate.Level.libdeflate(level)) {
	Ok(raw) => Ok(raw)
	Err(CompressBug) => Err(CompressorFailed)
}

stream_work : U64, U64 -> KernelDeflate.Work
stream_work = |input_bytes, emitted_bytes| KernelDeflate.Work.{
	emitted_bytes,
	input_bytes,
	max_chunk_bytes: emitted_bytes,
	streams: 1,
}

adler32 : List(U8) -> U64
adler32 = |bytes| {
	var $a = 1
	var $b = 0
	var $index = 0
	while $index < bytes.len() {
		$a = U64.mod_by($a + list_at_u8(bytes, $index).to_u64(), adler_modulus)
		$b = U64.mod_by($b + $a, adler_modulus)
		$index = $index + 1
	}
	$b.shl_wrap(16).bitwise_or($a)
}

add_work_totals : KernelDeflate.Work, KernelDeflate.Work -> Try(KernelDeflate.Work, KernelDeflate.Error)
add_work_totals = |left, right| {
	Ok(
		KernelDeflate.Work.{
			emitted_bytes: checked_add(left.emitted_bytes, right.emitted_bytes)?,
			input_bytes: checked_add(left.input_bytes, right.input_bytes)?,
			max_chunk_bytes: U64.max(left.max_chunk_bytes, right.max_chunk_bytes),
			streams: checked_add(left.streams, right.streams)?,
		},
	)
}

checked_add : U64, U64 -> Try(U64, KernelDeflate.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(total) => Ok(total)
}

## Appends every element of `source`. It deliberately does not
## `List.reserve` first: an explicit reserve sizes the allocation exactly, so
## a target that keeps growing was reallocated on every call, while `append`
## grows geometrically and keeps accumulation amortized linear.
append_all : List(U8), List(U8) -> List(U8)
append_all = |target, source| {
	var $out = target
	var $index = 0
	while $index < source.len() {
		$out = $out.append(list_at_u8(source, $index))
		$index = $index + 1
	}
	$out
}

list_at_u8 : List(U8), U64 -> U8
list_at_u8 = |list, index| match list.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "DEFLATE byte index invariant failed"
	}
}

inflate : List(U8) -> List(U8)
inflate = |zlib| {
	raw = zlib.sublist({ start: 2, len: zlib.len() - 6 })
	match Deflate.decompress(raw) {
		Ok(bytes) => bytes
		Err(_) => [0xde, 0xad]
	}
}

# The canonical empty stream keeps the compact fixed-block representation.
expect {
	plan = KernelDeflate.Plan.prepare([], KernelDeflate.Level.balanced, KernelDeflate.Limits.make({ max_input_bytes: 0, max_output_bytes: 8 }))?
	result = KernelDeflate.to_bytes(plan)?
	result.bytes == [120, 156, 3, 0, 0, 0, 0, 1] and KernelDeflate.Work.streams(result.work) == 1
}

# Limits reject input and output bounds before compression begins.
expect {
	input = [1, 2, 3]
	too_much_input = KernelDeflate.Plan.prepare(input, KernelDeflate.Level.balanced, KernelDeflate.Limits.make({ max_input_bytes: 2, max_output_bytes: 100 }))
	too_much_output = KernelDeflate.Plan.prepare(input, KernelDeflate.Level.balanced, KernelDeflate.Limits.make({ max_input_bytes: 3, max_output_bytes: 1 }))
	match too_much_input {
		Err(InputLimitExceeded({ attempted, limit })) => attempted == 3 and limit == 2
		_ => False
	} and match too_much_output {
		Err(OutputLimitExceeded({ attempted, limit })) => attempted > 1 and limit == 1
		_ => False
	}
}

# A nonempty stream is framed, checksummed, round-trips, and stays under its
# bound at every level, with the level's FLEVEL in a valid zlib header.
expect {
	input = Str.to_utf8("the cat, the cat, the cat, the cat, the cat, the cat, the cat")
	framed(input, KernelDeflate.Level.fastest, 1) and
		framed(input, KernelDeflate.Level.balanced, 156) and
			framed(input, KernelDeflate.Level.smallest, 218)
}

# Higher levels never produce a longer stream on repetitive content.
expect {
	input = Str.to_utf8("BT /F1 12 Tf [<0001> -3 <0002>] TJ ET\nBT /F1 12 Tf [<0003> -3 <0004>] TJ ET\nBT /F1 12 Tf [<0001> -3 <0002>] TJ ET\n0 0 1 rg 10 10 m 20 20 l S\n")
	fastest = compressed_length(input, KernelDeflate.Level.fastest)
	balanced = compressed_length(input, KernelDeflate.Level.balanced)
	smallest = compressed_length(input, KernelDeflate.Level.smallest)
	smallest > 0 and smallest <= balanced and balanced <= fastest
}

# Incompressible input stays inside the stored-block bound.
expect {
	input = List.repeat(0, 12000).map_with_index(|_, index| ((index * 2654435761).shr_wrap(13)).to_u8_wrap())
	bound = KernelDeflate.output_bound(input.len())?
	plan = KernelDeflate.Plan.prepare(input, KernelDeflate.Level.balanced, KernelDeflate.Limits.make({ max_input_bytes: input.len(), max_output_bytes: bound }))?
	result = KernelDeflate.to_bytes(plan)?
	result.bytes.len() <= bound and inflate(result.bytes) == input
}

# Compression is deterministic: equal input gives equal bytes.
expect {
	input = Str.to_utf8("BT /F1 12 Tf [<0001> -3 <0002>] TJ ET\nBT /F1 12 Tf [<0001> -3 <0002>] TJ ET\n")
	bound = KernelDeflate.output_bound(input.len())?
	limits = KernelDeflate.Limits.make({ max_input_bytes: input.len(), max_output_bytes: bound })
	first = KernelDeflate.to_bytes(KernelDeflate.Plan.prepare(input, KernelDeflate.Level.balanced, limits)?)?
	second = KernelDeflate.to_bytes(KernelDeflate.Plan.prepare(List.concat([], input), KernelDeflate.Level.balanced, limits)?)?
	first.bytes == second.bytes
}

# Adler-32 of "Wikipedia" is the RFC 1950 worked value 0x11E60398.
expect adler32(Str.to_utf8("Wikipedia")) == 0x11E60398

framed : List(U8), KernelDeflate.Level, U8 -> Bool
framed = |input, level, flag| {
	bound = match KernelDeflate.output_bound(input.len()) {
		Ok(value) => value
		Err(_) => 0
	}
	match KernelDeflate.Plan.prepare(input, level, KernelDeflate.Limits.make({ max_input_bytes: input.len(), max_output_bytes: bound })) {
		Err(_) => False
		Ok(plan) => match KernelDeflate.to_bytes(plan) {
			Err(_) => False
			Ok(result) => {
				header = result.bytes.sublist({ start: 0, len: 2 })
				trailer = result.bytes.sublist({ start: result.bytes.len() - 4, len: 4 })
				checksum = adler32(input)
				header == [120, flag] and
					(120 * 256 + flag.to_u64()) % 31 == 0 and
						trailer == [checksum.shr_wrap(24).to_u8_wrap(), checksum.shr_wrap(16).to_u8_wrap(), checksum.shr_wrap(8).to_u8_wrap(), checksum.to_u8_wrap()] and
							inflate(result.bytes) == input and
								result.bytes.len() < input.len() and
									result.bytes.len() <= bound and
										KernelDeflate.Work.input_bytes(result.work) == input.len() and
											KernelDeflate.Work.emitted_bytes(result.work) == result.bytes.len()
			}
		}
	}
}

compressed_length : List(U8), KernelDeflate.Level -> U64
compressed_length = |input, level| {
	limits = KernelDeflate.Limits.make({ max_input_bytes: input.len(), max_output_bytes: input.len() + 64 })
	match KernelDeflate.Plan.prepare(input, level, limits) {
		Err(_) => 0
		Ok(plan) => match KernelDeflate.to_bytes(plan) {
			Err(_) => 0
			Ok(result) => result.bytes.len()
		}
	}
}
