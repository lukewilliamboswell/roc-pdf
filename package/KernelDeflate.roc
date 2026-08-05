import deflate.Deflate exposing [Deflate]

WriteState : { bits : U64, bytes : List(U8), count : U8 }

BlockResult : {
	bits : U64,
	bytes : List(U8),
	candidate_visits : U64,
	count : U8,
	hash_inserts : U64,
	matches : U64,
	tokens : U64,
}

KernelDeflate :: [].{
	Error : [
		ArithmeticOverflow,
		InputLimitExceeded({ attempted : U64, limit : U64 }),
		OutputBoundExceeded({ bound : U64, attempted : U64 }),
		OutputLimitExceeded({ attempted : U64, limit : U64 }),
	]

	Limits :: {
		max_input_bytes : U64,
		max_output_bytes : U64,
	}.{
		make : { max_input_bytes : U64, max_output_bytes : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	Work :: {
		blocks : U64,
		candidate_visits : U64,
		emitted_bytes : U64,
		hash_inserts : U64,
		input_bytes : U64,
		matches : U64,
		max_chunk_bytes : U64,
		tokens : U64,
	}.{
		zero : Work
		zero = Work.{
			blocks: 0,
			candidate_visits: 0,
			emitted_bytes: 0,
			hash_inserts: 0,
			input_bytes: 0,
			matches: 0,
			max_chunk_bytes: 0,
			tokens: 0,
		}

		empty_stream : Work
		empty_stream = Work.{
			blocks: 1,
			candidate_visits: 0,
			emitted_bytes: 8,
			hash_inserts: 0,
			input_bytes: 0,
			matches: 0,
			max_chunk_bytes: 8,
			tokens: 0,
		}

		add : Work, Work -> Try(Work, Error)
		add = |left, right| add_work_totals(left, right)

		blocks : Work -> U64
		blocks = |work| work.blocks

		candidate_visits : Work -> U64
		candidate_visits = |work| work.candidate_visits

		emitted_bytes : Work -> U64
		emitted_bytes = |work| work.emitted_bytes

		hash_inserts : Work -> U64
		hash_inserts = |work| work.hash_inserts

		input_bytes : Work -> U64
		input_bytes = |work| work.input_bytes

		matches : Work -> U64
		matches = |work| work.matches

		max_chunk_bytes : Work -> U64
		max_chunk_bytes = |work| work.max_chunk_bytes

		tokens : Work -> U64
		tokens = |work| work.tokens
	}

	Plan :: {
		input : List(U8),
		output_bound : U64,
	}.{
		prepare : List(U8), Limits -> Try(Plan, Error)
		prepare = |input, limits| prepare_plan(input, limits)

		input_bytes : Plan -> U64
		input_bytes = |plan| plan.input.len()

		output_bound : Plan -> U64
		output_bound = |plan| plan.output_bound
	}

	Step : [Done(Work), Emit(List(U8), Encoder)]

	Encoder :: {
		adler_a : U64,
		adler_b : U64,
		bits : U64,
		bit_count : U8,
		finished : Bool,
		plan : Plan,
		position : U64,
		started : Bool,
		work : Work,
	}.{
		start : Plan -> Encoder
		start = |plan| Encoder.{
			adler_a: 1,
			adler_b: 0,
			bits: 0,
			bit_count: 0,
			finished: False,
			plan,
			position: 0,
			started: False,
			work: Work.zero,
		}

		next : Encoder -> Try(Step, Error)
		next = |encoder| next_chunk(encoder)

		work : Encoder -> Work
		work = |encoder| encoder.work
	}

	output_bound : U64 -> Try(U64, Error)
	output_bound = |input_bytes| compressed_output_bound(input_bytes)

	to_bytes : Plan -> Try({ bytes : List(U8), work : Work }, Error)
	to_bytes = |plan| {
		var $encoder = Encoder.start(plan)
		var $bytes = []
		var $work = Encoder.work($encoder)
		var $done = False
		while $done == False {
			match Encoder.next($encoder)? {
				Done(work) => {
					$work = work
					$done = True
				}
				Emit(chunk, next) => {
					$bytes = append_all($bytes, chunk)
					$encoder = next
				}
			}
		}
		Ok({ bytes: $bytes, work: $work })
	}
}

add_work_totals : KernelDeflate.Work, KernelDeflate.Work -> Try(KernelDeflate.Work, KernelDeflate.Error)
add_work_totals = |left, right| {
	Ok(
		KernelDeflate.Work.{
			blocks: checked_add(left.blocks, right.blocks)?,
			candidate_visits: checked_add(left.candidate_visits, right.candidate_visits)?,
			emitted_bytes: checked_add(left.emitted_bytes, right.emitted_bytes)?,
			hash_inserts: checked_add(left.hash_inserts, right.hash_inserts)?,
			input_bytes: checked_add(left.input_bytes, right.input_bytes)?,
			matches: checked_add(left.matches, right.matches)?,
			max_chunk_bytes: U64.max(left.max_chunk_bytes, right.max_chunk_bytes),
			tokens: checked_add(left.tokens, right.tokens)?,
		},
	)
}

block_input_limit : U64
block_input_limit = 65535

window_size : U64
window_size = 32768

hash_size : U64
hash_size = 32768

match_search_limit : U64
match_search_limit = 128

min_match : U64
min_match = 3

max_match : U64
max_match = 258

adler_modulus : U64
adler_modulus = 65521

prepare_plan : List(U8), KernelDeflate.Limits -> Try(KernelDeflate.Plan, KernelDeflate.Error)
prepare_plan = |input, limits| {
	input_bytes = input.len()
	if input_bytes > limits.max_input_bytes {
		Err(InputLimitExceeded({ attempted: input_bytes, limit: limits.max_input_bytes }))
	} else {
		bound = compressed_output_bound(input_bytes)?
		if bound > limits.max_output_bytes {
			Err(OutputLimitExceeded({ attempted: bound, limit: limits.max_output_bytes }))
		} else {
			# Prove the largest deterministic work counter before a plan escapes.
			_ = checked_times(input_bytes, match_search_limit)?
			Ok(KernelDeflate.Plan.{ input, output_bound: bound })
		}
	}
}

compressed_output_bound : U64 -> Try(U64, KernelDeflate.Error)
compressed_output_bound = |input_bytes| {
	if input_bytes == 0 {
		Ok(8)
	} else {
		blocks = U64.div_by(input_bytes - 1, block_input_limit) + 1
		token_bits = checked_times(input_bytes, 9)?
		block_bits = checked_times(blocks, 349)?
		bits = checked_add(token_bits, block_bits)?
		bytes = U64.div_by(checked_add(bits, 7)?, 8)
		checked_add(bytes, 6)
	}
}

next_chunk : KernelDeflate.Encoder -> Try(KernelDeflate.Step, KernelDeflate.Error)
next_chunk = |encoder| {
	if encoder.finished {
		Ok(Done(encoder.work))
	} else if encoder.plan.input.is_empty() and encoder.started == False {
		bytes = [120, 156, 3, 0, 0, 0, 0, 1]
		work = KernelDeflate.Work.empty_stream
		released = release_input(encoder.plan)
		Ok(Emit(bytes, encoder_with(encoder, released, 0, 0, 0, 1, 0, True, True, work)))
	} else {
		remaining = encoder.plan.input.len() - encoder.position
		length = U64.min(remaining, block_input_limit)
		final = length == remaining
		block = encoder.plan.input.sublist({ start: encoder.position, len: length })
		capacity = block_chunk_capacity(length, encoder.started == False, final)?
		var $bytes = List.with_capacity(capacity)
		if encoder.started == False {
			$bytes = $bytes.append(120).append(156)
		}
		written = encode_dynamic_block(block, final, $bytes, encoder.bits, encoder.bit_count)
		{ a, b } = update_adler(block, encoder.adler_a, encoder.adler_b)
		finalized = if final {
			append_zlib_trailer(finish_bits(written.bytes, written.bits, written.count), a, b)
		} else {
			written.bytes
		}
		position = checked_add(encoder.position, length)?
		work = add_work(encoder.work, length, finalized.len(), written)?
		if work.emitted_bytes > encoder.plan.output_bound {
			Err(OutputBoundExceeded({ bound: encoder.plan.output_bound, attempted: work.emitted_bytes }))
		} else {
			plan = if final release_input(encoder.plan) else encoder.plan
			next = encoder_with(
				encoder,
				plan,
				if final 0 else written.bits,
				if final 0 else written.count,
				position,
				a,
				b,
				True,
				final,
				work,
			)
			Ok(Emit(finalized, next))
		}
	}
}

encoder_with : KernelDeflate.Encoder, KernelDeflate.Plan, U64, U8, U64, U64, U64, Bool, Bool, KernelDeflate.Work -> KernelDeflate.Encoder
encoder_with = |_encoder, plan, bits, bit_count, position, adler_a, adler_b, started, finished, work| KernelDeflate.Encoder.{
	adler_a,
	adler_b,
	bits,
	bit_count,
	finished,
	plan,
	position,
	started,
	work,
}

release_input : KernelDeflate.Plan -> KernelDeflate.Plan
release_input = |plan| KernelDeflate.Plan.{ input: [], output_bound: plan.output_bound }

block_chunk_capacity : U64, Bool, Bool -> Try(U64, KernelDeflate.Error)
block_chunk_capacity = |input_bytes, first, final| {
	bits = checked_add(checked_times(input_bytes, 9)?, 356)?
	raw_bytes = U64.div_by(checked_add(bits, 7)?, 8)
	with_header = checked_add(raw_bytes, if first 2 else 0)?
	checked_add(with_header, if final 4 else 0)
}

add_work : KernelDeflate.Work, U64, U64, BlockResult -> Try(KernelDeflate.Work, KernelDeflate.Error)
add_work = |work, input_bytes, emitted_bytes, block| {
	Ok(
		KernelDeflate.Work.{
			blocks: checked_add(work.blocks, 1)?,
			candidate_visits: checked_add(work.candidate_visits, block.candidate_visits)?,
			emitted_bytes: checked_add(work.emitted_bytes, emitted_bytes)?,
			hash_inserts: checked_add(work.hash_inserts, block.hash_inserts)?,
			input_bytes: checked_add(work.input_bytes, input_bytes)?,
			matches: checked_add(work.matches, block.matches)?,
			max_chunk_bytes: U64.max(work.max_chunk_bytes, emitted_bytes),
			tokens: checked_add(work.tokens, block.tokens)?,
		},
	)
}

encode_dynamic_block : List(U8), Bool, List(U8), U64, U8 -> BlockResult
encode_dynamic_block = |input, final, bytes, bits, count| {
	{ bytes: header_bytes, bits: header_bits, count: header_count } = emit_dynamic_header(bytes, bits, count, final)
	var $table = List.repeat(0, hash_size + window_size)
	var $bytes = header_bytes
	var $bits = header_bits
	var $count = header_count
	var $candidate_visits = 0
	var $hash_inserts = 0
	var $matches = 0
	var $tokens = 0
	var $position = 0
	while $position < input.len() {
		can_match = input.len() - $position >= min_match
		field = if can_match {
			slot = hash3(input, $position)
			candidate = list_at_u64($table, slot)
			$table = insert_slot($table, slot, $position)
			$hash_inserts = $hash_inserts + 1
			found = chain_search(input, $position, $table, candidate)
			found_length = match_result_length(found)
			found_distance = match_result_distance(found)
			$candidate_visits = $candidate_visits + match_result_visits(found)
			if found_length >= min_match {
				$matches = $matches + 1
				end = $position + found_length
				insert_start = $position + 1
				last_hash_end = input.len() - min_match + 1
				insert_end = U64.min(end, last_hash_end)
				$table = insert_range(input, insert_start, insert_end, $table)
				$hash_inserts = $hash_inserts + insert_end - insert_start
				$position = end
				match_field(found_length, found_distance)
			} else {
				literal = litlen_field(list_at_u8(input, $position).to_u16())
				$position = $position + 1
				literal
			}
		} else {
			literal = litlen_field(list_at_u8(input, $position).to_u16())
			$position = $position + 1
			literal
		}
		value_count = field_count(field)
		combined = $bits.bitwise_or(field_value(field).shl_wrap($count))
		total = $count + value_count
		$bytes = flush_bytes($bytes, combined, total)
		remaining = total.bitwise_and(7)
		$bits = combined.shr_wrap(total - remaining)
		$count = remaining
		$tokens = $tokens + 1
	}
	end = litlen_field(256)
	finished = write_bits($bytes, $bits, $count, field_value(end), field_count(end))
	{
		bits: finished.bits,
		bytes: finished.bytes,
		candidate_visits: $candidate_visits,
		count: finished.count,
		hash_inserts: $hash_inserts,
		matches: $matches,
		tokens: $tokens,
	}
}

insert_slot : List(U64), U64, U64 -> List(U64)
insert_slot = |table, slot, position| {
	previous = list_at_u64(table, slot)
	with_head = list_set_u64(table, slot, position + 1)
	list_set_u64(with_head, hash_size + position.bitwise_and(window_size - 1), previous)
}

insert_range : List(U8), U64, U64, List(U64) -> List(U64)
insert_range = |input, position, end, table| {
	if position >= end {
		table
	} else {
		insert_range(input, position + 1, end, insert_slot(table, hash3(input, position), position))
	}
}

chain_search : List(U8), U64, List(U64), U64 -> U64
chain_search = |input, position, table, first_candidate| chain_search_help(input, position, table, first_candidate, match_search_limit, 0, 0, 0)

chain_search_help : List(U8), U64, List(U64), U64, U64, U64, U64, U64 -> U64
chain_search_help = |input, position, table, candidate, remaining, best_length, best_distance, visits| {
	if candidate == 0 or remaining == 0 or candidate > position or best_length >= max_match {
		pack_match_result(best_length, best_distance, visits)
	} else {
		start = candidate - 1
		distance = position - start
		if distance == 0 or distance > window_size {
			pack_match_result(best_length, best_distance, visits)
		} else {
			promising = position + best_length < input.len() and list_at_u8(input, start + best_length) == list_at_u8(input, position + best_length)
			length = if promising match_length(input, start, position) else 0
			next_candidate = list_at_u64(table, hash_size + start.bitwise_and(window_size - 1))
			if length > best_length {
				chain_search_help(input, position, table, next_candidate, remaining - 1, length, distance, visits + 1)
			} else {
				chain_search_help(input, position, table, next_candidate, remaining - 1, best_length, best_distance, visits + 1)
			}
		}
	}
}

pack_match_result : U64, U64, U64 -> U64
pack_match_result = |length, distance, visits| length.bitwise_or(distance.shl_wrap(9)).bitwise_or(visits.shl_wrap(25))

match_result_length : U64 -> U64
match_result_length = |result| result.bitwise_and(0x1FF)

match_result_distance : U64 -> U64
match_result_distance = |result| result.shr_wrap(9).bitwise_and(0xFFFF)

match_result_visits : U64 -> U64
match_result_visits = |result| result.shr_wrap(25).bitwise_and(0xFF)

match_length : List(U8), U64, U64 -> U64
match_length = |input, candidate, position| match_length_help(input, candidate, position, 0)

match_length_help : List(U8), U64, U64, U64 -> U64
match_length_help = |input, candidate, position, length| {
	if length >= max_match or position + length >= input.len() {
		length
	} else if list_at_u8(input, candidate + length) == list_at_u8(input, position + length) {
		match_length_help(input, candidate, position, length + 1)
	} else {
		length
	}
}

hash3 : List(U8), U64 -> U64
hash3 = |input, position| {
	b0 = list_at_u8(input, position).to_u64()
	b1 = list_at_u8(input, position + 1).to_u64()
	b2 = list_at_u8(input, position + 2).to_u64()
	(((b0.shl_wrap(16) + b1.shl_wrap(8) + b2) * 2654435761).shr_wrap(15)).bitwise_and(hash_size - 1)
}

emit_dynamic_header : List(U8), U64, U8, Bool -> WriteState
emit_dynamic_header = |bytes, bits, count, final| {
	bfinal = write_bits(bytes, bits, count, if final 1 else 0, 1)
	btype = write_bits(bfinal.bytes, bfinal.bits, bfinal.count, 2, 2)
	hlit = write_bits(btype.bytes, btype.bits, btype.count, 29, 5)
	hdist = write_bits(hlit.bytes, hlit.bits, hlit.count, 29, 5)
	hclen = write_bits(hdist.bytes, hdist.bits, hdist.count, 8, 4)
	declarations = emit_code_length_declarations(hclen.bytes, hclen.bits, hclen.count, 0)
	run8 = emit_same_code_length(declarations.bytes, declarations.bits, declarations.count, 8, 144)
	run9 = emit_same_code_length(run8.bytes, run8.bits, run8.count, 9, 112)
	run7 = emit_same_code_length(run9.bytes, run9.bits, run9.count, 7, 26)
	run8_tail = emit_same_code_length(run7.bytes, run7.bits, run7.count, 8, 4)
	run4 = emit_same_code_length(run8_tail.bytes, run8_tail.bits, run8_tail.count, 4, 2)
	emit_same_code_length(run4.bytes, run4.bits, run4.count, 5, 28)
}

emit_code_length_declarations : List(U8), U64, U8, U64 -> WriteState
emit_code_length_declarations = |bytes, bits, count, index| {
	if index == 12 {
		{ bits, bytes, count }
	} else {
		length = match index {
			0 => 2
			4 => 3
			5 => 3
			6 => 2
			9 => 3
			11 => 3
			_ => 0
		}
		next = write_bits(bytes, bits, count, length, 3)
		emit_code_length_declarations(next.bytes, next.bits, next.count, index + 1)
	}
}

emit_same_code_length : List(U8), U64, U8, U8, U64 -> WriteState
emit_same_code_length = |bytes, bits, count, length, copies| {
	first = code_length_field(length)
	written = write_bits(bytes, bits, count, field_value(first), field_count(first))
	emit_code_length_remainder(written.bytes, written.bits, written.count, length, copies - 1)
}

emit_code_length_remainder : List(U8), U64, U8, U8, U64 -> WriteState
emit_code_length_remainder = |bytes, bits, count, length, remaining| {
	if remaining == 0 {
		{ bits, bytes, count }
	} else if remaining >= 3 {
		repeat = U64.min(remaining, 6)
		code = code_length_field(16)
		written = write_bits(bytes, bits, count, field_value(code), field_count(code))
		extra = write_bits(written.bytes, written.bits, written.count, repeat - 3, 2)
		emit_code_length_remainder(extra.bytes, extra.bits, extra.count, length, remaining - repeat)
	} else {
		code = code_length_field(length)
		written = write_bits(bytes, bits, count, field_value(code), field_count(code))
		emit_code_length_remainder(written.bytes, written.bits, written.count, length, remaining - 1)
	}
}

code_length_field : U8 -> U64
code_length_field = |symbol| match symbol {
	4 => pack_field(1, 3)
	5 => pack_field(5, 3)
	7 => pack_field(3, 3)
	8 => pack_field(7, 3)
	9 => pack_field(0, 2)
	16 => pack_field(2, 2)
	_ => {
		crash "unsupported dynamic code-length symbol"
	}
}

match_field : U64, U64 -> U64
match_field = |length, distance| combine_fields(length_field(length), distance_field(distance))

length_field : U64 -> U64
length_field = |length| {
	if length <= 10 {
		litlen_field(257 + (length - 3).to_u16_wrap())
	} else if length <= 18 {
		length_group_field(length, 11, 265, 1)
	} else if length <= 34 {
		length_group_field(length, 19, 269, 2)
	} else if length <= 66 {
		length_group_field(length, 35, 273, 3)
	} else if length <= 130 {
		length_group_field(length, 67, 277, 4)
	} else if length <= 257 {
		length_group_field(length, 131, 281, 5)
	} else {
		litlen_field(285)
	}
}

length_group_field : U64, U64, U16, U8 -> U64
length_group_field = |length, first, first_symbol, extra_count| {
	span = power_of_two(extra_count)
	offset = length - first
	symbol = first_symbol + U64.div_by(offset, span).to_u16_wrap()
	append_extra(litlen_field(symbol), U64.mod_by(offset, span), extra_count)
}

distance_field : U64 -> U64
distance_field = |distance| {
	if distance <= 4 {
		distance_code_field((distance - 1).to_u8_wrap())
	} else {
		initial_extra_count : U8
		initial_extra_count = 1
		initial_symbol : U8
		initial_symbol = 4
		var $base = 5
		var $extra_count = initial_extra_count
		var $symbol = initial_symbol
		var $found = False
		var $extra = 0
		while $found == False {
			span = power_of_two($extra_count)
			if distance < $base + span * 2 {
				offset = distance - $base
				$symbol = $symbol + U64.div_by(offset, span).to_u8_wrap()
				$extra = U64.mod_by(offset, span)
				$found = True
			} else {
				$base = $base + span * 2
				$symbol = $symbol + 2
				$extra_count = $extra_count + 1
			}
		}
		append_extra(distance_code_field($symbol), $extra, $extra_count)
	}
}

litlen_field : U16 -> U64
litlen_field = |symbol| {
	if symbol <= 143 {
		pack_field(reverse_bits(52 + symbol.to_u32(), 8).to_u64(), 8)
	} else if symbol <= 255 {
		pack_field(reverse_bits(400 + (symbol - 144).to_u32(), 9).to_u64(), 9)
	} else if symbol <= 281 {
		pack_field(reverse_bits((symbol - 256).to_u32(), 7).to_u64(), 7)
	} else {
		pack_field(reverse_bits(196 + (symbol - 282).to_u32(), 8).to_u64(), 8)
	}
}

distance_code_field : U8 -> U64
distance_code_field = |symbol| {
	if symbol <= 1 {
		pack_field(reverse_bits(symbol.to_u32(), 4).to_u64(), 4)
	} else {
		pack_field(reverse_bits((symbol + 2).to_u32(), 5).to_u64(), 5)
	}
}

pack_field : U64, U8 -> U64
pack_field = |value, count| value.bitwise_or(count.to_u64().shl_wrap(56))

field_value : U64 -> U64
field_value = |field| field.bitwise_and(0x00FFFFFFFFFFFFFF)

field_count : U64 -> U8
field_count = |field| field.shr_wrap(56).to_u8_wrap()

append_extra : U64, U64, U8 -> U64
append_extra = |field, extra, extra_count| {
	count = field_count(field)
	pack_field(field_value(field).bitwise_or(extra.shl_wrap(count)), count + extra_count)
}

combine_fields : U64, U64 -> U64
combine_fields = |left, right| {
	left_count = field_count(left)
	pack_field(
		field_value(left).bitwise_or(field_value(right).shl_wrap(left_count)),
		left_count + field_count(right),
	)
}

power_of_two : U8 -> U64
power_of_two = |count| {
	one : U64
	one = 1
	one.shl_wrap(count)
}

reverse_bits : U32, U8 -> U32
reverse_bits = |code, count| {
	var $source = code
	var $remaining = count
	var $result = 0
	while $remaining > 0 {
		$result = $result.shl_wrap(1).bitwise_or($source.bitwise_and(1))
		$source = $source.shr_wrap(1)
		$remaining = $remaining - 1
	}
	$result
}

write_bits : List(U8), U64, U8, U64, U8 -> WriteState
write_bits = |bytes, bits, count, value, value_count| {
	combined = bits.bitwise_or(value.shl_wrap(count))
	total = count + value_count
	flushed = flush_bytes(bytes, combined, total)
	remaining = total.bitwise_and(7)
	{
		bits: combined.shr_wrap(total - remaining),
		bytes: flushed,
		count: remaining,
	}
}

flush_bytes : List(U8), U64, U8 -> List(U8)
flush_bytes = |bytes, bits, count| {
	if count < 8 {
		bytes
	} else {
		flush_bytes(bytes.append(bits.to_u8_wrap()), bits.shr_wrap(8), count - 8)
	}
}

finish_bits : List(U8), U64, U8 -> List(U8)
finish_bits = |bytes, bits, count| {
	if count == 0 bytes else bytes.append(bits.to_u8_wrap())
}

update_adler : List(U8), U64, U64 -> { a : U64, b : U64 }
update_adler = |bytes, initial_a, initial_b| {
	var $a = initial_a
	var $b = initial_b
	var $index = 0
	while $index < bytes.len() {
		$a = U64.mod_by($a + list_at_u8(bytes, $index).to_u64(), adler_modulus)
		$b = U64.mod_by($b + $a, adler_modulus)
		$index = $index + 1
	}
	{ a: $a, b: $b }
}

append_zlib_trailer : List(U8), U64, U64 -> List(U8)
append_zlib_trailer = |bytes, a, b| {
	checksum = b.shl_wrap(16).bitwise_or(a)
	bytes
		.append(checksum.shr_wrap(24).to_u8_wrap())
		.append(checksum.shr_wrap(16).to_u8_wrap())
		.append(checksum.shr_wrap(8).to_u8_wrap())
		.append(checksum.to_u8_wrap())
}

checked_add : U64, U64 -> Try(U64, KernelDeflate.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(total) => Ok(total)
}

checked_times : U64, U64 -> Try(U64, KernelDeflate.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(total) => Ok(total)
}

append_all : List(U8), List(U8) -> List(U8)
append_all = |target, source| {
	var $out = List.reserve(target, source.len())
	var $index = 0
	while $index < source.len() {
		$out = $out.append(list_at_u8(source, $index))
		$index = $index + 1
	}
	$out
}

list_at_u8 : List(U8), U64 -> U8
list_at_u8 = |list, index| match list.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "DEFLATE byte index invariant failed"
	}
}

