app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import fuzz.Model
import pdf.KernelObject
import pdf.KernelSeal

target = Fuzz.suite([])

Action : [AddScalar, AddPayload, AddReference(U64), AddStream(U64), ReuseStreamValue(U64)]

Entry : [Scalar, Reference(U64), Stream(U64), Length(U64), AliasedStream(U64)]

Ledger : { objects : List(Entry), sources : List(U64), payloads : U64 }

World : { builder : KernelObject.Builder, stream_values : List(KernelObject.ValueId), ledger : Ledger, history : List(Action) }

limits : KernelObject.Limits
limits = {
	max_array_items: 0,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 0,
	max_direct_depth: 1,
	max_name_bytes: 0,
	max_names: 0,
	max_objects: 10,
	max_payload_bytes: 2,
	max_payloads: 2,
	max_streams: 4,
	max_text_string_bytes: 0,
	max_text_strings: 0,
	max_values: 5,
}

machine : Model.Machine(World, Action)
machine = {
	init: {
		builder: KernelObject.init(limits),
		stream_values: [],
		ledger: { objects: [], sources: [], payloads: 0 },
		history: [],
	},
	actions,
	step,
	rules: [
		Model.always("the sealer agrees with the authored object and stream ledger", agrees),
		Model.sometimes("a forward reference resolves after a stream pair is appended", |world| world.history == [AddReference(3), AddPayload, AddStream(0)]),
		Model.sometimes("a stream value cannot acquire two object owners", |world| world.history == [AddPayload, AddStream(0), ReuseStreamValue(0)]),
		Model.sometimes("an interleaved payload survives until its final stream", |world| world.history == [AddPayload, AddPayload, AddStream(0), AddStream(1), AddStream(0)]),
	],
}

actions : World -> List(Action)
actions = |world| {
	if world.history.len() == 5 {
		return []
	}
	scalar_actions : List(Action)
	scalar_actions = [AddScalar, AddReference(1), AddReference(3)]
	with_payload = if (world.ledger.payloads < 2) scalar_actions.append(AddPayload) else scalar_actions
	with_first_stream = if (world.ledger.payloads > 0) with_payload.append(AddStream(0)) else with_payload
	stream_actions = if (world.ledger.payloads > 1) with_first_stream.append(AddStream(1)) else with_first_stream
	if (world.ledger.sources.is_empty()) stream_actions else stream_actions.append(ReuseStreamValue(0))
}

step : World, Action -> World
step = |world, action| {
	{ builder, stream_values, history, ledger } = world
	next = match action {
		AddScalar => {
			value = require(KernelObject.add_null(builder))
			{ builder: require(KernelObject.add_object(value.builder, value.id)).builder, stream_values }
		}
		AddPayload => {
			payload = require(KernelObject.add_payload(builder, [ledger.payloads.to_u8_wrap()], Generated))
			{ builder: payload.builder, stream_values }
		}
		AddReference(target_number) => {
			id = require(KernelObject.ObjectId.from_number(target_number))
			value = require(KernelObject.add_reference(builder, id))
			{ builder: require(KernelObject.add_object(value.builder, value.id)).builder, stream_values }
		}
		AddStream(source) => {
			stream = require(KernelObject.add_stream_object(builder, [], Unfiltered, KernelObject.PayloadId.from_index(source)))
			{ builder: stream.builder, stream_values: stream_values.append(stream.value) }
		}
		ReuseStreamValue(stream) => {
			value = require(stream_values.get(stream))
			{ builder: require(KernelObject.add_object(builder, value)).builder, stream_values }
		}
	}
	{ builder: next.builder, stream_values: next.stream_values, ledger: author(ledger, action), history: history.append(action) }
}

require : Try(a, e) -> a
require = |result| match result {
	Ok(value) => value
	Err(_) => crash "sealing model constructed an action outside its builder limits"
}

