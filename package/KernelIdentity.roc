import KernelLex
import KernelObject
import KernelSeal
import KernelSha256

KernelIdentity :: [].{
	Error : [Hash(KernelSha256.Error), WorkOverflow]
	Work : {
		fact_bytes : U64,
		objects : U64,
		payload_bytes_hashed : U64,

		## Bytes represented by source digests, counted once per stored entry.
		source_bytes_hashed : U64,
		values : U64,
	}
	Result : { digest : List(U8), work : Work }

	digest : KernelSeal.Plan -> Try(Result, Error)
	digest = |sealed| digest_plan(sealed)
}

digest_plan : KernelSeal.Plan -> Try(KernelIdentity.Result, KernelIdentity.Error)
digest_plan = |sealed| {
	store = KernelSeal.Plan.store(sealed)
	batch_bytes = if (store.objects.len() > 65536) large_plan_batch_bytes else short_plan_bytes
	{ result, .. } = digest_store(store, batch_bytes, name_cache_threshold)?
	Ok(result)
}

large_plan_batch_bytes : U64
large_plan_batch_bytes = 65536

short_plan_bytes : U64
short_plan_bytes = 16777216

## One complete payload record needs at most 58 bytes. There are at most
## nine 8-byte arena counts between any two batch checks, even if arenas
## are empty. A bounded buffer has room for that last group of facts.
batch_overhead : U64
batch_overhead = 58 + 9 * 8

CompletedFacts : [Buffered, Batched(KernelSha256.Batched)]

IdentityEvidence : { result : KernelIdentity.Result, name_cache_hits : U64 }

