import KernelDeflate
import KernelFileLayout
import KernelLex
import KernelObject
import KernelSeal

KernelOutputBound :: [].{
	Error : [ArithmeticOverflow, Deflate(KernelDeflate.Error), NestedStreamValue(KernelObject.ValueId), XrefObjectMismatch({ actual : KernelObject.ObjectId, expected : U64 })]

	Work : { object_visits : U64, payload_bound_lookups : U64, value_visits : U64 }

	Bound :: { bytes : U64, work : Work }.{
		bytes : Bound -> U64
		bytes = |bound| bound.bytes

		work : Bound -> Work
		work = |bound| bound.work
	}

	calculate : KernelSeal.Plan, KernelObject.ObjectId -> Try(Bound, Error)
	calculate = |sealed, xref_object| calculate_bound(sealed, xref_object)
}

ValueBound : { bytes : U64, visits : U64 }

calculate_bound : KernelSeal.Plan, KernelObject.ObjectId -> Try(KernelOutputBound.Bound, KernelOutputBound.Error)
calculate_bound = |sealed, xref_object| {
	store = KernelSeal.Plan.store(sealed)
	expected_xref = checked_add(store.objects.len(), 1)?
	if KernelObject.ObjectId.number(xref_object) != expected_xref {
		Err(XrefObjectMismatch({ actual: xref_object, expected: expected_xref }))
	} else {
		# Stream objects are bounded as top-level objects. Every other object
		# is bounded as an object-stream member (a header pair of at most two
		# 20-digit numbers and two spaces, its value, and a newline), and each
		# object stream closed by the shared partition adds its DEFLATE bound
		# and framing.
		var $bytes = 15
		var $batch = 0
		var $members = 0
		var $streams = 0
		var $object_index = 0
		var $payload_bound_lookups = 0
		var $value_visits = 0
		while $object_index < store.objects.len() {
			object = list_at(store.objects, $object_index)
			member = match object.content {
				LengthOf(stream_id) => {
					payload_bound = stream_payload_bound(store, stream_id)?
					$payload_bound_lookups = checked_add($payload_bound_lookups, 1)?
					Member(decimal_length(payload_bound))
				}
				Stored(value_id) => match list_at(store.values, KernelObject.ValueId.index(value_id)) {
					Stream(stream_id) => {
						stream = list_at(store.streams, KernelObject.StreamId.index(stream_id))
						dictionary = dictionary_bound(store, stream.dictionary)?
						$value_visits = checked_add($value_visits, dictionary.visits)?
						payload_bound = stream_payload_bound(store, stream_id)?
						$payload_bound_lookups = checked_add($payload_bound_lookups, 1)?
						$bytes = checked_add($bytes, checked_add(decimal_length(KernelObject.ObjectId.number(object.id)), 7)?)?
						$bytes = checked_add($bytes, dictionary.bytes)?
						$bytes = checked_add($bytes, stream_inserted_entries_bound(stream))?
						$bytes = checked_add($bytes, 8)?
						$bytes = checked_add($bytes, payload_bound)?
						$bytes = checked_add($bytes, 18)?
						TopLevel
					}
					_ => {
						value = value_bound(store, value_id)?
						$value_visits = checked_add($value_visits, value.visits)?
						Member(value.bytes)
					}
				}
			}
			match member {
				TopLevel => {}
				Member(body) => {
					$batch = checked_add($batch, checked_add(body, member_overhead_bound)?)?
					$members = $members + 1
					if $members == KernelFileLayout.max_objects_per_stream {
						$bytes = checked_add($bytes, object_stream_bound($batch)?)?
						$streams = $streams + 1
						$batch = 0
						$members = 0
					}
				}
			}
			$object_index = $object_index + 1
		}
		if $members > 0 {
			$bytes = checked_add($bytes, object_stream_bound($batch)?)?
			$streams = $streams + 1
		}

		xref_number = checked_add(KernelObject.ObjectId.number(xref_object), $streams)?
		xref = xref_bound(xref_number, $bytes)?
		Ok(
			KernelOutputBound.Bound.{
				bytes: checked_add($bytes, xref)?,
				work: {
					object_visits: store.objects.len(),
					payload_bound_lookups: $payload_bound_lookups,
					value_visits: $value_visits,
				},
			},
		)
	}
}

value_bound : KernelObject.Store, KernelObject.ValueId -> Try(ValueBound, KernelOutputBound.Error)
value_bound = |store, value_id| match list_at(store.values, KernelObject.ValueId.index(value_id)) {
	Array(span) => array_bound(store, span)
	Boolean(value) => Ok({ bytes: if value 4 else 5, visits: 1 })
	ByteString(string) => Ok({ bytes: checked_add(checked_times(list_at(store.byte_strings, KernelObject.ByteStringId.index(string)).len(), 2)?, 2)?, visits: 1 })
	Dictionary(span) => dictionary_bound(store, span)
	Integer(_) => Ok({ bytes: 20, visits: 1 })
	Name(name) => Ok({ bytes: name_bound(list_at(store.names, KernelObject.NameId.index(name)))?, visits: 1 })
	Null => Ok({ bytes: 4, visits: 1 })
	Real(_) => Ok({ bytes: 21, visits: 1 })
	Reference(object) => Ok({ bytes: checked_add(decimal_length(KernelObject.ObjectId.number(object)), 4)?, visits: 1 })
	Stream(_) => Err(NestedStreamValue(value_id))
	TextString(string) => Ok({ bytes: checked_add(checked_times(KernelLex.Text.bytes(list_at(store.text_strings, KernelObject.TextStringId.index(string))).len(), 4)?, 6)?, visits: 1 })
}

