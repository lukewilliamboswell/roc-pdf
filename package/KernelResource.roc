import KernelLex

KernelResource :: [].{
	Kind := [ColorSpace, Font, IccProfile, Image, Pattern, Shading, XObject]

	Error : [
		EntryLimitExceeded({ attempted : U64, limit : U64 }),
		IdentityOverflow({ identity : U64, index : U64 }),
		NameBytesLimitExceeded({ attempted : U64, limit : U64 }),
		NameBytesOverflow,
		NonDenseIdentity({ actual : U64, expected : U64, index : U64, kind : Kind }),
		NonMonotonicKind({ current : Kind, index : U64, previous : Kind }),
	]

	NameId :: U64.{
		index : NameId -> U64
		index = |NameId.(index)| index
	}

	Entry :: { identity : U64, kind : Kind }.{
		identity : Entry -> U64
		identity = |entry| entry.identity

		kind : Entry -> Kind
		kind = |entry| entry.kind

		make : Kind, U64 -> Entry
		make = |resource_kind, resource_identity| Entry.{ identity: resource_identity, kind: resource_kind }
	}

	Limits :: { max_entries : U64, max_name_bytes : U64 }.{
		make : { max_entries : U64, max_name_bytes : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	Work :: {
		entries_checked : U64,
		identity_checks : U64,
		kind_comparisons : U64,
		name_bytes_emitted : U64,
	}.{
		entries_checked : Work -> U64
		entries_checked = |work| work.entries_checked

		identity_checks : Work -> U64
		identity_checks = |work| work.identity_checks

		kind_comparisons : Work -> U64
		kind_comparisons = |work| work.kind_comparisons

		name_bytes_emitted : Work -> U64
		name_bytes_emitted = |work| work.name_bytes_emitted
	}

	Plan :: {
		entries : List(Entry),
		name_bytes : List(U8),
		name_spans : List({ length : U64, start : U64 }),
		work : Work,
	}.{
		build : List(Entry), Limits -> Try(Plan, Error)
		build = |entries, limits| build_plan(entries, limits)

		entry : Plan, NameId -> Entry
		entry = |plan, id| list_at(plan.entries, NameId.index(id))

		entry_at : Plan, U64 -> Entry
		entry_at = |plan, index| list_at(plan.entries, index)

		entry_count : Plan -> U64
		entry_count = |plan| plan.entries.len()

		id_at : Plan, U64 -> NameId
		id_at = |_plan, index| NameId.(index)

		name : Plan, NameId -> List(U8)
		name = |plan, id| plan_name_at(plan, NameId.index(id))

		name_at : Plan, U64 -> List(U8)
		name_at = |plan, index| plan_name_at(plan, index)

		name_bytes : Plan -> U64
		name_bytes = |plan| plan.name_bytes.len()

		work : Plan -> Work
		work = |plan| plan.work
	}
}

build_plan : List(KernelResource.Entry), KernelResource.Limits -> Try(KernelResource.Plan, KernelResource.Error)
build_plan = |entries, limits| {
	entry_count = entries.len()
	if entry_count > limits.max_entries {
		Err(EntryLimitExceeded({ attempted: entry_count, limit: limits.max_entries }))
	} else {
		validated = validate_entries(entries, limits.max_name_bytes)?
		var $name_bytes = List.with_capacity(validated.name_bytes)
		var $name_spans = List.with_capacity(entry_count)
		var $index = 0
		while $index < entry_count {
			entry = list_at(entries, $index)
			start = $name_bytes.len()
			$name_bytes = append_prefix($name_bytes, entry.kind)
			$name_bytes = KernelLex.append_unsigned($name_bytes, entry.identity + 1)
			$name_spans = $name_spans.append({ length: $name_bytes.len() - start, start })
			$index = $index + 1
		}

		Ok(
			KernelResource.Plan.{
				entries,
				name_bytes: $name_bytes,
				name_spans: $name_spans,
				work: KernelResource.Work.{
					entries_checked: entry_count,
					identity_checks: entry_count,
					kind_comparisons: if entry_count == 0 0 else entry_count - 1,
					name_bytes_emitted: validated.name_bytes,
				},
			},
		)
	}
}

validate_entries : List(KernelResource.Entry), U64 -> Try({ name_bytes : U64 }, KernelResource.Error)
validate_entries = |entries, max_name_bytes| {
	entry_count = entries.len()
	var $index = 0
	var $has_previous = False
	var $previous_kind = ColorSpace
	var $previous_rank = 0
	var $next_identity = 0
	var $name_bytes = 0
	var $error = NoError

	while $index < entry_count and $error == NoError {
		entry = list_at(entries, $index)
		rank = kind_rank(entry.kind)
		if $has_previous and rank < $previous_rank {
			$error = Invalid(NonMonotonicKind({ current: entry.kind, index: $index, previous: $previous_kind }))
		} else {
			expected = if $has_previous and rank == $previous_rank $next_identity else 0
			if entry.identity != expected {
				$error = Invalid(NonDenseIdentity({ actual: entry.identity, expected, index: $index, kind: entry.kind }))
			} else if entry.identity == U64.highest {
				$error = Invalid(IdentityOverflow({ identity: entry.identity, index: $index }))
			} else {
				one_based = entry.identity + 1
				name_length = prefix_length(entry.kind) + decimal_digits(one_based)
				if U64.highest - $name_bytes < name_length {
					$error = Invalid(NameBytesOverflow)
				} else {
					attempted = $name_bytes + name_length
					if attempted > max_name_bytes {
						$error = Invalid(NameBytesLimitExceeded({ attempted, limit: max_name_bytes }))
					} else {
						$name_bytes = attempted
						$has_previous = True
						$previous_kind = entry.kind
						$previous_rank = rank
						$next_identity = one_based
					}
				}
			}
		}
		$index = $index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ name_bytes: $name_bytes })
	}
}

