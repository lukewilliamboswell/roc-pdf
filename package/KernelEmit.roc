import KernelDeflate
import KernelLex
import KernelObject
import KernelSeal
import KernelSha256
import KernelStructure

SegmentOwnership : [Generated, OwnedResource, SharedResource]

Retention : [OwnResourceChunks, ShareResourceChunks]

PayloadPhase : {
	bytes : List(U8),
	next_object : U64,
	ownership : SegmentOwnership,
	release : [KeepPayload, ReleasePayload(KernelObject.PayloadId)],
}

DeflatePhase : {
	encoder : KernelDeflate.Encoder,
	emitted_length : U64,
	next_object : U64,
}

XrefEntriesPhase : {
	entry : U64,
	size : U64,
	xref_offset : U64,
}

Phase : [
	DeflatePayload(DeflatePhase),
	Finished,
	Header,
	Object(U64),
	Payload(PayloadPhase),
	StreamSuffix(U64),
	XrefEntries(XrefEntriesPhase),
	XrefPrefix,
	XrefSuffix(U64),
]

KernelEmit :: [].{
	Error : [
		ArithmeticOverflow,
		Deflate(KernelDeflate.Error),
		DeflateRequiresGeneratedPayload(KernelObject.StreamId),
		IdentifierInputTooLarge,
		IndexInvariant,
		NestedStreamValue,
		OutputBoundExceeded({ bound : U64, position : U64 }),
		ReservedStreamKey(KernelObject.NameId),
		StreamLengthUnavailable(KernelObject.StreamId),
	]

	Segment : { bytes : List(U8), ownership : SegmentOwnership }
	Step : [Done, Emit(Segment, Encoder)]

	Encoder :: {
		copied_resource_bytes : U64,
		deflate_work : KernelDeflate.Work,
		file_id : List(U8),
		offsets : List(U64),
		output_bound : U64,
		phase : Phase,
		plan : KernelStructure.Plan,
		position : U64,
		retention : Retention,
		stream_lengths : List(U64),
	}.{
		copied_resource_bytes : Encoder -> U64
		copied_resource_bytes = |encoder| encoder.copied_resource_bytes

		deflate_work : Encoder -> KernelDeflate.Work
		deflate_work = |encoder| encoder.deflate_work

		next : Encoder -> Try(Step, Error)
		next = |encoder| next_segment(encoder)

		output_bound : Encoder -> U64
		output_bound = |encoder| encoder.output_bound

		next_infallible : Encoder -> Step
		next_infallible = |encoder| match next_segment(encoder) {
			Ok(step) => step
			Err(_) => {
				crash "sealed structural emission invariant failed"
			}
		}
	}

	CountingSink :: {
		offsets : List(U64),
		position : U64,
	}.{
		start : U64 -> CountingSink
		start = |position| CountingSink.{ offsets: [], position }

		mark_object : CountingSink -> CountingSink
		mark_object = |sink| CountingSink.{ offsets: sink.offsets.append(sink.position), position: sink.position }

		position : CountingSink -> U64
		position = |sink| sink.position

		write : CountingSink, U64 -> Try(CountingSink, Error)
		write = |sink, length| {
			next_position = checked_add(sink.position, length)?
			Ok(CountingSink.{ offsets: sink.offsets, position: next_position })
		}

		xref_entry : CountingSink, U64 -> List(U8)
		xref_entry = |sink, index| append_xref_entry([], 1, list_at(sink.offsets, index), 0)
	}

	start : KernelStructure.Plan, Retention -> Try(Encoder, Error)
	start = |plan, retention| {
		validate_emittable(plan)?
		file_id = KernelSha256.digest(identifier_facts(plan)) ? |_| IdentifierInputTooLarge
		store = plan_store(plan)
		Ok(
			Encoder.{
				copied_resource_bytes: 0,
				deflate_work: KernelDeflate.Work.zero,
				file_id,
				offsets: List.with_capacity(store.objects.len() + 1),
				output_bound: KernelStructure.Plan.output_bound(plan),
				phase: Header,
				plan,
				position: 0,
				retention,
				stream_lengths: List.with_capacity(store.streams.len()),
			},
		)
	}

	to_bytes : KernelStructure.Plan -> Try(List(U8), Error)
	to_bytes = |plan| {
		var $encoder = start(plan, OwnResourceChunks)?
		var $output = []
		var $done = False
		while $done == False {
			match Encoder.next($encoder)? {
				Done => {
					$done = True
				}
				Emit(segment, next) => {
					$output = append_all($output, segment.bytes)
					$encoder = next
				}
			}
		}
		Ok($output)
	}
}

validate_emittable : KernelStructure.Plan -> Try({}, KernelEmit.Error)
validate_emittable = |plan| {
	store = plan_store(plan)
	length = store.streams.len()
	var $index = 0
	var $error = NoError
	while $index < length and $error == NoError {
		stream = list_at(store.streams, $index)
		match reserved_stream_key(store, stream.dictionary) {
			Reserved(key) => {
				$error = InvalidReserved(key)
			}
			NoReserved => {}
		}
		if $error == NoError and stream.filter == Deflate {
			payload = list_at(store.payloads, KernelObject.PayloadId.index(stream.source))
			if payload.kind != Generated {
				$error = InvalidDeflateKind(stream.id)
			} else if payload.bytes.is_empty() == False {
				match prepare_deflate(payload.bytes) {
					Err(deflate_error) => {
						$error = InvalidDeflate(deflate_error)
					}
					Ok(_) => {}
				}
			}
		}
		$index = $index + 1
	}

	match $error {
		InvalidReserved(key) => Err(ReservedStreamKey(key))
		InvalidDeflate(error) => Err(Deflate(error))
		InvalidDeflateKind(stream) => Err(DeflateRequiresGeneratedPayload(stream))
		NoError => Ok({})
	}
}

prepare_deflate : List(U8) -> Try(KernelDeflate.Plan, KernelDeflate.Error)
prepare_deflate = |bytes| {
	bound = KernelDeflate.output_bound(bytes.len())?
	KernelDeflate.Plan.prepare(bytes, KernelDeflate.Limits.make({ max_input_bytes: bytes.len(), max_output_bytes: bound }))
}

