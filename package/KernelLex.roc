KernelLex :: [].{
	Error : [DecimalScaleOutOfRange(U8), NullNameByte(U64)]

	Name :: List(U8).{
		from_bytes : List(U8) -> Try(Name, Error)
		from_bytes = |bytes| {
			length = bytes.len()
			var $index = 0
			while $index < length {
				if byte_at(bytes, $index) == 0 {
					return Err(NullNameByte($index))
				}
				$index = $index + 1
			}

			Ok(Name.(bytes))
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
	boolean = |value| append_keyword_boolean(List.with_capacity(if (value) 4 else 5), value)

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

	## A byte string is written in whichever canonical form is shorter: a
	## literal `( )` string, in which `(`, `)`, and `\\` are escaped with a
	## backslash and every byte outside printable ASCII is a three-digit octal
	## escape, or uppercase hex. A tie is written as hex.
	byte_string : List(U8) -> List(U8)
	byte_string = |bytes| write_byte_string([], bytes)

	## Always uppercase hex, for binary values such as file identifiers.
	hex_string : List(U8) -> List(U8)
	hex_string = |bytes| write_hex_string([], bytes)

	## A text string whose characters are all printable ASCII (U+0020 to
	## U+007E) is written as those bytes, which PDFDocEncoding maps to the same
	## characters, under the byte-string rule. Any other text is UTF-16BE with a
	## BOM in canonical uppercase hex. Roc Str supplies valid UTF-8, so
	## malformed encodings cannot cross this API.
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

	append_thousandths : List(U8), I64 -> List(U8)
	append_thousandths = |output, coefficient| append_decimal(output, coefficient, 3)

	## `coefficient` / 10^`digits` in canonical decimal form.
	append_decimal_digits : List(U8), I64, U8 -> List(U8)
	append_decimal_digits = |output, coefficient, digits| append_decimal(output, coefficient, digits)

	append_billionths : List(U8), I64 -> List(U8)
	append_billionths = |output, coefficient| append_decimal(output, coefficient, 9)

	## Exact signed OpenType 16.16 degrees. The quotient/remainder split keeps
	## every intermediate in U64 across the complete I32 domain, including the
	## negative endpoint. At most sixteen fractional digits are emitted.
	append_fixed16 : List(U8), I32 -> List(U8)
	append_fixed16 = |output, raw| append_fixed16_value(output, raw)

	append_name : List(U8), Name -> List(U8)
	append_name = |output, value| append_name_bytes(output, Name.bytes(value))

	append_byte_string : List(U8), List(U8) -> List(U8)
	append_byte_string = |output, bytes| write_byte_string(output, bytes)

	append_hex_string : List(U8), List(U8) -> List(U8)
	append_hex_string = |output, bytes| write_hex_string(output, bytes)

	append_text_string : List(U8), Str -> List(U8)
	append_text_string = |output, value| write_text_string(output, value)

	append_text : List(U8), Text -> List(U8)
	append_text = |output, value| write_text_utf8(output, Text.bytes(value))

	## Orders two strings by their UTF-8 bytes without copying either into a
	## list, which `Str.to_utf8` did once per comparison key.
	compare_utf8 : Str, Str -> [Equal, Greater, Less]
	compare_utf8 = |left, right| compare_iterators(Str.iter_utf8(left), Str.iter_utf8(right))

	## The bytes of a PDF name given as a `Str`. The standard structure types
	## and the attribute keys and values the package lowers come from static
	## constants; `Str.to_utf8` would allocate a fresh list for every
	## structure element and attribute. Any other name is converted.
	name_bytes : Str -> List(U8)
	name_bytes = |value| match value {
		"Document" => document_name
		"DocumentFragment" => document_fragment_name
		"Part" => part_name
		"Sect" => sect_name
		"Div" => div_name
		"Aside" => aside_name
		"NonStruct" => non_struct_name
		"P" => p_name
		"H" => h_name
		"H1" => h1_name
		"H2" => h2_name
		"H3" => h3_name
		"H4" => h4_name
		"H5" => h5_name
		"H6" => h6_name
		"Title" => title_name
		"FENote" => fe_note_name
		"Sub" => sub_name
		"Lbl" => lbl_name
		"Span" => span_name
		"Em" => em_name
		"Strong" => strong_name
		"Link" => link_name
		"Annot" => annot_name
		"Form" => form_name
		"Ruby" => ruby_name
		"RB" => rb_name
		"RT" => rt_name
		"RP" => rp_name
		"Warichu" => warichu_name
		"WT" => wt_name
		"WP" => wp_name
		"L" => l_name
		"LI" => li_name
		"LBody" => l_body_name
		"Table" => table_name
		"TR" => tr_name
		"TH" => th_name
		"TD" => td_name
		"THead" => t_head_name
		"TBody" => t_body_name
		"TFoot" => t_foot_name
		"Caption" => caption_name
		"Figure" => figure_name
		"Formula" => formula_name
		"Artifact" => artifact_name
		"Code" => code_name
		"Quote" => quote_name
		"BibEntry" => bib_entry_name
		"Reference" => reference_name
		"Note" => note_name
		"Chapter" => chapter_name
		"O" => o_name
		"List" => list_name
		"ListNumbering" => list_numbering_name
		"Scope" => scope_name
		"ColSpan" => col_span_name
		"RowSpan" => row_span_name
		"Headers" => headers_name
		"Summary" => summary_name
		"Row" => row_name
		"Column" => column_name
		"Both" => both_name
		"None" => none_name
		"Disc" => disc_name
		"Circle" => circle_name
		"Square" => square_name
		"Decimal" => decimal_name
		"UpperRoman" => upper_roman_name
		"LowerRoman" => lower_roman_name
		"UpperAlpha" => upper_alpha_name
		"LowerAlpha" => lower_alpha_name
		"Ordered" => ordered_name
		"Unordered" => unordered_name
		"Description" => description_name
		"Bullets" => bullets_name
		"Diagonal" => diagonal_name
		"ActualText" => actual_text_name
		"Alt" => alt_name
		"E" => e_name
		"Lang" => lang_name
		"ID" => id_name
		_ => Str.to_utf8(value)
	}
}

document_name : List(U8)
document_name = Str.to_utf8("Document")

document_fragment_name : List(U8)
document_fragment_name = Str.to_utf8("DocumentFragment")

part_name : List(U8)
part_name = Str.to_utf8("Part")

sect_name : List(U8)
sect_name = Str.to_utf8("Sect")

div_name : List(U8)
div_name = Str.to_utf8("Div")

aside_name : List(U8)
aside_name = Str.to_utf8("Aside")

non_struct_name : List(U8)
non_struct_name = Str.to_utf8("NonStruct")

p_name : List(U8)
p_name = Str.to_utf8("P")

h_name : List(U8)
h_name = Str.to_utf8("H")

h1_name : List(U8)
h1_name = Str.to_utf8("H1")

h2_name : List(U8)
h2_name = Str.to_utf8("H2")

h3_name : List(U8)
h3_name = Str.to_utf8("H3")

h4_name : List(U8)
h4_name = Str.to_utf8("H4")

h5_name : List(U8)
h5_name = Str.to_utf8("H5")

h6_name : List(U8)
h6_name = Str.to_utf8("H6")

title_name : List(U8)
title_name = Str.to_utf8("Title")

fe_note_name : List(U8)
fe_note_name = Str.to_utf8("FENote")

sub_name : List(U8)
sub_name = Str.to_utf8("Sub")

lbl_name : List(U8)
lbl_name = Str.to_utf8("Lbl")

span_name : List(U8)
span_name = Str.to_utf8("Span")

em_name : List(U8)
em_name = Str.to_utf8("Em")

strong_name : List(U8)
strong_name = Str.to_utf8("Strong")

link_name : List(U8)
link_name = Str.to_utf8("Link")

annot_name : List(U8)
annot_name = Str.to_utf8("Annot")

form_name : List(U8)
form_name = Str.to_utf8("Form")

ruby_name : List(U8)
ruby_name = Str.to_utf8("Ruby")

rb_name : List(U8)
rb_name = Str.to_utf8("RB")

rt_name : List(U8)
rt_name = Str.to_utf8("RT")

rp_name : List(U8)
rp_name = Str.to_utf8("RP")

warichu_name : List(U8)
warichu_name = Str.to_utf8("Warichu")

wt_name : List(U8)
wt_name = Str.to_utf8("WT")

wp_name : List(U8)
wp_name = Str.to_utf8("WP")

l_name : List(U8)
l_name = Str.to_utf8("L")

li_name : List(U8)
li_name = Str.to_utf8("LI")

l_body_name : List(U8)
l_body_name = Str.to_utf8("LBody")

table_name : List(U8)
table_name = Str.to_utf8("Table")

tr_name : List(U8)
tr_name = Str.to_utf8("TR")

th_name : List(U8)
th_name = Str.to_utf8("TH")

td_name : List(U8)
td_name = Str.to_utf8("TD")

t_head_name : List(U8)
t_head_name = Str.to_utf8("THead")

t_body_name : List(U8)
t_body_name = Str.to_utf8("TBody")

t_foot_name : List(U8)
t_foot_name = Str.to_utf8("TFoot")

caption_name : List(U8)
caption_name = Str.to_utf8("Caption")

figure_name : List(U8)
figure_name = Str.to_utf8("Figure")

formula_name : List(U8)
formula_name = Str.to_utf8("Formula")

artifact_name : List(U8)
artifact_name = Str.to_utf8("Artifact")

code_name : List(U8)
code_name = Str.to_utf8("Code")

quote_name : List(U8)
quote_name = Str.to_utf8("Quote")

bib_entry_name : List(U8)
bib_entry_name = Str.to_utf8("BibEntry")

reference_name : List(U8)
reference_name = Str.to_utf8("Reference")

note_name : List(U8)
note_name = Str.to_utf8("Note")

chapter_name : List(U8)
chapter_name = Str.to_utf8("Chapter")

o_name : List(U8)
o_name = Str.to_utf8("O")

list_name : List(U8)
list_name = Str.to_utf8("List")

list_numbering_name : List(U8)
list_numbering_name = Str.to_utf8("ListNumbering")

scope_name : List(U8)
scope_name = Str.to_utf8("Scope")

col_span_name : List(U8)
col_span_name = Str.to_utf8("ColSpan")

row_span_name : List(U8)
row_span_name = Str.to_utf8("RowSpan")

headers_name : List(U8)
headers_name = Str.to_utf8("Headers")

summary_name : List(U8)
summary_name = Str.to_utf8("Summary")

row_name : List(U8)
row_name = Str.to_utf8("Row")

column_name : List(U8)
column_name = Str.to_utf8("Column")

both_name : List(U8)
both_name = Str.to_utf8("Both")

none_name : List(U8)
none_name = Str.to_utf8("None")

disc_name : List(U8)
disc_name = Str.to_utf8("Disc")

circle_name : List(U8)
circle_name = Str.to_utf8("Circle")

square_name : List(U8)
square_name = Str.to_utf8("Square")

decimal_name : List(U8)
decimal_name = Str.to_utf8("Decimal")

upper_roman_name : List(U8)
upper_roman_name = Str.to_utf8("UpperRoman")

lower_roman_name : List(U8)
lower_roman_name = Str.to_utf8("LowerRoman")

upper_alpha_name : List(U8)
upper_alpha_name = Str.to_utf8("UpperAlpha")

lower_alpha_name : List(U8)
lower_alpha_name = Str.to_utf8("LowerAlpha")

ordered_name : List(U8)
ordered_name = Str.to_utf8("Ordered")

unordered_name : List(U8)
unordered_name = Str.to_utf8("Unordered")

description_name : List(U8)
description_name = Str.to_utf8("Description")

bullets_name : List(U8)
bullets_name = Str.to_utf8("Bullets")

diagonal_name : List(U8)
diagonal_name = Str.to_utf8("Diagonal")

actual_text_name : List(U8)
actual_text_name = Str.to_utf8("ActualText")

alt_name : List(U8)
alt_name = Str.to_utf8("Alt")

e_name : List(U8)
e_name = Str.to_utf8("E")

lang_name : List(U8)
lang_name = Str.to_utf8("Lang")

id_name : List(U8)
id_name = Str.to_utf8("ID")

append_keyword_boolean : List(U8), Bool -> List(U8)
append_keyword_boolean = |output, value| {
	length = if (value) 4 else 5
	var $out = output
	var $index = 0
	while $index < length {
		byte = match $index {
			0 => if (value) 116 else 102
			1 => if (value) 114 else 97
			2 => if (value) 117 else 108
			3 => if (value) 101 else 115
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

## The sign is bound once and each branch consumes it. A `var` output that
## one branch reassigned while the other passed it on as its value stayed live
## across that call, and the call copied the whole output: once per integral
## decimal, which is every whole coordinate in a content stream
## (development/performance/emission-linearity.md).
append_decimal : List(U8), I64, U8 -> List(U8)
append_decimal = |output, coefficient, scale| {
	if coefficient == 0 {
		output.append(48)
	} else {
		magnitude = if (coefficient < 0)
			U64.minus_wrap(0, coefficient.to_u64_wrap())
		else
			coefficient.to_u64_wrap()

		var $normalized = magnitude
		var $scale = scale.to_u64()
		while $scale > 0 and U64.mod_by($normalized, 10) == 0 {
			$normalized = U64.div_by($normalized, 10)
			$scale = $scale - 1
		}

		signed = if (coefficient < 0) output.append(45) else output
		if $scale == 0 {
			append_u64(signed, $normalized)
		} else {
			append_fraction(signed, $normalized, $scale)
		}
	}
}

append_fixed16_value : List(U8), I32 -> List(U8)
append_fixed16_value = |output, raw| {
	value = raw.to_i64()
	magnitude = (if (value < 0) 0 - value else value).to_u64_wrap()
	whole = U64.div_by(magnitude, 65536)
	fraction = U64.mod_by(magnitude, 65536)
	var $out = if (value < 0) output.append('-') else output
	$out = append_u64($out, whole)
	if fraction == 0 {
		return $out
	}
	# 5^16 converts the remainder / 2^16 to coefficient / 10^16.
	var $coefficient = fraction * 152587890625
	var $digits = 16
	while U64.mod_by($coefficient, 10) == 0 {
		$coefficient = U64.div_by($coefficient, 10)
		$digits = $digits - 1
	}
	$out = $out.append('.')
	var $divisor = power_of_ten($digits - 1)
	while $divisor > 0 {
		digit = U64.mod_by(U64.div_by($coefficient, $divisor), 10)
		$out = $out.append('0' + digit.to_u8_wrap())
		$divisor = U64.div_by($divisor, 10)
	}
	$out
}

append_fraction : List(U8), U64, U64 -> List(U8)
append_fraction = |output, normalized, scale| {
	power = power_of_ten(scale)
	whole = U64.div_by(normalized, power)
	fraction = U64.mod_by(normalized, power)
	var $out = append_u64(output, whole)
	$out = $out.append(46)

	var $divisor = U64.div_by(power, 10)
	while $divisor > 0 {
		digit = U64.mod_by(U64.div_by(fraction, $divisor), 10)
		$out = $out.append((48 + digit).to_u8_wrap())
		$divisor = U64.div_by($divisor, 10)
	}
	$out
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
	var $literal = 2
	var $index = 0
	while $index < bytes.len() {
		$literal = $literal + literal_width(byte_at(bytes, $index))
		$index = $index + 1
	}
	if $literal < 2 + 2 * bytes.len() {
		write_literal_string(output, bytes)
	} else {
		write_hex_string(output, bytes)
	}
}

## Bytes one byte takes in a canonical literal string.
literal_width : U8 -> U64
literal_width = |byte| {
	if byte == 40 or byte == 41 or byte == 92 {
		2
	} else if byte >= 32 and byte <= 126 {
		1
	} else {
		4
	}
}

write_literal_string : List(U8), List(U8) -> List(U8)
write_literal_string = |output, bytes| {
	var $out = output.append(40)
	var $index = 0
	while $index < bytes.len() {
		byte = byte_at(bytes, $index)
		if byte == 40 or byte == 41 or byte == 92 {
			$out = $out.append(92).append(byte)
		} else if byte >= 32 and byte <= 126 {
			$out = $out.append(byte)
		} else {
			$out = $out.append(92).append(48 + U8.div_by(byte, 64)).append(48 + U8.mod_by(U8.div_by(byte, 8), 8)).append(48 + U8.mod_by(byte, 8))
		}
		$index = $index + 1
	}
	$out.append(41)
}

write_hex_string : List(U8), List(U8) -> List(U8)
write_hex_string = |output, bytes| {
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
	var $ascii = True
	var $scan = 0
	while $ascii and $scan < utf8.len() {
		byte = byte_at(utf8, $scan)
		if byte < 32 or byte > 126 {
			$ascii = False
		}
		$scan = $scan + 1
	}
	if $ascii {
		write_byte_string(output, utf8)
	} else {
		write_text_utf16(output, utf8)
	}
}

write_text_utf16 : List(U8), List(U8) -> List(U8)
write_text_utf16 = |output, utf8| {
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
	byte = if (nibble < 10) 48 + nibble else 55 + nibble
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

# Fixed kernel scales append without constructing an opaque Decimal value.
expect KernelLex.append_thousandths([], -25) == Str.to_utf8("-0.025") and KernelLex.append_billionths([], 1) == Str.to_utf8("0.000000001")

# Byte strings take the shorter canonical form; ties and binary stay hex.
expect KernelLex.byte_string(Str.to_utf8("c000008")) == Str.to_utf8("(c000008)") and
	KernelLex.byte_string(Str.to_utf8("a(b)\\")) == Str.to_utf8("(a\\(b\\)\\\\)") and
		KernelLex.byte_string([0, 255]) == Str.to_utf8("<00FF>") and
			KernelLex.byte_string([65, 10]) == Str.to_utf8("<410A>") and
				KernelLex.byte_string([]) == Str.to_utf8("<>")

# Printable-ASCII text is written as PDFDocEncoding bytes; other text is UTF-16BE.
expect KernelLex.text_string("en-AU") == Str.to_utf8("(en-AU)") and
	KernelLex.text_string("Café") == Str.to_utf8("<FEFF00430061006600E9>") and
		KernelLex.text_string("") == Str.to_utf8("<>")

compare_iterators : Iter(U8), Iter(U8) -> [Equal, Greater, Less]
compare_iterators = |left, right| {
	var $left = left
	var $right = right
	while True {
		match Iter.next($left) {
			Skip({ rest }) => {
				$left = rest
			}
			Done => return match next_byte($right) {
				NoByte => Equal
				Byte(_) => Less
			}
			One({ item: a, rest: left_rest }) => match next_byte($right) {
				NoByte => return Greater
				Byte({ byte: b, rest: right_rest }) => {
					if a < b {
						return Less
					}
					if a > b {
						return Greater
					}
					$left = left_rest
					$right = right_rest
				}
			}
		}
	}
}

next_byte : Iter(U8) -> [Byte({ byte : U8, rest : Iter(U8) }), NoByte]
next_byte = |iter| {
	var $iter = iter
	while True {
		match Iter.next($iter) {
			Skip({ rest }) => {
				$iter = rest
			}
			Done => return NoByte
			One({ item, rest }) => return Byte({ byte: item, rest })
		}
	}
}

# UTF-8 byte order: a proper prefix sorts first, and a multi-byte scalar
# compares by its encoded bytes (é is C3 A9, above every ASCII byte).
expect KernelLex.compare_utf8("c000001", "c000002") == Less and
	KernelLex.compare_utf8("c000002", "c000001") == Greater and
		KernelLex.compare_utf8("c000001", "c000001") == Equal and
			KernelLex.compare_utf8("c", "c0") == Less and
				KernelLex.compare_utf8("c0", "c") == Greater and
					KernelLex.compare_utf8("", "") == Equal and
						KernelLex.compare_utf8("z", "é") == Less

# Fractional source angles retain every bit without floating point or rounding.
expect KernelLex.append_fixed16([], -616038) == Str.to_utf8("-9.399993896484375")
expect KernelLex.append_fixed16([], -511180) == Str.to_utf8("-7.79998779296875")
expect KernelLex.append_fixed16([], 98304) == Str.to_utf8("1.5")
expect KernelLex.append_fixed16([], -1) == Str.to_utf8("-0.0000152587890625")
expect KernelLex.append_fixed16([], I32.highest) == Str.to_utf8("32767.9999847412109375")
expect KernelLex.append_fixed16([], I32.lowest) == Str.to_utf8("-32768")
expect KernelLex.append_fixed16([], 0) == Str.to_utf8("0")
