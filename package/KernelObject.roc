import KernelLex

KernelObject :: [].{
	ValueId :: U64.{
		from_index : U64 -> ValueId
		from_index = |index| ValueId.(index)

		index : ValueId -> U64
		index = |ValueId.(index)| index

		is_eq : ValueId, ValueId -> Bool
		is_eq = |ValueId.(left), ValueId.(right)| left == right
	}

	NameId :: U64.{
		from_index : U64 -> NameId
		from_index = |index| NameId.(index)

		index : NameId -> U64
		index = |NameId.(index)| index

		is_eq : NameId, NameId -> Bool
		is_eq = |NameId.(left), NameId.(right)| left == right
	}

	ByteStringId :: U64.{
		from_index : U64 -> ByteStringId
		from_index = |index| ByteStringId.(index)

		index : ByteStringId -> U64
		index = |ByteStringId.(index)| index

		is_eq : ByteStringId, ByteStringId -> Bool
		is_eq = |ByteStringId.(left), ByteStringId.(right)| left == right
	}

	TextStringId :: U64.{
		from_index : U64 -> TextStringId
		from_index = |index| TextStringId.(index)

		index : TextStringId -> U64
		index = |TextStringId.(index)| index

		is_eq : TextStringId, TextStringId -> Bool
		is_eq = |TextStringId.(left), TextStringId.(right)| left == right
	}

	PayloadId :: U64.{
		from_index : U64 -> PayloadId
		from_index = |index| PayloadId.(index)

		index : PayloadId -> U64
		index = |PayloadId.(index)| index

		is_eq : PayloadId, PayloadId -> Bool
		is_eq = |PayloadId.(left), PayloadId.(right)| left == right
	}

	StreamId :: U64.{
		from_index : U64 -> StreamId
		from_index = |index| StreamId.(index)

		index : StreamId -> U64
		index = |StreamId.(index)| index

		is_eq : StreamId, StreamId -> Bool
		is_eq = |StreamId.(left), StreamId.(right)| left == right
	}

	ObjectId :: U64.{
		from_number : U64 -> Try(ObjectId, Error)
		from_number = |number|
			if number == 0 Err(ObjectNumberZero) else Ok(ObjectId.(number))

		number : ObjectId -> U64
		number = |ObjectId.(number)| number

		is_eq : ObjectId, ObjectId -> Bool
		is_eq = |ObjectId.(left), ObjectId.(right)| left == right
	}

	Span : { length : U64, start : U64 }
	DictionaryEntry : { key : NameId, value : ValueId }
	ObjectContent : [LengthOf(StreamId), Stored(ValueId)]
	Object : { content : ObjectContent, id : ObjectId }

	PayloadKind : [Generated, UnchangedResource]
	PayloadUse : [LastStream(StreamId), Unused]
	Payload : {
		bytes : List(U8),
		id : PayloadId,
		kind : PayloadKind,
		last_use : PayloadUse,
	}

	FilterPlan : [Deflate, Unfiltered]
	Stream : {
		dictionary : Span,
		filter : FilterPlan,
		id : StreamId,
		length_object : ObjectId,
		object : ObjectId,
		source : PayloadId,
	}

	Value : [
		Array(Span),
		Boolean(Bool),
		ByteString(ByteStringId),
		Dictionary(Span),
		Integer(I64),
		Name(NameId),
		Null,
		Real(KernelLex.Decimal),
		Reference(ObjectId),
		Stream(StreamId),
		TextString(TextStringId),
	]

	Dimension : [
		ArrayItems,
		ByteStringBytes,
		ByteStrings,
		DictionaryEntries,
		DirectDepth,
		NameBytes,
		Names,
		Objects,
		PayloadBytes,
		Payloads,
		Streams,
		TextStringBytes,
		TextStrings,
		Values,
		WorkUnits,
	]
	IndexKind : [ByteStringIndex, NameIndex, PayloadIndex, TextStringIndex, ValueIndex]
	Error : [
		DuplicateDictionaryKey(NameId),
		IndexOutOfRange({ available : U64, index : U64, kind : IndexKind }),
		Lexical(KernelLex.Error),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		NonMonotonicDictionaryKeys({ current : NameId, previous : NameId }),
		ObjectNumberZero,
		Overflow(Dimension),
	]

	Limits : {
		max_array_items : U64,
		max_byte_string_bytes : U64,
		max_byte_strings : U64,
		max_dictionary_entries : U64,
		max_direct_depth : U64,
		max_name_bytes : U64,
		max_names : U64,
		max_objects : U64,
		max_payload_bytes : U64,
		max_payloads : U64,
		max_streams : U64,
		max_text_string_bytes : U64,
		max_text_strings : U64,
		max_values : U64,
	}

	Work : {
		bytes_checked : U64,
		edges_appended : U64,
		index_checks : U64,
		values_appended : U64,
	}

	Store : {
		array_items : List(ValueId),
		byte_strings : List(List(U8)),
		depths : List(U64),
		dictionary_entries : List(DictionaryEntry),
		names : List(KernelLex.Name),
		objects : List(Object),
		payloads : List(Payload),
		streams : List(Stream),
		text_strings : List(Str),
		values : List(Value),
	}

	Builder : {
		limits : Limits,
		store : Store,
		total_byte_string_bytes : U64,
		total_name_bytes : U64,
		total_payload_bytes : U64,
		total_text_string_bytes : U64,
		work : Work,
	}

	Counts : {
		array_items : U64,
		byte_strings : U64,
		dictionary_entries : U64,
		names : U64,
		objects : U64,
		payloads : U64,
		streams : U64,
		text_strings : U64,
		values : U64,
	}

	init : Limits -> Builder
	init = |limits| {
		limits,
		store: {
			array_items: [],
			byte_strings: [],
			depths: [],
			dictionary_entries: [],
			names: [],
			objects: [],
			payloads: [],
			streams: [],
			text_strings: [],
			values: [],
		},
		total_byte_string_bytes: 0,
		total_name_bytes: 0,
		total_payload_bytes: 0,
		total_text_string_bytes: 0,
		work: { bytes_checked: 0, edges_appended: 0, index_checks: 0, values_appended: 0 },
	}

	counts : Builder -> Counts
	counts = |builder| {
		array_items: builder.store.array_items.len(),
		byte_strings: builder.store.byte_strings.len(),
		dictionary_entries: builder.store.dictionary_entries.len(),
		names: builder.store.names.len(),
		objects: builder.store.objects.len(),
		payloads: builder.store.payloads.len(),
		streams: builder.store.streams.len(),
		text_strings: builder.store.text_strings.len(),
		values: builder.store.values.len(),
	}

	add_name : Builder, List(U8) -> Try({ builder : Builder, id : NameId }, Error)
	add_name = |builder, bytes| {
		match KernelLex.Name.from_bytes(bytes) {
			Err(error) => Err(Lexical(error))
			Ok(name) => {
				match checked_increment(builder.store.names.len(), builder.limits.max_names, Names) {
					Err(error) => Err(error)
					Ok(_) => match checked_total(builder.total_name_bytes, bytes.len(), builder.limits.max_name_bytes, NameBytes) {
						Err(error) => Err(error)
						Ok(total_name_bytes) => match add_work(
							builder.work,
							{
								bytes_checked: bytes.len(),
								edges_appended: 0,
								index_checks: 0,
								values_appended: 0,
							},
						) {
							Err(error) => Err(error)
							Ok(work) => {
								id = NameId.from_index(builder.store.names.len())
								Ok({
									builder: {
										..builder,
										store: { ..builder.store, names: builder.store.names.append(name) },
										total_name_bytes,
										work,
									},
									id,
								})
							}
						}
					}
				}
			}
		}
	}

	add_byte_string : Builder, List(U8) -> Try({ builder : Builder, id : ByteStringId }, Error)
	add_byte_string = |builder, bytes| {
		match checked_increment(builder.store.byte_strings.len(), builder.limits.max_byte_strings, ByteStrings) {
			Err(error) => Err(error)
			Ok(_) => match checked_total(builder.total_byte_string_bytes, bytes.len(), builder.limits.max_byte_string_bytes, ByteStringBytes) {
				Err(error) => Err(error)
				Ok(total_byte_string_bytes) => {
					id = ByteStringId.from_index(builder.store.byte_strings.len())
					Ok({
						builder: {
							..builder,
							store: { ..builder.store, byte_strings: builder.store.byte_strings.append(bytes) },
							total_byte_string_bytes,
						},
						id,
					})
				}
			}
		}
	}

	add_text_string : Builder, Str -> Try({ builder : Builder, id : TextStringId }, Error)
	add_text_string = |builder, text| {
		byte_length = Str.to_utf8(text).len()
		match checked_increment(builder.store.text_strings.len(), builder.limits.max_text_strings, TextStrings) {
			Err(error) => Err(error)
			Ok(_) => match checked_total(builder.total_text_string_bytes, byte_length, builder.limits.max_text_string_bytes, TextStringBytes) {
				Err(error) => Err(error)
				Ok(total_text_string_bytes) => match add_work(
					builder.work,
					{
						bytes_checked: byte_length,
						edges_appended: 0,
						index_checks: 0,
						values_appended: 0,
					},
				) {
					Err(error) => Err(error)
					Ok(work) => {
						id = TextStringId.from_index(builder.store.text_strings.len())
						Ok({
							builder: {
								..builder,
								store: { ..builder.store, text_strings: builder.store.text_strings.append(text) },
								total_text_string_bytes,
								work,
							},
							id,
						})
					}
				}
			}
		}
	}

	add_payload : Builder, List(U8), PayloadKind -> Try({ builder : Builder, id : PayloadId }, Error)
	add_payload = |builder, bytes, kind| {
		match checked_increment(builder.store.payloads.len(), builder.limits.max_payloads, Payloads) {
			Err(error) => Err(error)
			Ok(_) => match checked_total(builder.total_payload_bytes, bytes.len(), builder.limits.max_payload_bytes, PayloadBytes) {
				Err(error) => Err(error)
				Ok(total_payload_bytes) => {
					id = PayloadId.from_index(builder.store.payloads.len())
					payload = { bytes, id, kind, last_use: Unused }
					Ok({
						builder: {
							..builder,
							store: { ..builder.store, payloads: builder.store.payloads.append(payload) },
							total_payload_bytes,
						},
						id,
					})
				}
			}
		}
	}

	add_null : Builder -> Try({ builder : Builder, id : ValueId }, Error)
	add_null = |builder| add_value(builder, Null, 1)

	add_boolean : Builder, Bool -> Try({ builder : Builder, id : ValueId }, Error)
	add_boolean = |builder, value| add_value(builder, Boolean(value), 1)

	add_integer : Builder, I64 -> Try({ builder : Builder, id : ValueId }, Error)
	add_integer = |builder, value| add_value(builder, Integer(value), 1)

	add_real : Builder, KernelLex.Decimal -> Try({ builder : Builder, id : ValueId }, Error)
	add_real = |builder, value| add_value(builder, Real(value), 1)

	add_name_value : Builder, NameId -> Try({ builder : Builder, id : ValueId }, Error)
	add_name_value = |builder, name| {
		match check_index(NameId.index(name), builder.store.names.len(), NameIndex) {
			Err(error) => Err(error)
			Ok(_) => match add_index_work(builder.work, 1) {
				Err(error) => Err(error)
				Ok(work) => add_value({ ..builder, work }, Name(name), 1)
			}
		}
	}

	add_byte_string_value : Builder, ByteStringId -> Try({ builder : Builder, id : ValueId }, Error)
	add_byte_string_value = |builder, string| {
		match check_index(ByteStringId.index(string), builder.store.byte_strings.len(), ByteStringIndex) {
			Err(error) => Err(error)
			Ok(_) => match add_index_work(builder.work, 1) {
				Err(error) => Err(error)
				Ok(work) => add_value({ ..builder, work }, ByteString(string), 1)
			}
		}
	}

	add_text_string_value : Builder, TextStringId -> Try({ builder : Builder, id : ValueId }, Error)
	add_text_string_value = |builder, string| {
		match check_index(TextStringId.index(string), builder.store.text_strings.len(), TextStringIndex) {
			Err(error) => Err(error)
			Ok(_) => match add_index_work(builder.work, 1) {
				Err(error) => Err(error)
				Ok(work) => add_value({ ..builder, work }, TextString(string), 1)
			}
		}
	}

	add_reference : Builder, ObjectId -> Try({ builder : Builder, id : ValueId }, Error)
	add_reference = |builder, object| add_value(builder, Reference(object), 1)

	add_array : Builder, List(ValueId) -> Try({ builder : Builder, id : ValueId }, Error)
	add_array = |builder, items| {
		match validate_value_edges(builder, items) {
			Err(error) => Err(error)
			Ok(max_child_depth) => match checked_total(builder.store.array_items.len(), items.len(), builder.limits.max_array_items, ArrayItems) {
				Err(error) => Err(error)
				Ok(_) => match checked_increment(max_child_depth, builder.limits.max_direct_depth, DirectDepth) {
					Err(error) => Err(error)
					Ok(depth) => match add_work(
						builder.work,
						{
							bytes_checked: 0,
							edges_appended: items.len(),
							index_checks: items.len(),
							values_appended: 0,
						},
					) {
						Err(error) => Err(error)
						Ok(work) => {
							start = builder.store.array_items.len()
							array_items = append_all(builder.store.array_items, items)
							with_edges = {
								..builder,
								store: { ..builder.store, array_items },
								work,
							}
							add_value(with_edges, Array({ start, length: items.len() }), depth)
						}
					}
				}
			}
		}
	}

	add_dictionary : Builder, List(DictionaryEntry) -> Try({ builder : Builder, id : ValueId }, Error)
	add_dictionary = |builder, entries| {
		match validate_dictionary(builder, entries) {
			Err(error) => Err(error)
			Ok(validation) => match checked_total(builder.store.dictionary_entries.len(), entries.len(), builder.limits.max_dictionary_entries, DictionaryEntries) {
				Err(error) => Err(error)
				Ok(_) => match checked_increment(validation.max_child_depth, builder.limits.max_direct_depth, DirectDepth) {
					Err(error) => Err(error)
					Ok(depth) => match add_dictionary_work(builder.work, entries.len(), validation.key_byte_comparisons, 0) {
						Err(error) => Err(error)
						Ok(work) => {
							start = builder.store.dictionary_entries.len()
							dictionary_entries = append_all(builder.store.dictionary_entries, entries)
							with_edges = {
								..builder,
								store: { ..builder.store, dictionary_entries },
								work,
							}
							add_value(with_edges, Dictionary({ start, length: entries.len() }), depth)
						}
					}
				}
			}
		}
	}

	add_stream_object : Builder, List(DictionaryEntry), FilterPlan, PayloadId -> Try({ builder : Builder, id : ObjectId, length_object : ObjectId, value : ValueId }, Error)
	add_stream_object = |builder, entries, filter, source| {
		match check_index(PayloadId.index(source), builder.store.payloads.len(), PayloadIndex) {
			Err(error) => Err(error)
			Ok(_) => match checked_increment(builder.store.streams.len(), builder.limits.max_streams, Streams) {
				Err(error) => Err(error)
				Ok(_) => match checked_total(builder.store.objects.len(), 2, builder.limits.max_objects, Objects) {
					Err(error) => Err(error)
					Ok(length_number) => match validate_dictionary(builder, entries) {
						Err(error) => Err(error)
						Ok(validation) => match checked_total(builder.store.dictionary_entries.len(), entries.len(), builder.limits.max_dictionary_entries, DictionaryEntries) {
							Err(error) => Err(error)
							Ok(_) => match checked_increment(validation.max_child_depth, builder.limits.max_direct_depth, DirectDepth) {
								Err(error) => Err(error)
								Ok(depth) => match add_dictionary_work(builder.work, entries.len(), validation.key_byte_comparisons, 1) {
									Err(error) => Err(error)
									Ok(work) => {
										start = builder.store.dictionary_entries.len()
										dictionary_entries = append_all(builder.store.dictionary_entries, entries)
										stream_id = StreamId.from_index(builder.store.streams.len())
										object_id = object_id_from_nonzero(builder.store.objects.len() + 1)
										length_object = object_id_from_nonzero(length_number)
										stream = {
											dictionary: { start, length: entries.len() },
											filter,
											id: stream_id,
											length_object,
											object: object_id,
											source,
										}
										payload_index = PayloadId.index(source)
										payload = list_at(builder.store.payloads, payload_index)
										payloads = list_set(builder.store.payloads, payload_index, { ..payload, last_use: LastStream(stream_id) })
										before_value = {
											..builder,
											store: {
												..builder.store,
												dictionary_entries,
												payloads,
												streams: builder.store.streams.append(stream),
											},
											work,
										}
										match add_value(before_value, Stream(stream_id), depth) {
											Err(error) => Err(error)
											Ok(added_value) => {
												objects = added_value.builder.store.objects
													.append({ content: Stored(added_value.id), id: object_id })
													.append({ content: LengthOf(stream_id), id: length_object })
												Ok({
													builder: { ..added_value.builder, store: { ..added_value.builder.store, objects } },
													id: object_id,
													length_object,
													value: added_value.id,
												})
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}

	add_object : Builder, ValueId -> Try({ builder : Builder, id : ObjectId }, Error)
	add_object = |builder, value| {
		match check_index(ValueId.index(value), builder.store.values.len(), ValueIndex) {
			Err(error) => Err(error)
			Ok(_) => match checked_increment(builder.store.objects.len(), builder.limits.max_objects, Objects) {
				Err(error) => Err(error)
				Ok(number) => match add_index_work(builder.work, 1) {
					Err(error) => Err(error)
					Ok(work) => {
						object_id = object_id_from_nonzero(number)
						object = { content: Stored(value), id: object_id }
						Ok({
							builder: {
								..builder,
								store: { ..builder.store, objects: builder.store.objects.append(object) },
								work,
							},
							id: object_id,
						})
					}
				}
			}
		}
	}
}

add_value : KernelObject.Builder, KernelObject.Value, U64 -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelObject.Error)
add_value = |builder, value, depth| {
	match checked_limit(depth, builder.limits.max_direct_depth, DirectDepth) {
		Err(error) => Err(error)
		Ok(_) => match checked_increment(builder.store.values.len(), builder.limits.max_values, Values) {
			Err(error) => Err(error)
			Ok(_) => match add_work(
				builder.work,
				{
					bytes_checked: 0,
					edges_appended: 0,
					index_checks: 0,
					values_appended: 1,
				},
			) {
				Err(error) => Err(error)
				Ok(work) => {
					id = KernelObject.ValueId.from_index(builder.store.values.len())
					Ok({
						builder: {
							..builder,
							store: {
								..builder.store,
								depths: builder.store.depths.append(depth),
								values: builder.store.values.append(value),
							},
							work,
						},
						id,
					})
				}
			}
		}
	}
}

validate_value_edges : KernelObject.Builder, List(KernelObject.ValueId) -> Try(U64, KernelObject.Error)
validate_value_edges = |builder, items| {
	length = items.len()
	var $index = 0
	var $max_depth = 0
	var $error = NoError
	while $index < length and $error == NoError {
		value_id = list_at(items, $index)
		value_index = KernelObject.ValueId.index(value_id)
		match check_index(value_index, builder.store.values.len(), ValueIndex) {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(_) => {
				depth = list_at(builder.store.depths, value_index)
				$max_depth = U64.max($max_depth, depth)
			}
		}
		$index = $index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => Ok($max_depth)
	}
}

validate_dictionary : KernelObject.Builder, List(KernelObject.DictionaryEntry) -> Try({ key_byte_comparisons : U64, max_child_depth : U64 }, KernelObject.Error)
validate_dictionary = |builder, entries| {
	length = entries.len()
	var $index = 0
	var $key_byte_comparisons = 0
	var $max_depth = 0
	var $previous = NoPrevious
	var $error = NoError
	while $index < length and $error == NoError {
		entry = list_at(entries, $index)
		name_index = KernelObject.NameId.index(entry.key)
		value_index = KernelObject.ValueId.index(entry.value)

		match check_index(name_index, builder.store.names.len(), NameIndex) {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(_) => match check_index(value_index, builder.store.values.len(), ValueIndex) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(_) => {
					depth = list_at(builder.store.depths, value_index)
					$max_depth = U64.max($max_depth, depth)
					match $previous {
						NoPrevious => {}
						Previous(previous_id) => {
							previous_name = list_at(builder.store.names, KernelObject.NameId.index(previous_id))
							current_name = list_at(builder.store.names, name_index)
							match compare_bytes(KernelLex.Name.bytes(previous_name), KernelLex.Name.bytes(current_name)) {
								Err(error) => {
									$error = Invalid(error)
								}
								Ok(comparison) => {
									match U64.plus_try($key_byte_comparisons, comparison.byte_comparisons) {
										Err(Overflow) => {
											$error = Invalid(Overflow(WorkUnits))
										}
										Ok(total) => {
											$key_byte_comparisons = total
										}
									}
									if $error == NoError {
										match comparison.ordering {
											Equal => {
												$error = Invalid(DuplicateDictionaryKey(entry.key))
											}
											Greater => {
												$error = Invalid(NonMonotonicDictionaryKeys({ current: entry.key, previous: previous_id }))
											}
											Less => {}
										}
									}
								}
							}
						}
					}
					$previous = Previous(entry.key)
				}
			}
		}
		$index = $index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ key_byte_comparisons: $key_byte_comparisons, max_child_depth: $max_depth })
	}
}

compare_bytes : List(U8), List(U8) -> Try({ byte_comparisons : U64, ordering : [Equal, Greater, Less] }, KernelObject.Error)
compare_bytes = |left, right| {
	shared = U64.min(left.len(), right.len())
	var $index = 0
	var $ordering = Equal
	var $error = NoError
	while $index < shared and $ordering == Equal and $error == NoError {
		left_byte = list_at(left, $index)
		right_byte = list_at(right, $index)
		if left_byte < right_byte {
			$ordering = Less
		} else if left_byte > right_byte {
			$ordering = Greater
		}
		match U64.plus_try($index, 1) {
			Err(Overflow) => {
				$error = Invalid(Overflow(WorkUnits))
			}
			Ok(next) => {
				$index = next
			}
		}
	}

	ordering = if $ordering != Equal {
		$ordering
	} else if left.len() < right.len() {
		Less
	} else if left.len() > right.len() {
		Greater
	} else {
		Equal
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ byte_comparisons: $index, ordering })
	}
}

checked_increment : U64, U64, KernelObject.Dimension -> Try(U64, KernelObject.Error)
checked_increment = |current, limit, dimension| {
	match U64.plus_try(current, 1) {
		Err(Overflow) => Err(Overflow(dimension))
		Ok(attempted) => if attempted > limit {
			Err(LimitExceeded({ attempted, dimension, limit }))
		} else {
			Ok(attempted)
		}
	}
}

checked_limit : U64, U64, KernelObject.Dimension -> Try(U64, KernelObject.Error)
checked_limit = |attempted, limit, dimension|
	if attempted > limit {
		Err(LimitExceeded({ attempted, dimension, limit }))
	} else {
		Ok(attempted)
	}

checked_total : U64, U64, U64, KernelObject.Dimension -> Try(U64, KernelObject.Error)
checked_total = |current, added, limit, dimension| {
	match U64.plus_try(current, added) {
		Err(Overflow) => Err(Overflow(dimension))
		Ok(attempted) => if attempted > limit {
			Err(LimitExceeded({ attempted, dimension, limit }))
		} else {
			Ok(attempted)
		}
	}
}

check_index : U64, U64, KernelObject.IndexKind -> Try({}, KernelObject.Error)
check_index = |index, available, kind| {
	if index < available {
		Ok({})
	} else {
		Err(IndexOutOfRange({ available, index, kind }))
	}
}

add_work : KernelObject.Work, KernelObject.Work -> Try(KernelObject.Work, KernelObject.Error)
add_work = |work, added| {
	match U64.plus_try(work.bytes_checked, added.bytes_checked) {
		Err(Overflow) => Err(Overflow(WorkUnits))
		Ok(bytes_checked) => match U64.plus_try(work.edges_appended, added.edges_appended) {
			Err(Overflow) => Err(Overflow(WorkUnits))
			Ok(edges_appended) => match U64.plus_try(work.index_checks, added.index_checks) {
				Err(Overflow) => Err(Overflow(WorkUnits))
				Ok(index_checks) => match U64.plus_try(work.values_appended, added.values_appended) {
					Err(Overflow) => Err(Overflow(WorkUnits))
					Ok(values_appended) => Ok({ bytes_checked, edges_appended, index_checks, values_appended })
				}
			}
		}
	}
}

add_index_work : KernelObject.Work, U64 -> Try(KernelObject.Work, KernelObject.Error)
add_index_work = |work, count| add_work(
	work,
	{
		bytes_checked: 0,
		edges_appended: 0,
		index_checks: count,
		values_appended: 0,
	},
)

add_dictionary_work : KernelObject.Work, U64, U64, U64 -> Try(KernelObject.Work, KernelObject.Error)
add_dictionary_work = |work, entry_count, key_byte_comparisons, extra_index_checks| {
	match add_work(
		work,
		{
			bytes_checked: key_byte_comparisons,
			edges_appended: entry_count,
			index_checks: entry_count,
			values_appended: 0,
		},
	) {
		Err(error) => Err(error)
		Ok(first) => match add_index_work(first, entry_count) {
			Err(error) => Err(error)
			Ok(second) => add_index_work(second, extra_index_checks)
		}
	}
}

append_all : List(a), List(a) -> List(a)
append_all = |target, source| {
	length = source.len()
	var $out = List.reserve(target, length)
	var $index = 0
	while $index < length {
		$out = $out.append(list_at(source, $index))
		$index = $index + 1
	}
	$out
}

list_at : List(a), U64 -> a
list_at = |list, index| match list.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "kernel object index invariant failed"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |list, index, value| match list.set(index, value) {
	Ok(updated) => updated
	Err(OutOfBounds) => {
		crash "kernel object index invariant failed"
	}
}

object_id_from_nonzero : U64 -> KernelObject.ObjectId
object_id_from_nonzero = |number| match KernelObject.ObjectId.from_number(number) {
	Ok(id) => id
	Err(ObjectNumberZero) => {
		crash "kernel object number invariant failed"
	}
	Err(_) => {
		crash "unexpected object ID construction error"
	}
}

test_limits : KernelObject.Limits
test_limits = {
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

## Flat stores assign dense IDs and record exact construction work.
expect {
	initial = KernelObject.init(test_limits)
	match KernelObject.add_name(initial, Str.to_utf8("A")) {
		Err(_) => False
		Ok(first_name) => match KernelObject.add_name(first_name.builder, Str.to_utf8("B")) {
			Err(_) => False
			Ok(second_name) => match KernelObject.add_integer(second_name.builder, 7) {
				Err(_) => False
				Ok(integer) => match KernelObject.add_dictionary(
					integer.builder,
					[
						{ key: first_name.id, value: integer.id },
						{ key: second_name.id, value: integer.id },
					],
				) {
					Err(_) => False
					Ok(dictionary) => match KernelObject.add_object(dictionary.builder, dictionary.id) {
						Err(_) => False
						Ok(object) => {
							counts = KernelObject.counts(object.builder)
							actual =
								\\names: ${Str.inspect(counts.names)}
								\\values: ${Str.inspect(counts.values)}
								\\dictionary entries: ${Str.inspect(counts.dictionary_entries)}
								\\objects: ${Str.inspect(counts.objects)}
								\\object number: ${Str.inspect(KernelObject.ObjectId.number(object.id))}
								\\work: ${Str.inspect(object.builder.work)}

							expected =
								\\names: 2
								\\values: 2
								\\dictionary entries: 2
								\\objects: 1
								\\object number: 1
								\\work: { bytes_checked: 3, edges_appended: 2, index_checks: 5, values_appended: 2 }

							actual == expected
						}
					}
				}
			}
		}
	}
}

## Duplicate dictionary keys fail without appending any edge.
expect {
	initial = KernelObject.init(test_limits)
	match KernelObject.add_name(initial, Str.to_utf8("A")) {
		Err(_) => False
		Ok(name) => match KernelObject.add_null(name.builder) {
			Err(_) => False
			Ok(value) => match KernelObject.add_dictionary(
				value.builder,
				[
					{ key: name.id, value: value.id },
					{ key: name.id, value: value.id },
				],
			) {
				Err(DuplicateDictionaryKey(_)) => KernelObject.counts(value.builder).dictionary_entries == 0
				_ => False
			}
		}
	}
}

## Dictionary keys must already be in canonical byte order.
expect {
	initial = KernelObject.init(test_limits)
	match KernelObject.add_name(initial, Str.to_utf8("B")) {
		Err(_) => False
		Ok(second) => match KernelObject.add_name(second.builder, Str.to_utf8("A")) {
			Err(_) => False
			Ok(first) => match KernelObject.add_null(first.builder) {
				Err(_) => False
				Ok(value) => match KernelObject.add_dictionary(
					value.builder,
					[
						{ key: second.id, value: value.id },
						{ key: first.id, value: value.id },
					],
				) {
					Err(NonMonotonicDictionaryKeys(_)) => True
					_ => False
				}
			}
		}
	}
}

## Array edges reject value IDs outside the dense value store.
expect {
	initial = KernelObject.init(test_limits)
	match KernelObject.add_array(initial, [KernelObject.ValueId.from_index(99)]) {
		Err(IndexOutOfRange({ available, index, kind: ValueIndex })) => available == 0 and index == 99
		_ => False
	}
}

## Count limits fail at the exact attempted value.
expect {
	limits = { ..test_limits, max_names: 0 }
	match KernelObject.add_name(KernelObject.init(limits), Str.to_utf8("A")) {
		Err(LimitExceeded({ attempted, dimension: Names, limit })) => attempted == 1 and limit == 0
		_ => False
	}
}

## Scalar values obey the same direct-depth limit as containers.
expect {
	limits = { ..test_limits, max_direct_depth: 0 }
	initial = KernelObject.init(limits)
	match KernelObject.add_null(initial) {
		Err(LimitExceeded({ attempted, dimension: DirectDepth, limit })) => {
			attempted == 1 and limit == 0 and KernelObject.counts(initial).values == 0
		}
		_ => False
	}
}

## Byte-string value errors identify the byte-string store.
expect {
	initial = KernelObject.init(test_limits)
	match KernelObject.add_byte_string_value(initial, KernelObject.ByteStringId.from_index(0)) {
		Err(IndexOutOfRange({ available, index, kind: ByteStringIndex })) => available == 0 and index == 0
		_ => False
	}
}

## Text-string value errors identify the text-string store.
expect {
	initial = KernelObject.init(test_limits)
	match KernelObject.add_text_string_value(initial, KernelObject.TextStringId.from_index(0)) {
		Err(IndexOutOfRange({ available, index, kind: TextStringIndex })) => available == 0 and index == 0
		_ => False
	}
}

## Streams retain a payload ID and a preassigned length-object ID.
expect {
	initial = KernelObject.init(test_limits)
	match KernelObject.add_payload(initial, [1, 2, 3], UnchangedResource) {
		Err(_) => False
		Ok(payload) => match KernelObject.add_stream_object(payload.builder, [], Unfiltered, payload.id) {
			Err(_) => False
			Ok(stream_value) => {
				counts = KernelObject.counts(stream_value.builder)
				actual =
					\\payloads: ${Str.inspect(counts.payloads)}
					\\streams: ${Str.inspect(counts.streams)}
					\\values: ${Str.inspect(counts.values)}
					\\objects: ${Str.inspect(counts.objects)}
					\\object number: ${Str.inspect(KernelObject.ObjectId.number(stream_value.id))}
					\\length object number: ${Str.inspect(KernelObject.ObjectId.number(stream_value.length_object))}
					\\work: ${Str.inspect(stream_value.builder.work)}

				expected =
					\\payloads: 1
					\\streams: 1
					\\values: 1
					\\objects: 2
					\\object number: 1
					\\length object number: 2
					\\work: { bytes_checked: 0, edges_appended: 0, index_checks: 1, values_appended: 1 }

				actual == expected
			}
		}
	}
}

## PDF object number zero is never constructible.
expect {
	match KernelObject.ObjectId.from_number(0) {
		Err(ObjectNumberZero) => True
		_ => False
	}
}
