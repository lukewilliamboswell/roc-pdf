import fuzz.Model
import pdf.Document
import pdf.KernelNavigation
import pdf.KernelPageLabels

PageLabelModel := [].{}

Flavor : [Decimal, UpperRoman, LowerRoman, UpperLetters, LowerLetters, PrefixOnly, Empty, MaxStart, TooLarge, Zero, NumberWithoutStyle, LongPrefix]

RangeChoice : { page : U64, flavor : Flavor }

flavors : List(Flavor)
flavors = [Decimal, UpperRoman, LowerRoman, UpperLetters, LowerLetters, PrefixOnly, Empty, MaxStart, TooLarge, Zero, NumberWithoutStyle, LongPrefix]

# Five physical pages with zero, one, or two authored range starts. Later
# starts include a restart, a duplicate, and one outside the document.
machine : Model.Machine(List(RangeChoice), RangeChoice)
machine = {
	init: [],
	actions: |ranges| match ranges.len() {
		0 => actions([0, 1])
		1 => actions([0, 2, 4, 5])
		_ => []
	},
	step: |ranges, range| ranges.append(range),
	rules: [
		Model.always("validation and each visible label agree with the authored ranges", agrees),
		witness("an alphabetic restart follows a Roman range", [{ page: 0, flavor: UpperRoman }, { page: 2, flavor: UpperLetters }]),
		witness("an empty prefix-only range follows a numbered range", [{ page: 0, flavor: LowerLetters }, { page: 4, flavor: Empty }]),
		witness("a multibyte prefix needs its full byte budget", [{ page: 0, flavor: PrefixOnly }]),
		witness("the largest PDF integer starts a valid range", [{ page: 0, flavor: MaxStart }]),
		witness("the second range exceeds the positive PDF integer domain", [{ page: 0, flavor: Decimal }, { page: 2, flavor: TooLarge }]),
		witness("a duplicate start wins over the number error", [{ page: 0, flavor: Decimal }, { page: 0, flavor: TooLarge }]),
	],
}

actions : List(U64) -> List(RangeChoice)
actions = |starts| starts.map(|page| flavors.map(|flavor| { page, flavor })).join()

witness : Str, List(RangeChoice) -> Model.Rule(List(RangeChoice), RangeChoice)
witness = |name, example| Model.sometimes(name, |ranges| ranges == example)

# The writer's signed integer bound is represented here as a literal
# so the model can detect a change in the accepted domain.
last_pdf_integer : U64
last_pdf_integer = 9223372036854775807

describe : Flavor -> { prefix : Str, start_number : U64, style : Document.PageLabelStyle }
describe = |flavor| match flavor {
	Decimal => { prefix: "p-", start_number: 8, style: DecimalArabic }
	UpperRoman => { prefix: "", start_number: 8, style: RomanUpper }
	LowerRoman => { prefix: "", start_number: 4, style: RomanLower }
	UpperLetters => { prefix: "", start_number: 25, style: LettersUpper }
	LowerLetters => { prefix: "", start_number: 51, style: LettersLower }
	PrefixOnly => { prefix: "é中", start_number: 1, style: NoNumber }
	Empty => { prefix: "", start_number: 1, style: NoNumber }
	MaxStart => { prefix: "", start_number: last_pdf_integer, style: DecimalArabic }
	TooLarge => { prefix: "", start_number: last_pdf_integer + 1, style: DecimalArabic }
	Zero => { prefix: "", start_number: 0, style: DecimalArabic }
	NumberWithoutStyle => { prefix: "", start_number: U64.highest, style: NoNumber }
	LongPrefix => { prefix: "ééé", start_number: 0, style: DecimalArabic }
}

authored : RangeChoice -> Document.PageLabelRange
authored = |range| {
	facts = describe(range.flavor)
	{ prefix: facts.prefix, start_number: facts.start_number, start_page: range.page, style: facts.style }
}

# Table 161's numbering runs in literal lexical examples. In particular the
# letters repeat (AA, BB, ...), and only the authored /St is a PDF integer.
# Consecutive visible decimal values can exceed that serialized start domain.
expected_labels : Flavor -> List(Str)
expected_labels = |flavor| match flavor {
	Decimal => ["p-8", "p-9", "p-10", "p-11", "p-12"]
	UpperRoman => ["VIII", "IX", "X", "XI", "XII"]
	LowerRoman => ["iv", "v", "vi", "vii", "viii"]
	UpperLetters => ["Y", "Z", "AA", "BB", "CC"]
	LowerLetters => ["yy", "zz", "aaa", "bbb", "ccc"]
	MaxStart => ["9223372036854775807", "9223372036854775808", "9223372036854775809", "9223372036854775810", "9223372036854775811"]
	Empty => ["", "", "", "", ""]
	_ => []
}