next_segment : KernelEmit.Encoder -> Try(KernelEmit.Step, KernelEmit.Error)
next_segment = |encoder| match encoder.phase {
	Finished => Ok(Done)
	Header => emit_generated(
		encoder,
		append_pdf_header([]),
		Object(0),
	)
	Object(index) => emit_object(encoder, index)
	DeflatePayload(state) => emit_deflate_payload(encoder, state)
	Payload(payload) => {
		next_plan = match payload.release {
			KeepPayload => encoder.plan
			ReleasePayload(payload_id) => KernelStructure.Plan.release_payload_bytes(encoder.plan, payload_id)
		}
		next_encoder = encoder_with_plan_and_phase(encoder, next_plan, StreamSuffix(payload.next_object))
		if payload.bytes.is_empty() {
			next_segment(next_encoder)
		} else {
			emit_bytes(next_encoder, payload.bytes, payload.ownership)
		}
	}
	StreamSuffix(next_object) => emit_generated(
		encoder,
		append_stream_suffix([]),
		next_object_phase(encoder.plan, next_object),
	)
	XrefPrefix => emit_xref_prefix(encoder)
	XrefEntries(state) => emit_xref_entries(encoder, state)
	XrefSuffix(xref_offset) => emit_generated(
		encoder,
		append_xref_suffix([], xref_offset),
		Finished,
	)
}

emit_object : KernelEmit.Encoder, U64 -> Try(KernelEmit.Step, KernelEmit.Error)
emit_object = |encoder, index| {
	store = plan_store(encoder.plan)
	if index >= store.objects.len() {
		next_segment(encoder_with_phase(encoder, XrefPrefix))
	} else {
		object = list_at(store.objects, index)
		offsets = encoder.offsets.append(encoder.position)
		with_offset = encoder_with_offsets(encoder, offsets)
		match object.content {
			LengthOf(stream_id) => {
				stream_index = KernelObject.StreamId.index(stream_id)
				match encoder.stream_lengths.get(stream_index) {
					Err(OutOfBounds) => Err(StreamLengthUnavailable(stream_id))
					Ok(length) => {
						var $bytes = append_object_header([], object.id)
						$bytes = KernelLex.append_unsigned($bytes, length)
						$bytes = append_end_object($bytes)
						emit_generated(with_offset, $bytes, next_object_phase(encoder.plan, index + 1))
					}
				}
			}
			Stored(value_id) => match list_at(store.values, KernelObject.ValueId.index(value_id)) {
				Stream(stream_id) => emit_stream_prefix(with_offset, object.id, stream_id, index + 1)
				_ => {
					var $bytes = append_object_header([], object.id)
					$bytes = emit_value($bytes, store, value_id)?
					$bytes = append_end_object($bytes)
					emit_generated(with_offset, $bytes, next_object_phase(encoder.plan, index + 1))
				}
			}
		}
	}
}

emit_stream_prefix : KernelEmit.Encoder, KernelObject.ObjectId, KernelObject.StreamId, U64 -> Try(KernelEmit.Step, KernelEmit.Error)
emit_stream_prefix = |encoder, object_id, stream_id, next_object| {
	store = plan_store(encoder.plan)
	stream = list_at(store.streams, KernelObject.StreamId.index(stream_id))
	payload = list_at(store.payloads, KernelObject.PayloadId.index(stream.source))

	match stream.filter {
		Dct => emit_stored_stream_prefix(encoder, object_id, stream, payload, next_object)
		Deflate => emit_deflate_stream_prefix(encoder, object_id, stream, payload, next_object)
		Unfiltered => emit_stored_stream_prefix(encoder, object_id, stream, payload, next_object)
	}
}

emit_stored_stream_prefix : KernelEmit.Encoder, KernelObject.ObjectId, KernelObject.Stream, KernelObject.Payload, U64 -> Try(KernelEmit.Step, KernelEmit.Error)
emit_stored_stream_prefix = |encoder, object_id, stream, payload, next_object| {
	{ bytes: emitted_payload, ownership } = match payload.kind {
		Generated => { bytes: payload.bytes, ownership: Generated }
		UnchangedResource => if encoder.retention == ShareResourceChunks {
			{ bytes: payload.bytes, ownership: SharedResource }
		} else {
			{ bytes: copy_bytes(payload.bytes), ownership: OwnedResource }
		}
	}

	if KernelObject.StreamId.index(stream.id) != encoder.stream_lengths.len() {
		Err(IndexInvariant)
	} else {
		copied_resource_bytes = if ownership == OwnedResource {
			checked_add(encoder.copied_resource_bytes, payload.bytes.len())?
		} else {
			encoder.copied_resource_bytes
		}
		stream_lengths = encoder.stream_lengths.append(emitted_payload.len())
		release = payload_release(encoder.plan, stream)
		var $prefix = append_object_header([], object_id)
		$prefix = append_stream_dictionary($prefix, plan_store(encoder.plan), stream)?
		$prefix = append_stream_keyword($prefix)
		with_length = encoder_with_stream_lengths(encoder_with_copied_resource_bytes(encoder, copied_resource_bytes), stream_lengths)
		next = encoder_with_phase(with_length, Payload({ bytes: emitted_payload, next_object, ownership, release }))
		emit_bytes(next, $prefix, Generated)
	}
}

emit_deflate_stream_prefix : KernelEmit.Encoder, KernelObject.ObjectId, KernelObject.Stream, KernelObject.Payload, U64 -> Try(KernelEmit.Step, KernelEmit.Error)
emit_deflate_stream_prefix = |encoder, object_id, stream, payload, next_object| {
	if KernelObject.StreamId.index(stream.id) != encoder.stream_lengths.len() {
		Err(IndexInvariant)
	} else if payload.kind != Generated {
		Err(DeflateRequiresGeneratedPayload(stream.id))
	} else {
		store = plan_store(encoder.plan)
		var $prefix = append_object_header([], object_id)
		$prefix = append_stream_dictionary($prefix, store, stream)?
		$prefix = append_stream_keyword($prefix)
		if payload.bytes.is_empty() {
			stream_lengths = encoder.stream_lengths.append(8)
			with_work = encoder_with_stream_lengths(encoder, stream_lengths)
			next = encoder_with_phase(with_work, Payload({ bytes: [120, 156, 3, 0, 0, 0, 0, 1], next_object, ownership: Generated, release: KeepPayload }))
			emit_bytes(next, $prefix, Generated)
		} else {
			plan = prepare_deflate(payload.bytes) ? Deflate
			compressor = KernelDeflate.Encoder.start(plan)
			release = payload_release(encoder.plan, stream)
			next_plan = match release {
				KeepPayload => encoder.plan
				ReleasePayload(payload_id) => KernelStructure.Plan.release_payload_bytes(encoder.plan, payload_id)
			}
			next = encoder_with_plan_and_phase(encoder, next_plan, DeflatePayload({ emitted_length: 0, encoder: compressor, next_object }))
			emit_bytes(next, $prefix, Generated)
		}
	}
}

