import Document
import KernelNavigation

## Visible PDF page labels. PDF alphabetic labels repeat one letter
## (A..Z, AA..ZZ, AAA..), independently of list numbering (A..Z, AA, AB).
## Formatting proves its exact byte budget before allocating output.
KernelPageLabels :: [].{
	Error : [ArithmeticOverflow, EmptyLabel, InvalidPage, LimitExceeded({ attempted : U64, limit : U64 })]

	format : KernelNavigation.LabelPlan, U64, U64 -> Try(Str, Error)
	format = |plan, page, max_bytes| format_plan(plan, page, max_bytes, False)

	## An explicitly unnumbered empty label is valid page-artifact
	## furniture. Semantic body references use `format` and reject it.
	format_allow_empty : KernelNavigation.LabelPlan, U64, U64 -> Try(Str, Error)
	format_allow_empty = |plan, page, max_bytes| format_plan(plan, page, max_bytes, True)

	value : Str, Document.PageLabelStyle, U64, U64 -> Try(Str, Error)
	value = |prefix, style, number, max_bytes| format_value(prefix, style, number, max_bytes, False)
}

format_plan : KernelNavigation.LabelPlan, U64, U64, Bool -> Try(Str, KernelPageLabels.Error)
format_plan = |plan, page, max_bytes, allow_empty| {
	if page >= KernelNavigation.LabelPlan.pages(plan) {
		return Err(InvalidPage)
	}
	ranges = KernelNavigation.LabelPlan.ranges(plan)
	if ranges.is_empty() {
		return format_value("", DecimalArabic, checked_add(page, 1)?, max_bytes, allow_empty)
	}
	var $low = 0
	var $high = ranges.len()
	while $low < $high {
		middle = $low + ($high - $low) // 2
		if at(ranges, middle).start_page <= page {
			$low = middle + 1
		} else {
			$high = middle
		}
	}
	if $low == 0 {
		return Err(InvalidPage)
	}
	range = at(ranges, $low - 1)
	format_value(range.prefix, range.style, checked_add(range.start_number, page - range.start_page)?, max_bytes, allow_empty)
}

format_value : Str, Document.PageLabelStyle, U64, U64, Bool -> Try(Str, KernelPageLabels.Error)
format_value = |prefix, style, number, max_bytes, allow_empty| {
	if number == 0 {
		return Err(InvalidPage)
	}
	prefix_length = prefix.count_utf8_bytes()
	digits = if (style == DecimalArabic) number.to_str() else ""
	suffix_length = match style {
		NoNumber => 0
		DecimalArabic => digits.count_utf8_bytes()
		LettersLower | LettersUpper => (number - 1) // 26 + 1
		RomanLower | RomanUpper => roman_length(number)?
	}
	total = checked_add(prefix_length, suffix_length)?
	if total > max_bytes {
		return Err(LimitExceeded({ attempted: total, limit: max_bytes }))
	}
	if total == 0 and !allow_empty {
		return Err(EmptyLabel)
	}
	var $output = List.with_capacity(total)
	for byte in prefix.to_utf8() {
		$output = $output.append(byte)
	}
	match style {
		NoNumber => {}
		DecimalArabic => for byte in digits.to_utf8() {
			$output = $output.append(byte)
		}
		LettersLower | LettersUpper => {
			base : U8
			base = if (style == LettersLower) 97 else 65
			letter = base + ((number - 1) % 26).to_u8_wrap()
			var $index = 0
			while $index < suffix_length {
				$output = $output.append(letter)
				$index = $index + 1
			}
		}
		RomanLower | RomanUpper => {
			$output = append_roman($output, number, style == RomanLower)
		}
	}
	match Str.from_utf8($output) {
		Ok(text) => Ok(text)
		Err(_) => crash "page label ASCII suffix changed valid UTF-8"
	}
}

roman_values : List(U64)
roman_values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]

roman_tokens : List(Str)
roman_tokens = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]

roman_length : U64 -> Try(U64, KernelPageLabels.Error)
roman_length = |number| {
	var $remaining = number
	var $length = 0
	var $index = 0
	while $index < roman_values.len() {
		value = at(roman_values, $index)
		count = $remaining // value
		width = at(roman_tokens, $index).count_utf8_bytes()
		added = match count.times_try(width) {
			Ok(result) => result
			Err(_) => return Err(ArithmeticOverflow)
		}
		$length = checked_add($length, added)?
		$remaining = $remaining % value
		$index = $index + 1
	}
	Ok($length)
}

append_roman : List(U8), U64, Bool -> List(U8)
append_roman = |output, number, lower| {
	var $output = output
	var $remaining = number
	var $index = 0
	while $index < roman_values.len() {
		value = at(roman_values, $index)
		count = $remaining // value
		var $copy = 0
		while $copy < count {
			for byte in at(roman_tokens, $index).to_utf8() {
				$output = $output.append(if (lower) byte + 32 else byte)
			}
			$copy = $copy + 1
		}
		$remaining = $remaining % value
		$index = $index + 1
	}
	$output
}

checked_add : U64, U64 -> Try(U64, KernelPageLabels.Error)
checked_add = |left, right| match left.plus_try(right) {
	Ok(value) => Ok(value)
	Err(_) => Err(ArithmeticOverflow)
}

at : List(a), U64 -> a
at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(_) => crash "page label validated index escaped its arena"
}

expect KernelPageLabels.value("", LettersUpper, 26, 32) == Ok("Z")
expect KernelPageLabels.value("", LettersUpper, 27, 32) == Ok("AA")
expect KernelPageLabels.value("", LettersUpper, 28, 32) == Ok("BB")
expect KernelPageLabels.value("A-", LettersLower, 53, 32) == Ok("A-aaa")
expect KernelPageLabels.value("pré-", DecimalArabic, 2, 32) == Ok("pré-2")
expect KernelPageLabels.value("", RomanLower, 49, 32) == Ok("xlix")
expect KernelPageLabels.value("", RomanUpper, 4000, 32) == Ok("MMMM")
expect KernelPageLabels.value("", NoNumber, 1, 32) == Err(EmptyLabel)
expect match KernelPageLabels.value("", LettersUpper, U64.highest, 32) {
	Err(_) => True
	Ok(_) => False
}
expect match KernelPageLabels.value("", RomanUpper, U64.highest, 32) {
	Err(_) => True
	Ok(_) => False
}
expect {
	plan = KernelNavigation.LabelPlan.build([], 9, KernelNavigation.standard_limits)?
	KernelPageLabels.format(plan, 8, 32) == Ok("9")
}
expect {
	plan = KernelNavigation.LabelPlan.build([{ prefix: "front-", start_number: 1, start_page: 0, style: RomanLower }, { prefix: "", start_number: 1, start_page: 4, style: DecimalArabic }], 6, KernelNavigation.standard_limits)?
	KernelPageLabels.format(plan, 5, 32) == Ok("2")
}

expect {
	labels = KernelNavigation.LabelPlan.build([{ prefix: "", start_number: 1, start_page: 0, style: NoNumber }], 2, KernelNavigation.standard_limits)?
	KernelPageLabels.format_allow_empty(labels, 1, 128) == Ok("") and KernelPageLabels.format(labels, 1, 128) == Err(EmptyLabel)
}