expected_bytes : List(RangeChoice), U64 -> List(U8)
expected_bytes = |ranges, page| match ranges.keep_if(|range| range.page <= page).last() {
	Ok({ flavor: PrefixOnly, .. }) => [195, 169, 228, 184, 173]
	Ok(range) => (expected_labels(range.flavor).get(page - range.page) ?? crash "missing model label").to_utf8()
	Err(ListWasEmpty) => (["1", "2", "3", "4", "5"].get(page) ?? crash "missing model page").to_utf8()
}

expected_rejection : List(RangeChoice) -> [Accepted, Rejected(Document.NavigationError)]
expected_rejection = |ranges| {
	var $index = 0
	for range in ranges {
		# This menu's only nonzero initial page is one, and a second
		# start at zero is always duplicate or descending.
		if $index == 0 and range.page != 0 {
			return Rejected(LabelStartPageNotZero({ start: range.page }))
		}
		if $index == 1 and range.page == 0 {
			return Rejected(LabelRangeNotAscending({ range: $index }))
		}
		if range.page == 5 {
			return Rejected(LabelStartPageOutOfRange({ attempted: 5, pages: 5, range: $index }))
		}
		match range.flavor {
			TooLarge => return Rejected(LabelStartNumberOutOfRange({ attempted: last_pdf_integer + 1, limit: last_pdf_integer, range: $index }))
			Zero => return Rejected(LabelStartNumberZero({ range: $index }))
			NumberWithoutStyle => return Rejected(LabelNumberWithoutStyle({ range: $index }))
			LongPrefix => return Rejected(LabelPrefixTooLong({ attempted: 6, limit: 5, range: $index }))
			_ => {}
		}
		$index = $index + 1
	}
	Accepted
}

agrees : List(RangeChoice) -> Bool
agrees = |ranges| {
	limits = KernelNavigation.Limits.make({ ..KernelNavigation.standard_limit_values, max_label_prefix_bytes: 5 })
	match (KernelNavigation.LabelPlan.build(ranges.map(authored), 5, limits), expected_rejection(ranges)) {
		(Err(actual), Rejected(expected)) => actual == expected
		(Ok(plan), Accepted) => {
			KernelPageLabels.format(plan, 5, 0) == Err(InvalidPage) and
				KernelPageLabels.format_allow_empty(plan, 5, 0) == Err(InvalidPage) and
					[0, 1, 2, 3, 4].all(
						|page| {
							bytes = expected_bytes(ranges, page)
							[0, 4, 5, 20].all(
								|limit| {
									expected = if (bytes.len() > limit) Err(LimitExceeded({ attempted: bytes.len(), limit })) else Ok(bytes)
									body = if (bytes.is_empty()) Err(EmptyLabel) else expected
									KernelPageLabels.format(plan, page, limit).map_ok(Str.to_utf8) == body and
										KernelPageLabels.format_allow_empty(plan, page, limit).map_ok(Str.to_utf8) == expected
								},
							)
						},
					)
		}
		_ => False
	}
}

# The EC3 12.4.2 example restarts at physical indices 4 and 7.
expect {
	ranges = [
		{ prefix: "", start_number: 1, start_page: 0, style: RomanLower },
		{ prefix: "", start_number: 1, start_page: 4, style: DecimalArabic },
		{ prefix: "A-", start_number: 8, start_page: 7, style: DecimalArabic },
	]
	plan = KernelNavigation.LabelPlan.build(ranges, 10, KernelNavigation.standard_limits)?
	["i", "ii", "iii", "iv", "1", "2", "3", "A-8", "A-9", "A-10"].map_with_index(|text, page|
		KernelPageLabels.format(plan, page, 4) == Ok(text)).all(|matches| matches)
}

expect {
	report = Model.explore(machine, { depth: 3, key: |ranges| ranges, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 1177 and report.steps == 1176 and report.depth == 2 and report.reached.len() == 6
}
