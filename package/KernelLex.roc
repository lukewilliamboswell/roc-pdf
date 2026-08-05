KernelLex :: [].{
	Error : [DecimalScaleOutOfRange(U8), NullNameByte(U64)]

	Name :: List(U8).{
		from_bytes : List(U8) -> Try(Name, Error)
		from_bytes = |bytes| {
			length = bytes.len()
			var $index = 0
			var $error = NoError
			while $index < length and $error == NoError {
				if byte_at(bytes, $index) == 0 {
					$error = Invalid($index)
				}
				$index = $index + 1
			}

			match $error {
				Invalid(index) => Err(NullNameByte(index))
				NoError => Ok(Name.(bytes))
			}
		}

		bytes : Name -> List(U8)
		bytes = |Name.(bytes)| bytes
	}

	Text :: List(U8).{
		from_str : Str -> Text
		from_str = |value| Text.(Str.to_utf8(value))

		bytes : Text -> List(U8)
		bytes = |Text.(bytes)| bytes
	}

	## Decimal is an exact signed coefficient and a base-10 scale. Floating-point
	## values never enter the lexical boundary.
	Decimal :: { coefficient : I64, scale : U8 }.{
		from_coefficient : I64, U8 -> Try(Decimal, Error)
		from_coefficient = |coefficient, scale|
			if scale <= 9 {
				Ok(Decimal.{ coefficient, scale })
			} else {
				Err(DecimalScaleOutOfRange(scale))
			}

		coefficient : Decimal -> I64
		coefficient = |decimal| decimal.coefficient

		scale : Decimal -> U8
		scale = |decimal| decimal.scale
	}

	boolean : Bool -> List(U8)
	boolean = |value| append_keyword_boolean(List.with_capacity(if value 4 else 5), value)

	null_value : List(U8)
	null_value = append_keyword_null(List.with_capacity(4))

	integer : I64 -> List(U8)
	integer = |value| append_i64([], value)

	unsigned : U64 -> List(U8)
	unsigned = |value| append_u64([], value)

	real : Decimal -> List(U8)
	real = |value| append_decimal([], Decimal.coefficient(value), Decimal.scale(value))

	name : Name -> List(U8)
	name = |value| append_name_bytes([], Name.bytes(value))

	byte_string : List(U8) -> List(U8)
	byte_string = |bytes| write_byte_string([], bytes)

	## Text strings use UTF-16BE with a BOM and canonical uppercase hex syntax.
	## Roc Str supplies valid UTF-8, so malformed encodings cannot cross this API.
	text_string : Str -> List(U8)
	text_string = |value| write_text_string([], value)

	append_boolean : List(U8), Bool -> List(U8)
	append_boolean = |output, value| append_keyword_boolean(output, value)

	append_null : List(U8) -> List(U8)
	append_null = |output| append_keyword_null(output)

	append_integer : List(U8), I64 -> List(U8)
	append_integer = |output, value| append_i64(output, value)

	append_unsigned : List(U8), U64 -> List(U8)
	append_unsigned = |output, value| append_u64(output, value)

	append_real : List(U8), Decimal -> List(U8)
	append_real = |output, value| append_decimal(output, Decimal.coefficient(value), Decimal.scale(value))

	append_name : List(U8), Name -> List(U8)
	append_name = |output, value| append_name_bytes(output, Name.bytes(value))

	append_byte_string : List(U8), List(U8) -> List(U8)
	append_byte_string = |output, bytes| write_byte_string(output, bytes)

	append_text_string : List(U8), Str -> List(U8)
	append_text_string = |output, value| write_text_string(output, value)

	append_text : List(U8), Text -> List(U8)
	append_text = |output, value| write_text_utf8(output, Text.bytes(value))
}

append_keyword_boolean : List(U8), Bool -> List(U8)
append_keyword_boolean = |output, value| {
	length = if value 4 else 5
	var $out = output
	var $index = 0
	while $index < length {
		byte = match $index {
			0 => if value 116 else 102
			1 => if value 114 else 97
			2 => if value 117 else 108
			3 => if value 101 else 115
			_ => 101
		}
		$out = $out.append(byte)
		$index = $index + 1
	}
	$out
}

append_keyword_null : List(U8) -> List(U8)
append_keyword_null = |output| {
	var $out = output
	$out = $out.append(110)
	$out = $out.append(117)
	$out = $out.append(108)
	$out.append(108)
}

