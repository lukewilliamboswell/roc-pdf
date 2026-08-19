import KernelLex

KernelResourceName :: [].{
	bytes : Str, U64 -> List(U8)
	bytes = |prefix, index| append(Str.to_utf8(prefix), index)

	append : List(U8), U64 -> List(U8)
	append = |output, index| append_index(output, index)

	suffix_length : U64 -> U64
	suffix_length = |index| decimal_length(decimal_length(index)) + 1 + decimal_length(index)
}

append_index : List(U8), U64 -> List(U8)
append_index = |output, index| {
	digits = decimal_length(index)
	with_length = KernelLex.append_unsigned(output, digits)
	KernelLex.append_unsigned(with_length.append(95), index)
}

decimal_length : U64 -> U64
decimal_length = |value| {
	var $digits = 1
	var $remaining = value
	while $remaining >= 10 {
		$remaining = U64.div_by($remaining, 10)
		$digits = $digits + 1
	}
	$digits
}

## Length-prefixed decimal names remain sorted across digit boundaries.
expect KernelResourceName.bytes("CS", 9) == Str.to_utf8("CS1_9") and KernelResourceName.bytes("CS", 10) == Str.to_utf8("CS2_10") and KernelResourceName.bytes("CS", 99) == Str.to_utf8("CS2_99") and KernelResourceName.bytes("CS", 100) == Str.to_utf8("CS3_100")

## U64 indices carry their exact decimal width without a fixed object limit.
expect KernelResourceName.bytes("Im", U64.highest) == Str.to_utf8("Im20_18446744073709551615")
