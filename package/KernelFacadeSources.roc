import KernelUnicode
import Semantics
import unicode.Scalar

KernelFacadeSources :: [].{
	Dimension : [HashProbes, Inputs, SourceBytes, SourceScalars, TableSlots, UniqueSources]
	Error : [
		ArithmeticOverflow,
		EmptySource({ input : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		TableExhausted,
		Unicode(KernelUnicode.UnicodeError),
	]
	Limits :: {
		max_hash_probes : U64,
		max_inputs : U64,
		max_source_bytes : U64,
		max_source_scalars : U64,
		max_table_slots : U64,
		max_unique_sources : U64,
		unicode : KernelUnicode.UnicodeLimits,
	}.{
		make : {
			max_hash_probes : U64,
			max_inputs : U64,
			max_source_bytes : U64,
			max_source_scalars : U64,
			max_table_slots : U64,
			max_unique_sources : U64,
			unicode : KernelUnicode.UnicodeLimits,
		} -> Limits
		make = |limits| Limits.(limits)
	}
	Source : { analysis : KernelUnicode.UnicodeAnalysis, unicode : Str }
	Work : {
		adjacent_hits : U64,
		equality_byte_bound : U64,
		equality_checks : U64,
		hash_scalar_visits : U64,
		inputs : U64,
		probes : U64,
		table_slots : U64,
		unique_source_bytes : U64,
		unique_source_scalars : U64,
		unique_sources : U64,
	}
	Plan :: { input_sources : List(Semantics.TextSourceId), sources : List(Source), work : Work }.{
		build : List(Str), Limits -> Try(Plan, Error)
		build = |inputs, limits| build_plan(inputs, limits)

		## Append exact resolved sources after pagination, reusing every
		## existing Unicode analysis and preserving all source identities.
		extend : Plan, List(Str), Limits -> Try(Plan, Error)
		extend = |plan, inputs, limits| extend_plan(plan, inputs, limits)

		input_sources : Plan -> List(Semantics.TextSourceId)
		input_sources = |plan| plan.input_sources

		sources : Plan -> List(Source)
		sources = |plan| plan.sources

		work : Plan -> Work
		work = |plan| plan.work
	}
}

empty_slot : U64
empty_slot = U64.highest

hash_offset : U64
hash_offset = 14695981039346656037

build_plan : List(Str), KernelFacadeSources.Limits -> Try(KernelFacadeSources.Plan, KernelFacadeSources.Error)
build_plan = |inputs, limits| {
	check_limit(inputs.len(), limits.max_inputs, Inputs)?
	capacity = table_capacity(inputs.len(), limits.max_table_slots)?
	var $slots = List.repeat(empty_slot, capacity)
	var $sources = []
	var $input_sources = List.with_capacity(inputs.len())
	var $source_bytes = 0
	var $source_scalars = 0
	var $hash_scalar_visits = 0
	var $probes = 0
	var $equality_checks = 0
	var $equality_byte_bound = 0
	var $adjacent_hits = 0
	var $previous = empty_slot
	var $input_index = 0
	while $input_index < inputs.len() {
		source = list_at(inputs, $input_index)
		if source.is_empty() {
			return Err(EmptySource({ input: $input_index }))
		}
		var $resolved = False
		if $previous != empty_slot {
			adjacent = list_at($sources, $previous)
			$equality_checks = checked_add($equality_checks, 1)?
			$equality_byte_bound = checked_add($equality_byte_bound, U64.max(adjacent.unicode.count_utf8_bytes(), source.count_utf8_bytes()))?
			if adjacent.unicode == source {
				$input_sources = $input_sources.append(Semantics.TextSourceId.from_index($previous))
				$adjacent_hits = checked_add($adjacent_hits, 1)?
				$resolved = True
			}
		}
		if $resolved == False {
			hashed = hash_source(source)
			$hash_scalar_visits = checked_add($hash_scalar_visits, hashed.scalars)?
			var $probe = 0
			while $probe < capacity and $resolved == False {
				$probes = checked_add($probes, 1)?
				check_limit($probes, limits.max_hash_probes, HashProbes)?
				slot_index = (hashed.value + $probe) % capacity
				candidate = list_at($slots, slot_index)
				if candidate == empty_slot {
					unique_count = checked_add($sources.len(), 1)?
					check_limit(unique_count, limits.max_unique_sources, UniqueSources)?
					analysis = KernelUnicode.analyze(source, limits.unicode) ? Unicode
					$source_bytes = checked_add($source_bytes, source.count_utf8_bytes())?
					$source_scalars = checked_add($source_scalars, analysis.work.scalar_visits)?
					check_limit($source_bytes, limits.max_source_bytes, SourceBytes)?
					check_limit($source_scalars, limits.max_source_scalars, SourceScalars)?
					id = $sources.len()
					$sources = $sources.append({ analysis, unicode: source })
					$slots = list_set($slots, slot_index, id)
					$input_sources = $input_sources.append(Semantics.TextSourceId.from_index(id))
					$resolved = True
				} else {
					candidate_source = list_at($sources, candidate).unicode
					$equality_checks = checked_add($equality_checks, 1)?
					$equality_byte_bound = checked_add($equality_byte_bound, U64.max(candidate_source.count_utf8_bytes(), source.count_utf8_bytes()))?
					if candidate_source == source {
						$input_sources = $input_sources.append(Semantics.TextSourceId.from_index(candidate))
						$resolved = True
					}
				}
				$probe = $probe + 1
			}
		}
		if $resolved == False {
			return Err(TableExhausted)
		}
		$previous = list_at($input_sources, $input_sources.len() - 1).index()
		$input_index = $input_index + 1
	}
	Ok(
		KernelFacadeSources.Plan.{
			input_sources: $input_sources,
			sources: $sources,
			work: {
				adjacent_hits: $adjacent_hits,
				equality_byte_bound: $equality_byte_bound,
				equality_checks: $equality_checks,
				hash_scalar_visits: $hash_scalar_visits,
				inputs: inputs.len(),
				probes: $probes,
				table_slots: capacity,
				unique_source_bytes: $source_bytes,
				unique_source_scalars: $source_scalars,
				unique_sources: $sources.len(),
			},
		},
	)
}

extend_plan : KernelFacadeSources.Plan, List(Str), KernelFacadeSources.Limits -> Try(KernelFacadeSources.Plan, KernelFacadeSources.Error)
extend_plan = |plan, inputs, limits| {
	initial = plan.work
	first_input = plan.input_sources.len()
	total_inputs = checked_add(first_input, inputs.len())?
	check_limit(total_inputs, limits.max_inputs, Inputs)?
	capacity = table_capacity(total_inputs, limits.max_table_slots)?
	var $slots = List.repeat(empty_slot, capacity)
	var $sources = plan.sources
	var $input_sources = plan.input_sources
	var $source_bytes = initial.unique_source_bytes
	var $source_scalars = initial.unique_source_scalars
	var $hash_scalar_visits = initial.hash_scalar_visits
	var $probes = initial.probes
	var $equality_checks = initial.equality_checks
	var $equality_byte_bound = initial.equality_byte_bound
	var $adjacent_hits = initial.adjacent_hits
	var $previous = if $input_sources.is_empty() empty_slot else list_at($input_sources, $input_sources.len() - 1).index()

	## Rebuild only the bounded interning index; source Unicode facts are
	## retained. Every hash/probe is charged to the same work/error bounds.
	var $seed = 0
	while $seed < $sources.len() {
		hashed = hash_source(list_at($sources, $seed).unicode)
		$hash_scalar_visits = checked_add($hash_scalar_visits, hashed.scalars)?
		var $probe = 0
		var $placed = False
		while $probe < capacity and !$placed {
			$probes = checked_add($probes, 1)?
			check_limit($probes, limits.max_hash_probes, HashProbes)?
			slot_index = (hashed.value + $probe) % capacity
			if list_at($slots, slot_index) == empty_slot {
				$slots = list_set($slots, slot_index, $seed)
				$placed = True
			}
			$probe = $probe + 1
		}
		if !$placed {
			return Err(TableExhausted)
		}
		$seed = $seed + 1
	}
	var $input_index = 0
	while $input_index < inputs.len() {
		source = list_at(inputs, $input_index)
		if source.is_empty() {
			return Err(EmptySource({ input: first_input + $input_index }))
		}
		var $resolved = False
		if $previous != empty_slot {
			adjacent = list_at($sources, $previous)
			$equality_checks = checked_add($equality_checks, 1)?
			$equality_byte_bound = checked_add($equality_byte_bound, U64.max(adjacent.unicode.count_utf8_bytes(), source.count_utf8_bytes()))?
			if adjacent.unicode == source {
				$input_sources = $input_sources.append(Semantics.TextSourceId.from_index($previous))
				$adjacent_hits = checked_add($adjacent_hits, 1)?
				$resolved = True
			}
		}
		if $resolved == False {
			hashed = hash_source(source)
			$hash_scalar_visits = checked_add($hash_scalar_visits, hashed.scalars)?
			var $probe = 0
			while $probe < capacity and $resolved == False {
				$probes = checked_add($probes, 1)?
				check_limit($probes, limits.max_hash_probes, HashProbes)?
				slot_index = (hashed.value + $probe) % capacity
				candidate = list_at($slots, slot_index)
				if candidate == empty_slot {
					unique_count = checked_add($sources.len(), 1)?
					check_limit(unique_count, limits.max_unique_sources, UniqueSources)?
					analysis = KernelUnicode.analyze(source, limits.unicode) ? Unicode
					$source_bytes = checked_add($source_bytes, source.count_utf8_bytes())?
					$source_scalars = checked_add($source_scalars, analysis.work.scalar_visits)?
					check_limit($source_bytes, limits.max_source_bytes, SourceBytes)?
					check_limit($source_scalars, limits.max_source_scalars, SourceScalars)?
					id = $sources.len()
					$sources = $sources.append({ analysis, unicode: source })
					$slots = list_set($slots, slot_index, id)
					$input_sources = $input_sources.append(Semantics.TextSourceId.from_index(id))
					$resolved = True
				} else {
					candidate_source = list_at($sources, candidate).unicode
					$equality_checks = checked_add($equality_checks, 1)?
					$equality_byte_bound = checked_add($equality_byte_bound, U64.max(candidate_source.count_utf8_bytes(), source.count_utf8_bytes()))?
					if candidate_source == source {
						$input_sources = $input_sources.append(Semantics.TextSourceId.from_index(candidate))
						$resolved = True
					}
				}
				$probe = $probe + 1
			}
		}
		if $resolved == False {
			return Err(TableExhausted)
		}
		$previous = list_at($input_sources, $input_sources.len() - 1).index()
		$input_index = $input_index + 1
	}
	Ok(
		KernelFacadeSources.Plan.{
			input_sources: $input_sources,
			sources: $sources,
			work: {
				adjacent_hits: $adjacent_hits,
				equality_byte_bound: $equality_byte_bound,
				equality_checks: $equality_checks,
				hash_scalar_visits: $hash_scalar_visits,
				inputs: total_inputs,
				probes: $probes,
				table_slots: capacity,
				unique_source_bytes: $source_bytes,
				unique_source_scalars: $source_scalars,
				unique_sources: $sources.len(),
			},
		},
	)
}

table_capacity : U64, U64 -> Try(U64, KernelFacadeSources.Error)
table_capacity = |inputs, limit| {
	required = checked_mul(inputs, 2)?
	var $capacity = 8
	while $capacity < required {
		$capacity = checked_mul($capacity, 2)?
	}
	check_limit($capacity, limit, TableSlots)?
	Ok($capacity)
}

hash_source : Str -> { scalars : U64, value : U64 }
hash_source = |source| {
	var $hash = hash_offset
	var $scalars = 0
	for located in Scalar.iter(source) {
		mixed = $hash.bitwise_xor(Scalar.to_u32(located.scalar).to_u64())
		left = mixed.bitwise_xor(mixed.shl_wrap(13))
		right = left.bitwise_xor(left.shr_wrap(7))
		$hash = right.bitwise_xor(right.shl_wrap(17))
		$scalars = $scalars + 1
	}
	{ scalars: $scalars, value: $hash }
}

check_limit : U64, U64, KernelFacadeSources.Dimension -> Try({}, KernelFacadeSources.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelFacadeSources.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(_) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_mul : U64, U64 -> Try(U64, KernelFacadeSources.Error)
checked_mul = |left, right| {
	if left == 0 or right == 0 {
		return Ok(0)
	}
	if left > U64.highest / right {
		Err(ArithmeticOverflow)
	} else {
		Ok(left * right)
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated facade source index escaped"
	}
	Ok(value) => value
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated facade source table index escaped"
	}
	Ok(updated) => updated
}

test_limits : KernelFacadeSources.Limits
test_limits = KernelFacadeSources.Limits.make({
	max_hash_probes: 32,
	max_inputs: 8,
	max_source_bytes: 32,
	max_source_scalars: 32,
	max_table_slots: 16,
	max_unique_sources: 8,
	unicode: { max_graphemes: 16, max_line_boundaries: 17, max_scalars: 16, max_script_runs: 8 },
})

# Equal immutable strings share one Unicode analysis and source identity.
expect {
	plan = KernelFacadeSources.Plan.build(["Body", "Body", "Café"], test_limits)?
	ids = KernelFacadeSources.Plan.input_sources(plan)
	work = KernelFacadeSources.Plan.work(plan)
	KernelFacadeSources.Plan.sources(plan).len() == 2 and list_at(ids, 0).index() == 0 and list_at(ids, 1).index() == 0 and list_at(ids, 2).index() == 1 and work.inputs == 3 and work.unique_sources == 2 and work.unique_source_scalars == 8
}

# The fast path follows the previous resolved input identity, even after a
# non-adjacent hash-table hit.
expect {
	plan = KernelFacadeSources.Plan.build(["A", "B", "A", "A"], test_limits)?
	ids = KernelFacadeSources.Plan.input_sources(plan)
	work = KernelFacadeSources.Plan.work(plan)
	ids.map(|id| id.index()) == [0, 1, 0, 0] and work.unique_sources == 2 and work.adjacent_hits == 1
}

# The first probe crossing fails atomically under its explicit work bound.
expect {
	limits = KernelFacadeSources.Limits.make({
		max_hash_probes: 0,
		max_inputs: 8,
		max_source_bytes: 32,
		max_source_scalars: 32,
		max_table_slots: 16,
		max_unique_sources: 8,
		unicode: { max_graphemes: 16, max_line_boundaries: 17, max_scalars: 16, max_script_runs: 8 },
	})
	match KernelFacadeSources.Plan.build(["Body"], limits) {
		Err(LimitExceeded({ attempted: 1, dimension: HashProbes, limit: 0 })) => True
		_ => False
	}
}

expect match KernelFacadeSources.Plan.build([""], test_limits) {
	Err(EmptySource({ input: 0 })) => True
	_ => False
}

# Late exact labels reuse existing source identities and Unicode analyses;
# the explicit index rebuild is charged, without analyzing literal text again.
expect {
	initial = KernelFacadeSources.Plan.build(["Café", "A"], test_limits)?
	final = KernelFacadeSources.Plan.extend(initial, ["Café", "12", "12"], test_limits)?
	KernelFacadeSources.Plan.input_sources(final).map(|id| id.index()) == [0, 1, 0, 2, 2]
		and KernelFacadeSources.Plan.sources(final).map(|source| source.unicode) == ["Café", "A", "12"]
			and KernelFacadeSources.Plan.work(final).unique_source_scalars == 7
}