list_at_u64 : List(U64), U64 -> U64
list_at_u64 = |list, index| match list.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "DEFLATE table index invariant failed"
	}
}

list_set_u64 : List(U64), U64, U64 -> List(U64)
list_set_u64 = |list, index, value| match list.set(index, value) {
	Ok(updated) => updated
	Err(OutOfBounds) => {
		crash "DEFLATE table update invariant failed"
	}
}

## The canonical empty stream keeps the compact fixed-block representation.
expect {
	plan = KernelDeflate.Plan.prepare([], KernelDeflate.Limits.make({ max_input_bytes: 0, max_output_bytes: 8 }))?
	result = KernelDeflate.to_bytes(plan)?
	result.bytes == [120, 156, 3, 0, 0, 0, 0, 1] and KernelDeflate.Work.blocks(result.work) == 1
}

## Limits reject input and output bounds before compression begins.
expect {
	input = [1, 2, 3]
	too_much_input = KernelDeflate.Plan.prepare(input, KernelDeflate.Limits.make({ max_input_bytes: 2, max_output_bytes: 100 }))
	too_much_output = KernelDeflate.Plan.prepare(input, KernelDeflate.Limits.make({ max_input_bytes: 3, max_output_bytes: 1 }))
	match too_much_input {
		Err(InputLimitExceeded({ attempted, limit })) => attempted == 3 and limit == 2
		_ => False
	} and match too_much_output {
		Err(OutputLimitExceeded({ attempted, limit })) => attempted > 1 and limit == 1
		_ => False
	}
}

