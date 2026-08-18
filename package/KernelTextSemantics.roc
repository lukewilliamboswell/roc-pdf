import KernelSemantics
import Semantics
import unicode.ByteRange
import unicode.Scalar

KernelTextSemantics :: [].{
	Dimension : [TextProperties, TextPropertyBytes, TextSourceBytes, TextSourceScalars, TextSources]
	Error : [
		ArithmeticOverflow,
		DuplicateTextPropertyOwnership({ property : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		OrphanTextProperty({ property : U64 }),
		Semantic(KernelSemantics.Error),
		TextPropertySpanOutOfRange({ available : U64, length : U64, owner : U64, start : U64 }),
	]

	Limits :: {
		max_text_properties : U64,
		max_text_property_bytes : U64,
		max_text_source_bytes : U64,
		max_text_source_scalars : U64,
		max_text_sources : U64,
	}.{
		make : {
			max_text_properties : U64,
			max_text_property_bytes : U64,
			max_text_source_bytes : U64,
			max_text_source_scalars : U64,
			max_text_sources : U64,
		} -> Limits
		make = |limits| Limits.(limits)
	}

	Work : {
		property_bytes : U64,
		property_visits : U64,
		source_bytes : U64,
		source_scalars : U64,
		source_visits : U64,
	}

	Plan :: { semantics : KernelSemantics.Plan, source_facts : List(KernelSemantics.TextSourceFact), work : Work }.{
		build : Semantics.Store, U64, U64, KernelSemantics.Limits, Limits -> Try(Plan, Error)
		build = |store, page_count, content_stream_count, semantic_limits, limits| build_plan(store, page_count, content_stream_count, semantic_limits, limits, False)

		## The navigation-enabled variant accepts Link roles and, after
		## layout, annotation spine occurrences; source-fact preparation is
		## identical.
		build_navigation : Semantics.Store, U64, U64, KernelSemantics.Limits, Limits -> Try(Plan, Error)
		build_navigation = |store, page_count, content_stream_count, semantic_limits, limits| build_plan(store, page_count, content_stream_count, semantic_limits, limits, True)

		## Layout attaches final fragments after source validation. Reuse the
		## exact scalar/byte facts produced by `build`; do not rescan source text.
		attach_fragments : Plan, List(Semantics.LayoutFragment), U64, U64, KernelSemantics.Limits -> Try(Plan, Error)
		attach_fragments = |plan, fragments, page_count, content_stream_count, semantic_limits| attach_fragment_plan(plan, fragments, page_count, content_stream_count, semantic_limits)

		## The post-layout navigation attach: fragments join together with the
		## patched content spine, nodes, and annotation records the navigation
		## stage derived from pagination, and the store revalidates on the
		## navigation path. Source facts are reused exactly.
		attach_fragments_navigation : Plan, { annotations : List(Semantics.Annotation), content_spine : List(Semantics.ContentSpineItem), nodes : List(Semantics.Node) }, List(Semantics.LayoutFragment), U64, U64, KernelSemantics.Limits -> Try(Plan, Error)
		attach_fragments_navigation = |plan, patch, fragments, page_count, content_stream_count, semantic_limits| attach_fragment_navigation_plan(plan, patch, fragments, page_count, content_stream_count, semantic_limits)

		semantics : Plan -> KernelSemantics.Plan
		semantics = |plan| plan.semantics

		source_facts : Plan -> List(KernelSemantics.TextSourceFact)
		source_facts = |plan| plan.source_facts

		work : Plan -> Work
		work = |plan| plan.work
	}
}

Prepared := {
	property_bytes : U64,
	property_visits : U64,
	source_bytes : U64,
	source_facts : List(KernelSemantics.TextSourceFact),
	source_scalars : U64,
	source_visits : U64,
}

build_plan : Semantics.Store, U64, U64, KernelSemantics.Limits, KernelTextSemantics.Limits, Bool -> Try(KernelTextSemantics.Plan, KernelTextSemantics.Error)
build_plan = |store, page_count, content_stream_count, semantic_limits, limits, navigation| {
	prepared = prepare(store, limits)?
	semantics = (
		if navigation {
			KernelSemantics.Plan.build_text_navigation(store, prepared.source_facts, page_count, content_stream_count, semantic_limits)
		} else {
			KernelSemantics.Plan.build_text_validated(store, prepared.source_facts, page_count, content_stream_count, semantic_limits)
		}
	) ? Semantic
	Ok(
		KernelTextSemantics.Plan.{
			semantics,
			source_facts: prepared.source_facts,
			work: {
				property_bytes: prepared.property_bytes,
				property_visits: prepared.property_visits,
				source_bytes: prepared.source_bytes,
				source_scalars: prepared.source_scalars,
				source_visits: prepared.source_visits,
			},
		},
	)
}

attach_fragment_plan : KernelTextSemantics.Plan, List(Semantics.LayoutFragment), U64, U64, KernelSemantics.Limits -> Try(KernelTextSemantics.Plan, KernelTextSemantics.Error)
attach_fragment_plan = |plan, fragments, page_count, content_stream_count, semantic_limits| {
	preliminary = KernelSemantics.Plan.store(plan.semantics)
	store = { ..preliminary, fragments, occurrence_fragments: [] }
	semantics = KernelSemantics.Plan.build_text_validated(store, plan.source_facts, page_count, content_stream_count, semantic_limits) ? Semantic
	Ok(KernelTextSemantics.Plan.{ semantics, source_facts: plan.source_facts, work: plan.work })
}

attach_fragment_navigation_plan : KernelTextSemantics.Plan, { annotations : List(Semantics.Annotation), content_spine : List(Semantics.ContentSpineItem), nodes : List(Semantics.Node) }, List(Semantics.LayoutFragment), U64, U64, KernelSemantics.Limits -> Try(KernelTextSemantics.Plan, KernelTextSemantics.Error)
attach_fragment_navigation_plan = |plan, patch, fragments, page_count, content_stream_count, semantic_limits| {
	preliminary = KernelSemantics.Plan.store(plan.semantics)
	store = { ..preliminary, annotations: patch.annotations, content_spine: patch.content_spine, fragments, nodes: patch.nodes, occurrence_fragments: [] }
	semantics = KernelSemantics.Plan.build_text_navigation(store, plan.source_facts, page_count, content_stream_count, semantic_limits) ? Semantic
	Ok(KernelTextSemantics.Plan.{ semantics, source_facts: plan.source_facts, work: plan.work })
}

prepare : Semantics.Store, KernelTextSemantics.Limits -> Try(Prepared, KernelTextSemantics.Error)
prepare = |store, limits| {
	check_limit(store.text_sources.len(), limits.max_text_sources, TextSources)?
	check_limit(store.text_properties.len(), limits.max_text_properties, TextProperties)?
	var $facts = List.with_capacity(store.text_sources.len())
	var $source_bytes = 0
	var $source_scalars = 0
	var $source_index = 0
	while $source_index < store.text_sources.len() {
		source = list_at(store.text_sources, $source_index).unicode
		byte_count = source.count_utf8_bytes()
		$source_bytes = checked_add($source_bytes, byte_count)?
		check_limit($source_bytes, limits.max_text_source_bytes, TextSourceBytes)?
		var $offsets = [0]
		var $scalars = 0
		for located in Scalar.iter(source) {
			$scalars = checked_add($scalars, 1)?
			attempted = checked_add($source_scalars, $scalars)?
			check_limit(attempted, limits.max_text_source_scalars, TextSourceScalars)?
			$offsets = $offsets.append(ByteRange.end(located.byte_range))
		}
		$source_scalars = checked_add($source_scalars, $scalars)?
		$facts = $facts.append({ byte_count, scalar_byte_offsets: $offsets, scalar_count: $scalars })
		$source_index = $source_index + 1
	}
	properties = validate_property_ownership(store, limits.max_text_property_bytes)?
	Ok({
		property_bytes: properties.bytes,
		property_visits: properties.visits,
		source_bytes: $source_bytes,
		source_facts: $facts,
		source_scalars: $source_scalars,
		source_visits: store.text_sources.len(),
	})
}

validate_property_ownership : Semantics.Store, U64 -> Try({ bytes : U64, visits : U64 }, KernelTextSemantics.Error)
validate_property_ownership = |store, byte_limit| {
	var $owners = List.repeat(0, store.text_properties.len())
	var $bytes = 0
	var $visits = 0
	var $node_index = 0
	while $node_index < store.nodes.len() {
		range = list_at(store.nodes, $node_index).text_properties
		if range.length() == 0 {
			if range.start() > store.text_properties.len() {
				return Err(TextPropertySpanOutOfRange({ available: store.text_properties.len(), length: 0, owner: $node_index, start: range.start() }))
			}
		} else {
			marked = mark_property_range(range, $node_index, $owners, store.text_properties, $bytes, byte_limit)?
			$owners = marked.owners
			$bytes = marked.bytes
			$visits = checked_add($visits, marked.visits)?
		}
		$node_index = $node_index + 1
	}
	var $occurrence_index = 0
	while $occurrence_index < store.occurrences.len() {
		range = list_at(store.occurrences, $occurrence_index).text_properties
		if store.nodes.len() > U64.highest - $occurrence_index {
			return Err(ArithmeticOverflow)
		}
		owner = store.nodes.len() + $occurrence_index
		if range.length() == 0 {
			if range.start() > store.text_properties.len() {
				return Err(TextPropertySpanOutOfRange({ available: store.text_properties.len(), length: 0, owner, start: range.start() }))
			}
		} else {
			marked = mark_property_range(range, owner, $owners, store.text_properties, $bytes, byte_limit)?
			$owners = marked.owners
			$bytes = marked.bytes
			$visits = checked_add($visits, marked.visits)?
		}
		$occurrence_index = $occurrence_index + 1
	}
	var $index = 0
	while $index < $owners.len() {
		if list_at($owners, $index) == 0 {
			return Err(OrphanTextProperty({ property: $index }))
		}
		$index = $index + 1
	}
	Ok({ bytes: $bytes, visits: $visits })
}

mark_property_range : Semantics.Range, U64, List(U8), List(Semantics.TextProperty), U64, U64 -> Try({ bytes : U64, owners : List(U8), visits : U64 }, KernelTextSemantics.Error)
mark_property_range = |range, owner, owners, properties, used_bytes, byte_limit| {
	start = range.start()
	length = range.length()
	if start > properties.len() or length > properties.len() - start {
		return Err(TextPropertySpanOutOfRange({ available: properties.len(), length, owner, start }))
	}
	var $owners = owners
	var $bytes = used_bytes
	var $index = start
	end = start + length
	while $index < end {
		if list_at($owners, $index) != 0 {
			return Err(DuplicateTextPropertyOwnership({ property: $index }))
		}
		$owners = list_set($owners, $index, 1)
		$bytes = checked_add($bytes, text_property_bytes(list_at(properties, $index)))?
		check_limit($bytes, byte_limit, TextPropertyBytes)?
		$index = $index + 1
	}
	Ok({ bytes: $bytes, owners: $owners, visits: length })
}

text_property_bytes : Semantics.TextProperty -> U64
text_property_bytes = |property| match property {
	ActualText(value) => value.count_utf8_bytes()
	AlternativeText(value) => value.count_utf8_bytes()
	ExpandedText(value) => value.count_utf8_bytes()
	Phoneme(value) => value.count_utf8_bytes()
	PhoneticAlphabet(value) => value.count_utf8_bytes()
	ReplacementText(value) => value.count_utf8_bytes()
	SourceToPresentation({ kind: _, presentation, source: _ }) => presentation.count_utf8_bytes()
}

check_limit : U64, U64, KernelTextSemantics.Dimension -> Try({}, KernelTextSemantics.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelTextSemantics.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Ok(value) => Ok(value)
	Err(_) => Err(ArithmeticOverflow)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated text-semantic index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated text-semantic update escaped"
	}
}

empty_range : Semantics.Range
empty_range = Semantics.Range.from_start_and_length(0, 0)

full_range : Semantics.TextRange
full_range = { scalars: Semantics.Range.from_start_and_length(0, 2), utf8_bytes: Semantics.Range.from_start_and_length(0, 3) }

test_store : Semantics.Store
test_store = {
	annotations: [],
	assertions: [],
	attribute_roles: [],
	attributes: [],
	content_spine: [ContentOccurrence(Semantics.OccurrenceId.from_index(0))],
	contextual_artifacts: [],
	document_root: Semantics.NodeId.from_index(0),
	element_identifiers: [],
	fragments: [{ content_stream: Semantics.ContentStreamId.from_index(0), continuation_index: 0, id: Semantics.FragmentId.from_index(0), occurrence: Semantics.OccurrenceId.from_index(0), page: Semantics.PageId.from_index(0), source_range: UnicodeRange(full_range) }],
	mathml_subtrees: [],
	namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
	nodes: [{ attributes: empty_range, content: Semantics.Range.from_start_and_length(0, 1), element_identifier: NoElementIdentifier, id: Semantics.NodeId.from_index(0), language: Inherited, parent: DocumentRoot, role: { local_name: "Document", namespace: Semantics.NamespaceId.from_index(0) }, structure_element: Semantics.StructureElementId.from_index(0), text_properties: empty_range }],
	non_text_sources: [],
	occurrence_fragments: [],
	occurrences: [{ fragments: empty_range, id: Semantics.OccurrenceId.from_index(0), language: Inherited, source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange(full_range)), text_properties: Semantics.Range.from_start_and_length(0, 1) }],
	relationships: [],
	role_mappings: [],
	text_properties: [ActualText("é")],
	text_sources: [{ unicode: "éA" }],
}

