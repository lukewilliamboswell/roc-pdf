import KernelLex
import KernelObject
import KernelSeal
import KernelSha256

KernelGate2Identity :: [].{
	Error : [Hash(KernelSha256.Error), WorkOverflow]
	Work : {
		fact_bytes : U64,
		objects : U64,
		payload_bytes_hashed : U64,
		source_bytes_hashed : U64,
		values : U64,
	}
	Result : { digest : List(U8), work : Work }

	digest : KernelSeal.Plan -> Try(Result, Error)
	digest = |sealed| digest_plan(sealed)
}

digest_plan : KernelSeal.Plan -> Try(KernelGate2Identity.Result, KernelGate2Identity.Error)
digest_plan = |sealed| {
	store = KernelSeal.Plan.store(sealed)
	var $facts = Str.to_utf8("")
	$facts = append_u64($facts, store.names.len())
	var $source_bytes = 0
	var $index = 0
	while $index < store.names.len() {
		bytes = KernelLex.Name.bytes(list_at(store.names, $index))
		$facts = append_blob_digest($facts, bytes)?
		$source_bytes = checked_add($source_bytes, bytes.len())?
		$index = $index + 1
	}
	$facts = append_u64($facts, store.byte_strings.len())
	$index = 0
	while $index < store.byte_strings.len() {
		bytes = list_at(store.byte_strings, $index)
		$facts = append_blob_digest($facts, bytes)?
		$source_bytes = checked_add($source_bytes, bytes.len())?
		$index = $index + 1
	}
	$facts = append_u64($facts, store.text_strings.len())
	$index = 0
	while $index < store.text_strings.len() {
		bytes = KernelLex.Text.bytes(list_at(store.text_strings, $index))
		$facts = append_blob_digest($facts, bytes)?
		$source_bytes = checked_add($source_bytes, bytes.len())?
		$index = $index + 1
	}
	$facts = append_u64($facts, store.array_items.len())
	$index = 0
	while $index < store.array_items.len() {
		$facts = append_u64($facts, KernelObject.ValueId.index(list_at(store.array_items, $index)))
		$index = $index + 1
	}
	$facts = append_u64($facts, store.dictionary_entries.len())
	$index = 0
	while $index < store.dictionary_entries.len() {
		entry = list_at(store.dictionary_entries, $index)
		$facts = append_u64(append_u64($facts, KernelObject.NameId.index(entry.key)), KernelObject.ValueId.index(entry.value))
		$index = $index + 1
	}
	$facts = append_u64($facts, store.values.len())
	$index = 0
	while $index < store.values.len() {
		$facts = append_value($facts, list_at(store.values, $index))
		$index = $index + 1
	}
	$facts = append_u64($facts, store.objects.len())
	$index = 0
	while $index < store.objects.len() {
		$facts = append_object($facts, list_at(store.objects, $index))
		$index = $index + 1
	}
	$facts = append_u64($facts, store.streams.len())
	$index = 0
	while $index < store.streams.len() {
		$facts = append_stream($facts, list_at(store.streams, $index))
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
		$index = $index + 1
	}
	digest = KernelSha256.digest($facts) ? Hash
	Ok({
		digest,
		work: {
			fact_bytes: $facts.len(),
			objects: store.objects.len(),
			payload_bytes_hashed: $payload_bytes,
			source_bytes_hashed: $source_bytes,
			values: store.values.len(),
		},
	})
}

append_value : List(U8), KernelObject.Value -> List(U8)
append_value = |facts, value| match value {
	Array(span) => append_span(facts.append(0), span)
	Boolean(boolean) => facts.append(1).append(if boolean 1 else 0)
	ByteString(string) => append_u64(facts.append(2), KernelObject.ByteStringId.index(string))
	Dictionary(span) => append_span(facts.append(3), span)
	Integer(integer) => append_i64(facts.append(4), integer)
	Name(name) => append_u64(facts.append(5), KernelObject.NameId.index(name))
	Null => facts.append(6)
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

append_stream : List(U8), KernelObject.Stream -> List(U8)
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

append_blob_digest : List(U8), List(U8) -> Try(List(U8), KernelGate2Identity.Error)
append_blob_digest = |facts, bytes| {
	digest = KernelSha256.digest(bytes) ? Hash
	Ok(append_all(append_u64(facts, bytes.len()), digest))
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

checked_add : U64, U64 -> Try(U64, KernelGate2Identity.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(WorkOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "sealed Gate 2 identity index escaped"
	}
}