emit_deflate_payload : KernelEmit.Encoder, DeflatePhase -> Try(KernelEmit.Step, KernelEmit.Error)
emit_deflate_payload = |encoder, state| match KernelDeflate.Encoder.next(state.encoder) {
	Err(error) => Err(Deflate(error))
	Ok(Done(work)) => {
		stream_lengths = encoder.stream_lengths.append(state.emitted_length)
		deflate_work = KernelDeflate.Work.add(encoder.deflate_work, work) ? Deflate
		next = encoder_with_deflate_work(
			encoder_with_stream_lengths(encoder, stream_lengths),
			deflate_work,
		)
		next_segment(encoder_with_phase(next, StreamSuffix(state.next_object)))
	}
	Ok(Emit(bytes, next_compressor)) => {
		emitted_length = checked_add(state.emitted_length, bytes.len())?
		next = encoder_with_phase(encoder, DeflatePayload({ emitted_length, encoder: next_compressor, next_object: state.next_object }))
		emit_bytes(next, bytes, Generated)
	}
}

payload_release : KernelStructure.Plan, KernelObject.Stream -> [KeepPayload, ReleasePayload(KernelObject.PayloadId)]
payload_release = |plan, stream| match KernelSeal.Plan.payload_last_use(KernelStructure.Plan.sealed(plan), stream.source) {
	LastStream(last) => if KernelObject.StreamId.is_eq(last, stream.id) ReleasePayload(stream.source) else KeepPayload
	Unused => KeepPayload
}

emit_xref_prefix : KernelEmit.Encoder -> Try(KernelEmit.Step, KernelEmit.Error)
emit_xref_prefix = |encoder| {
	xref_object = KernelStructure.Plan.xref_object(encoder.plan)
	xref_offset = encoder.position
	offsets = encoder.offsets.append(xref_offset)
	size = checked_add(KernelObject.ObjectId.number(xref_object), 1)?
	stream_length = checked_times_small(size, 11)?
	root = KernelStructure.Plan.root(encoder.plan)

	var $prefix = append_object_header([], xref_object)
	$prefix = append_xref_dictionary($prefix, size, stream_length, root, encoder.file_id)
	$prefix = append_stream_keyword($prefix)
	next = encoder_with_phase(encoder_with_offsets(encoder, offsets), XrefEntries({ entry: 0, size, xref_offset }))
	emit_bytes(next, $prefix, Generated)
}

emit_xref_entries : KernelEmit.Encoder, XrefEntriesPhase -> Try(KernelEmit.Step, KernelEmit.Error)
emit_xref_entries = |encoder, state| {
	if state.entry >= state.size {
		next_segment(encoder_with_phase(encoder, XrefSuffix(state.xref_offset)))
	} else {
		end = U64.min(state.size, state.entry + xref_entries_per_chunk)
		var $entry = state.entry
		var $bytes = List.with_capacity((end - state.entry) * 11)
		while $entry < end {
			if $entry == 0 {
				$bytes = append_xref_entry($bytes, 0, 0, 65535)
			} else {
				offset = list_at(encoder.offsets, $entry - 1)
				$bytes = append_xref_entry($bytes, 1, offset, 0)
			}
			$entry = $entry + 1
		}
		next = encoder_with_phase(encoder, XrefEntries({ ..state, entry: end }))
		emit_bytes(next, $bytes, Generated)
	}
}

xref_entries_per_chunk : U64
xref_entries_per_chunk = 256

emit_generated : KernelEmit.Encoder, List(U8), Phase -> Try(KernelEmit.Step, KernelEmit.Error)
emit_generated = |encoder, bytes, phase| {
	next = encoder_with_phase(encoder, phase)
	emit_bytes(next, bytes, Generated)
}

emit_bytes : KernelEmit.Encoder, List(U8), SegmentOwnership -> Try(KernelEmit.Step, KernelEmit.Error)
emit_bytes = |next, bytes, ownership| {
	position = checked_add(next.position, bytes.len())?
	if position > next.output_bound {
		Err(OutputBoundExceeded({ bound: next.output_bound, position }))
	} else {
		Ok(Emit({ bytes, ownership }, encoder_with_position(next, position)))
	}
}

encoder_with_phase : KernelEmit.Encoder, Phase -> KernelEmit.Encoder
encoder_with_phase = |encoder, phase| KernelEmit.Encoder.{
	copied_resource_bytes: encoder.copied_resource_bytes,
	deflate_work: encoder.deflate_work,
	file_id: encoder.file_id,
	offsets: encoder.offsets,
	output_bound: encoder.output_bound,
	phase,
	plan: encoder.plan,
	position: encoder.position,
	retention: encoder.retention,
	stream_lengths: encoder.stream_lengths,
}

encoder_with_plan_and_phase : KernelEmit.Encoder, KernelStructure.Plan, Phase -> KernelEmit.Encoder
encoder_with_plan_and_phase = |encoder, plan, phase| KernelEmit.Encoder.{
	copied_resource_bytes: encoder.copied_resource_bytes,
	deflate_work: encoder.deflate_work,
	file_id: encoder.file_id,
	offsets: encoder.offsets,
	output_bound: encoder.output_bound,
	phase,
	plan,
	position: encoder.position,
	retention: encoder.retention,
	stream_lengths: encoder.stream_lengths,
}

encoder_with_copied_resource_bytes : KernelEmit.Encoder, U64 -> KernelEmit.Encoder
encoder_with_copied_resource_bytes = |encoder, copied_resource_bytes| KernelEmit.Encoder.{
	copied_resource_bytes,
	deflate_work: encoder.deflate_work,
	file_id: encoder.file_id,
	offsets: encoder.offsets,
	output_bound: encoder.output_bound,
	phase: encoder.phase,
	plan: encoder.plan,
	position: encoder.position,
	retention: encoder.retention,
	stream_lengths: encoder.stream_lengths,
}