kind_rank : KernelResource.Kind -> U8
kind_rank = |kind| match kind {
	ColorSpace => 0
	Font => 1
	IccProfile => 2
	Image => 3
	Pattern => 4
	Shading => 5
	XObject => 6
}

prefix_length : KernelResource.Kind -> U64
prefix_length = |kind| match kind {
	ColorSpace => 2
	Font => 1
	IccProfile => 3
	Image => 2
	Pattern => 1
	Shading => 2
	XObject => 2
}

append_prefix : List(U8), KernelResource.Kind -> List(U8)
append_prefix = |output, kind| match kind {
	ColorSpace => output.append(67).append(83)
	Font => output.append(70)
	IccProfile => output.append(73).append(67).append(67)
	Image => output.append(73).append(109)
	Pattern => output.append(80)
	Shading => output.append(83).append(104)
	XObject => output.append(88).append(79)
}

decimal_digits : U64 -> U64
decimal_digits = |value| {
	var $remaining = value
	var $digits = 1
	while $remaining >= 10 {
		$remaining = U64.div_by($remaining, 10)
		$digits = $digits + 1
	}
	$digits
}

plan_name_at : KernelResource.Plan, U64 -> List(U8)
plan_name_at = |plan, index| {
	span = list_at(plan.name_spans, index)
	plan.name_bytes.sublist({ start: span.start, len: span.length })
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated resource-name index escaped"
	}
}

## Empty resource dictionaries need no synthetic name entries.
expect {
	plan = KernelResource.Plan.build([], KernelResource.Limits.make({ max_entries: 0, max_name_bytes: 0 }))?
	work = KernelResource.Plan.work(plan)
	KernelResource.Plan.entry_count(plan) == 0 and
		KernelResource.Plan.name_bytes(plan) == 0 and
			KernelResource.Work.entries_checked(work) == 0
}

