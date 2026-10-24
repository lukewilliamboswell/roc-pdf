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

## The message schedule as a sliding window of its next 16 words. Each round
## consumes `w0` and shifts in the word 16 ahead, so hashing needs no
## schedule list: a fresh 64-word list per digest was one allocation for
## every name, string and payload digested.
Window : {
	w0 : U32,
	w1 : U32,
	w2 : U32,
	w3 : U32,
	w4 : U32,
	w5 : U32,
	w6 : U32,
	w7 : U32,
	w8 : U32,
	w9 : U32,
	w10 : U32,
	w11 : U32,
	w12 : U32,
	w13 : U32,
	w14 : U32,
	w15 : U32,
}

## One logical message assembled from a prefix and an exact range of a second
## already-owned list. Hashing reads both through index arithmetic, so a large
## payload is never copied into a concatenated digest input.
Parts : { input : List(U8), length : U64, prefix : List(U8), start : U64 }

KernelSha256 :: [].{
	Error : [InputTooLarge]

	digest : List(U8) -> Try(List(U8), Error)
	digest = |input| digest_message({ input, length: input.len(), prefix: [], start: 0 })

	## Digests `prefix` followed by `input[start .. start + length]`. The range
	## must already be validated by the caller; the payload allocation is read in
	## place rather than concatenated.
	digest_range : List(U8), List(U8), U64, U64 -> Try(List(U8), Error)
	digest_range = |prefix, input, start, length| digest_message({ input, length, prefix, start })

	## Appends the digest of `input` to `output`, so a caller accumulating
	## digests writes each one in place instead of copying a 32-byte list.
	append_digest : List(U8), List(U8) -> Try(List(U8), Error)
	append_digest = |output, input| {
		state = digest_state({ input, length: input.len(), prefix: [], start: 0 })?
		Ok(append_state(output, state))
	}
}

digest_message : Parts -> Try(List(U8), KernelSha256.Error)
digest_message = |parts| {
	state = digest_state(parts)?
	Ok(append_state(List.with_capacity(32), state))
}