encoder_with_offsets : KernelEmit.Encoder, List(U64) -> KernelEmit.Encoder
encoder_with_offsets = |encoder, offsets| KernelEmit.Encoder.{
	copied_resource_bytes: encoder.copied_resource_bytes,
	deflate_work: encoder.deflate_work,
	file_id: encoder.file_id,
	offsets,
	output_bound: encoder.output_bound,
	phase: encoder.phase,
	plan: encoder.plan,
	position: encoder.position,
	retention: encoder.retention,
	stream_lengths: encoder.stream_lengths,
}

encoder_with_position : KernelEmit.Encoder, U64 -> KernelEmit.Encoder
encoder_with_position = |encoder, position| KernelEmit.Encoder.{
	copied_resource_bytes: encoder.copied_resource_bytes,
	deflate_work: encoder.deflate_work,
	file_id: encoder.file_id,
	offsets: encoder.offsets,
	output_bound: encoder.output_bound,
	phase: encoder.phase,
	plan: encoder.plan,
	position,
	retention: encoder.retention,
	stream_lengths: encoder.stream_lengths,
}

encoder_with_stream_lengths : KernelEmit.Encoder, List(U64) -> KernelEmit.Encoder
encoder_with_stream_lengths = |encoder, stream_lengths| KernelEmit.Encoder.{
	copied_resource_bytes: encoder.copied_resource_bytes,
	deflate_work: encoder.deflate_work,
	file_id: encoder.file_id,
	offsets: encoder.offsets,
	output_bound: encoder.output_bound,
	phase: encoder.phase,
	plan: encoder.plan,
	position: encoder.position,
	retention: encoder.retention,
	stream_lengths,
}

encoder_with_deflate_work : KernelEmit.Encoder, KernelDeflate.Work -> KernelEmit.Encoder
encoder_with_deflate_work = |encoder, deflate_work| KernelEmit.Encoder.{
	copied_resource_bytes: encoder.copied_resource_bytes,
	deflate_work,
	file_id: encoder.file_id,
	offsets: encoder.offsets,
	output_bound: encoder.output_bound,
	phase: encoder.phase,
	plan: encoder.plan,
	position: encoder.position,
	retention: encoder.retention,
	stream_lengths: encoder.stream_lengths,
}

next_object_phase : KernelStructure.Plan, U64 -> Phase
next_object_phase = |plan, index| {
	store = plan_store(plan)
	if index < store.objects.len() Object(index) else XrefPrefix
}

emit_value : List(U8), KernelObject.Store, KernelObject.ValueId -> Try(List(U8), KernelEmit.Error)
emit_value = |output, store, value_id| match list_at(store.values, KernelObject.ValueId.index(value_id)) {
	Array(span) => emit_array(output, store, span)
	Boolean(value) => Ok(KernelLex.append_boolean(output, value))
	ByteString(string) => Ok(KernelLex.append_byte_string(output, list_at(store.byte_strings, KernelObject.ByteStringId.index(string))))
	Dictionary(span) => emit_dictionary(output, store, span)
	Integer(value) => Ok(KernelLex.append_integer(output, value))
	Name(name) => Ok(KernelLex.append_name(output, list_at(store.names, KernelObject.NameId.index(name))))
	Null => Ok(KernelLex.append_null(output))
	Real(value) => Ok(KernelLex.append_real(output, value))
	Reference(object) => Ok(append_reference(output, object))
	Stream(_) => Err(NestedStreamValue)
	TextString(string) => Ok(KernelLex.append_text(output, list_at(store.text_strings, KernelObject.TextStringId.index(string))))
}

emit_array : List(U8), KernelObject.Store, KernelObject.Span -> Try(List(U8), KernelEmit.Error)
emit_array = |output, store, span| {
	var $out = output.append(91)
	var $index = 0
	while $index < span.length {
		if $index > 0 {
			$out = $out.append(32)
		}
		value = list_at(store.array_items, span.start + $index)
		$out = emit_value($out, store, value)?
		$index = $index + 1
	}
	Ok($out.append(93))
}

emit_dictionary : List(U8), KernelObject.Store, KernelObject.Span -> Try(List(U8), KernelEmit.Error)
emit_dictionary = |output, store, span| {
	var $out = append_dictionary_open(output)
	var $index = 0
	while $index < span.length {
		entry = list_at(store.dictionary_entries, span.start + $index)
		$out = $out.append(32)
		$out = KernelLex.append_name($out, list_at(store.names, KernelObject.NameId.index(entry.key)))
		$out = $out.append(32)
		$out = emit_value($out, store, entry.value)?
		$index = $index + 1
	}
	Ok(append_dictionary_close($out))
}

append_pdf_header : List(U8) -> List(U8)
append_pdf_header = |output| {
	var $out = output
	$out = $out.append(37)
	$out = $out.append(80)
	$out = $out.append(68)
	$out = $out.append(70)
	$out = $out.append(45)
	$out = $out.append(50)
	$out = $out.append(46)
	$out = $out.append(48)
	$out = $out.append(10)
	$out = $out.append(37)
	$out = $out.append(226)
	$out = $out.append(227)
	$out = $out.append(207)
	$out = $out.append(211)
	$out.append(10)
}

append_object_header : List(U8), KernelObject.ObjectId -> List(U8)
append_object_header = |output, object| {
	var $out = KernelLex.append_unsigned(output, KernelObject.ObjectId.number(object))
	$out = $out.append(32)
	$out = $out.append(48)
	$out = $out.append(32)
	$out = $out.append(111)
	$out = $out.append(98)
	$out = $out.append(106)
	$out.append(10)
}

append_end_object : List(U8) -> List(U8)
append_end_object = |output| {
	var $out = output.append(10)
	$out = $out.append(101)
	$out = $out.append(110)
	$out = $out.append(100)
	$out = $out.append(111)
	$out = $out.append(98)
	$out = $out.append(106)
	$out.append(10)
}

append_dictionary_open : List(U8) -> List(U8)
append_dictionary_open = |output| output.append(60).append(60)