## Kind prefixes and one-based dense identities form canonical resource names.
expect {
	entries = [
		KernelResource.Entry.make(ColorSpace, 0),
		KernelResource.Entry.make(Font, 0),
		KernelResource.Entry.make(Font, 1),
		KernelResource.Entry.make(IccProfile, 0),
		KernelResource.Entry.make(Image, 0),
		KernelResource.Entry.make(Pattern, 0),
		KernelResource.Entry.make(Shading, 0),
		KernelResource.Entry.make(XObject, 0),
	]
	plan = KernelResource.Plan.build(entries, KernelResource.Limits.make({ max_entries: 8, max_name_bytes: 32 }))?

	KernelResource.Plan.name_at(plan, 0) == Str.to_utf8("CS1") and
		KernelResource.Plan.name_at(plan, 1) == Str.to_utf8("F1") and
			KernelResource.Plan.name_at(plan, 2) == Str.to_utf8("F2") and
				KernelResource.Plan.name_at(plan, 3) == Str.to_utf8("ICC1") and
					KernelResource.Plan.name_at(plan, 4) == Str.to_utf8("Im1") and
						KernelResource.Plan.name_at(plan, 5) == Str.to_utf8("P1") and
							KernelResource.Plan.name_at(plan, 6) == Str.to_utf8("Sh1") and
								KernelResource.Plan.name_at(plan, 7) == Str.to_utf8("XO1")
}

## Decimal-width transitions use the same canonical unsigned lexical policy.
expect {
	var $entries = List.with_capacity(10)
	var $index = 0
	while $index < 10 {
		$entries = $entries.append(KernelResource.Entry.make(Font, $index))
		$index = $index + 1
	}
	plan = KernelResource.Plan.build($entries, KernelResource.Limits.make({ max_entries: 10, max_name_bytes: 32 }))?
	KernelResource.Plan.name_at(plan, 8) == Str.to_utf8("F9") and KernelResource.Plan.name_at(plan, 9) == Str.to_utf8("F10")
}

## A kind-order reversal is rejected before a plan can escape.
expect match KernelResource.Plan.build(
	[KernelResource.Entry.make(Font, 0), KernelResource.Entry.make(ColorSpace, 0)],
	KernelResource.Limits.make({ max_entries: 2, max_name_bytes: 8 }),
) {
	Err(NonMonotonicKind({ current: ColorSpace, index: 1, previous: Font })) => True
	_ => False
}

## Duplicate, skipped, and nonzero-first identities are one dense-order error.
expect {
	limits = KernelResource.Limits.make({ max_entries: 2, max_name_bytes: 8 })
	duplicate = KernelResource.Plan.build(
		[KernelResource.Entry.make(Font, 0), KernelResource.Entry.make(Font, 0)],
		limits,
	)
	skipped = KernelResource.Plan.build(
		[KernelResource.Entry.make(Font, 0), KernelResource.Entry.make(Font, 2)],
		limits,
	)
	first = KernelResource.Plan.build([KernelResource.Entry.make(Font, 1)], limits)

	match duplicate {
		Err(NonDenseIdentity({ actual: 0, expected: 1, index: 1, kind: Font })) => match skipped {
			Err(NonDenseIdentity({ actual: 2, expected: 1, index: 1, kind: Font })) => match first {
				Err(NonDenseIdentity({ actual: 1, expected: 0, index: 0, kind: Font })) => True
				_ => False
			}
			_ => False
		}
		_ => False
	}
}

## Entry and aggregate-name limits reject the exact attempted dimension.
expect {
	entry = KernelResource.Entry.make(Font, 0)
	too_many = KernelResource.Plan.build([entry], KernelResource.Limits.make({ max_entries: 0, max_name_bytes: 2 }))
	too_many_bytes = KernelResource.Plan.build([entry], KernelResource.Limits.make({ max_entries: 1, max_name_bytes: 1 }))

	match too_many {
		Err(EntryLimitExceeded({ attempted: 1, limit: 0 })) => match too_many_bytes {
			Err(NameBytesLimitExceeded({ attempted: 2, limit: 1 })) => True
			_ => False
		}
		_ => False
	}
}
