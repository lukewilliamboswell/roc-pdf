import KernelObject

KernelSeal :: [].{
	StoreKind : [ArrayEdge, ByteStringValue, DictionaryEdge, NameValue, ObjectContent, StreamValue, TextStringValue]
	Error : [
		IndexOutOfRange({ available : U64, index : U64, kind : StoreKind }),
		ObjectOrder({ actual : KernelObject.ObjectId, expected : U64 }),
		ReferenceOutOfRange({ available : U64, source : KernelObject.ValueId, target : KernelObject.ObjectId }),
		SpanOutOfRange({ available : U64, kind : StoreKind, length : U64, start : U64 }),
		SpanOverflow(StoreKind),
		StreamLengthNotAdjacent({ length_object : KernelObject.ObjectId, object : KernelObject.ObjectId, stream : KernelObject.StreamId }),
		StreamLengthObjectMismatch({ length_object : KernelObject.ObjectId, stream : KernelObject.StreamId }),
		StreamObjectMismatch({ object : KernelObject.ObjectId, stream : KernelObject.StreamId }),
		WorkOverflow,
	]

	Work : {
		objects_checked : U64,
		references_checked : U64,
		streams_checked : U64,
		values_checked : U64,
	}

	SourceBytes : {
		byte_strings : U64,
		names : U64,
		payloads : U64,
		text_strings : U64,
	}

	Plan :: {
		build_work : KernelObject.Work,
		seal_work : Work,
		source_bytes : SourceBytes,
		store : KernelObject.Store,
	}.{
		build_work : Plan -> KernelObject.Work
		build_work = |plan| plan.build_work

		counts : Plan -> KernelObject.Counts
		counts = |plan| counts_from_store(plan.store)

		seal_work : Plan -> Work
		seal_work = |plan| plan.seal_work

		source_bytes : Plan -> SourceBytes
		source_bytes = |plan| plan.source_bytes

		store : Plan -> KernelObject.Store
		store = |plan| plan.store
	}

	seal : KernelObject.Builder -> Try(Plan, Error)
	seal = |builder| {
		object_work = validate_objects(builder.store)?
		value_work = validate_values(builder.store)?
		stream_work = validate_streams(builder.store)?

		Ok(
			Plan.{
				build_work: builder.work,
				seal_work: {
					objects_checked: object_work,
					references_checked: value_work.references_checked,
					streams_checked: stream_work,
					values_checked: value_work.values_checked,
				},
				source_bytes: {
					byte_strings: builder.total_byte_string_bytes,
					names: builder.total_name_bytes,
					payloads: builder.total_payload_bytes,
					text_strings: builder.total_text_string_bytes,
				},
				store: builder.store,
			},
		)
	}
}

validate_objects : KernelObject.Store -> Try(U64, KernelSeal.Error)
validate_objects = |store| {
	length = store.objects.len()
	var $index = 0
	var $error = NoError
	while $index < length and $error == NoError {
		object = list_at(store.objects, $index)
		expected = $index + 1
		if KernelObject.ObjectId.number(object.id) != expected {
			$error = Invalid(ObjectOrder({ actual: object.id, expected }))
		} else {
			match object.content {
				Stored(value) => if KernelObject.ValueId.index(value) >= store.values.len() {
					$error = Invalid(
						IndexOutOfRange({
							available: store.values.len(),
							index: KernelObject.ValueId.index(value),
							kind: ObjectContent,
						}),
					)
				}
				LengthOf(stream) => if KernelObject.StreamId.index(stream) >= store.streams.len() {
					$error = Invalid(
						IndexOutOfRange({
							available: store.streams.len(),
							index: KernelObject.StreamId.index(stream),
							kind: ObjectContent,
						}),
					)
				}
			}
		}
		$index = $index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => Ok(length)
	}
}