# The ledger records one semantic entry per authored object. It has no value-ID
# indirection or payload-to-last-stream index.
author : Ledger, Action -> Ledger
author = |ledger, action| match action {
	AddScalar => { ..ledger, objects: ledger.objects.append(Scalar) }
	AddPayload => { ..ledger, payloads: ledger.payloads + 1 }
	AddReference(number) => { ..ledger, objects: ledger.objects.append(Reference(number)) }
	AddStream(source) => {
		stream = ledger.sources.len()
		{ ..ledger, objects: ledger.objects.append(Stream(stream)).append(Length(stream)), sources: ledger.sources.append(source) }
	}
	ReuseStreamValue(stream) => { ..ledger, objects: ledger.objects.append(AliasedStream(stream)) }
}

Expected : [Accept, RejectStream({ object : U64, stream : U64 }), RejectReference({ source : U64, target : U64 })]

expectation : Ledger -> Expected
expectation = |ledger| {
	var $position = 0
	while $position < ledger.objects.len() {
		match require(ledger.objects.get($position)) {
			AliasedStream(stream) => return RejectStream({ object: $position + 1, stream })
			_ => {}
		}
		$position = $position + 1
	}
	var $value = 0
	for entry in ledger.objects {
		match entry {
			Reference(target_number) if target_number > ledger.objects.len() =>
				return RejectReference({ source: $value, target: target_number })
			Length(_) => {}
			_ => {
				$value = $value + 1
			}
		}
	}
	Accept
}

agrees : World -> Bool
agrees = |world| match (expectation(world.ledger), KernelSeal.seal(world.builder)) {
	(Accept, Ok(plan)) => matches_plan(world.ledger, plan)
	(RejectStream(expected), Err(StreamObjectMismatch(actual))) =>
		actual.object.number() == expected.object and actual.stream.index() == expected.stream
	(RejectReference(expected), Err(ReferenceOutOfRange(actual))) =>
		actual.available == world.ledger.objects.len() and actual.source.index() == expected.source and actual.target.number() == expected.target
	_ => False
}

matches_plan : Ledger, KernelSeal.Plan -> Bool
matches_plan = |ledger, plan| {
	store = KernelSeal.Plan.store(plan)
	observed = store.objects.map(
		|object| match object.content {
			LengthOf(stream) => Length(stream.index())
			Stored(value) => match require(store.values.get(value.index())) {
				Null => Scalar
				Reference(target_number) => Reference(target_number.number())
				Stream(stream) => Stream(stream.index())
				_ => crash "sealing model observed an unexpected stored object"
			}
		},
	)
	if observed != ledger.objects or store.payloads.len() != ledger.payloads {
		return False
	}
	owners = store.streams.map(|stream| { object: stream.object.number(), length: stream.length_object.number(), source: stream.source.index(), stream: stream.id.index() })
	if owners != authored_owners(ledger) {
		return False
	}
	var $object = 0
	while $object < store.objects.len() {
		if require(store.objects.get($object)).id.number() != $object + 1 {
			return False
		}
		$object = $object + 1
	}
	var $payload = 0
	while $payload < ledger.payloads {
		payload_id = KernelObject.PayloadId.from_index($payload)
		if KernelSeal.Plan.payload_last_use(plan, payload_id) != last_reader(ledger.sources, $payload) {
			return False
		}
		$payload = $payload + 1
	}
	True
}

authored_owners : Ledger -> List({ object : U64, length : U64, source : U64, stream : U64 })
authored_owners = |ledger| {
	var $owners = []
	var $position = 1
	for entry in ledger.objects {
		match entry {
			Stream(stream) => {
				$owners = $owners.append({ object: $position, length: $position + 1, source: require(ledger.sources.get(stream)), stream })
			}
			_ => {}
		}
		$position = $position + 1
	}
	$owners
}

last_reader : List(U64), U64 -> KernelObject.PayloadUse
last_reader = |sources, payload| {
	var $index = sources.len()
	while $index > 0 {
		$index = $index - 1
		if require(sources.get($index)) == payload {
			return LastStream(KernelObject.StreamId.from_index($index))
		}
	}
	Unused
}

expect {
	# Ordered commands identify the whole deterministic state. Check every
	# admitted transition, including alternative orders with equal results.
	report = Model.explore(machine, { depth: 6, key: |world| world.history, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 2379 and report.steps == 2378 and report.depth == 5 and report.reached.len() == 3
}
