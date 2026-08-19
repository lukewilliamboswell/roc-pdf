import KernelColor
import KernelContent
import KernelEmit
import KernelIdentity
import KernelObjectPlan
import KernelOutputBound
import KernelPageObjects
import KernelPipelineFixture
import KernelResourceObjects
import KernelTaggedObjects
import KernelImage
import KernelObject
import KernelSeal
import KernelStructure
import KernelTagged

KernelTaggedStructure :: [].{
	Error : [
		Identity(KernelIdentity.Error),
		OutputBound(KernelOutputBound.Error),
		Pages(KernelPageObjects.Error),
		Resources(KernelResourceObjects.Error),
		Seal(KernelSeal.Error),
		TaggedObjects(KernelTaggedObjects.Error),
	]

	Limits :: { object_limits : KernelObject.Limits }.{
		make : { object_limits : KernelObject.Limits } -> Limits
		make = |limits| Limits.(limits)
	}

	Work : {
		identity : KernelIdentity.Work,
		output_bound : KernelOutputBound.Work,
		pages : KernelPageObjects.Work,
		resources : KernelResourceObjects.Work,
		tagged_objects : KernelTaggedObjects.Work,
	}

	Plan :: { structure : KernelStructure.Plan, work : Work }.{
		build : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelObjectPlan.Plan, Limits -> Try(Plan, Error)
		build = |tagged, colors, images, content, objects, limits| build_plan(tagged, colors, images, content, objects, limits)

		structure : Plan -> KernelStructure.Plan
		structure = |plan| plan.structure

		work : Plan -> Work
		work = |plan| plan.work
	}
}

build_plan : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelObjectPlan.Plan, KernelTaggedStructure.Limits -> Try(KernelTaggedStructure.Plan, KernelTaggedStructure.Error)
build_plan = |tagged, colors, images, content, objects, limits| {
	prefix = KernelTaggedObjects.Plan.build(tagged, objects, limits.object_limits) ? TaggedObjects
	pages = KernelPageObjects.Plan.build(prefix, tagged, content, objects) ? Pages
	resources = KernelResourceObjects.Plan.build(pages, colors, images, objects) ? Resources
	sealed = KernelSeal.seal(KernelResourceObjects.Plan.builder(resources)) ? Seal
	identity = KernelIdentity.digest(sealed) ? Identity
	bound = KernelOutputBound.calculate(sealed, KernelObjectPlan.Plan.xref(objects)) ? OutputBound
	structure = KernelStructure.Plan.from_sealed({
		identity: NormalizedPlanDigest(identity.digest),
		output_bound: KernelOutputBound.Bound.bytes(bound),
		page_count: KernelTagged.Plan.scenes(tagged).pages.len(),
		root: KernelObjectPlan.Plan.catalog(objects),
		sealed,
		tree_nodes: KernelObjectPlan.Plan.page_tree(objects).len(),
		xref_object: KernelObjectPlan.Plan.xref(objects),
	})
	Ok(
		KernelTaggedStructure.Plan.{
			structure,
			work: {
				identity: identity.work,
				output_bound: KernelOutputBound.Bound.work(bound),
				pages: KernelPageObjects.Plan.work(pages),
				resources: KernelResourceObjects.Plan.work(resources),
				tagged_objects: KernelTaggedObjects.Plan.work(prefix),
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

test_plan : {} -> Try(KernelTaggedStructure.Plan, [Fixture(KernelPipelineFixture.Error), Structure(KernelTaggedStructure.Error)])
test_plan = |_| {
	pipeline = KernelPipelineFixture.pipeline({}) ? Fixture
	plan = KernelTaggedStructure.Plan.build(pipeline.tagged, pipeline.colors, pipeline.images, pipeline.content, pipeline.objects, KernelTaggedStructure.Limits.make({ object_limits: test_object_limits })) ? Structure
	Ok(plan)
}

## The complete tagged-visual object graph emits one deterministic PDF 2.0 byte stream.
expect {
	plan = test_plan({})?
	structure = KernelTaggedStructure.Plan.structure(plan)
	first = KernelEmit.to_bytes(structure)?
	second = KernelEmit.to_bytes(structure)?
	starts_with(first, Str.to_utf8("%PDF-2.0\n")) and first == second
}

## The sealed object graph proves an emission bound before encoding begins.
expect {
	plan = test_plan({})?
	structure = KernelTaggedStructure.Plan.structure(plan)
	bytes = KernelEmit.to_bytes(structure)?
	bytes.len() <= KernelStructure.Plan.output_bound(structure)
}

## Bound construction visits each sealed object once and is linear in serialized value occurrences.
expect {
	plan = test_plan({})?
	structure = KernelTaggedStructure.Plan.structure(plan)
	bound_work = KernelTaggedStructure.Plan.work(plan).output_bound
	bound_work.object_visits == KernelStructure.Plan.object_count(structure)
}

## Bound construction traverses direct values and looks up each stream payload twice.
expect {
	plan = test_plan({})?
	structure = KernelTaggedStructure.Plan.structure(plan)
	bound_work = KernelTaggedStructure.Plan.work(plan).output_bound
	stream_count = KernelSeal.Plan.counts(KernelStructure.Plan.sealed(structure)).streams
	bound_work.payload_bound_lookups == stream_count * 2 and bound_work.value_visits > 0
}

## An xref identifier outside the sealed object sequence cannot acquire a bound.
expect {
	plan = test_plan({})?
	structure = KernelTaggedStructure.Plan.structure(plan)
	match KernelOutputBound.calculate(KernelStructure.Plan.sealed(structure), KernelStructure.Plan.root(structure)) {
		Err(XrefObjectMismatch({ actual, expected })) => KernelObject.ObjectId.is_eq(actual, KernelStructure.Plan.root(structure)) and expected == KernelStructure.Plan.object_count(structure) + 1
		_ => False
	}
}

## The file identity covers the sealed normalized plan and all payload source bytes.
expect {
	plan = test_plan({})?
	structure = KernelTaggedStructure.Plan.structure(plan)
	work = KernelTaggedStructure.Plan.work(plan).identity
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
		crash "tagged-visual structure test index escaped"
	}
}