append_dictionary_close : List(U8) -> List(U8)
append_dictionary_close = |output| output.append(32).append(62).append(62)

append_reference : List(U8), KernelObject.ObjectId -> List(U8)
append_reference = |output, object| {
	var $out = KernelLex.append_unsigned(output, KernelObject.ObjectId.number(object))
	$out = $out.append(32)
	$out = $out.append(48)
	$out = $out.append(32)
	$out.append(82)
}

append_stream_dictionary : List(U8), KernelObject.Store, KernelObject.Stream -> Try(List(U8), KernelEmit.Error)
append_stream_dictionary = |output, store, stream| {
	var $out = append_dictionary_open(output)
	var $filter_pending = stream.filter != Unfiltered
	var $length_pending = True
	var $index = 0
	while $index < stream.dictionary.length {
		entry = list_at(store.dictionary_entries, stream.dictionary.start + $index)
		name = list_at(store.names, KernelObject.NameId.index(entry.key))
		key_bytes = KernelLex.Name.bytes(name)
		if $filter_pending and compare_ascii(key_bytes, [70, 105, 108, 116, 101, 114]) == Greater {
			$out = append_filter_entry($out, stream.filter)
			$filter_pending = False
		}
		if $length_pending and compare_ascii(key_bytes, [76, 101, 110, 103, 116, 104]) == Greater {
			$out = append_length_entry($out, stream.length_object)
			$length_pending = False
		}
		$out = $out.append(32)
		$out = KernelLex.append_name($out, name)
		$out = $out.append(32)
		$out = emit_value($out, store, entry.value)?
		$index = $index + 1
	}
	if $filter_pending {
		$out = append_filter_entry($out, stream.filter)
	}
	if $length_pending {
		$out = append_length_entry($out, stream.length_object)
	}
	Ok(append_dictionary_close($out))
}

reserved_stream_key : KernelObject.Store, KernelObject.Span -> [NoReserved, Reserved(KernelObject.NameId)]
reserved_stream_key = |store, span| {
	var $index = 0
	var $result = NoReserved
	while $index < span.length and $result == NoReserved {
		entry = list_at(store.dictionary_entries, span.start + $index)
		name = list_at(store.names, KernelObject.NameId.index(entry.key))
		bytes = KernelLex.Name.bytes(name)
		if compare_ascii(bytes, [70, 105, 108, 116, 101, 114]) == Equal or compare_ascii(bytes, [76, 101, 110, 103, 116, 104]) == Equal {
			$result = Reserved(entry.key)
		}
		$index = $index + 1
	}
	$result
}

compare_ascii : List(U8), List(U8) -> [Equal, Greater, Less]
compare_ascii = |left, right| {
	shared = U64.min(left.len(), right.len())
	var $index = 0
	var $ordering = Equal
	while $index < shared and $ordering == Equal {
		left_byte = list_at(left, $index)
		right_byte = list_at(right, $index)
		if left_byte < right_byte {
			$ordering = Less
		} else if left_byte > right_byte {
			$ordering = Greater
		}
		$index = $index + 1
	}
	if $ordering != Equal {
		$ordering
	} else if left.len() < right.len() {
		Less
	} else if left.len() > right.len() {
		Greater
	} else {
		Equal
	}
}

append_filter_entry : List(U8), KernelObject.FilterPlan -> List(U8)
append_filter_entry = |output, filter| {
	var $out = output.append(32)
	$out = append_ascii_filter_name($out)
	$out = $out.append(32)
	match filter {
		Dct => append_ascii_dct_decode_name($out)
		Deflate => append_ascii_flate_decode_name($out)
		Unfiltered => $out
	}
}

append_length_entry : List(U8), KernelObject.ObjectId -> List(U8)
append_length_entry = |output, object| {
	var $out = output.append(32)
	$out = append_ascii_length_name($out)
	$out = $out.append(32)
	append_reference($out, object)
}

append_ascii_filter_name : List(U8) -> List(U8)
append_ascii_filter_name = |output| output.append(47).append(70).append(105).append(108).append(116).append(101).append(114)

append_ascii_dct_decode_name : List(U8) -> List(U8)
append_ascii_dct_decode_name = |output| output.append(47).append(68).append(67).append(84).append(68).append(101).append(99).append(111).append(100).append(101)

append_ascii_flate_decode_name : List(U8) -> List(U8)
append_ascii_flate_decode_name = |output| output.append(47).append(70).append(108).append(97).append(116).append(101).append(68).append(101).append(99).append(111).append(100).append(101)

append_ascii_length_name : List(U8) -> List(U8)
append_ascii_length_name = |output| output.append(47).append(76).append(101).append(110).append(103).append(116).append(104)

append_stream_keyword : List(U8) -> List(U8)
append_stream_keyword = |output| {
	var $out = output.append(10)
	$out = $out.append(115)
	$out = $out.append(116)
	$out = $out.append(114)
	$out = $out.append(101)
	$out = $out.append(97)
	$out = $out.append(109)
	$out.append(10)
}

append_stream_suffix : List(U8) -> List(U8)
append_stream_suffix = |output| {
	var $out = output.append(10)
	$out = $out.append(101)
	$out = $out.append(110)
	$out = $out.append(100)
	$out = $out.append(115)
	$out = $out.append(116)
	$out = $out.append(114)
	$out = $out.append(101)
	$out = $out.append(97)
	$out = $out.append(109)
	append_end_object($out)
}

append_xref_dictionary : List(U8), U64, U64, KernelObject.ObjectId, List(U8) -> List(U8)
append_xref_dictionary = |output, size, stream_length, root, file_id| {
	var $out = append_dictionary_open(output)
	$out = append_ascii_id_entry($out, file_id)
	$out = append_ascii_index_entry($out, size)
	$out = append_direct_length_entry($out, stream_length)
	$out = append_ascii_root_entry($out, root)
	$out = append_ascii_size_entry($out, size)
	$out = append_ascii_type_xref_entry($out)
	$out = append_ascii_w_entry($out)
	append_dictionary_close($out)
}

append_ascii_id_entry : List(U8), List(U8) -> List(U8)
append_ascii_id_entry = |output, file_id| {
	var $out = output.append(32).append(47).append(73).append(68).append(32).append(91)
	$out = KernelLex.append_byte_string($out, file_id)
	$out = $out.append(32)
	$out = KernelLex.append_byte_string($out, file_id)
	$out.append(93)
}