validate_values : KernelObject.Store -> Try({ references_checked : U64, values_checked : U64 }, KernelSeal.Error)
validate_values = |store| {
	length = store.values.len()
	var $index = 0
	var $references_checked = 0
	var $error = NoError
	while $index < length and $error == NoError {
		value = list_at(store.values, $index)
		match value {
			Array(span) => match validate_span(span, store.array_items.len(), ArrayEdge) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(_) => {}
			}
			Boolean(_) => {}
			ByteString(string) => if KernelObject.ByteStringId.index(string) >= store.byte_strings.len() {
				$error = Invalid(
					IndexOutOfRange({
						available: store.byte_strings.len(),
						index: KernelObject.ByteStringId.index(string),
						kind: ByteStringValue,
					}),
				)
			}
			Dictionary(span) => match validate_span(span, store.dictionary_entries.len(), DictionaryEdge) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(_) => {}
			}
			Integer(_) => {}
			Name(name) => if KernelObject.NameId.index(name) >= store.names.len() {
				$error = Invalid(
					IndexOutOfRange({
						available: store.names.len(),
						index: KernelObject.NameId.index(name),
						kind: NameValue,
					}),
				)
			}
			Null => {}
			Real(_) => {}
			Reference(target) => {
				number = KernelObject.ObjectId.number(target)
				if number == 0 or number > store.objects.len() {
					$error = Invalid(
						ReferenceOutOfRange({
							available: store.objects.len(),
							source: KernelObject.ValueId.from_index($index),
							target,
						}),
					)
				} else {
					match U64.plus_try($references_checked, 1) {
						Err(Overflow) => {
							$error = Invalid(WorkOverflow)
						}
						Ok(next) => {
							$references_checked = next
						}
					}
				}
			}
			Stream(stream) => if KernelObject.StreamId.index(stream) >= store.streams.len() {
				$error = Invalid(
					IndexOutOfRange({
						available: store.streams.len(),
						index: KernelObject.StreamId.index(stream),
						kind: StreamValue,
					}),
				)
			}
			TextString(string) => if KernelObject.TextStringId.index(string) >= store.text_strings.len() {
				$error = Invalid(
					IndexOutOfRange({
						available: store.text_strings.len(),
						index: KernelObject.TextStringId.index(string),
						kind: TextStringValue,
					}),
				)
			}
		}
		$index = $index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ references_checked: $references_checked, values_checked: length })
	}
}

validate_streams : KernelObject.Store -> Try(U64, KernelSeal.Error)
validate_streams = |store| {
	length = store.streams.len()
	var $index = 0
	var $error = NoError
	while $index < length and $error == NoError {
		stream = list_at(store.streams, $index)
		stream_id = KernelObject.StreamId.from_index($index)
		object_number = KernelObject.ObjectId.number(stream.object)
		length_number = KernelObject.ObjectId.number(stream.length_object)

		if stream.id != stream_id {
			$error = Invalid(StreamObjectMismatch({ object: stream.object, stream: stream_id }))
		} else if object_number == 0 or object_number > store.objects.len() {
			$error = Invalid(StreamObjectMismatch({ object: stream.object, stream: stream_id }))
		} else if length_number == 0 or length_number > store.objects.len() {
			$error = Invalid(StreamLengthObjectMismatch({ length_object: stream.length_object, stream: stream_id }))
		} else if object_number == store.objects.len() or length_number != object_number + 1 {
			$error = Invalid(
				StreamLengthNotAdjacent({
					length_object: stream.length_object,
					object: stream.object,
					stream: stream_id,
				}),
			)
		} else {
			object = list_at(store.objects, object_number - 1)
			length_object = list_at(store.objects, length_number - 1)
			match object.content {
				Stored(value_id) => match list_at(store.values, KernelObject.ValueId.index(value_id)) {
					Stream(actual) => if actual != stream_id {
						$error = Invalid(StreamObjectMismatch({ object: stream.object, stream: stream_id }))
					}
					_ => {
						$error = Invalid(StreamObjectMismatch({ object: stream.object, stream: stream_id }))
					}
				}
				_ => {
					$error = Invalid(StreamObjectMismatch({ object: stream.object, stream: stream_id }))
				}
			}

			if $error == NoError {
				match length_object.content {
					LengthOf(actual) => if actual != stream_id {
						$error = Invalid(StreamLengthObjectMismatch({ length_object: stream.length_object, stream: stream_id }))
					}
					_ => {
						$error = Invalid(StreamLengthObjectMismatch({ length_object: stream.length_object, stream: stream_id }))
					}
				}
			}
		}
		$index = $index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => Ok(length)
	}
}