semantic_limits : KernelSemantics.Limits
semantic_limits = KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 1, max_fragments: 1, max_namespaces: 1, max_nodes: 1, max_occurrences: 1, max_semantic_depth: 1 })

text_limits : KernelTextSemantics.Limits
text_limits = KernelTextSemantics.Limits.make({ max_text_properties: 1, max_text_property_bytes: 2, max_text_source_bytes: 3, max_text_source_scalars: 2, max_text_sources: 1 })

## Gate 3 text semantics retain exact scalar-to-byte boundaries and bounded work.
expect {
	plan = KernelTextSemantics.Plan.build(test_store, 1, 1, semantic_limits, text_limits)?
	fact = list_at(KernelTextSemantics.Plan.source_facts(plan), 0)
	work = KernelTextSemantics.Plan.work(plan)
	fact.byte_count == 3 and fact.scalar_count == 2 and fact.scalar_byte_offsets == [0, 2, 3] and work.source_bytes == 3 and work.source_scalars == 2 and work.property_visits == 1 and work.property_bytes == 2
}

## Gate 2 cannot silently accept a text semantic store.
expect match KernelSemantics.Plan.build(test_store, 1, 1, semantic_limits) {
	Err(UnsupportedStoreContent) => True
	_ => False
}

## Scalar and UTF-8 occurrence coordinates must name the same boundaries.
expect {
	occurrence = list_at(test_store.occurrences, 0)
	bad_range = { ..full_range, utf8_bytes: Semantics.Range.from_start_and_length(0, 2) }
	bad = { ..test_store, occurrences: [{ ..occurrence, source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange(bad_range)) }] }
	match KernelTextSemantics.Plan.build(bad, 1, 1, semantic_limits, text_limits) {
		Err(Semantic(UnsupportedTextOccurrence({ occurrence: 0 }))) => True
		_ => False
	}
}