digest_store : KernelObject.Store, U64, U64 -> Try(IdentityEvidence, KernelIdentity.Error)
digest_store = |store, batch_bytes, minimum_cached_names| {
	capacity = batch_bytes + batch_overhead
	var $facts = if (batch_bytes == short_plan_bytes) Str.to_utf8("") else List.with_capacity(capacity)
	var $completed = Buffered
	$facts = append_u64($facts, store.names.len())
	var $source_bytes = 0
	var $index = 0
	var $name_cache_hits = 0
	cache_names = store.names.len() >= minimum_cached_names
	var $cache = if (cache_names) List.repeat(empty_name_entry, name_cache_slots) else []
	while $index < store.names.len() {
		bytes = KernelLex.Name.bytes(list_at(store.names, $index))
		length = bytes.len()
		if cache_names and length <= max_cached_name_length {
			key = name_key(bytes, length)
			slot = name_slot(key)
			previous = list_at($cache, slot)
			var $digest = previous.digest
			if previous.key == key {
				$name_cache_hits = $name_cache_hits + 1
			} else {
				digest = Crypto.SHA256.hash(bytes).to_bytes()
				$cache = set_name_entry($cache, slot, { key, digest })
				$digest = digest
			}
			$facts = append_all(append_u64($facts, length), $digest)
		} else {
			$facts = append_blob_digest($facts, bytes)?
		}
		$source_bytes = checked_add($source_bytes, length)?
		if $facts.len() >= batch_bytes {
			$completed = hash_batch($completed, $facts)?
			$facts = $facts.clear()
		}
		$index = $index + 1
	}
	$facts = append_u64($facts, store.byte_strings.len())
	$index = 0
	while $index < store.byte_strings.len() {
		bytes = list_at(store.byte_strings, $index)
		$facts = append_blob_digest($facts, bytes)?
		$source_bytes = checked_add($source_bytes, bytes.len())?
		if $facts.len() >= batch_bytes {
			$completed = hash_batch($completed, $facts)?
			$facts = $facts.clear()
		}
		$index = $index + 1
	}
	$facts = append_u64($facts, store.text_strings.len())
	$index = 0
	while $index < store.text_strings.len() {
		bytes = KernelLex.Text.bytes(list_at(store.text_strings, $index))
		$facts = append_blob_digest($facts, bytes)?
		$source_bytes = checked_add($source_bytes, bytes.len())?
		if $facts.len() >= batch_bytes {
			$completed = hash_batch($completed, $facts)?
			$facts = $facts.clear()
		}
		$index = $index + 1
	}
	$facts = append_u64($facts, store.array_items.len())
	$index = 0
	while $index < store.array_items.len() {
		$facts = append_u64($facts, KernelObject.ValueId.index(list_at(store.array_items, $index)))
		if $facts.len() >= batch_bytes {
			$completed = hash_batch($completed, $facts)?
			$facts = $facts.clear()
		}
		$index = $index + 1
	}
	$facts = append_u64($facts, store.dictionary_entries.len())
	$index = 0
	while $index < store.dictionary_entries.len() {
		entry = list_at(store.dictionary_entries, $index)
		$facts = append_u64(append_u64($facts, KernelObject.NameId.index(entry.key)), KernelObject.ValueId.index(entry.value))
		if $facts.len() >= batch_bytes {
			$completed = hash_batch($completed, $facts)?
			$facts = $facts.clear()
		}
		$index = $index + 1
	}
	$facts = append_u64($facts, store.values.len())
	$index = 0
	while $index < store.values.len() {
		$facts = append_value($facts, list_at(store.values, $index))
		if $facts.len() >= batch_bytes {
			$completed = hash_batch($completed, $facts)?
			$facts = $facts.clear()
		}
		$index = $index + 1
	}
	$facts = append_u64($facts, store.objects.len())
	$index = 0
	while $index < store.objects.len() {
		$facts = append_object($facts, list_at(store.objects, $index))
		if $facts.len() >= batch_bytes {
			$completed = hash_batch($completed, $facts)?
			$facts = $facts.clear()
		}
		$index = $index + 1
	}
	$facts = append_u64($facts, store.streams.len())
	$index = 0
	while $index < store.streams.len() {
		$facts = append_stream($facts, list_at(store.streams, $index))
		if $facts.len() >= batch_bytes {
			$completed = hash_batch($completed, $facts)?
			$facts = $facts.clear()
		}
		$index = $index + 1
	}
	$facts = append_u64($facts, store.payloads.len())
	var $payload_bytes = 0
	$index = 0
	while $index < store.payloads.len() {
		payload = list_at(store.payloads, $index)
		$facts = append_u64($facts, KernelObject.PayloadId.index(payload.id))
		$facts = $facts.append(
			match payload.kind {
				Generated => 0
				UnchangedResource => 1
			},
		)
		$facts = append_payload_use($facts, payload.last_use)
		$facts = append_blob_digest($facts, payload.bytes)?
		$payload_bytes = checked_add($payload_bytes, payload.bytes.len())?
		if $facts.len() >= batch_bytes {
			$completed = hash_batch($completed, $facts)?
			$facts = $facts.clear()
		}
		$index = $index + 1
	}
	{ bytes, digest } = match $completed {
		Buffered => { bytes: $facts.len(), digest: KernelSha256.digest($facts) ? Hash }
		Batched(hasher) => {
			final = KernelSha256.Batched.write(hasher, $facts) ? Hash
			KernelSha256.Batched.finish(final)
		}
	}
	Ok({
		name_cache_hits: $name_cache_hits,
		result: {
			digest,
			work: {
				fact_bytes: bytes,
				objects: store.objects.len(),
				payload_bytes_hashed: $payload_bytes,
				source_bytes_hashed: $source_bytes,
				values: store.values.len(),
			},
		},
	})
}

hash_batch : CompletedFacts, List(U8) -> Try(CompletedFacts, KernelIdentity.Error)
hash_batch = |completed, facts| {
	hasher = match completed {
		Buffered => KernelSha256.Batched.start()
		Batched(value) => value
	}
	next = KernelSha256.Batched.write(hasher, facts) ? Hash
	Ok(Batched(next))
}

## A fixed table amortizes short repeated PDF names within one digest
## computation. Long names retain the uncached identity path.
name_cache_threshold : U64
name_cache_threshold = 32768

name_cache_slots : U64
name_cache_slots = 512

max_cached_name_length : U64
max_cached_name_length = 16

NameKey : { length : U64, first_word : U64, second_word : U64 }

NameEntry : { key : NameKey, digest : List(U8) }

empty_name_entry : NameEntry
empty_name_entry = { key: { length: max_cached_name_length + 1, first_word: 0, second_word: 0 }, digest: [] }

name_key : List(U8), U64 -> NameKey
name_key = |bytes, length| {
	length,
	first_word: pack_name_word(bytes, 0, U64.min(length, 8)),
	second_word: pack_name_word(bytes, 8, length),
}

