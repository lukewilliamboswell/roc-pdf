ShaState : {
	a : U32,
	b : U32,
	c : U32,
	d : U32,
	e : U32,
	f : U32,
	g : U32,
	h : U32,
}

CompressResult : { schedule : List(U32), state : ShaState }

KernelSha256 :: [].{
	Error : [InputTooLarge]

	digest : List(U8) -> Try(List(U8), Error)
	digest = |input| {
		byte_length = input.len()
		if byte_length > 2305843009213693951 {
			Err(InputTooLarge)
		} else {
			bit_length = byte_length * 8
			with_marker_and_length = byte_length + 9
			blocks = ceil_div_64(with_marker_and_length)
			constants = round_constants
			var $state = initial_state
			var $schedule = List.repeat(0, 64)
			var $block = 0
			while $block < blocks {
				compressed = compress_block($state, input, $block, blocks, bit_length, constants, $schedule)
				$state = compressed.state
				$schedule = compressed.schedule
				$block = $block + 1
			}
			Ok(state_bytes($state))
		}
	}
}

initial_state : ShaState
initial_state = {
	a: 0x6a09e667,
	b: 0xbb67ae85,
	c: 0x3c6ef372,
	d: 0xa54ff53a,
	e: 0x510e527f,
	f: 0x9b05688c,
	g: 0x1f83d9ab,
	h: 0x5be0cd19,
}

round_constants : List(U32)
round_constants = [
	0x428a2f98,
	0x71374491,
	0xb5c0fbcf,
	0xe9b5dba5,
	0x3956c25b,
	0x59f111f1,
	0x923f82a4,
	0xab1c5ed5,
	0xd807aa98,
	0x12835b01,
	0x243185be,
	0x550c7dc3,
	0x72be5d74,
	0x80deb1fe,
	0x9bdc06a7,
	0xc19bf174,
	0xe49b69c1,
	0xefbe4786,
	0x0fc19dc6,
	0x240ca1cc,
	0x2de92c6f,
	0x4a7484aa,
	0x5cb0a9dc,
	0x76f988da,
	0x983e5152,
	0xa831c66d,
	0xb00327c8,
	0xbf597fc7,
	0xc6e00bf3,
	0xd5a79147,
	0x06ca6351,
	0x14292967,
	0x27b70a85,
	0x2e1b2138,
	0x4d2c6dfc,
	0x53380d13,
	0x650a7354,
	0x766a0abb,
	0x81c2c92e,
	0x92722c85,
	0xa2bfe8a1,
	0xa81a664b,
	0xc24b8b70,
	0xc76c51a3,
	0xd192e819,
	0xd6990624,
	0xf40e3585,
	0x106aa070,
	0x19a4c116,
	0x1e376c08,
	0x2748774c,
	0x34b0bcb5,
	0x391c0cb3,
	0x4ed8aa4a,
	0x5b9cca4f,
	0x682e6ff3,
	0x748f82ee,
	0x78a5636f,
	0x84c87814,
	0x8cc70208,
	0x90befffa,
	0xa4506ceb,
	0xbef9a3f7,
	0xc67178f2,
]

compress_block : ShaState, List(U8), U64, U64, U64, List(U32), List(U32) -> CompressResult
compress_block = |state, input, block, blocks, bit_length, constants, schedule| {
	block_start = block * 64
	var $schedule = schedule
	var $word = 0
	while $word < 16 {
		byte_start = block_start + $word * 4
		value = padded_byte(input, byte_start, blocks, bit_length).to_u32().shl_wrap(24)
			.bitwise_or(padded_byte(input, byte_start + 1, blocks, bit_length).to_u32().shl_wrap(16))
			.bitwise_or(padded_byte(input, byte_start + 2, blocks, bit_length).to_u32().shl_wrap(8))
			.bitwise_or(padded_byte(input, byte_start + 3, blocks, bit_length).to_u32())
		$schedule = word_set($schedule, $word, value)
		$word = $word + 1
	}
	while $word < 64 {
		before_15 = word_at($schedule, $word - 15)
		before_2 = word_at($schedule, $word - 2)
		small_0 = rotate_right(before_15, 7).bitwise_xor(rotate_right(before_15, 18)).bitwise_xor(before_15.shr_wrap(3))
		small_1 = rotate_right(before_2, 17).bitwise_xor(rotate_right(before_2, 19)).bitwise_xor(before_2.shr_wrap(10))
		value = add4(word_at($schedule, $word - 16), small_0, word_at($schedule, $word - 7), small_1)
		$schedule = word_set($schedule, $word, value)
		$word = $word + 1
	}

	var $working = state
	var $round = 0
	while $round < 64 {
		big_1 = rotate_right($working.e, 6).bitwise_xor(rotate_right($working.e, 11)).bitwise_xor(rotate_right($working.e, 25))
		choice = $working.e.bitwise_and($working.f).bitwise_xor($working.e.bitwise_xor(0xffffffff).bitwise_and($working.g))
		temporary_1 = add5($working.h, big_1, choice, word_at(constants, $round), word_at($schedule, $round))
		big_0 = rotate_right($working.a, 2).bitwise_xor(rotate_right($working.a, 13)).bitwise_xor(rotate_right($working.a, 22))
		majority = $working.a.bitwise_and($working.b).bitwise_xor($working.a.bitwise_and($working.c)).bitwise_xor($working.b.bitwise_and($working.c))
		temporary_2 = U32.plus_wrap(big_0, majority)
		$working = {
			a: U32.plus_wrap(temporary_1, temporary_2),
			b: $working.a,
			c: $working.b,
			d: $working.c,
			e: U32.plus_wrap($working.d, temporary_1),
			f: $working.e,
			g: $working.f,
			h: $working.g,
		}
		$round = $round + 1
	}

	{
		schedule: $schedule,
		state: {
			a: U32.plus_wrap(state.a, $working.a),
			b: U32.plus_wrap(state.b, $working.b),
			c: U32.plus_wrap(state.c, $working.c),
			d: U32.plus_wrap(state.d, $working.d),
			e: U32.plus_wrap(state.e, $working.e),
			f: U32.plus_wrap(state.f, $working.f),
			g: U32.plus_wrap(state.g, $working.g),
			h: U32.plus_wrap(state.h, $working.h),
		},
	}
}