append_ascii_index_entry : List(U8), U64 -> List(U8)
append_ascii_index_entry = |output, size| {
	var $out = output.append(32).append(47).append(73).append(110).append(100).append(101).append(120).append(32).append(91).append(48).append(32)
	$out = KernelLex.append_unsigned($out, size)
	$out.append(93)
}

append_direct_length_entry : List(U8), U64 -> List(U8)
append_direct_length_entry = |output, length| {
	var $out = output.append(32)
	$out = append_ascii_length_name($out).append(32)
	KernelLex.append_unsigned($out, length)
}

append_ascii_root_entry : List(U8), KernelObject.ObjectId -> List(U8)
append_ascii_root_entry = |output, root| {
	var $out = output.append(32).append(47).append(82).append(111).append(111).append(116).append(32)
	append_reference($out, root)
}

append_ascii_size_entry : List(U8), U64 -> List(U8)
append_ascii_size_entry = |output, size| {
	var $out = output.append(32).append(47).append(83).append(105).append(122).append(101).append(32)
	KernelLex.append_unsigned($out, size)
}

append_ascii_type_xref_entry : List(U8) -> List(U8)
append_ascii_type_xref_entry = |output| output.append(32).append(47).append(84).append(121).append(112).append(101).append(32).append(47).append(88).append(82).append(101).append(102)

append_ascii_w_entry : List(U8) -> List(U8)
append_ascii_w_entry = |output| output.append(32).append(47).append(87).append(32).append(91).append(49).append(32).append(56).append(32).append(50).append(93)

append_xref_entry : List(U8), U8, U64, U16 -> List(U8)
append_xref_entry = |output, entry_type, offset, generation| {
	var $out = output.append(entry_type)
	$out = $out.append(offset.shr_wrap(56).to_u8_wrap())
	$out = $out.append(offset.shr_wrap(48).to_u8_wrap())
	$out = $out.append(offset.shr_wrap(40).to_u8_wrap())
	$out = $out.append(offset.shr_wrap(32).to_u8_wrap())
	$out = $out.append(offset.shr_wrap(24).to_u8_wrap())
	$out = $out.append(offset.shr_wrap(16).to_u8_wrap())
	$out = $out.append(offset.shr_wrap(8).to_u8_wrap())
	$out = $out.append(offset.to_u8_wrap())
	$out = $out.append(generation.shr_wrap(8).to_u8_wrap())
	$out.append(generation.to_u8_wrap())
}

append_xref_suffix : List(U8), U64 -> List(U8)
append_xref_suffix = |output, xref_offset| {
	var $out = append_stream_suffix(output)
	$out = $out.append(115).append(116).append(97).append(114).append(116).append(120).append(114).append(101).append(102).append(10)
	$out = KernelLex.append_unsigned($out, xref_offset)
	$out = $out.append(10).append(37).append(37).append(69).append(79).append(70).append(10)
	$out
}

copy_bytes : List(U8) -> List(U8)
copy_bytes = |source| append_all(List.with_capacity(source.len()), source)

append_all : List(U8), List(U8) -> List(U8)
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

plan_store : KernelStructure.Plan -> KernelObject.Store
plan_store = |plan| KernelSeal.Plan.store(KernelStructure.Plan.sealed(plan))

identifier_facts : KernelStructure.Plan -> List(U8)
identifier_facts = |plan| {
	var $facts = List.with_capacity(80)
	$facts = append_all($facts, Str.to_utf8("roc-pdf:document-id:v1"))
	$facts = $facts.append(0)
	$facts = match KernelStructure.Plan.identity(plan) {
		Blank => append_all($facts, Str.to_utf8("blank"))
		GeneratedContentDigest(digest) => {
			with_kind = append_all($facts, Str.to_utf8("generated-content"))
			append_all(with_kind.append(0), digest)
		}
		NormalizedPlanDigest(digest) => {
			with_kind = append_all($facts, Str.to_utf8("normalized-plan"))
			append_all(with_kind.append(0), digest)
		}
		UnchangedContentDigest(digest) => {
			with_kind = append_all($facts, Str.to_utf8("unchanged-content"))
			append_all(with_kind.append(0), digest)
		}
	}
	$facts = $facts.append(0)
	page_count = KernelStructure.Plan.page_count(plan)
	$facts = $facts.append(page_count.shr_wrap(56).to_u8_wrap())
	$facts = $facts.append(page_count.shr_wrap(48).to_u8_wrap())
	$facts = $facts.append(page_count.shr_wrap(40).to_u8_wrap())
	$facts = $facts.append(page_count.shr_wrap(32).to_u8_wrap())
	$facts = $facts.append(page_count.shr_wrap(24).to_u8_wrap())
	$facts = $facts.append(page_count.shr_wrap(16).to_u8_wrap())
	$facts = $facts.append(page_count.shr_wrap(8).to_u8_wrap())
	$facts = $facts.append(page_count.to_u8_wrap())
	$facts.append(
		match KernelStructure.Plan.page_geometry(plan) {
			Fixed(A4) => 0
			Fixed(Letter) => 1
			Variable => 2
		},
	)
}

list_at : List(a), U64 -> a
list_at = |list, index| match list.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "emission-plan index invariant failed"
	}
}

checked_add : U64, U64 -> Try(U64, KernelEmit.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(total) => Ok(total)
}

checked_times_small : U64, U64 -> Try(U64, KernelEmit.Error)
checked_times_small = |value, multiplier| {
	var $total = 0
	var $index = 0
	var $error = NoError
	while $index < multiplier and $error == NoError {
		match U64.plus_try($total, value) {
			Err(Overflow) => {
				$error = Overflowed
			}
			Ok(next) => {
				$total = next
			}
		}
		$index = $index + 1
	}

	match $error {
		Overflowed => Err(ArithmeticOverflow)
		NoError => Ok($total)
	}
}

contains_bytes : List(U8), List(U8) -> Bool
contains_bytes = |haystack, needle| {
	if needle.is_empty() {
		True
	} else {
		var $start = 0
		var $found = False
		while $found == False and $start + needle.len() <= haystack.len() {
			var $index = 0
			var $matches = True
			while $matches and $index < needle.len() {
				if list_at(haystack, $start + $index) != list_at(needle, $index) {
					$matches = False
				}
				$index = $index + 1
			}
			if $matches {
				$found = True
			}
			$start = $start + 1
		}
		$found
	}
}