append_i64 : List(U8), I64 -> List(U8)
append_i64 = |output, value| {
	if value < 0 {
		with_sign = output.append(45)
		append_u64(with_sign, U64.minus_wrap(0, value.to_u64_wrap()))
	} else {
		append_u64(output, value.to_u64_wrap())
	}
}

append_u64 : List(U8), U64 -> List(U8)
append_u64 = |output, value| {
	if value == 0 {
		output.append(48)
	} else {
		var $remaining = value
		var $divisor = 1
		while $remaining >= 10 {
			$remaining = U64.div_by($remaining, 10)
			$divisor = $divisor * 10
		}

		var $out = output
		while $divisor > 0 {
			digit = U64.mod_by(U64.div_by(value, $divisor), 10)
			$out = $out.append((48 + digit).to_u8_wrap())
			$divisor = U64.div_by($divisor, 10)
		}
		$out
	}
}

append_decimal : List(U8), I64, U8 -> List(U8)
append_decimal = |output, coefficient, scale| {
	if coefficient == 0 {
		output.append(48)
	} else {
		magnitude = if coefficient < 0
			U64.minus_wrap(0, coefficient.to_u64_wrap())
		else
			coefficient.to_u64_wrap()

		var $normalized = magnitude
		var $scale = scale.to_u64()
		while $scale > 0 and U64.mod_by($normalized, 10) == 0 {
			$normalized = U64.div_by($normalized, 10)
			$scale = $scale - 1
		}

		var $out = if coefficient < 0 output.append(45) else output
		if $scale == 0 {
			append_u64($out, $normalized)
		} else {
			power = power_of_ten($scale)
			whole = U64.div_by($normalized, power)
			fraction = U64.mod_by($normalized, power)
			$out = append_u64($out, whole)
			$out = $out.append(46)

			var $divisor = U64.div_by(power, 10)
			while $divisor > 0 {
				digit = U64.mod_by(U64.div_by(fraction, $divisor), 10)
				$out = $out.append((48 + digit).to_u8_wrap())
				$divisor = U64.div_by($divisor, 10)
			}
			$out
		}
	}
}

power_of_ten : U64 -> U64
power_of_ten = |exponent| {
	var $value = 1
	var $index = 0
	while $index < exponent {
		$value = $value * 10
		$index = $index + 1
	}
	$value
}

append_name_bytes : List(U8), List(U8) -> List(U8)
append_name_bytes = |output, bytes| {
	length = bytes.len()
	var $out = output.append(47)
	var $index = 0
	while $index < length {
		byte = byte_at(bytes, $index)
		if is_regular_name_byte(byte) {
			$out = $out.append(byte)
		} else {
			$out = $out.append(35)
			$out = append_hex_byte($out, byte)
		}
		$index = $index + 1
	}
	$out
}

is_regular_name_byte : U8 -> Bool
is_regular_name_byte = |byte| {
	byte >= 33 and byte <= 126 and
		byte != 35 and byte != 37 and byte != 40 and byte != 41 and
			byte != 47 and byte != 60 and byte != 62 and byte != 91 and
				byte != 93 and byte != 123 and byte != 125
}

write_byte_string : List(U8), List(U8) -> List(U8)
write_byte_string = |output, bytes| {
	length = bytes.len()
	var $out = output.append(60)
	var $index = 0
	while $index < length {
		$out = append_hex_byte($out, byte_at(bytes, $index))
		$index = $index + 1
	}
	$out.append(62)
}

write_text_string : List(U8), Str -> List(U8)
write_text_string = |output, value| write_text_utf8(output, Str.to_utf8(value))