pack_name_word : List(U8), U64, U64 -> U64
pack_name_word = |bytes, start, end| {
	if end <= start {
		return 0
	}
	if end - start == 8 {
		return U64.from_le_bytes(bytes, start) ?? crash "name word escaped its bytes"
	}
	var $word = 0
	var $index = start
	while $index < end {
		shift = (($index - start) * 8).to_u8_wrap()
		$word = $word.bitwise_or(list_at(bytes, $index).to_u64().shl_wrap(shift))
		$index = $index + 1
	}
	$word
}

## The folded hash only chooses a slot. A hit requires exact key equality.
name_slot : NameKey -> U64
name_slot = |key| {
	rotated = key.second_word.shl_wrap(17).bitwise_or(key.second_word.shr_wrap(47))
	mixed = key.first_word.bitwise_xor(rotated).bitwise_xor(key.length.times_wrap(0x9e3779b97f4a7c15))
	folded = mixed.bitwise_xor(mixed.shr_wrap(33)).times_wrap(0xff51afd7ed558ccd)
	U64.mod_by(folded.bitwise_xor(folded.shr_wrap(33)), name_cache_slots)
}

set_name_entry : List(NameEntry), U64, NameEntry -> List(NameEntry)
set_name_entry = |cache, slot, entry| cache.set(slot, entry) ?? crash "name cache slot escaped"

append_value : List(U8), KernelObject.Value -> List(U8)
append_value = |facts, value| match value {
	Array(span) => append_span(facts.append(0), span)
	Boolean(boolean) => facts.append(1).append(if (boolean) 1 else 0)
	ByteString(string) => append_u64(facts.append(2), KernelObject.ByteStringId.index(string))
	Dictionary(span) => append_span(facts.append(3), span)
	Integer(integer) => append_i64(facts.append(4), integer)
	Name(name) => append_u64(facts.append(5), KernelObject.NameId.index(name))
	Null => facts.append(6)
	Fixed16(raw) => append_i64(facts.append(11), raw.to_i64())
	Real(decimal) => append_u64(append_i64(facts.append(7), KernelLex.Decimal.coefficient(decimal)), KernelLex.Decimal.scale(decimal).to_u64())
	Reference(object) => append_u64(facts.append(8), KernelObject.ObjectId.number(object))
	Stream(stream) => append_u64(facts.append(9), KernelObject.StreamId.index(stream))
	TextString(string) => append_u64(facts.append(10), KernelObject.TextStringId.index(string))
}

append_object : List(U8), KernelObject.Object -> List(U8)
append_object = |facts, object| {
	with_id = append_u64(facts, KernelObject.ObjectId.number(object.id))
	match object.content {
		LengthOf(stream) => append_u64(with_id.append(0), KernelObject.StreamId.index(stream))
		Stored(value) => append_u64(with_id.append(1), KernelObject.ValueId.index(value))
	}
}

append_stream : List(U8), KernelObject.StreamObject -> List(U8)
append_stream = |facts, stream| {
	with_dictionary = append_span(facts, stream.dictionary)
	with_filter = with_dictionary.append(
		match stream.filter {
			Dct => 0
			Deflate => 1
			Unfiltered => 2
		},
	)
	with_id = append_u64(with_filter, KernelObject.StreamId.index(stream.id))
	with_length = append_u64(with_id, KernelObject.ObjectId.number(stream.length_object))
	with_object = append_u64(with_length, KernelObject.ObjectId.number(stream.object))
	append_u64(with_object, KernelObject.PayloadId.index(stream.source))
}

append_payload_use : List(U8), KernelObject.PayloadUse -> List(U8)
append_payload_use = |facts, use| match use {
	Unused => facts.append(0)
	LastStream(stream) => append_u64(facts.append(1), KernelObject.StreamId.index(stream))
}

append_span : List(U8), KernelObject.Span -> List(U8)
append_span = |facts, span| append_u64(append_u64(facts, span.start), span.length)

append_blob_digest : List(U8), List(U8) -> Try(List(U8), KernelIdentity.Error)
append_blob_digest = |facts, bytes| {
	KernelSha256.append_digest(append_u64(facts, bytes.len()), bytes).map_err(|error| Hash(error))
}

append_i64 : List(U8), I64 -> List(U8)
append_i64 = |facts, value| append_u64(facts, value.to_u64_wrap())