digest_state : Parts -> Try(ShaState, KernelSha256.Error)
digest_state = |parts| {
	byte_length = parts.prefix.len() + parts.length
	if byte_length > 2305843009213693951 {
		Err(InputTooLarge)
	} else {
		bit_length = byte_length * 8
		with_marker_and_length = byte_length + 9
		blocks = ceil_div_64(with_marker_and_length)
		constants = round_constants
		var $state = initial_state
		var $block = 0
		while $block < blocks {
			$state = compress_block($state, parts, $block, blocks, bit_length, constants)
			$block = $block + 1
		}
		Ok($state)
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

compress_block : ShaState, Parts, U64, U64, U64, List(U32) -> ShaState
compress_block = |state, input, block, blocks, bit_length, constants| {
	block_start = block * 64
	word = |index| {
		byte_start = block_start + index * 4
		padded_byte(input, byte_start, blocks, bit_length).to_u32().shl_wrap(24)
			.bitwise_or(padded_byte(input, byte_start + 1, blocks, bit_length).to_u32().shl_wrap(16))
			.bitwise_or(padded_byte(input, byte_start + 2, blocks, bit_length).to_u32().shl_wrap(8))
			.bitwise_or(padded_byte(input, byte_start + 3, blocks, bit_length).to_u32())
	}
	var $window = {
		w0: word(0),
		w1: word(1),
		w2: word(2),
		w3: word(3),
		w4: word(4),
		w5: word(5),
		w6: word(6),
		w7: word(7),
		w8: word(8),
		w9: word(9),
		w10: word(10),
		w11: word(11),
		w12: word(12),
		w13: word(13),
		w14: word(14),
		w15: word(15),
	}

	var $working = state
	var $round = 0
	while $round < 64 {
		big_1 = rotate_right($working.e, 6).bitwise_xor(rotate_right($working.e, 11)).bitwise_xor(rotate_right($working.e, 25))
		choice = $working.e.bitwise_and($working.f).bitwise_xor($working.e.bitwise_xor(0xffffffff).bitwise_and($working.g))
		temporary_1 = add5($working.h, big_1, choice, word_at(constants, $round), $window.w0)
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
		$window = next_window($window)
		$round = $round + 1
	}

	{
		a: U32.plus_wrap(state.a, $working.a),
		b: U32.plus_wrap(state.b, $working.b),
		c: U32.plus_wrap(state.c, $working.c),
		d: U32.plus_wrap(state.d, $working.d),
		e: U32.plus_wrap(state.e, $working.e),
		f: U32.plus_wrap(state.f, $working.f),
		g: U32.plus_wrap(state.g, $working.g),
		h: U32.plus_wrap(state.h, $working.h),
	}
}

## Shifts in W[t + 16] = σ1(W[t + 14]) + W[t + 9] + σ0(W[t + 1]) + W[t].
next_window : Window -> Window
next_window = |window| {
	small_0 = rotate_right(window.w1, 7).bitwise_xor(rotate_right(window.w1, 18)).bitwise_xor(window.w1.shr_wrap(3))
	small_1 = rotate_right(window.w14, 17).bitwise_xor(rotate_right(window.w14, 19)).bitwise_xor(window.w14.shr_wrap(10))
	{
		w0: window.w1,
		w1: window.w2,
		w2: window.w3,
		w3: window.w4,
		w4: window.w5,
		w5: window.w6,
		w6: window.w7,
		w7: window.w8,
		w8: window.w9,
		w9: window.w10,
		w10: window.w11,
		w11: window.w12,
		w12: window.w13,
		w13: window.w14,
		w14: window.w15,
		w15: add4(window.w0, small_0, window.w9, small_1),
	}
}

padded_byte : Parts, U64, U64, U64 -> U8
padded_byte = |input, index, blocks, bit_length| {
	input_length = input.prefix.len() + input.length
	total_length = blocks * 64
	if index < input_length {
		message_byte(input, index)
	} else if index == input_length {
		128
	} else if index >= total_length - 8 {
		shift = ((total_length - 1 - index) * 8).to_u8_wrap()
		bit_length.shr_wrap(shift).to_u8_wrap()
	} else {
		0
	}
}

message_byte : Parts, U64 -> U8
message_byte = |parts, index| {
	prefix_length = parts.prefix.len()
	if index < prefix_length {
		byte_at(parts.prefix, index)
	} else {
		byte_at(parts.input, parts.start + (index - prefix_length))
	}
}

rotate_right : U32, U8 -> U32
rotate_right = |value, bits| value.shr_wrap(bits).bitwise_or(value.shl_wrap(32 - bits))

add4 : U32, U32, U32, U32 -> U32
add4 = |a, b, c, d| U32.plus_wrap(U32.plus_wrap(a, b), U32.plus_wrap(c, d))

add5 : U32, U32, U32, U32, U32 -> U32
add5 = |a, b, c, d, e| U32.plus_wrap(add4(a, b, c, d), e)

ceil_div_64 : U64 -> U64
ceil_div_64 = |value| U64.div_by(value, 64) + (if (U64.mod_by(value, 64) == 0) 0 else 1)

append_state : List(U8), ShaState -> List(U8)
append_state = |output, state| {
	var $bytes = output
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
		crash "SHA-256 round constant invariant failed"
	}
}

byte_at : List(U8), U64 -> U8
byte_at = |bytes, index| match bytes.get(index) {
	Ok(byte) => byte
	Err(OutOfBounds) => {
		crash "SHA-256 input invariant failed"
	}
}

# Empty input matches the NIST SHA-256 example digest.
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

# Multi-block input matches an independently published SHA-256 vector.
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

# Hashing an exact range of an owned allocation with a prefix equals hashing
# the concatenation, without materializing that concatenation.
expect {
	prefix = Str.to_utf8("abcdbcdecdefdefgefghfghighijhijk")
	payload = Str.to_utf8("XXXXijkljklmklmnlmnomnopnopqYYYY")
	KernelSha256.digest_range(prefix, payload, 4, 24)? == KernelSha256.digest(Str.to_utf8("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))?
}