validate_span : KernelObject.Span, U64, KernelSeal.StoreKind -> Try({}, KernelSeal.Error)
validate_span = |span, available, kind| {
	match U64.plus_try(span.start, span.length) {
		Err(Overflow) => Err(SpanOverflow(kind))
		Ok(end) => if end > available {
			Err(SpanOutOfRange({ available, kind, length: span.length, start: span.start }))
		} else {
			Ok({})
		}
	}
}

counts_from_store : KernelObject.Store -> KernelObject.Counts
counts_from_store = |store| {
	array_items: store.array_items.len(),
	byte_strings: store.byte_strings.len(),
	dictionary_entries: store.dictionary_entries.len(),
	names: store.names.len(),
	objects: store.objects.len(),
	payloads: store.payloads.len(),
	streams: store.streams.len(),
	text_strings: store.text_strings.len(),
	values: store.values.len(),
}

list_at : List(a), U64 -> a
list_at = |list, index| match list.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "sealed object-plan index invariant failed"
	}
}

seal_limits : KernelObject.Limits
seal_limits = {
	max_array_items: 16,
	max_byte_string_bytes: 64,
	max_byte_strings: 8,
	max_dictionary_entries: 16,
	max_direct_depth: 8,
	max_name_bytes: 64,
	max_names: 8,
	max_objects: 8,
	max_payload_bytes: 64,
	max_payloads: 8,
	max_streams: 8,
	max_text_string_bytes: 64,
	max_text_strings: 8,
	max_values: 32,
}

## Sealing preserves the compact stores and records exact linear work.
expect {
	null = KernelObject.add_null(KernelObject.init(seal_limits))?
	object = KernelObject.add_object(null.builder, null.id)?
	plan = KernelSeal.seal(object.builder)?

	actual =
		\\counts: ${Str.inspect(KernelSeal.Plan.counts(plan))}
		\\work: ${Str.inspect(KernelSeal.Plan.seal_work(plan))}

	expected =
		\\counts: { array_items: 0, byte_strings: 0, dictionary_entries: 0, names: 0, objects: 1, payloads: 0, streams: 0, text_strings: 0, values: 1 }
		\\work: { objects_checked: 1, references_checked: 0, streams_checked: 0, values_checked: 1 }

	actual == expected
}

## Forward references resolve against the complete sealed object range.
expect {
	target = KernelObject.ObjectId.from_number(2)?
	reference = KernelObject.add_reference(KernelObject.init(seal_limits), target)?
	first = KernelObject.add_object(reference.builder, reference.id)?
	null = KernelObject.add_null(first.builder)?
	second = KernelObject.add_object(null.builder, null.id)?
	plan = KernelSeal.seal(second.builder)?

	KernelSeal.Plan.seal_work(plan).references_checked == 1
}

## A reference outside the final object range is rejected by source value ID.
expect {
	target = KernelObject.ObjectId.from_number(2)?
	reference = KernelObject.add_reference(KernelObject.init(seal_limits), target)?
	object = KernelObject.add_object(reference.builder, reference.id)?

	match KernelSeal.seal(object.builder) {
		Err(ReferenceOutOfRange({ available, source, target: actual })) => {
			available == 1 and KernelObject.ValueId.index(source) == 0 and actual == target
		}
		_ => False
	}
}

## Stream and indirect length objects seal as one consecutive pair.
expect {
	payload = KernelObject.add_payload(KernelObject.init(seal_limits), [1, 2, 3], Generated)?
	stream = KernelObject.add_stream_object(payload.builder, [], Unfiltered, payload.id)?
	plan = KernelSeal.seal(stream.builder)?

	KernelSeal.Plan.counts(plan).objects == 2 and KernelSeal.Plan.seal_work(plan).streams_checked == 1
}

## A non-adjacent stream-length object is rejected before emission.
expect {
	payload = KernelObject.add_payload(KernelObject.init(seal_limits), [1, 2, 3], Generated)?
	stream_result = KernelObject.add_stream_object(payload.builder, [], Unfiltered, payload.id)?
	stream = stream_result.builder.store.streams.get(0)?
	bad_store = {
		..stream_result.builder.store,
		streams: [{ ..stream, length_object: stream_result.id }],
	}
	bad_builder = { ..stream_result.builder, store: bad_store }

	match KernelSeal.seal(bad_builder) {
		Err(StreamLengthNotAdjacent(_)) => True
		_ => False
	}
}