append_u64 : List(U8), U64 -> List(U8)
append_u64 = |facts, value| facts
	.append(value.shr_wrap(56).to_u8_wrap())
	.append(value.shr_wrap(48).to_u8_wrap())
	.append(value.shr_wrap(40).to_u8_wrap())
	.append(value.shr_wrap(32).to_u8_wrap())
	.append(value.shr_wrap(24).to_u8_wrap())
	.append(value.shr_wrap(16).to_u8_wrap())
	.append(value.shr_wrap(8).to_u8_wrap())
	.append(value.to_u8_wrap())

append_all : List(a), List(a) -> List(a)
append_all = |left, right| {
	var $output = left
	var $index = 0
	while $index < right.len() {
		$output = $output.append(list_at(right, $index))
		$index = $index + 1
	}
	$output
}

checked_add : U64, U64 -> Try(U64, KernelIdentity.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(WorkOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "sealed tagged-visual identity index escaped"
	}
}

# Compare the same sealed plan through single-shot and multiple batched
# paths, including updates spanning SHA-256 block and padding boundaries.
expect {
	limits : KernelObject.Limits
	limits = {
		max_array_items: 4,
		max_byte_string_bytes: 4,
		max_byte_strings: 1,
		max_dictionary_entries: 1,
		max_direct_depth: 3,
		max_name_bytes: 3,
		max_names: 1,
		max_objects: 2,
		max_payload_bytes: 79,
		max_payloads: 1,
		max_streams: 1,
		max_text_string_bytes: 8,
		max_text_strings: 1,
		max_values: 8,
	}
	key = KernelObject.add_name(KernelObject.init(limits), Str.to_utf8("Key"))?
	bytes = KernelObject.add_byte_string(key.builder, [0, 128, 255])?
	text = KernelObject.add_text_string(bytes.builder, "Title")?
	byte_value = KernelObject.add_byte_string_value(text.builder, bytes.id)?
	text_value = KernelObject.add_text_string_value(byte_value.builder, text.id)?
	integer = KernelObject.add_integer(text_value.builder, -100)?
	array = KernelObject.add_array(integer.builder, [byte_value.id, text_value.id, integer.id])?
	payload = KernelObject.add_payload(array.builder, List.repeat(0xff, 79), Generated)?
	stream = KernelObject.add_stream_object(payload.builder, [{ key: key.id, value: array.id }], Deflate, payload.id)?
	sealed = KernelSeal.seal(stream.builder)?
	store = KernelSeal.Plan.store(sealed)
	expected = KernelIdentity.digest(sealed)?
	[1, 8, 16, 55, 56, 63, 64, 65, 128, 257].all(|batch_bytes| digest_store(store, batch_bytes, name_cache_threshold) == Ok({ result: expected, name_cache_hits: 0 }))
}

# Cache hits, replacements, and long-name bypass all leave the normalized
# digest and logical work unchanged. N10 and N13 collide on slot selection.
expect {
	inputs = ["", "", "N10", "N10", "N13", "N13", "N10", "ABCDEFGHIJKLMNOP", "ABCDEFGHIJKLMNOP", "ABCDEFGHIJKLMNOPQ", "ABCDEFGHIJKLMNOPQ", "XObject", "XObject"]
	initial = KernelObject.init({
		max_array_items: 0,
		max_byte_string_bytes: 0,
		max_byte_strings: 0,
		max_dictionary_entries: 0,
		max_direct_depth: 0,
		max_name_bytes: 256,
		max_names: inputs.len(),
		max_objects: 0,
		max_payload_bytes: 0,
		max_payloads: 0,
		max_streams: 0,
		max_text_string_bytes: 0,
		max_text_strings: 0,
		max_values: 0,
	})
	var $builder = initial
	for input in inputs {
		match KernelObject.add_name($builder, Str.to_utf8(input)) {
			Ok(added) => {
				$builder = added.builder
			}
			Err(_) => crash "name cache test fixture escaped its limits"
		}
	}
	sealed = KernelSeal.seal($builder)?
	store = KernelSeal.Plan.store(sealed)
	uncached = digest_store(store, short_plan_bytes, name_cache_threshold)?
	cached = digest_store(store, short_plan_bytes, 0)?
	streamed = digest_store(store, 55, 0)?
	name_slot(name_key(Str.to_utf8("N10"), 3)) == name_slot(name_key(Str.to_utf8("N13"), 3))
		and cached.result == uncached.result
		and uncached.name_cache_hits == 0
		and cached.name_cache_hits == 5
		and streamed == cached
}