write_text_utf8 : List(U8), List(U8) -> List(U8)
write_text_utf8 = |output, utf8| {
	length = utf8.len()
	var $out = output.append(60)
	$out = append_hex_byte($out, 254)
	$out = append_hex_byte($out, 255)

	var $index = 0
	while $index < length {
		first = byte_at(utf8, $index).to_u64()
		if first < 128 {
			$out = append_utf16_unit($out, first)
			$index = $index + 1
		} else if first < 224 {
			second = byte_at(utf8, $index + 1).to_u64()
			scalar = U64.mod_by(first, 32) * 64 + U64.mod_by(second, 64)
			$out = append_utf16_unit($out, scalar)
			$index = $index + 2
		} else if first < 240 {
			second = byte_at(utf8, $index + 1).to_u64()
			third = byte_at(utf8, $index + 2).to_u64()
			scalar = U64.mod_by(first, 16) * 4096 + U64.mod_by(second, 64) * 64 + U64.mod_by(third, 64)
			$out = append_utf16_unit($out, scalar)
			$index = $index + 3
		} else {
			second = byte_at(utf8, $index + 1).to_u64()
			third = byte_at(utf8, $index + 2).to_u64()
			fourth = byte_at(utf8, $index + 3).to_u64()
			scalar = U64.mod_by(first, 8) * 262144 + U64.mod_by(second, 64) * 4096 + U64.mod_by(third, 64) * 64 + U64.mod_by(fourth, 64)
			shifted = scalar - 65536
			high = 55296 + U64.div_by(shifted, 1024)
			low = 56320 + U64.mod_by(shifted, 1024)
			$out = append_utf16_unit($out, high)
			$out = append_utf16_unit($out, low)
			$index = $index + 4
		}
	}
	$out.append(62)
}

append_utf16_unit : List(U8), U64 -> List(U8)
append_utf16_unit = |output, unit| {
	var $out = output
	$out = append_hex_nibble($out, U64.mod_by(U64.div_by(unit, 4096), 16).to_u8_wrap())
	$out = append_hex_nibble($out, U64.mod_by(U64.div_by(unit, 256), 16).to_u8_wrap())
	$out = append_hex_nibble($out, U64.mod_by(U64.div_by(unit, 16), 16).to_u8_wrap())
	append_hex_nibble($out, U64.mod_by(unit, 16).to_u8_wrap())
}

append_hex_byte : List(U8), U8 -> List(U8)
append_hex_byte = |output, byte| {
	var $out = append_hex_nibble(output, U8.div_by(byte, 16))
	append_hex_nibble($out, U8.mod_by(byte, 16))
}

append_hex_nibble : List(U8), U8 -> List(U8)
append_hex_nibble = |output, nibble| {
	byte = if nibble < 10 48 + nibble else 55 + nibble
	output.append(byte)
}

byte_at : List(U8), U64 -> U8
byte_at = |bytes, index| match bytes.get(index) {
	Ok(byte) => byte
	Err(OutOfBounds) => {
		crash "kernel lexical index invariant failed"
	}
}

expect KernelLex.boolean(True) == Str.to_utf8("true")
expect KernelLex.boolean(False) == Str.to_utf8("false")
expect KernelLex.null_value == Str.to_utf8("null")
expect KernelLex.integer(I64.lowest) == Str.to_utf8("-9223372036854775808")
expect KernelLex.integer(I64.highest) == Str.to_utf8("9223372036854775807")
expect KernelLex.unsigned(U64.highest) == Str.to_utf8("18446744073709551615")

expect {
	match KernelLex.Decimal.from_coefficient(1200, 3) {
		Ok(value) => KernelLex.real(value) == Str.to_utf8("1.2")
		Err(_) => False
	}
}

expect {
	match KernelLex.Decimal.from_coefficient(-25, 3) {
		Ok(value) => KernelLex.real(value) == Str.to_utf8("-0.025")
		Err(_) => False
	}
}

expect {
	match KernelLex.Decimal.from_coefficient(1, 10) {
		Err(DecimalScaleOutOfRange(scale)) => scale == 10
		_ => False
	}
}

expect {
	match KernelLex.Name.from_bytes([65, 32, 66, 47, 35]) {
		Ok(name) => KernelLex.name(name) == Str.to_utf8("/A#20B#2F#23")
		Err(_) => False
	}
}

expect {
	match KernelLex.Name.from_bytes([65, 66, 0]) {
		Err(NullNameByte(index)) => index == 2
		_ => False
	}
}
expect KernelLex.byte_string([0, 255]) == Str.to_utf8("<00FF>")
expect KernelLex.byte_string([]) == Str.to_utf8("<>")
expect KernelLex.text_string("A😀") == Str.to_utf8("<FEFF0041D83DDE00>")
expect KernelLex.text_string("é水") == Str.to_utf8("<FEFF00E96C34>")

expect {
	match KernelLex.Decimal.from_coefficient(1, 9) {
		Ok(value) => KernelLex.real(value) == Str.to_utf8("0.000000001")
		Err(_) => False
	}
}

expect {
	match KernelLex.Decimal.from_coefficient(I64.lowest, 0) {
		Ok(value) => KernelLex.real(value) == Str.to_utf8("-9223372036854775808")
		Err(_) => False
	}
}