padded_byte : List(U8), U64, U64, U64 -> U8
padded_byte = |input, index, blocks, bit_length| {
	input_length = input.len()
	total_length = blocks * 64
	if index < input_length {
		byte_at(input, index)
	} else if index == input_length {
		128
	} else if index >= total_length - 8 {
		shift = ((total_length - 1 - index) * 8).to_u8_wrap()
		bit_length.shr_wrap(shift).to_u8_wrap()
	} else {
		0
	}
}

rotate_right : U32, U8 -> U32
rotate_right = |value, bits| value.shr_wrap(bits).bitwise_or(value.shl_wrap(32 - bits))

add4 : U32, U32, U32, U32 -> U32
add4 = |a, b, c, d| U32.plus_wrap(U32.plus_wrap(a, b), U32.plus_wrap(c, d))

add5 : U32, U32, U32, U32, U32 -> U32
add5 = |a, b, c, d, e| U32.plus_wrap(add4(a, b, c, d), e)

ceil_div_64 : U64 -> U64
ceil_div_64 = |value| U64.div_by(value, 64) + (if U64.mod_by(value, 64) == 0 0 else 1)

state_bytes : ShaState -> List(U8)
state_bytes = |state| {
	var $bytes = List.with_capacity(32)
	$bytes = append_word($bytes, state.a)
	$bytes = append_word($bytes, state.b)
	$bytes = append_word($bytes, state.c)
	$bytes = append_word($bytes, state.d)
	$bytes = append_word($bytes, state.e)
	$bytes = append_word($bytes, state.f)
	$bytes = append_word($bytes, state.g)
	append_word($bytes, state.h)
}

append_word : List(U8), U32 -> List(U8)
append_word = |output, word| output
	.append(word.shr_wrap(24).to_u8_wrap())
	.append(word.shr_wrap(16).to_u8_wrap())
	.append(word.shr_wrap(8).to_u8_wrap())
	.append(word.to_u8_wrap())

word_at : List(U32), U64 -> U32
word_at = |words, index| match words.get(index) {
	Ok(word) => word
	Err(OutOfBounds) => {
		crash "SHA-256 schedule invariant failed"
	}
}

word_set : List(U32), U64, U32 -> List(U32)
word_set = |words, index, value| match words.set(index, value) {
	Ok(updated) => updated
	Err(OutOfBounds) => {
		crash "SHA-256 schedule update invariant failed"
	}
}

byte_at : List(U8), U64 -> U8
byte_at = |bytes, index| match bytes.get(index) {
	Ok(byte) => byte
	Err(OutOfBounds) => {
		crash "SHA-256 input invariant failed"
	}
}

## Empty input matches the NIST SHA-256 example digest.
expect KernelSha256.digest([])? == [
	0xe3,
	0xb0,
	0xc4,
	0x42,
	0x98,
	0xfc,
	0x1c,
	0x14,
	0x9a,
	0xfb,
	0xf4,
	0xc8,
	0x99,
	0x6f,
	0xb9,
	0x24,
	0x27,
	0xae,
	0x41,
	0xe4,
	0x64,
	0x9b,
	0x93,
	0x4c,
	0xa4,
	0x95,
	0x99,
	0x1b,
	0x78,
	0x52,
	0xb8,
	0x55,
]

## Multi-block input matches an independently published SHA-256 vector.
expect KernelSha256.digest(Str.to_utf8("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))? == [
	0x24,
	0x8d,
	0x6a,
	0x61,
	0xd2,
	0x06,
	0x38,
	0xb8,
	0xe5,
	0xc0,
	0x26,
	0x93,
	0x0c,
	0x3e,
	0x60,
	0x39,
	0xa3,
	0x3c,
	0xe4,
	0x59,
	0x64,
	0xff,
	0x21,
	0x67,
	0xf6,
	0xec,
	0xed,
	0xd4,
	0x19,
	0xdb,
	0x06,
	0xc1,
]
