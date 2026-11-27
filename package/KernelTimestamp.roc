## The canonical timestamp form is `YYYY-MM-DDThh:mm:ssZ`: a UTC instant with
## a valid proleptic-Gregorian date and no fractional seconds or offsets.
KernelTimestamp :: [].{
	invalid_utc : List(U8) -> [NoViolation, ViolationAt(U64)]
	invalid_utc = |bytes| {
		if bytes.len() != 20 {
			return ViolationAt(bytes.len())
		}
		digits_ok = digit_run_ok(bytes, 0, 4) and digit_run_ok(bytes, 5, 2) and digit_run_ok(bytes, 8, 2) and digit_run_ok(bytes, 11, 2) and digit_run_ok(bytes, 14, 2) and digit_run_ok(bytes, 17, 2)
		if !digits_ok {
			first_bad_digit(bytes)
		} else if list_at(bytes, 4) != 0x2D {
			ViolationAt(4)
		} else if list_at(bytes, 7) != 0x2D {
			ViolationAt(7)
		} else if list_at(bytes, 10) != 0x54 {
			ViolationAt(10)
		} else if list_at(bytes, 13) != 0x3A {
			ViolationAt(13)
		} else if list_at(bytes, 16) != 0x3A {
			ViolationAt(16)
		} else if list_at(bytes, 19) != 0x5A {
			ViolationAt(19)
		} else {
			year = digit_run_value(bytes, 0, 4)
			month = digit_run_value(bytes, 5, 2)
			day = digit_run_value(bytes, 8, 2)
			hour = digit_run_value(bytes, 11, 2)
			minute = digit_run_value(bytes, 14, 2)
			second = digit_run_value(bytes, 17, 2)
			if year == 0 {
				ViolationAt(0)
			} else if month == 0 or month > 12 {
				ViolationAt(5)
			} else if day == 0 or day > days_in_month(year, month) {
				ViolationAt(8)
			} else if hour > 23 {
				ViolationAt(11)
			} else if minute > 59 {
				ViolationAt(14)
			} else if second > 59 {
				ViolationAt(17)
			} else {
				NoViolation
			}
		}
	}
}

first_bad_digit : List(U8) -> [NoViolation, ViolationAt(U64)]
first_bad_digit = |bytes| {
	var $offset = NoViolation
	var $index = 0
	while $index < 20 and $offset == NoViolation {
		in_digit_run = $index <= 3 or ($index >= 5 and $index <= 6) or ($index >= 8 and $index <= 9) or ($index >= 11 and $index <= 12) or ($index >= 14 and $index <= 15) or ($index >= 17 and $index <= 18)
		if in_digit_run and !is_digit(list_at(bytes, $index)) {
			$offset = ViolationAt($index)
		}
		$index = $index + 1
	}
	$offset
}

digit_run_ok : List(U8), U64, U64 -> Bool
digit_run_ok = |bytes, start, count| {
	var $index = 0
	var $ok = True
	while $index < count and $ok {
		if !is_digit(list_at(bytes, start + $index)) {
			$ok = False
		}
		$index = $index + 1
	}
	$ok
}

digit_run_value : List(U8), U64, U64 -> U64
digit_run_value = |bytes, start, count| {
	var $value = 0
	var $index = 0
	while $index < count {
		$value = $value * 10 + (list_at(bytes, start + $index) - 0x30).to_u64()
		$index = $index + 1
	}
	$value
}

days_in_month : U64, U64 -> U64
days_in_month = |year, month| if month == 2 {
	leap = U64.mod_by(year, 4) == 0 and (U64.mod_by(year, 100) != 0 or U64.mod_by(year, 400) == 0)
	if (leap) 29 else 28
} else if month == 4 or month == 6 or month == 9 or month == 11 {
	30
} else {
	31
}

is_digit : U8 -> Bool
is_digit = |byte| byte >= 48 and byte <= 57

list_at : List(a), U64 -> a
list_at = |list, index| list.get(index) ?? crash "canonical timestamp index escaped its 20 source bytes"