## Fragment text coordinates are validated against their occurrence and source.
expect {
	fragment = list_at(test_store.fragments, 0)
	bad_range = { scalars: Semantics.Range.from_start_and_length(0, 1), utf8_bytes: Semantics.Range.from_start_and_length(0, 1) }
	bad = { ..test_store, fragments: [{ ..fragment, source_range: UnicodeRange(bad_range) }] }
	match KernelTextSemantics.Plan.build(bad, 1, 1, semantic_limits, text_limits) {
		Err(Semantic(FragmentRangeOutsideOccurrence({ fragment: 0 }))) => True
		_ => False
	}
}

## Text-property ownership stays unique across nodes and occurrences.
expect {
	node = list_at(test_store.nodes, 0)
	bad = { ..test_store, nodes: [{ ..node, text_properties: Semantics.Range.from_start_and_length(0, 1) }] }
	match KernelTextSemantics.Plan.build(bad, 1, 1, semantic_limits, text_limits) {
		Err(DuplicateTextPropertyOwnership({ property: 0 })) => True
		_ => False
	}
}

## Cumulative Unicode work is rejected at the exact configured limit.
expect {
	too_small = KernelTextSemantics.Limits.make({ max_text_properties: 1, max_text_property_bytes: 2, max_text_source_bytes: 3, max_text_source_scalars: 1, max_text_sources: 1 })
	match KernelTextSemantics.Plan.build(test_store, 1, 1, semantic_limits, too_small) {
		Err(LimitExceeded({ attempted: 2, dimension: TextSourceScalars, limit: 1 })) => True
		_ => False
	}
}

## Empty property ranges still validate their cursor without allocating a
## per-owner marking result.
expect {
	node = list_at(test_store.nodes, 0)
	bad = { ..test_store, nodes: [{ ..node, text_properties: Semantics.Range.from_start_and_length(2, 0) }] }
	match KernelTextSemantics.Plan.build(bad, 1, 1, semantic_limits, text_limits) {
		Err(TextPropertySpanOutOfRange({ available: 1, length: 0, owner: 0, start: 2 })) => True
		_ => False
	}
}