## Nonempty input emits a final dynamic-Huffman block and remains under its bound.
expect {
	input = Str.to_utf8("the cat, the cat, the cat, the cat")
	bound = KernelDeflate.output_bound(input.len())?
	plan = KernelDeflate.Plan.prepare(input, KernelDeflate.Limits.make({ max_input_bytes: input.len(), max_output_bytes: bound }))?
	result = KernelDeflate.to_bytes(plan)?
	first_deflate_byte = list_at_u8(result.bytes, 2)
	raw = result.bytes.sublist({ start: 2, len: result.bytes.len() - 6 })
	trailer = result.bytes.sublist({ start: result.bytes.len() - 4, len: 4 })
	first_deflate_byte.bitwise_and(7) == 5 and
		Deflate.decompress(raw) == Ok(input) and
			trailer == [197, 224, 11, 73] and
				result.bytes.len() <= bound and
					KernelDeflate.Work.input_bytes(result.work) == input.len() and
						KernelDeflate.Work.matches(result.work) > 0 and
							KernelDeflate.Work.candidate_visits(result.work) <= input.len() * match_search_limit
}

## Bit state carries across the canonical block boundary without joining chunks.
expect {
	input = List.repeat(0, block_input_limit + 465).map_with_index(|_, index| index.to_u8_wrap())
	bound = KernelDeflate.output_bound(input.len())?
	plan = KernelDeflate.Plan.prepare(input, KernelDeflate.Limits.make({ max_input_bytes: input.len(), max_output_bytes: bound }))?
	result = KernelDeflate.to_bytes(plan)?
	raw = result.bytes.sublist({ start: 2, len: result.bytes.len() - 6 })
	KernelDeflate.Work.blocks(result.work) == 2 and Deflate.decompress(raw) == Ok(input)
}

## The full 32 KiB window produces a valid maximum-distance code.
expect {
	with_gap = append_all([1, 2, 3], List.repeat(0, window_size - 3))
	input = append_all(with_gap, [1, 2, 3])
	bound = KernelDeflate.output_bound(input.len())?
	plan = KernelDeflate.Plan.prepare(input, KernelDeflate.Limits.make({ max_input_bytes: input.len(), max_output_bytes: bound }))?
	result = KernelDeflate.to_bytes(plan)?
	raw = result.bytes.sublist({ start: 2, len: result.bytes.len() - 6 })
	table = insert_slot(List.repeat(0, hash_size + window_size), hash3(input, 0), 0)
	search = chain_search(input, window_size, table, list_at_u64(table, hash3(input, window_size)))
	Deflate.decompress(raw) == Ok(input) and
		match_result_length(search) == 3 and
			match_result_distance(search) == window_size and
				field_count(distance_field(window_size)) == 18
}