array_bound : KernelObject.Store, KernelObject.Span -> Try(ValueBound, KernelOutputBound.Error)
array_bound = |store, span| {
	var $bytes = checked_add(2, if span.length == 0 0 else span.length - 1)?
	var $visits = 1
	var $index = 0
	while $index < span.length {
		item = value_bound(store, list_at(store.array_items, span.start + $index))?
		$bytes = checked_add($bytes, item.bytes)?
		$visits = checked_add($visits, item.visits)?
		$index = $index + 1
	}
	Ok({ bytes: $bytes, visits: $visits })
}

dictionary_bound : KernelObject.Store, KernelObject.Span -> Try(ValueBound, KernelOutputBound.Error)
dictionary_bound = |store, span| {
	var $bytes = 5
	var $visits = 1
	var $index = 0
	while $index < span.length {
		entry = list_at(store.dictionary_entries, span.start + $index)
		value = value_bound(store, entry.value)?
		$bytes = checked_add($bytes, 2)?
		$bytes = checked_add($bytes, name_bound(list_at(store.names, KernelObject.NameId.index(entry.key)))?)?
		$bytes = checked_add($bytes, value.bytes)?
		$visits = checked_add($visits, value.visits)?
		$index = $index + 1
	}
	Ok({ bytes: $bytes, visits: $visits })
}

name_bound : KernelLex.Name -> Try(U64, KernelOutputBound.Error)
name_bound = |name| checked_add(checked_times(KernelLex.Name.bytes(name).len(), 3)?, 1)

stream_inserted_entries_bound : KernelObject.Stream -> U64
stream_inserted_entries_bound = |stream| {
	length_entry = 13 + decimal_length(KernelObject.ObjectId.number(stream.length_object))
	filter_entry = match stream.filter {
		Dct => 19
		Deflate => 21
		Unfiltered => 0
	}
	length_entry + filter_entry
}

stream_payload_bound : KernelObject.Store, KernelObject.StreamId -> Try(U64, KernelOutputBound.Error)
stream_payload_bound = |store, stream_id| {
	stream = list_at(store.streams, KernelObject.StreamId.index(stream_id))
	payload = list_at(store.payloads, KernelObject.PayloadId.index(stream.source))
	match stream.filter {
		Dct => Ok(payload.bytes.len())
		Unfiltered => Ok(payload.bytes.len())
		Deflate => if payload.bytes.is_empty() {
			Ok(8)
		} else {
			match KernelDeflate.output_bound(payload.bytes.len()) {
				Ok(bound) => Ok(bound)
				Err(error) => Err(Deflate(error))
			}
		}
	}
}

## One member's header pair (two numbers of at most 20 digits and two
## spaces) and its terminating newline.
member_overhead_bound : U64
member_overhead_bound = 43

## An object stream over members whose serialized bound is `batch`: the
## header's final newline, the DEFLATE bound, and the framing (object header,
## a dictionary of at most three 20-digit numbers, and the stream keywords).
object_stream_bound : U64 -> Try(U64, KernelOutputBound.Error)
object_stream_bound = |batch| {
	compressed = KernelDeflate.output_bound(checked_add(batch, 1)?) ? Deflate
	checked_add(compressed, 256)
}

## The cross-reference stream: one predicted row per object of at most
## 1 + 1 + 8 + 2 bytes, its DEFLATE bound, a dictionary with two 32-byte
## identifiers and at most five 20-digit numbers, and the trailer.
xref_bound : U64, U64 -> Try(U64, KernelOutputBound.Error)
xref_bound = |xref_number, xref_offset_bound| {
	size = checked_add(xref_number, 1)?
	rows = checked_times(size, 12)?
	compressed = KernelDeflate.output_bound(rows) ? Deflate
	header = decimal_length(xref_number) + 7
	dictionary = 512
	suffix = 35 + decimal_length(xref_offset_bound)
	checked_add(checked_add(checked_add(header, dictionary)?, compressed)?, suffix)
}

decimal_length : U64 -> U64
decimal_length = |value| {
	var $digits = 1
	var $remaining = value
	while $remaining >= 10 {
		$remaining = U64.div_by($remaining, 10)
		$digits = $digits + 1
	}
	$digits
}

checked_add : U64, U64 -> Try(U64, KernelOutputBound.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(total) => Ok(total)
}

checked_times : U64, U64 -> Try(U64, KernelOutputBound.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(total) => Ok(total)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "sealed tagged-visual output-bound index escaped"
	}
}
