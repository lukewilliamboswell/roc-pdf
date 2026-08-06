import KernelColor
import KernelContent
import KernelEmit
import KernelGate2Identity
import KernelGate2Objects
import KernelGate2OutputBound
import KernelGate2PageObjects
import KernelGate2PipelineFixture
import KernelGate2ResourceObjects
import KernelGate2TaggedObjects
import KernelImage
import KernelObject
import KernelSeal
import KernelStructure
import KernelTagged

KernelGate2Structure :: [].{
	Error : [
		Identity(KernelGate2Identity.Error),
		OutputBound(KernelGate2OutputBound.Error),
		Pages(KernelGate2PageObjects.Error),
		Resources(KernelGate2ResourceObjects.Error),
		Seal(KernelSeal.Error),
		TaggedObjects(KernelGate2TaggedObjects.Error),
	]

	Limits :: { object_limits : KernelObject.Limits }.{
		make : { object_limits : KernelObject.Limits } -> Limits
		make = |limits| Limits.(limits)
	}

	Work : {
		identity : KernelGate2Identity.Work,
		output_bound : KernelGate2OutputBound.Work,
		pages : KernelGate2PageObjects.Work,
		resources : KernelGate2ResourceObjects.Work,
		tagged_objects : KernelGate2TaggedObjects.Work,
	}

	Plan :: { structure : KernelStructure.Plan, work : Work }.{
		build : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelGate2Objects.Plan, Limits -> Try(Plan, Error)
		build = |tagged, colors, images, content, objects, limits| build_plan(tagged, colors, images, content, objects, limits)

		structure : Plan -> KernelStructure.Plan
		structure = |plan| plan.structure

		work : Plan -> Work
		work = |plan| plan.work
	}
}

build_plan : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelGate2Objects.Plan, KernelGate2Structure.Limits -> Try(KernelGate2Structure.Plan, KernelGate2Structure.Error)
build_plan = |tagged, colors, images, content, objects, limits| {
	prefix = KernelGate2TaggedObjects.Plan.build(tagged, objects, limits.object_limits) ? TaggedObjects
	pages = KernelGate2PageObjects.Plan.build(prefix, tagged, content, objects) ? Pages
	resources = KernelGate2ResourceObjects.Plan.build(pages, colors, images, objects) ? Resources
	sealed = KernelSeal.seal(KernelGate2ResourceObjects.Plan.builder(resources)) ? Seal
	identity = KernelGate2Identity.digest(sealed) ? Identity
	bound = KernelGate2OutputBound.calculate(sealed, KernelGate2Objects.Plan.xref(objects)) ? OutputBound
	structure = KernelStructure.Plan.from_sealed({
		identity: NormalizedPlanDigest(identity.digest),
		output_bound: KernelGate2OutputBound.Bound.bytes(bound),
		page_count: KernelTagged.Plan.scenes(tagged).pages.len(),
		root: KernelGate2Objects.Plan.catalog(objects),
		sealed,
		tree_nodes: KernelGate2Objects.Plan.page_tree(objects).len(),
		xref_object: KernelGate2Objects.Plan.xref(objects),
	})
	Ok(
		KernelGate2Structure.Plan.{
			structure,
			work: {
				identity: identity.work,
				output_bound: KernelGate2OutputBound.Bound.work(bound),
				pages: KernelGate2PageObjects.Plan.work(pages),
				resources: KernelGate2ResourceObjects.Plan.work(resources),
				tagged_objects: KernelGate2TaggedObjects.Plan.work(prefix),
			},
		},
	)
}

test_object_limits : KernelObject.Limits
test_object_limits = {
	max_array_items: 192,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 320,
	max_direct_depth: 8,
	max_name_bytes: 3072,
	max_names: 128,
	max_objects: 16,
	max_payload_bytes: 1024,
	max_payloads: 3,
	max_streams: 3,
	max_text_string_bytes: 64,
	max_text_strings: 1,
	max_values: 640,
}

test_plan : {} -> Try(KernelGate2Structure.Plan, [Fixture(KernelGate2PipelineFixture.Error), Structure(KernelGate2Structure.Error)])
test_plan = |_| {
	pipeline = KernelGate2PipelineFixture.pipeline({}) ? Fixture
	plan = KernelGate2Structure.Plan.build(pipeline.tagged, pipeline.colors, pipeline.images, pipeline.content, pipeline.objects, KernelGate2Structure.Limits.make({ object_limits: test_object_limits })) ? Structure
	Ok(plan)
}

## The complete Gate 2 object graph emits one deterministic PDF 2.0 byte stream.
expect {
	plan = test_plan({})?
	structure = KernelGate2Structure.Plan.structure(plan)
	first = KernelEmit.to_bytes(structure)?
	second = KernelEmit.to_bytes(structure)?
	starts_with(first, Str.to_utf8("%PDF-2.0\n")) and first == second
}

## The sealed object graph proves an emission bound before encoding begins.
expect {
	plan = test_plan({})?
	structure = KernelGate2Structure.Plan.structure(plan)
	bytes = KernelEmit.to_bytes(structure)?
	bytes.len() <= KernelStructure.Plan.output_bound(structure)
}

## Bound construction visits each sealed object once and is linear in serialized value occurrences.
expect {
	plan = test_plan({})?
	structure = KernelGate2Structure.Plan.structure(plan)
	bound_work = KernelGate2Structure.Plan.work(plan).output_bound
	bound_work.object_visits == KernelStructure.Plan.object_count(structure)
}

## Bound construction traverses direct values and looks up each stream payload twice.
expect {
	plan = test_plan({})?
	structure = KernelGate2Structure.Plan.structure(plan)
	bound_work = KernelGate2Structure.Plan.work(plan).output_bound
	stream_count = KernelSeal.Plan.counts(KernelStructure.Plan.sealed(structure)).streams
	bound_work.payload_bound_lookups == stream_count * 2 and bound_work.value_visits > 0
}

## An xref identifier outside the sealed object sequence cannot acquire a bound.
expect {
	plan = test_plan({})?
	structure = KernelGate2Structure.Plan.structure(plan)
	match KernelGate2OutputBound.calculate(KernelStructure.Plan.sealed(structure), KernelStructure.Plan.root(structure)) {
		Err(XrefObjectMismatch({ actual, expected })) => KernelObject.ObjectId.is_eq(actual, KernelStructure.Plan.root(structure)) and expected == KernelStructure.Plan.object_count(structure) + 1
		_ => False
	}
}

## The file identity covers the sealed normalized plan and all payload source bytes.
expect {
	plan = test_plan({})?
	structure = KernelGate2Structure.Plan.structure(plan)
	work = KernelGate2Structure.Plan.work(plan).identity
	identity_ok = match KernelStructure.Plan.identity(structure) {
		NormalizedPlanDigest(digest) => digest.len() == 32
		_ => False
	}
	identity_ok and work.objects == KernelStructure.Plan.object_count(structure) and work.payload_bytes_hashed > 0 and work.fact_bytes > 0
}

starts_with : List(U8), List(U8) -> Bool
starts_with = |bytes, prefix| {
	if bytes.len() < prefix.len() {
		False
	} else {
		var $index = 0
		var $same = True
		while $index < prefix.len() and $same {
			if list_at(bytes, $index) != list_at(prefix, $index) {
				$same = False
			}
			$index = $index + 1
		}
		$same
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "Gate 2 structure test index escaped"
	}
}
