## SHA-256 identity bytes come from the language's digest implementation.
## Prefix/range hashing borrows the selected bytes rather than concatenating
## a potentially large identity payload.
KernelSha256 :: [].{
	Error : [InputTooLarge]

	## Largest byte-aligned input representable by the SHA-256 bit count.
	max_input_length : U64
	max_input_length = 2305843009213693951

	## Large canonical inputs reuse one native incremental state across
	## batches. Checked total length protects its SHA-256 bit counter.
	Batched :: { bytes : U64, hasher : Crypto.SHA256.Hasher }.{
		start : () -> Batched
		start = || Batched.{ bytes: 0, hasher: Crypto.SHA256.Hasher.empty() }

		write : Batched, List(U8) -> Try(Batched, Error)
		write = |state, chunk| {
			if chunk.len() > max_input_length - state.bytes {
				return Err(InputTooLarge)
			}
			Ok(Batched.{ bytes: state.bytes + chunk.len(), hasher: state.hasher.write(chunk) })
		}

		finish : Batched -> { bytes : U64, digest : List(U8) }
		finish = |state| { bytes: state.bytes, digest: state.hasher.finish().to_bytes() }
	}

	digest : List(U8) -> Try(List(U8), Error)
	digest = |input| {
		check_length(input.len())?
		Ok(Crypto.SHA256.hash(input).to_bytes())
	}

	## The caller supplies an already-validated range.
	digest_range : List(U8), List(U8), U64, U64 -> Try(List(U8), Error)
	digest_range = |prefix, input, start, length| {
		if length > max_input_length or prefix.len() > max_input_length - length {
			return Err(InputTooLarge)
		}
		if start > input.len() or length > input.len() - start {
			crash "SHA-256 input invariant failed"
		}
		range = input.sublist({ start, len: length })
		if prefix.is_empty() {
			Ok(Crypto.SHA256.hash(range).to_bytes())
		} else {
			Ok(Crypto.SHA256.Hasher.empty().write(prefix).write(range).finish().to_bytes())
		}
	}

	## Keep the caller's accumulator uniquely owned and grow it geometrically.
	append_digest : List(U8), List(U8) -> Try(List(U8), Error)
	append_digest = |output, input| {
		bytes = digest(input)?
		var $output = output
		for byte in bytes {
			$output = $output.append(byte)
		}
		Ok($output)
	}
}

check_length : U64 -> Try({}, KernelSha256.Error)
check_length = |length| if (length > KernelSha256.max_input_length) Err(InputTooLarge) else Ok({})

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

# Independent SHA-256 vectors straddle both padding and compression blocks.
expect [
	(0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
	(1, "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"),
	(55, "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"),
	(56, "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"),
	(63, "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34"),
	(64, "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"),
	(65, "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0"),
	(127, "c57e9278af78fa3cab38667bef4ce29d783787a2f731d4e12200270f0c32320a"),
	(128, "6836cf13bac400e9105071cd6af47084dfacad4e5e302c94bfed24e013afb73e"),
	(129, "c12cb024a2e5551cca0e08fce8f1c5e314555cc3fef6329ee994a3db752166ae"),
].all(|(length, hex)| verify_digest_splits(length, hex))

verify_digest_splits : U64, Str -> Bool
verify_digest_splits = |length, hex| {
	expected = (Crypto.SHA256.Digest.from_hex(hex) ?? crash "invalid test vector").to_bytes()
	input = List.repeat(0x61.U8, length)
	if KernelSha256.digest(input) != Ok(expected) {
		return False
	}
	var $split = 0
	while $split <= length {
		prefix = input.take_first($split)
		padded = [0xff, 0x00].concat(input.drop_first($split)).concat([0x80])
		if KernelSha256.digest_range(prefix, padded, 2, length - $split) != Ok(expected) {
			return False
		}
		$split = $split + 1
	}
	True
}

expect {
	input = [0, 0x80, 0xff, 1]
	prefix = [9, 8, 7]
	expected = KernelSha256.digest(input)?
	appended = KernelSha256.append_digest(prefix, input)?
	appended == prefix.concat(expected) and prefix == [9, 8, 7]
}

expect KernelSha256.digest_range([], [], 0, 2305843009213693952) == Err(InputTooLarge)
expect KernelSha256.digest_range([1], [], 0, 2305843009213693951) == Err(InputTooLarge)
expect KernelSha256.digest_range([1], [], 0, U64.highest) == Err(InputTooLarge)