emission_test_limits : KernelObject.Limits
emission_test_limits = {
	max_array_items: 0,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 4,
	max_direct_depth: 4,
	max_name_bytes: 32,
	max_names: 4,
	max_objects: 2,
	max_payload_bytes: 0,
	max_payloads: 1,
	max_streams: 1,
	max_text_string_bytes: 0,
	max_text_strings: 0,
	max_values: 2,
}

## Every direct lexical value crosses the flat store, sealing, and shared value emitter.
expect {
	limits : KernelObject.Limits
	limits = {
		max_array_items: 8,
		max_byte_string_bytes: 2,
		max_byte_strings: 1,
		max_dictionary_entries: 2,
		max_direct_depth: 3,
		max_name_bytes: 6,
		max_names: 3,
		max_objects: 1,
		max_payload_bytes: 0,
		max_payloads: 0,
		max_streams: 0,
		max_text_string_bytes: 5,
		max_text_strings: 1,
		max_values: 10,
	}
	a_key = KernelObject.add_name(KernelObject.init(limits), Str.to_utf8("A"))?
	b_key = KernelObject.add_name(a_key.builder, Str.to_utf8("B"))?
	escaped_name = KernelObject.add_name(b_key.builder, [78, 32, 47, 35])?
	byte_string = KernelObject.add_byte_string(escaped_name.builder, [0, 255])?
	text_string = KernelObject.add_text_string(byte_string.builder, "A😀")?
	null = KernelObject.add_null(text_string.builder)?
	boolean = KernelObject.add_boolean(null.builder, True)?
	integer = KernelObject.add_integer(boolean.builder, I64.lowest)?
	decimal = KernelLex.Decimal.from_coefficient(1200, 3)?
	real = KernelObject.add_real(integer.builder, decimal)?
	name = KernelObject.add_name_value(real.builder, escaped_name.id)?
	bytes = KernelObject.add_byte_string_value(name.builder, byte_string.id)?
	text = KernelObject.add_text_string_value(bytes.builder, text_string.id)?
	object_id = KernelObject.ObjectId.from_number(1)?
	reference = KernelObject.add_reference(text.builder, object_id)?
	array = KernelObject.add_array(reference.builder, [null.id, boolean.id, integer.id, real.id, name.id, bytes.id, text.id, reference.id])?
	dictionary = KernelObject.add_dictionary(
		array.builder,
		[{ key: a_key.id, value: array.id }, { key: b_key.id, value: text.id }],
	)?
	object = KernelObject.add_object(dictionary.builder, dictionary.id)?
	sealed = KernelSeal.seal(object.builder)?
	store = KernelSeal.Plan.store(sealed)

	var $actual = emit_value([], store, null.id)?
	$actual = $actual.append(124)
	$actual = emit_value($actual, store, boolean.id)?
	$actual = $actual.append(124)
	$actual = emit_value($actual, store, integer.id)?
	$actual = $actual.append(124)
	$actual = emit_value($actual, store, real.id)?
	$actual = $actual.append(124)
	$actual = emit_value($actual, store, name.id)?
	$actual = $actual.append(124)
	$actual = emit_value($actual, store, bytes.id)?
	$actual = $actual.append(124)
	$actual = emit_value($actual, store, text.id)?
	$actual = $actual.append(124)
	$actual = emit_value($actual, store, reference.id)?
	$actual = $actual.append(124)
	$actual = emit_value($actual, store, array.id)?
	$actual = $actual.append(124)
	$actual = emit_value($actual, store, dictionary.id)?

	$actual == Str.to_utf8("null|true|-9223372036854775808|1.2|/N#20#2F#23|<00FF>|<FEFF0041D83DDE00>|1 0 R|[null true -9223372036854775808 1.2 /N#20#2F#23 <00FF> <FEFF0041D83DDE00> 1 0 R]|<< /A [null true -9223372036854775808 1.2 /N#20#2F#23 <00FF> <FEFF0041D83DDE00> 1 0 R] /B <FEFF0041D83DDE00> >>")
}

## Planned stream keys merge canonically around generated Filter and Length keys.
expect {
	decode_parms = KernelObject.add_name(KernelObject.init(emission_test_limits), Str.to_utf8("DecodeParms"))?
	metadata = KernelObject.add_name(decode_parms.builder, Str.to_utf8("Metadata"))?
	null = KernelObject.add_null(metadata.builder)?
	payload = KernelObject.add_payload(null.builder, [], Generated)?
	stream_object = KernelObject.add_stream_object(
		payload.builder,
		[
			{ key: decode_parms.id, value: null.id },
			{ key: metadata.id, value: null.id },
		],
		Deflate,
		payload.id,
	)?
	stream = list_at(stream_object.builder.store.streams, 0)
	actual = append_stream_dictionary([], stream_object.builder.store, stream)?

	actual == Str.to_utf8("<< /DecodeParms null /Filter /FlateDecode /Length 2 0 R /Metadata null >>")
}

## Sanitized JPEG streams retain their bytes and declare the DCT filter.
expect {
	limits = { ..emission_test_limits, max_payload_bytes: 4 }
	payload = KernelObject.add_payload(KernelObject.init(limits), [0xff, 0xd8, 0xff, 0xd9], UnchangedResource)?
	stream_object = KernelObject.add_stream_object(payload.builder, [], Dct, payload.id)?
	stream = list_at(stream_object.builder.store.streams, 0)
	actual = append_stream_dictionary([], stream_object.builder.store, stream)?

	actual == Str.to_utf8("<< /Filter /DCTDecode /Length 2 0 R >>")
}

## Planned stream dictionaries cannot override generated Filter or Length entries.
expect {
	filter = KernelObject.add_name(KernelObject.init(emission_test_limits), Str.to_utf8("Filter"))?
	null = KernelObject.add_null(filter.builder)?
	payload = KernelObject.add_payload(null.builder, [], Generated)?
	stream_object = KernelObject.add_stream_object(
		payload.builder,
		[{ key: filter.id, value: null.id }],
		Unfiltered,
		payload.id,
	)?
	stream = list_at(stream_object.builder.store.streams, 0)

	reserved_stream_key(stream_object.builder.store, stream.dictionary) == Reserved(filter.id)
}

## The structural bound covers a multi-level plan before emission starts.
expect {
	plan = KernelStructure.build_blank(4096, A4)?
	encoder = KernelEmit.start(plan, OwnResourceChunks)?
	bytes = KernelEmit.to_bytes(plan)?

	KernelEmit.Encoder.output_bound(encoder) == KernelStructure.Plan.output_bound(plan) and
		bytes.len() <= KernelEmit.Encoder.output_bound(encoder)
}

## Nonempty generated streams compress statefully and release their source at the transition.
expect {
	input = Str.to_utf8("q 0 0 100 100 re f Q\nq 0 0 100 100 re f Q\n")
	plan = KernelStructure.build_deflate_stream_probe(input, input.len())?
	deflate_bound = KernelDeflate.output_bound(input.len())?
	deflate_plan = KernelDeflate.Plan.prepare(input, KernelDeflate.Limits.make({ max_input_bytes: input.len(), max_output_bytes: deflate_bound }))?
	expected = KernelDeflate.to_bytes(deflate_plan)?
	var $encoder = KernelEmit.start(plan, ShareResourceChunks)?
	var $bytes = []
	var $released = False
	var $done = False
	while $done == False {
		match KernelEmit.Encoder.next($encoder)? {
			Done => {
				$done = True
			}
			Emit(segment, next) => {
				$bytes = append_all($bytes, segment.bytes)
				match next.phase {
					DeflatePayload(_) => {
						store = plan_store(next.plan)
						$released = list_at(store.payloads, 0).bytes.is_empty()
					}
					_ => {}
				}
				$encoder = next
			}
		}
	}
	work = KernelEmit.Encoder.deflate_work($encoder)

	$released and
		contains_bytes($bytes, expected.bytes) and
			KernelDeflate.Work.blocks(work) == 1 and
				KernelDeflate.Work.input_bytes(work) == input.len() and
					KernelDeflate.Work.emitted_bytes(work) == expected.bytes.len()
}

## The counting sink preserves fixed-width offsets beyond four GiB.
expect {
	sink = KernelEmit.CountingSink.start(4294967312)
	marked = KernelEmit.CountingSink.mark_object(sink)
	written = KernelEmit.CountingSink.write(marked, 8192)?

	actual =
		\\entry: ${Str.inspect(KernelEmit.CountingSink.xref_entry(written, 0))}
		\\position: ${Str.inspect(KernelEmit.CountingSink.position(written))}

	expected =
		\\entry: [1, 0, 0, 0, 1, 0, 0, 0, 16, 0, 0]
		\\position: 4294975504

	actual == expected
}

## The counting sink reports overflow before accepting a segment length.
expect match KernelEmit.CountingSink.write(KernelEmit.CountingSink.start(18446744073709551615), 1) {
	Err(ArithmeticOverflow) => True
	_ => False
}

## Shared and owned policies emit identical bytes while classifying the unchanged range.
expect {
	plan = KernelStructure.build_unchanged_stream_probe(Str.to_utf8("% unchanged range\n"))?
	var $shared_encoder = KernelEmit.start(plan, ShareResourceChunks)?
	var $shared_bytes = []
	var $shared_ranges = 0
	var $released_after_range = False
	var $shared_done = False
	while $shared_done == False {
		match KernelEmit.Encoder.next($shared_encoder)? {
			Done => {
				$shared_done = True
			}
			Emit(segment, next) => {
				$shared_bytes = append_all($shared_bytes, segment.bytes)
				if segment.ownership == SharedResource {
					$shared_ranges = $shared_ranges + 1
					next_store = plan_store(next.plan)
					$released_after_range = list_at(next_store.payloads, 0).bytes.is_empty()
				}
				$shared_encoder = next
			}
		}
	}

	var $owned_encoder = KernelEmit.start(plan, OwnResourceChunks)?
	var $owned_bytes = []
	var $owned_ranges = 0
	var $owned_done = False
	while $owned_done == False {
		match KernelEmit.Encoder.next($owned_encoder)? {
			Done => {
				$owned_done = True
			}
			Emit(segment, next) => {
				$owned_bytes = append_all($owned_bytes, segment.bytes)
				if segment.ownership == OwnedResource {
					$owned_ranges = $owned_ranges + 1
				}
				$owned_encoder = next
			}
		}
	}

	$shared_ranges == 1 and
		$owned_ranges == 1 and
			$released_after_range and
				KernelEmit.Encoder.copied_resource_bytes($shared_encoder) == 0 and
					KernelEmit.Encoder.copied_resource_bytes($owned_encoder) == Str.to_utf8("% unchanged range\n").len() and
						$shared_bytes == $owned_bytes
}

## Unchanged bytes participate in deterministic file identity.
expect {
	left = KernelStructure.build_unchanged_stream_probe(Str.to_utf8("% left\n"))?
	right = KernelStructure.build_unchanged_stream_probe(Str.to_utf8("% right\n"))?

	identifier_facts(left) != identifier_facts(right)
}

## Buffered emission writes a PDF 2.0 header, binary marker, and EOF marker.
expect {
	plan = KernelStructure.build_blank(1, KernelStructure.PageSize.A4)?
	bytes = KernelEmit.to_bytes(plan)?

	bytes.sublist({ start: 0, len: 15 }) == [37, 80, 68, 70, 45, 50, 46, 48, 10, 37, 226, 227, 207, 211, 10] and
		bytes.sublist({ start: bytes.len() - 6, len: 6 }) == [37, 37, 69, 79, 70, 10]
}

## The chunk transition concatenates byte-identically with buffered emission.
expect {
	plan = KernelStructure.build_blank(33, KernelStructure.PageSize.Letter)?
	expected = KernelEmit.to_bytes(plan)?
	var $encoder = KernelEmit.start(plan, ShareResourceChunks)?
	var $actual = []
	var $done = False
	while $done == False {
		match KernelEmit.Encoder.next($encoder)? {
			Done => {
				$done = True
			}
			Emit(segment, next) => {
				$actual = append_all($actual, segment.bytes)
				$encoder = next
			}
		}
	}

	$actual == expected
}
