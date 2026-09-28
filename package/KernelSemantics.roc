import Semantics

KernelSemantics :: [].{
	Dimension : [Attributes, ContentSpine, Fragments, Namespaces, Nodes, Occurrences, SemanticDepth]
	IndexKind : [AnnotationIndex, AttributeIndex, ContentIndex, ContextualArtifactIndex, ElementIdentifierIndex, FragmentIndex, NamespaceIndex, NodeIndex, NonTextSourceIndex, OccurrenceIndex, RelationshipIndex, StructureElementIndex, TextPropertyIndex, TextSourceIndex]

	## Structural rejections carry dense node, content, attribute, element
	## identifier, or relationship indexes; they never carry PDF object identity.
	## Containment, content-item, cardinality, and Caption-position rejections
	## come from the ISO/TS 32005 table below, not from role-specific branches.
	Error : [
		AnnotationLogicalOrderInvalid({ actual : U64, annotation : U64, expected : U64 }),
		AnnotationOwnerMismatch({ annotation : U64, occurrence_owner : U64, owner : U64 }),
		ArithmeticOverflow,
		CaptionPosition({ caption : U64, parent : U64 }),
		DuplicateChildRole({ child : U64, parent : U64 }),
		DuplicateElementIdentifier({ first : U64, second : U64 }),
		DuplicateOwnership({ index : U64, kind : IndexKind }),
		ElementIdentifierOrder({ element : U64 }),
		EmptyElementIdentifier({ element : U64 }),
		FragmentRangeOutsideOccurrence({ fragment : U64 }),
		IllegalContainment({ child : U64, parent : U64 }),
		IllegalContentItem({ content : U64, node : U64 }),
		IndexOutOfRange({ available : U64, index : U64, kind : IndexKind }),
		InvalidAttribute({ attribute : U64, node : U64 }),
		InvalidContextualArtifactAttribute({ artifact : U64, attribute : U64 }),
		InvalidDocumentRoot({ node : U64 }),
		InvalidLanguage({ node : U64 }),
		InvalidNodeTextProperty({ node : U64, property : U64 }),
		InvalidParent({ actual : U64, expected : U64, node : U64 }),
		InvalidPdf20Namespace,
		InvalidRelationship({ relationship : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		NonDenseIdentity({ actual : U64, expected : U64, kind : IndexKind }),
		Orphaned({ index : U64, kind : IndexKind }),
		SpanOutOfRange({ available : U64, kind : IndexKind, length : U64, owner : U64, start : U64 }),
		UnknownAttributeTarget({ attribute : U64, node : U64 }),
		UnsupportedAnnotation({ content : U64 }),
		UnsupportedRole({ node : U64 }),
		UnsupportedStoreContent,
		UnsupportedTextOccurrence({ occurrence : U64 }),
	]

	TextSourceFact : {
		byte_count : U64,
		scalar_byte_offsets : List(U64),
		scalar_count : U64,
	}

	Limits :: {
		max_attributes : U64,
		max_content_spine : U64,
		max_fragments : U64,
		max_namespaces : U64,
		max_nodes : U64,
		max_occurrences : U64,
		max_semantic_depth : U64,
	}.{
		make : {
			max_attributes : U64,
			max_content_spine : U64,
			max_fragments : U64,
			max_namespaces : U64,
			max_nodes : U64,
			max_occurrences : U64,
			max_semantic_depth : U64,
		} -> Limits
		make = |limits| Limits.(limits)
	}

	Work : {
		annotation_visits : U64,
		attribute_visits : U64,
		containment_edges : U64,
		content_visits : U64,
		fragment_count_visits : U64,
		fragment_validation_visits : U64,
		identifier_visits : U64,
		max_semantic_depth : U64,
		namespace_visits : U64,
		node_visits : U64,
		occurrence_visits : U64,
		prefix_steps : U64,
		relationship_visits : U64,
		reverse_writes : U64,
	}

	Plan :: { content_stream_count : U64, page_count : U64, store : Semantics.Store, work : Work }.{
		build : Semantics.Store, U64, U64, Limits -> Try(Plan, Error)
		build = |store, page_count, content_stream_count, limits| build_plan(store, page_count, content_stream_count, limits, False)

		build_text_validated : Semantics.Store, List(TextSourceFact), U64, U64, Limits -> Try(Plan, Error)
		build_text_validated = |store, text_source_facts, page_count, content_stream_count, limits| build_text_plan(store, text_source_facts, page_count, content_stream_count, limits, False)

		## The navigation-enabled variants additionally accept the annotation
		## store and `AnnotationOccurrence` spine items: every annotation must
		## occur exactly once in its owner's content spine, its owner must be a
		## valid node, and its logical order must equal its rank among the
		## spine's annotation occurrences. A path that cannot lower annotation
		## objects keeps the plain variants and their rejections.
		build_navigation : Semantics.Store, U64, U64, Limits -> Try(Plan, Error)
		build_navigation = |store, page_count, content_stream_count, limits| build_plan(store, page_count, content_stream_count, limits, True)

		build_text_navigation : Semantics.Store, List(TextSourceFact), U64, U64, Limits -> Try(Plan, Error)
		build_text_navigation = |store, text_source_facts, page_count, content_stream_count, limits| build_text_plan(store, text_source_facts, page_count, content_stream_count, limits, True)

		content_stream_count : Plan -> U64
		content_stream_count = |plan| plan.content_stream_count

		page_count : Plan -> U64
		page_count = |plan| plan.page_count

		store : Plan -> Semantics.Store
		store = |plan| plan.store

		work : Plan -> Work
		work = |plan| plan.work
	}

	## The language-tag shape nested `/Lang` values must have. Authoring
	## stages apply it before layout so a malformed tag can name its authored
	## location; graph validation applies the same predicate to every node.
	language_tag_valid : Str -> Bool
	language_tag_valid = |tag| valid_language_tag(tag)
}

## `language_owner` is the nearest ancestor with an explicit language, or
## `U64.highest` when the node inherits only the document default.
NodeFrame := { depth : U64, language_owner : U64, node : Semantics.NodeId, role : U64 }

PendingCaption := [NoPendingCaption, PendingCaption(U64)]

build_plan : Semantics.Store, U64, U64, KernelSemantics.Limits, Bool -> Try(KernelSemantics.Plan, KernelSemantics.Error)
build_plan = |store, page_count, content_stream_count, limits, navigation| {
	validate_tagged_visual_subset(store, navigation)?
	check_limit(checked_add(store.attributes.len(), store.relationships.len())?, limits.max_attributes, Attributes)?
	check_limit(store.content_spine.len(), limits.max_content_spine, ContentSpine)?
	check_limit(store.fragments.len(), limits.max_fragments, Fragments)?
	check_limit(store.namespaces.len(), limits.max_namespaces, Namespaces)?
	check_limit(store.nodes.len(), limits.max_nodes, Nodes)?
	check_limit(store.occurrences.len(), limits.max_occurrences, Occurrences)?

	namespace_work = validate_namespaces(store.namespaces)?
	annotation_work = validate_annotations(store, navigation)?
	occurrence_work = validate_occurrences(store, [], False)?
	fragment_work = validate_fragments(store, [], page_count, content_stream_count)?
	reverse = build_reverse_index(store.occurrences, store.fragments)?
	normalized = { ..store, occurrence_fragments: reverse.fragment_ids, occurrences: reverse.occurrences }
	graph_work = validate_graph(normalized, limits.max_semantic_depth, False, navigation)?

	Ok(
		KernelSemantics.Plan.{
			content_stream_count,
			page_count,
			store: normalized,
			work: {
				annotation_visits: annotation_work,
				attribute_visits: graph_work.attribute_visits,
				containment_edges: graph_work.containment_edges,
				content_visits: graph_work.content_visits,
				fragment_count_visits: reverse.count_visits,
				fragment_validation_visits: fragment_work,
				identifier_visits: graph_work.identifier_visits,
				max_semantic_depth: graph_work.max_depth,
				namespace_visits: namespace_work,
				node_visits: graph_work.node_visits,
				occurrence_visits: occurrence_work,
				prefix_steps: reverse.prefix_steps,
				relationship_visits: graph_work.relationship_visits,
				reverse_writes: reverse.reverse_writes,
			},
		},
	)
}

build_text_plan : Semantics.Store, List(KernelSemantics.TextSourceFact), U64, U64, KernelSemantics.Limits, Bool -> Try(KernelSemantics.Plan, KernelSemantics.Error)
build_text_plan = |store, text_source_facts, page_count, content_stream_count, limits, navigation| {
	validate_text_subset(store, navigation)?
	check_limit(checked_add(store.attributes.len(), store.relationships.len())?, limits.max_attributes, Attributes)?
	check_limit(store.content_spine.len(), limits.max_content_spine, ContentSpine)?
	check_limit(store.fragments.len(), limits.max_fragments, Fragments)?
	check_limit(store.namespaces.len(), limits.max_namespaces, Namespaces)?
	check_limit(store.nodes.len(), limits.max_nodes, Nodes)?
	check_limit(store.occurrences.len(), limits.max_occurrences, Occurrences)?

	namespace_work = validate_namespaces(store.namespaces)?
	annotation_work = validate_annotations(store, navigation)?
	occurrence_work = validate_occurrences(store, text_source_facts, True)?
	fragment_work = validate_fragments(store, text_source_facts, page_count, content_stream_count)?
	reverse = build_reverse_index(store.occurrences, store.fragments)?
	normalized = { ..store, occurrence_fragments: reverse.fragment_ids, occurrences: reverse.occurrences }
	graph_work = validate_graph(normalized, limits.max_semantic_depth, True, navigation)?
	Ok(
		KernelSemantics.Plan.{
			content_stream_count,
			page_count,
			store: normalized,
			work: {
				annotation_visits: annotation_work,
				attribute_visits: graph_work.attribute_visits,
				containment_edges: graph_work.containment_edges,
				content_visits: graph_work.content_visits,
				fragment_count_visits: reverse.count_visits,
				fragment_validation_visits: fragment_work,
				identifier_visits: graph_work.identifier_visits,
				max_semantic_depth: graph_work.max_depth,
				namespace_visits: namespace_work,
				node_visits: graph_work.node_visits,
				occurrence_visits: occurrence_work,
				prefix_steps: reverse.prefix_steps,
				relationship_visits: graph_work.relationship_visits,
				reverse_writes: reverse.reverse_writes,
			},
		},
	)
}

validate_namespaces : List(Semantics.Namespace) -> Try(U64, KernelSemantics.Error)
validate_namespaces = |namespaces| {
	if namespaces.len() != 1 {
		Err(InvalidPdf20Namespace)
	} else {
		namespace = list_at(namespaces, 0)
		if namespace.id.index() != 0 {
			Err(NonDenseIdentity({ actual: namespace.id.index(), expected: 0, kind: NamespaceIndex }))
		} else if namespace.kind != Pdf20 or namespace.uri != "http://iso.org/pdf2/ssn" {
			Err(InvalidPdf20Namespace)
		} else {
			Ok(1)
		}
	}
}

validate_tagged_visual_subset : Semantics.Store, Bool -> Try({}, KernelSemantics.Error)
validate_tagged_visual_subset = |store, navigation| {
	validate_text_subset(store, navigation)?
	if !store.text_properties.is_empty() or !store.text_sources.is_empty() {
		Err(UnsupportedStoreContent)
	} else {
		Ok({})
	}
}

## The text subset admits typed element identifiers, `HeaderFor`,
## `CaptionFor`, and `LabelFor` relationships, and Table- or List-owned node
## attributes; each is validated after the graph walk. Author assertions,
## per-role attribute applicability lists, MathML subtrees, and role mappings
## remain outside it, so no `/RoleMap` is ever lowered.
validate_text_subset : Semantics.Store, Bool -> Try({}, KernelSemantics.Error)
validate_text_subset = |store, navigation| {
	if (!store.annotations.is_empty() and !navigation) or
		!store.assertions.is_empty() or
			!store.attribute_roles.is_empty() or
				!store.mathml_subtrees.is_empty() or
					!store.role_mappings.is_empty() {
		Err(UnsupportedStoreContent)
	} else {
		Ok({})
	}
}

## Annotation records validate once: dense identities, owner nodes in range,
## and a logical order equal to each annotation's rank among the spine's
## annotation occurrences. Spine ownership itself is proven by the graph walk.
validate_annotations : Semantics.Store, Bool -> Try(U64, KernelSemantics.Error)
validate_annotations = |store, navigation| {
	if !navigation {
		Ok(0)
	} else {
		var $index = 0
		var $error = NoError
		while $index < store.annotations.len() and $error == NoError {
			annotation = list_at(store.annotations, $index)
			if annotation.id.index() != $index {
				$error = Invalid(NonDenseIdentity({ actual: annotation.id.index(), expected: $index, kind: AnnotationIndex }))
			} else if annotation.owner.index() >= store.nodes.len() {
				$error = Invalid(IndexOutOfRange({ available: store.nodes.len(), index: annotation.owner.index(), kind: NodeIndex }))
			}
			$index = $index + 1
		}
		var $spine_index = 0
		var $rank = 0
		while $spine_index < store.content_spine.len() and $error == NoError {
			match list_at(store.content_spine, $spine_index) {
				AnnotationOccurrence(annotation_id) => {
					annotation_index = annotation_id.index()
					if annotation_index >= store.annotations.len() {
						$error = Invalid(IndexOutOfRange({ available: store.annotations.len(), index: annotation_index, kind: AnnotationIndex }))
					} else {
						annotation = list_at(store.annotations, annotation_index)
						if annotation.logical_order != $rank {
							$error = Invalid(AnnotationLogicalOrderInvalid({ actual: annotation.logical_order, annotation: annotation_index, expected: $rank }))
						}
					}
					$rank = $rank + 1
				}
				_ => {}
			}
			$spine_index = $spine_index + 1
		}
		match $error {
			Invalid(error) => Err(error)
			NoError => Ok(store.annotations.len() + $rank)
		}
	}
}

validate_occurrences : Semantics.Store, List(KernelSemantics.TextSourceFact), Bool -> Try(U64, KernelSemantics.Error)
validate_occurrences = |store, text_facts, text_allowed| {
	var $index = 0
	var $error = NoError
	while $index < store.occurrences.len() and $error == NoError {
		occurrence = list_at(store.occurrences, $index)
		if occurrence.id.index() != $index {
			$error = Invalid(NonDenseIdentity({ actual: occurrence.id.index(), expected: $index, kind: OccurrenceIndex }))
		} else if occurrence.text_properties.length() != 0 and !text_allowed {
			$error = Invalid(UnsupportedStoreContent)
		} else {
			match occurrence.source {
				Text(source, range) => if !text_allowed {
					$error = Invalid(UnsupportedTextOccurrence({ occurrence: $index }))
				} else {
					source_index = source.index()
					if source_index >= text_facts.len() {
						$error = Invalid(IndexOutOfRange({ available: text_facts.len(), index: source_index, kind: TextSourceIndex }))
					} else {
						match range {
							ByteRange(_) => {
								$error = Invalid(UnsupportedTextOccurrence({ occurrence: $index }))
							}
							UnicodeRange(text_range) => if !valid_text_range(text_range, list_at(text_facts, source_index)) {
								$error = Invalid(UnsupportedTextOccurrence({ occurrence: $index }))
							}
						}
					}
				}
				NonText(source, range) => {
					source_index = source.index()
					if source_index >= store.non_text_sources.len() {
						$error = Invalid(IndexOutOfRange({ available: store.non_text_sources.len(), index: source_index, kind: NonTextSourceIndex }))
					} else {
						match range {
							UnicodeRange(_) => {
								$error = Invalid(UnsupportedTextOccurrence({ occurrence: $index }))
							}
							ByteRange(bytes) => match validate_span(bytes, list_at(store.non_text_sources, source_index).len(), FragmentIndex, $index) {
								Err(error) => {
									$error = Invalid(error)
								}
								Ok(_) => {}
							}
						}
					}
				}
			}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok(store.occurrences.len())
	}
}

validate_fragments : Semantics.Store, List(KernelSemantics.TextSourceFact), U64, U64 -> Try(U64, KernelSemantics.Error)
validate_fragments = |store, text_facts, page_count, content_stream_count| {
	var $index = 0
	var $error = NoError
	while $index < store.fragments.len() and $error == NoError {
		fragment = list_at(store.fragments, $index)
		if fragment.id.index() != $index {
			$error = Invalid(NonDenseIdentity({ actual: fragment.id.index(), expected: $index, kind: FragmentIndex }))
		} else if fragment.occurrence.index() >= store.occurrences.len() {
			$error = Invalid(IndexOutOfRange({ available: store.occurrences.len(), index: fragment.occurrence.index(), kind: OccurrenceIndex }))
		} else if fragment.page.index() >= page_count {
			$error = Invalid(IndexOutOfRange({ available: page_count, index: fragment.page.index(), kind: FragmentIndex }))
		} else if fragment.content_stream.index() >= content_stream_count {
			$error = Invalid(IndexOutOfRange({ available: content_stream_count, index: fragment.content_stream.index(), kind: FragmentIndex }))
		} else if !fragment_range_valid(fragment, list_at(store.occurrences, fragment.occurrence.index()), text_facts) {
			$error = Invalid(FragmentRangeOutsideOccurrence({ fragment: $index }))
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok(store.fragments.len())
	}
}

fragment_range_valid : Semantics.LayoutFragment, Semantics.ContentOccurrence, List(KernelSemantics.TextSourceFact) -> Bool
fragment_range_valid = |fragment, occurrence, text_facts| match (fragment.source_range, occurrence.source) {
	(ByteRange(fragment_range), NonText(_, ByteRange(occurrence_range))) => range_contains(occurrence_range, fragment_range)
	(UnicodeRange(fragment_range), Text(source, UnicodeRange(occurrence_range))) => if source.index() < text_facts.len() {
		valid_text_range(fragment_range, list_at(text_facts, source.index())) and text_range_contains(occurrence_range, fragment_range)
	} else {
		False
	}
	_ => False
}

valid_text_range : Semantics.TextRange, KernelSemantics.TextSourceFact -> Bool
valid_text_range = |range, fact| {
	scalar_start = range.scalars.start()
	scalar_length = range.scalars.length()
	byte_start = range.utf8_bytes.start()
	byte_length = range.utf8_bytes.length()
	if scalar_start > fact.scalar_count or scalar_length > fact.scalar_count - scalar_start or byte_start > fact.byte_count or byte_length > fact.byte_count - byte_start {
		False
	} else {
		scalar_end = scalar_start + scalar_length
		byte_end = byte_start + byte_length
		list_at(fact.scalar_byte_offsets, scalar_start) == byte_start and list_at(fact.scalar_byte_offsets, scalar_end) == byte_end
	}
}

text_range_contains : Semantics.TextRange, Semantics.TextRange -> Bool
text_range_contains = |outer, inner| range_contains(outer.scalars, inner.scalars) and range_contains(outer.utf8_bytes, inner.utf8_bytes)

range_contains : Semantics.Range, Semantics.Range -> Bool
range_contains = |outer, inner| {
	outer_start = outer.start()
	outer_length = outer.length()
	inner_start = inner.start()
	inner_length = inner.length()
	if inner_start < outer_start {
		False
	} else {
		relative = inner_start - outer_start
		relative <= outer_length and inner_length <= outer_length - relative
	}
}

build_reverse_index : List(Semantics.ContentOccurrence), List(Semantics.LayoutFragment) -> Try({ count_visits : U64, fragment_ids : List(Semantics.FragmentId), occurrences : List(Semantics.ContentOccurrence), prefix_steps : U64, reverse_writes : U64 }, KernelSemantics.Error)
build_reverse_index = |occurrences, fragments| {
	var $counts = List.repeat(0, occurrences.len())
	var $fragment_index = 0
	while $fragment_index < fragments.len() {
		occurrence_index = list_at(fragments, $fragment_index).occurrence.index()
		count = list_at($counts, occurrence_index)
		next_count = U64.plus_try(count, 1) ? |_| ArithmeticOverflow
		$counts = list_set($counts, occurrence_index, next_count)
		$fragment_index = $fragment_index + 1
	}

	var $starts = List.repeat(0, occurrences.len())
	var $total = 0
	var $occurrence_index = 0
	while $occurrence_index < occurrences.len() {
		$starts = list_set($starts, $occurrence_index, $total)
		$total = U64.plus_try($total, list_at($counts, $occurrence_index)) ? |_| ArithmeticOverflow
		$occurrence_index = $occurrence_index + 1
	}

	var $cursors = $starts
	var $fragment_ids = List.repeat(Semantics.FragmentId.from_index(0), fragments.len())
	$fragment_index = 0
	while $fragment_index < fragments.len() {
		fragment = list_at(fragments, $fragment_index)
		owner = fragment.occurrence.index()
		write_index = list_at($cursors, owner)
		$fragment_ids = list_set($fragment_ids, write_index, fragment.id)
		$cursors = list_set($cursors, owner, write_index + 1)
		$fragment_index = $fragment_index + 1
	}

	var $normalized_occurrences = occurrences
	$occurrence_index = 0
	while $occurrence_index < occurrences.len() {
		occurrence = list_at(occurrences, $occurrence_index)
		normalized = { ..occurrence, fragments: Semantics.Range.from_start_and_length(list_at($starts, $occurrence_index), list_at($counts, $occurrence_index)) }
		$normalized_occurrences = list_set($normalized_occurrences, $occurrence_index, normalized)
		$occurrence_index = $occurrence_index + 1
	}

	Ok({ count_visits: fragments.len(), fragment_ids: $fragment_ids, occurrences: $normalized_occurrences, prefix_steps: occurrences.len(), reverse_writes: fragments.len() })
}

GraphWork : {
	attribute_visits : U64,
	containment_edges : U64,
	content_visits : U64,
	identifier_visits : U64,
	max_depth : U64,
	node_visits : U64,
	relationship_visits : U64,
}

## One breadth-first walk proves reachability, single ownership, depth, role
## enablement, and every parent/child edge against the ISO/TS 32005 table in
## O(1) per edge. Element identifiers, typed attributes, and relationships
## are validated after the walk, once each, in dense-store order.
validate_graph : Semantics.Store, U64, Bool, Bool -> Try(GraphWork, KernelSemantics.Error)
validate_graph = |store, max_depth, text_allowed, navigation| {
	if store.nodes.len() == 0 or store.document_root.index() >= store.nodes.len() {
		Err(InvalidDocumentRoot({ node: store.document_root.index() }))
	} else {
		identity_check = validate_dense_graph_identities(store)?
		_ = identity_check
		var $node_owners = List.repeat(0, store.nodes.len())
		var $content_owners = List.repeat(0, store.content_spine.len())
		var $occurrence_owners = List.repeat(0, store.occurrences.len())
		var $annotation_owners = List.repeat(0, store.annotations.len())
		var $artifact_owners = List.repeat(0, store.contextual_artifacts.len())
		var $attribute_owners = List.repeat(0, store.attributes.len())
		var $identifier_owners = List.repeat(0, store.element_identifiers.len())
		root = list_at(store.nodes, store.document_root.index())
		var $frames = [NodeFrame.{ depth: 1, language_owner: U64.highest, node: store.document_root, role: role_index(root.role.local_name) }]
		var $frame_index = 0
		var $content_visits = 0
		var $attribute_visits = 0
		var $containment_edges = 0
		var $node_visits = 0
		var $maximum_depth = 0
		var $error = NoError
		while $frame_index < $frames.len() and $error == NoError {
			frame = list_at($frames, $frame_index)
			node_index = frame.node.index()
			if frame.depth > max_depth {
				$error = Invalid(LimitExceeded({ attempted: frame.depth, dimension: SemanticDepth, limit: max_depth }))
			} else {
				if list_at($node_owners, node_index) != 0 {
					$error = Invalid(DuplicateOwnership({ index: node_index, kind: NodeIndex }))
				} else {
					$node_owners = list_set($node_owners, node_index, 1)
					node = list_at(store.nodes, node_index)
					is_root = node_index == store.document_root.index()
					if !role_enabled(frame.role, node.role.namespace.index(), is_root, text_allowed, navigation) {
						$error = Invalid(UnsupportedRole({ node: node_index }))
					} else if node.text_properties.length() != 0 and !text_allowed {
						$error = Invalid(UnsupportedStoreContent)
					} else if is_root and node.parent != DocumentRoot {
						$error = Invalid(InvalidDocumentRoot({ node: node_index }))
					} else {
						$maximum_depth = U64.max($maximum_depth, frame.depth)
						match validate_node_facts(store, node, node_index, is_root, text_allowed, frame.language_owner, $identifier_owners) {
							Err(error) => {
								$error = Invalid(error)
							}
							Ok(identifier_owners) => {
								$identifier_owners = identifier_owners
								match mark_attribute_range(node.attributes, node_index, False, $attribute_owners, store.attributes) {
									Err(error) => {
										$error = Invalid(error)
									}
									Ok(marked) => {
										$attribute_owners = marked.owners
										$attribute_visits = $attribute_visits + marked.visits
										match validate_span(node.content, store.content_spine.len(), ContentIndex, node_index) {
											Err(error) => {
												$error = Invalid(error)
											}
											Ok(span) => {
												var $content_index = span.start
												var $limited_seen = 0
												var $child_position = 0
												var $pending_caption = NoPendingCaption
												while $content_index < span.end and $error == NoError {
													if list_at($content_owners, $content_index) != 0 {
														$error = Invalid(DuplicateOwnership({ index: $content_index, kind: ContentIndex }))
													} else {
														$content_owners = list_set($content_owners, $content_index, 1)
														item = list_at(store.content_spine, $content_index)
														match item {
															AnnotationOccurrence(annotation_id) => if !navigation {
																$error = Invalid(UnsupportedAnnotation({ content: $content_index }))
															} else {
																annotation_index = annotation_id.index()
																if annotation_index >= $annotation_owners.len() {
																	$error = Invalid(IndexOutOfRange({ available: $annotation_owners.len(), index: annotation_index, kind: AnnotationIndex }))
																} else if list_at($annotation_owners, annotation_index) != 0 {
																	$error = Invalid(DuplicateOwnership({ index: annotation_index, kind: AnnotationIndex }))
																} else {
																	$annotation_owners = list_set($annotation_owners, annotation_index, 1)
																	annotation = list_at(store.annotations, annotation_index)
																	if annotation.owner.index() != node_index {
																		$error = Invalid(AnnotationOwnerMismatch({ annotation: annotation_index, occurrence_owner: node_index, owner: annotation.owner.index() }))
																	}
																}
															}
															ChildNode(child) => {
																child_index = child.index()
																if child_index >= store.nodes.len() {
																	$error = Invalid(IndexOutOfRange({ available: store.nodes.len(), index: child_index, kind: NodeIndex }))
																} else {
																	child_node = list_at(store.nodes, child_index)
																	match child_node.parent {
																		DocumentRoot => {
																			$error = Invalid(InvalidParent({ actual: child_index, expected: node_index, node: child_index }))
																		}
																		ParentNode(parent) => if parent.index() != node_index {
																			$error = Invalid(InvalidParent({ actual: parent.index(), expected: node_index, node: child_index }))
																		} else {
																			child_role = role_index(child_node.role.local_name)
																			child_bit = role_bit(child_role)
																			$containment_edges = $containment_edges + 1
																			if child_role != unknown_role and !may_contain(frame.role, child_role) {
																				$error = Invalid(IllegalContainment({ child: child_index, parent: node_index }))
																			} else if $limited_seen.bitwise_and(child_bit) != 0 {
																				$error = Invalid(DuplicateChildRole({ child: child_index, parent: node_index }))
																			} else {
																				match $pending_caption {
																					PendingCaption(caption) => {
																						$error = Invalid(CaptionPosition({ caption, parent: node_index }))
																					}
																					NoPendingCaption => {
																						$limited_seen = $limited_seen.bitwise_or(at_most_one_children(frame.role).bitwise_and(child_bit))
																						if child_role == role_caption and $child_position > 0 {
																							$pending_caption = PendingCaption(child_index)
																						}
																						$child_position = $child_position + 1
																						depth = U64.plus_try(frame.depth, 1) ? |_| ArithmeticOverflow
																						language_owner = match node.language {
																							Language(_) => node_index
																							Inherited => frame.language_owner
																						}
																						$frames = $frames.append(NodeFrame.{ depth, language_owner, node: child, role: child_role })
																					}
																				}
																			}
																		}
																	}
																}
															}
															ContentOccurrence(occurrence) => {
																occurrence_index = occurrence.index()
																if forbids_content_items(frame.role) {
																	$error = Invalid(IllegalContentItem({ content: $content_index, node: node_index }))
																} else if occurrence_index >= $occurrence_owners.len() {
																	$error = Invalid(IndexOutOfRange({ available: $occurrence_owners.len(), index: occurrence_index, kind: OccurrenceIndex }))
																} else if list_at($occurrence_owners, occurrence_index) != 0 {
																	$error = Invalid(DuplicateOwnership({ index: occurrence_index, kind: OccurrenceIndex }))
																} else {
																	$occurrence_owners = list_set($occurrence_owners, occurrence_index, 1)
																}
															}
															ContextualArtifact(artifact) => {
																artifact_index = artifact.index()
																match mark_index($artifact_owners, artifact_index, ContextualArtifactIndex) {
																	Err(error) => {
																		$error = Invalid(error)
																	}
																	Ok(next_owners) => {
																		$artifact_owners = next_owners
																		artifact_record = list_at(store.contextual_artifacts, artifact_index)
																		if artifact_record.parent.index() != node_index {
																			$error = Invalid(InvalidParent({ actual: artifact_record.parent.index(), expected: node_index, node: artifact_index }))
																		} else {
																			match mark_attribute_range(artifact_record.attributes, artifact_index, True, $attribute_owners, store.attributes) {
																				Err(error) => {
																					$error = Invalid(error)
																				}
																				Ok(artifact_marked) => {
																					$attribute_owners = artifact_marked.owners
																					$attribute_visits = $attribute_visits + artifact_marked.visits
																				}
																			}
																		}
																	}
																}
															}
														}
													}
													$content_index = $content_index + 1
													$content_visits = $content_visits + 1
												}
											}
										}
									}
								}
							}
						}
						$node_visits = $node_visits + 1
					}
				}
			}
			$frame_index = $frame_index + 1
		}

		match $error {
			Invalid(error) => Err(error)
			NoError => {
				ensure_all_owned($node_owners, NodeIndex)?
				ensure_all_owned($content_owners, ContentIndex)?
				ensure_all_owned($occurrence_owners, OccurrenceIndex)?
				ensure_all_owned($annotation_owners, AnnotationIndex)?
				ensure_all_owned($artifact_owners, ContextualArtifactIndex)?
				ensure_all_owned($attribute_owners, AttributeIndex)?
				ensure_all_owned($identifier_owners, ElementIdentifierIndex)?
				keys = validate_identifiers(store.element_identifiers)?
				attribute_checks = validate_attributes(store, keys)?
				relationship_visits = validate_relationships(store)?
				Ok({
					attribute_visits: $attribute_visits + attribute_checks,
					containment_edges: $containment_edges,
					content_visits: $content_visits,
					identifier_visits: store.element_identifiers.len(),
					max_depth: $maximum_depth,
					node_visits: $node_visits,
					relationship_visits,
				})
			}
		}
	}
}

## Per-node facts outside the content spine: an explicit non-root language
## that differs from the language it inherits must be a well-formed language
## tag (ISO 32000-2 14.9.2; the catalog language is validated by the metadata
## stage, and a repeated inherited language lowers nothing and was already
## checked on its ancestor), node text properties are limited to one each of
## ActualText, Alt, and E, and an element identifier is owned by exactly one
## node.
validate_node_facts : Semantics.Store, Semantics.Node, U64, Bool, Bool, U64, List(U8) -> Try(List(U8), KernelSemantics.Error)
validate_node_facts = |store, node, node_index, is_root, text_allowed, language_owner, identifier_owners| {
	match node.language {
		Inherited => {}
		Language(tag) => if !is_root and !repeats_language(store, language_owner, tag) and !valid_language_tag(tag) {
			return Err(InvalidLanguage({ node: node_index }))
		}
	}
	if text_allowed and node.text_properties.length() != 0 {
		validate_node_properties(store, node, node_index)?
	}
	match node.element_identifier {
		NoElementIdentifier => Ok(identifier_owners)
		HasElementIdentifier(element) => mark_index(identifier_owners, element.index(), ElementIdentifierIndex)
	}
}

validate_node_properties : Semantics.Store, Semantics.Node, U64 -> Try({}, KernelSemantics.Error)
validate_node_properties = |store, node, node_index| {
	span = validate_span(node.text_properties, store.text_properties.len(), TextPropertyIndex, node_index)?
	var $seen = 0
	var $index = span.start
	while $index < span.end {
		bit = match list_at(store.text_properties, $index) {
			ActualText(_) => 1
			AlternativeText(_) => 2
			ExpandedText(_) => 4
			_ => 0
		}
		if bit == 0 or $seen.bitwise_and(bit) != 0 {
			return Err(InvalidNodeTextProperty({ node: node_index, property: $index }))
		}
		$seen = $seen.bitwise_or(bit)
		$index = $index + 1
	}
	Ok({})
}

repeats_language : Semantics.Store, U64, Str -> Bool
repeats_language = |store, owner, tag| if owner >= store.nodes.len() {
	False
} else {
	match list_at(store.nodes, owner).language {
		Language(inherited) => inherited == tag
		Inherited => False
	}
}

## `^[A-Za-z]{1,8}(-[A-Za-z0-9]{1,8})*$`: the language-tag shape PDF/UA-2
## 8.4.4 checks for every structure-element `/Lang` (RFC 3066 syntax).
valid_language_tag : Str -> Bool
valid_language_tag = |tag| {
	bytes = Str.to_utf8(tag)
	zero = bytes.len() - bytes.len()
	var $subtag = zero
	var $length = zero
	var $valid = !bytes.is_empty()
	for byte in bytes {
		if byte == 45 {
			$valid = $valid and $length >= 1 and $length <= 8
			$subtag = $subtag + 1
			$length = 0
		} else if (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or ($subtag > 0 and byte >= 48 and byte <= 57) {
			$length = $length + 1
		} else {
			$valid = False
		}
	}
	$valid and $length >= 1 and $length <= 8

}

## Element identifiers are dense, non-empty, and stored in strictly
## ascending byte order of their values. Order is a normalized-store
## invariant: uniqueness is one adjacent comparison per identifier and the
## IDTree lowers the same order without sorting. The returned keys serve
## `/Headers` target lookups by binary search.
validate_identifiers : List(Semantics.ElementIdentifier) -> Try(List(List(U8)), KernelSemantics.Error)
validate_identifiers = |identifiers| {
	if identifiers.is_empty() {
		return Ok([])
	}
	var $keys = List.with_capacity(identifiers.len())
	var $index = 0
	while $index < identifiers.len() {
		identifier = list_at(identifiers, $index)
		if identifier.id.index() != $index {
			return Err(NonDenseIdentity({ actual: identifier.id.index(), expected: $index, kind: ElementIdentifierIndex }))
		}
		key = Str.to_utf8(identifier.value)
		if key.is_empty() {
			return Err(EmptyElementIdentifier({ element: $index }))
		}
		if $index > 0 {
			match compare_bytes(list_at($keys, $index - 1), key) {
				Less => {}
				Equal => return Err(DuplicateElementIdentifier({ first: $index - 1, second: $index }))
				Greater => return Err(ElementIdentifierOrder({ element: $index }))
			}
		}
		$keys = $keys.append(key)
		$index = $index + 1
	}
	Ok($keys)
}

AttributeCheck := [AttributeBit(U64), HeadersBit(List(Str)), InvalidAttributeCheck]

## Node attributes are typed by owner, standard name, value, and the role
## they sit on (ISO 32000-2 14.8.5.4 List and 14.8.5.7 Table attributes).
## Each name occurs at most once per node, and every `/Headers` value names
## an existing element identifier.
validate_attributes : Semantics.Store, List(List(U8)) -> Try(U64, KernelSemantics.Error)
validate_attributes = |store, keys| {
	if store.attributes.is_empty() {
		return Ok(0)
	}
	var $checks = 0
	var $node_index = 0
	while $node_index < store.nodes.len() {
		node = list_at(store.nodes, $node_index)
		start = node.attributes.start()
		end = start + node.attributes.length()
		if end > start {
			role = role_index(node.role.local_name)
			var $seen = 0
			var $attribute = start
			while $attribute < end {
				bit = match check_attribute(list_at(store.attributes, $attribute), role) {
					InvalidAttributeCheck => return Err(InvalidAttribute({ attribute: $attribute, node: $node_index }))
					AttributeBit(value) => value
					HeadersBit(header_ids) => {
						var $target = 0
						while $target < header_ids.len() {
							if !contains_key(keys, Str.to_utf8(list_at(header_ids, $target))) {
								return Err(UnknownAttributeTarget({ attribute: $attribute, node: $node_index }))
							}
							$checks = $checks + 1
							$target = $target + 1
						}
						2
					}
				}
				if $seen.bitwise_and(bit) != 0 {
					return Err(InvalidAttribute({ attribute: $attribute, node: $node_index }))
				}
				$seen = $seen.bitwise_or(bit)
				$checks = $checks + 1
				$attribute = $attribute + 1
			}
		}
		$node_index = $node_index + 1
	}
	Ok($checks)
}

check_attribute : Semantics.StructureAttribute, U64 -> AttributeCheck
check_attribute = |attribute, role| {
	name = match attribute.name {
		Standard(value) => value
		Namespaced(_) => return InvalidAttributeCheck
	}
	cell = role == role_th or role == role_td
	match attribute.owner {
		Table => if !applies_to(attribute.applicability, TableFamily) {
			InvalidAttributeCheck
		} else if name == "Scope" {
			match attribute.value {
				Name(value) => if role == role_th and (value == "Row" or value == "Column" or value == "Both") AttributeBit(1) else InvalidAttributeCheck
				_ => InvalidAttributeCheck
			}
		} else if name == "Headers" {
			match attribute.value {
				Names(values) => if cell and !values.is_empty() HeadersBit(values) else InvalidAttributeCheck
				_ => InvalidAttributeCheck
			}
		} else if name == "ColSpan" {
			match attribute.value {
				Integer(value) => if cell and value >= 1 AttributeBit(4) else InvalidAttributeCheck
				_ => InvalidAttributeCheck
			}
		} else if name == "RowSpan" {
			match attribute.value {
				Integer(value) => if cell and value >= 1 AttributeBit(8) else InvalidAttributeCheck
				_ => InvalidAttributeCheck
			}
		} else if name == "Summary" {
			match attribute.value {
				Text(value) => if role == role_table and !value.is_empty() AttributeBit(16) else InvalidAttributeCheck
				_ => InvalidAttributeCheck
			}
		} else {
			InvalidAttributeCheck
		}
		List => if !applies_to(attribute.applicability, ListFamily) or name != "ListNumbering" or role != role_l {
			InvalidAttributeCheck
		} else {
			match attribute.value {
				Name(value) => if valid_list_numbering(value) AttributeBit(32) else InvalidAttributeCheck
				_ => InvalidAttributeCheck
			}
		}
		_ => InvalidAttributeCheck
	}
}

applies_to : Semantics.AttributeApplicability, [ListFamily, TableFamily] -> Bool
applies_to = |applicability, family| match applicability {
	AllRoles => True
	Family(TableRoles) => family == TableFamily
	Family(ListRoles) => family == ListFamily
	_ => False
}

## ISO 32000-2 Table 380 ListNumbering values.
valid_list_numbering : Str -> Bool
valid_list_numbering = |value|
	value == "None" or value == "Unordered" or value == "Description" or value == "Disc" or value == "Circle" or value == "Square" or value == "Ordered" or value == "Decimal" or value == "UpperRoman" or value == "LowerRoman" or value == "UpperAlpha" or value == "LowerAlpha"

contains_key : List(List(U8)), List(U8) -> Bool
contains_key = |keys, key| {
	var $low = 0
	var $high = keys.len()
	var $found = False
	while !$found and $low < $high {
		middle = $low + ($high - $low) // 2
		match compare_bytes(list_at(keys, middle), key) {
			Equal => {
				$found = True
			}
			Less => {
				$low = middle + 1
			}
			Greater => {
				$high = middle
			}
		}
	}
	$found
}

compare_bytes : List(U8), List(U8) -> [Equal, Greater, Less]
compare_bytes = |left, right| {
	shared = U64.min(left.len(), right.len())
	var $index = 0
	var $ordering = Equal
	while $ordering == Equal and $index < shared {
		a = list_at(left, $index)
		b = list_at(right, $index)
		if a < b {
			$ordering = Less
		} else if a > b {
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

## Typed non-parental relations. `HeaderFor` links a TH or TD cell to a TH
## header by element identifier; `CaptionFor` links a Caption to an element
## that may contain one, as its child or its sibling; `LabelFor` links an Lbl
## to a sibling. Other relation kinds are outside the text subset.
validate_relationships : Semantics.Store -> Try(U64, KernelSemantics.Error)
validate_relationships = |store| {
	if store.relationships.is_empty() {
		return Ok(0)
	}
	var $owners = List.repeat(0, store.element_identifiers.len())
	var $node_index = 0
	while $node_index < store.nodes.len() {
		match list_at(store.nodes, $node_index).element_identifier {
			NoElementIdentifier => {}
			HasElementIdentifier(element) => {
				$owners = list_set($owners, element.index(), $node_index)
			}
		}
		$node_index = $node_index + 1
	}
	var $index = 0
	while $index < store.relationships.len() {
		valid = match list_at(store.relationships, $index) {
			HeaderFor({ cell, header }) => header_relation_valid(store, $owners, cell.index(), header.index())
			CaptionFor({ caption, target }) => caption_relation_valid(store, caption.index(), target.index())
			LabelFor({ label, target }) => label_relation_valid(store, label.index(), target.index())
			_ => False
		}
		if !valid {
			return Err(InvalidRelationship({ relationship: $index }))
		}
		$index = $index + 1
	}
	Ok(store.relationships.len())
}

header_relation_valid : Semantics.Store, List(U64), U64, U64 -> Bool
header_relation_valid = |store, owners, cell, header| {
	if cell >= owners.len() or header >= owners.len() or cell == header {
		False
	} else {
		cell_role = node_role(store, list_at(owners, cell))
		node_role(store, list_at(owners, header)) == role_th and (cell_role == role_th or cell_role == role_td)
	}
}

caption_relation_valid : Semantics.Store, U64, U64 -> Bool
caption_relation_valid = |store, caption, target| {
	if caption >= store.nodes.len() or target >= store.nodes.len() or caption == target {
		False
	} else {
		caption_parent = list_at(store.nodes, caption).parent
		target_parent = list_at(store.nodes, target).parent
		node_role(store, caption) == role_caption and may_contain(node_role(store, target), role_caption) and (parent_index(caption_parent) == target or parent_index(caption_parent) == parent_index(target_parent))
	}
}

label_relation_valid : Semantics.Store, U64, U64 -> Bool
label_relation_valid = |store, label, target| {
	if label >= store.nodes.len() or target >= store.nodes.len() or label == target {
		False
	} else {
		node_role(store, label) == role_lbl and node_role(store, target) != role_lbl and parent_index(list_at(store.nodes, label).parent) == parent_index(list_at(store.nodes, target).parent)
	}
}

parent_index : Semantics.NodeParent -> U64
parent_index = |parent| match parent {
	DocumentRoot => U64.highest
	ParentNode(node) => node.index()
}

node_role : Semantics.Store, U64 -> U64
node_role = |store, node| role_index(list_at(store.nodes, node).role.local_name)

validate_dense_graph_identities : Semantics.Store -> Try({}, KernelSemantics.Error)
validate_dense_graph_identities = |store| {
	var $structure_ids = List.repeat(0, store.nodes.len())
	var $node_index = 0
	var $error = NoError
	while $node_index < store.nodes.len() and $error == NoError {
		node = list_at(store.nodes, $node_index)
		if node.id.index() != $node_index {
			$error = Invalid(NonDenseIdentity({ actual: node.id.index(), expected: $node_index, kind: NodeIndex }))
		} else {
			structure_index = node.structure_element.index()
			if structure_index >= store.nodes.len() {
				$error = Invalid(IndexOutOfRange({ available: store.nodes.len(), index: structure_index, kind: StructureElementIndex }))
			} else if list_at($structure_ids, structure_index) != 0 {
				$error = Invalid(DuplicateOwnership({ index: structure_index, kind: StructureElementIndex }))
			} else {
				$structure_ids = list_set($structure_ids, structure_index, 1)
			}
		}
		$node_index = $node_index + 1
	}
	var $artifact_index = 0
	while $artifact_index < store.contextual_artifacts.len() and $error == NoError {
		artifact = list_at(store.contextual_artifacts, $artifact_index)
		if artifact.id.index() != $artifact_index {
			$error = Invalid(NonDenseIdentity({ actual: artifact.id.index(), expected: $artifact_index, kind: ContextualArtifactIndex }))
		}
		$artifact_index = $artifact_index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({})
	}
}

## Dense PDF 2.0 standard-role indexes for the structure vocabulary the
## kernel accepts. `H1`..`H6` share the `Hn` row, as in ISO/TS 32005 Table 5.
## Every other local name is `unknown_role` and is rejected as an
## unsupported role; it is never mapped or flattened.
role_index : Str -> U64
role_index = |name| {
	if name == "P" {
		role_p
	} else if name == "Span" {
		16
	} else if name == "Document" {
		role_document
	} else if name == "H1" or name == "H2" or name == "H3" or name == "H4" or name == "H5" or name == "H6" {
		role_hn
	} else if name == "L" {
		role_l
	} else if name == "LI" {
		10
	} else if name == "Lbl" {
		role_lbl
	} else if name == "LBody" {
		12
	} else if name == "Link" {
		role_link
	} else if name == "TD" {
		role_td
	} else if name == "TH" {
		role_th
	} else if name == "TR" {
		25
	} else if name == "Sect" {
		3
	} else if name == "Div" {
		4
	} else if name == "Part" {
		2
	} else if name == "Title" {
		5
	} else if name == "Figure" {
		13
	} else if name == "Caption" {
		role_caption
	} else if name == "Em" {
		17
	} else if name == "Strong" {
		18
	} else if name == "Code" {
		19
	} else if name == "Quote" {
		20
	} else if name == "Table" {
		role_table
	} else if name == "THead" {
		22
	} else if name == "TBody" {
		23
	} else if name == "TFoot" {
		24
	} else if name == "DocumentFragment" {
		1
	} else if name == "H" {
		6
	} else {
		unknown_role
	}
}

role_document : U64
role_document = 0

role_hn : U64
role_hn = 7

role_p : U64
role_p = 8

role_l : U64
role_l = 9

role_lbl : U64
role_lbl = 11

role_caption : U64
role_caption = 14

role_link : U64
role_link = 15

role_table : U64
role_table = 21

role_th : U64
role_th = 26

role_td : U64
role_td = 27

unknown_role : U64
unknown_role = 63

role_bit : U64 -> U64
role_bit = |role| if role == unknown_role 0 else U64.shl_wrap(1, role.to_u8_wrap())

## Roles are enabled per validation subset: the root is exactly `Document`
## (PDF/UA-2 8.2.5.2) and `Document` never nests; the tagged-visual subset
## admits only `P`; `Link` requires the navigation-enabled variants; the text
## subset admits the whole vocabulary above.
role_enabled : U64, U64, Bool, Bool, Bool -> Bool
role_enabled = |role, namespace, is_root, text_enabled, navigation| {
	if namespace != 0 or role == unknown_role {
		False
	} else if is_root {
		role == role_document
	} else if role == role_document {
		False
	} else if role == role_link {
		navigation
	} else if text_enabled {
		True
	} else {
		role == role_p
	}
}

## ISO/TS 32005:2023 Table 5 parent/child containment, restricted to the
## roles above. Bit `c` of row `p` is set when a `p` element may contain a
## `c` element. The rows were transcribed from the pinned veraPDF 1.30.2
## `PDFUA-2-ISO32005.xml` profile, whose rules "Table 5. <Parent>-<Child>"
## encode each forbidden pair; every pair not forbidden there is permitted.
## `scripts/check_structure_semantics.py` holds an independent transcription
## that its self-test compares against the same profile.
containment_row : U64 -> U64
containment_row = |parent| match parent {

	## Document: Document, DocumentFragment, Part, Sect, Div, Title, H, Hn, P, L, Figure, Link, Code, Table
	0 => 2663423

	## DocumentFragment: same as Document
	1 => 2663423

	## Part: every role
	2 => 268435455

	## Sect: DocumentFragment, Part, Sect, Div, Title, H, Hn, P, L, Lbl, Figure, Caption, Link, Code, Table
	3 => 2681854

	## Div: every role
	4 => 268435455

	## Title: Part, Div, P, L, Lbl, Figure, Caption, Link, Span, Em, Strong, Code, Quote, Table
	5 => 4188948

	## H and Hn: Sect, Lbl, Figure, Link, Span, Em, Strong, Code, Quote
	6 => 2074632
	7 => 2074632

	## P: L, Lbl, Figure, Link, Span, Em, Strong, Code, Quote, Table
	8 => 4172288

	## L: L, LI, Caption
	9 => 17920

	## LI: Div, Lbl, LBody
	10 => 6160

	## Lbl: Figure, Link, Span, Em, Strong, Code, Quote
	11 => 2072576

	## LBody: Part, Sect, Div, H, Hn, P, L, Figure, Caption, Link, Span, Em, Strong, Code, Quote, Table
	12 => 4187100

	## Figure: Part, Sect, Div, H, Hn, P, L, Lbl, Figure, Caption, Link, Span, Em, Strong, Code, Quote, Table
	13 => 4189148

	## Caption: DocumentFragment, Part, Sect, Div, H, Hn, P, L, Lbl, Figure, Link, Span, Em, Strong, Code, Quote, Table
	14 => 4172766

	## Link: DocumentFragment, Part, Sect, Div, Title, H, Hn, P, L, Lbl, Figure, Caption, Link, Span, Em, Strong, Code, Quote, Table
	15 => 4189182

	## Span, Em, Strong: Lbl, Figure, Link, Span, Em, Strong, Code, Quote
	16 => 2074624
	17 => 2074624
	18 => 2074624

	## Code: DocumentFragment, Part, Sect, Div, P, L, Lbl, Figure, Caption, Link, Span, Em, Strong, Code, Quote, Table
	19 => 4188958

	## Quote: Div, Lbl, Figure, Link, Span, Em, Strong, Code, Quote
	20 => 2074640

	## Table: Caption, THead, TBody, TFoot, TR
	21 => 62930944

	## THead, TBody, TFoot: TR
	22 => 33554432
	23 => 33554432
	24 => 33554432

	## TR: TH, TD
	25 => 201326592

	## TH, TD: Sect, Div, H, Hn, P, L, Lbl, Figure, Link, Span, Em, Strong, Code, Quote, Table
	26 => 4172760
	27 => 4172760
	_ => 0
}

may_contain : U64, U64 -> Bool
may_contain = |parent, child| containment_row(parent).bitwise_and(role_bit(child)) != 0

## Table 5 "<X> shall not contain content items" for Document,
## DocumentFragment, Sect, L, Table, THead, TBody, TFoot, and TR, plus
## PDF/UA-2 8.2.5.25: real content in LI is enclosed in Lbl or LBody.
forbids_content_items : U64 -> Bool
forbids_content_items = |role| role == role_document or role == 1 or role == 3 or role == role_l or role == 10 or role == role_table or role == 22 or role == 23 or role == 24 or role == 25

## Table 5 "<X> shall contain at most one <Y>" rules as child-role masks:
## one generic H in Document, DocumentFragment, Sect, LBody, Figure, Caption,
## TH, and TD; one Sect in H and Hn; one Caption in Title, L, LBody, Figure,
## Link, Code, and Table; and one THead and one TFoot in Table.
at_most_one_children : U64 -> U64
at_most_one_children = |parent| match parent {
	0 => role_bit(6)
	1 => role_bit(6)
	3 => role_bit(6)
	5 => role_bit(role_caption)
	6 => role_bit(3)
	7 => role_bit(3)
	9 => role_bit(role_caption)
	12 => role_bit(6).bitwise_or(role_bit(role_caption))
	13 => role_bit(6).bitwise_or(role_bit(role_caption))
	14 => role_bit(6)
	15 => role_bit(role_caption)
	19 => role_bit(role_caption)
	21 => role_bit(role_caption).bitwise_or(role_bit(22)).bitwise_or(role_bit(24))
	26 => role_bit(6)
	27 => role_bit(6)
	_ => 0
}

valid_role : Semantics.Node, Bool, Bool, Bool -> Bool
valid_role = |node, is_root, text_enabled, navigation| role_enabled(role_index(node.role.local_name), node.role.namespace.index(), is_root, text_enabled, navigation)

mark_attribute_range : Semantics.Range, U64, Bool, List(U8), List(Semantics.StructureAttribute) -> Try({ owners : List(U8), visits : U64 }, KernelSemantics.Error)
mark_attribute_range = |range, owner, contextual, owners, attributes| {
	span = validate_span(range, attributes.len(), AttributeIndex, owner)?
	var $owners = owners
	var $index = span.start
	var $error = NoError
	while $index < span.end and $error == NoError {
		attribute = list_at(attributes, $index)
		if contextual and attribute.owner != Artifact {
			$error = Invalid(InvalidContextualArtifactAttribute({ artifact: owner, attribute: $index }))
		} else if !contextual and attribute.owner == Artifact {
			$error = Invalid(InvalidContextualArtifactAttribute({ artifact: owner, attribute: $index }))
		} else {
			match mark_once($owners, $index, AttributeIndex) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(next) => {
					$owners = next
				}
			}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ owners: $owners, visits: span.end - span.start })
	}
}

mark_index : List(U8), U64, KernelSemantics.IndexKind -> Try(List(U8), KernelSemantics.Error)
mark_index = |owners, index, kind| {
	if index >= owners.len() {
		Err(IndexOutOfRange({ available: owners.len(), index, kind }))
	} else {
		mark_once(owners, index, kind)
	}
}

mark_once : List(U8), U64, KernelSemantics.IndexKind -> Try(List(U8), KernelSemantics.Error)
mark_once = |owners, index, kind| {
	if list_at(owners, index) != 0 {
		Err(DuplicateOwnership({ index, kind }))
	} else {
		Ok(list_set(owners, index, 1))
	}
}

ensure_all_owned : List(U8), KernelSemantics.IndexKind -> Try({}, KernelSemantics.Error)
ensure_all_owned = |owners, kind| {
	var $index = 0
	var $orphan = NoOrphan
	while $index < owners.len() and $orphan == NoOrphan {
		if list_at(owners, $index) == 0 {
			$orphan = Orphan($index)
		}
		$index = $index + 1
	}
	match $orphan {
		NoOrphan => Ok({})
		Orphan(index) => Err(Orphaned({ index, kind }))
	}
}

validate_span : Semantics.Range, U64, KernelSemantics.IndexKind, U64 -> Try({ end : U64, start : U64 }, KernelSemantics.Error)
validate_span = |range, available, kind, owner| {
	start = range.start()
	length = range.length()
	if start > available or length > available - start {
		Err(SpanOutOfRange({ available, kind, length, owner, start }))
	} else {
		Ok({ end: start + length, start })
	}
}

checked_add : U64, U64 -> Try(U64, KernelSemantics.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(_) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

check_limit : U64, U64, KernelSemantics.Dimension -> Try({}, KernelSemantics.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated semantic index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated semantic update escaped"
	}
}

empty_range : Semantics.Range
empty_range = Semantics.Range.from_start_and_length(0, 0)

test_occurrence : U64 -> Semantics.ContentOccurrence
test_occurrence = |index| {
	fragments: empty_range,
	id: Semantics.OccurrenceId.from_index(index),
	language: Inherited,
	source: NonText(Semantics.NonTextSourceId.from_index(index), ByteRange(empty_range)),
	text_properties: empty_range,
}

test_fragment : U64, U64 -> Semantics.LayoutFragment
test_fragment = |index, occurrence| {
	content_stream: Semantics.ContentStreamId.from_index(0),
	continuation_index: index,
	id: Semantics.FragmentId.from_index(index),
	occurrence: Semantics.OccurrenceId.from_index(occurrence),
	page: Semantics.PageId.from_index(0),
	source_range: ByteRange(empty_range),
}

test_store : Semantics.Store
test_store = {
	annotations: [],
	assertions: [],
	attribute_roles: [],
	attributes: [{ applicability: AllRoles, name: Standard("Type"), owner: Artifact, value: Name("Pagination") }],
	content_spine: [ChildNode(Semantics.NodeId.from_index(1)), ContextualArtifact(Semantics.ContextualArtifactId.from_index(0)), ContentOccurrence(Semantics.OccurrenceId.from_index(0)), ContentOccurrence(Semantics.OccurrenceId.from_index(1))],
	contextual_artifacts: [{ attributes: Semantics.Range.from_start_and_length(0, 1), id: Semantics.ContextualArtifactId.from_index(0), parent: Semantics.NodeId.from_index(0) }],
	document_root: Semantics.NodeId.from_index(0),
	fragments: [test_fragment(0, 1), test_fragment(1, 0), test_fragment(2, 0)],
	element_identifiers: [],
	mathml_subtrees: [],
	namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
	nodes: [
		{ attributes: empty_range, content: Semantics.Range.from_start_and_length(0, 2), element_identifier: NoElementIdentifier, id: Semantics.NodeId.from_index(0), language: Inherited, parent: DocumentRoot, role: { local_name: "Document", namespace: Semantics.NamespaceId.from_index(0) }, structure_element: Semantics.StructureElementId.from_index(0), text_properties: empty_range },
		{ attributes: empty_range, content: Semantics.Range.from_start_and_length(2, 2), element_identifier: NoElementIdentifier, id: Semantics.NodeId.from_index(1), language: Inherited, parent: ParentNode(Semantics.NodeId.from_index(0)), role: { local_name: "P", namespace: Semantics.NamespaceId.from_index(0) }, structure_element: Semantics.StructureElementId.from_index(1), text_properties: empty_range },
	],
	non_text_sources: [[], []],
	occurrence_fragments: [],
	occurrences: [test_occurrence(0), test_occurrence(1)],
	relationships: [],
	role_mappings: [],
	text_properties: [],
	text_sources: [],
}

test_limits : KernelSemantics.Limits
test_limits = KernelSemantics.Limits.make({ max_attributes: 1, max_content_spine: 4, max_fragments: 3, max_namespaces: 1, max_nodes: 2, max_occurrences: 2, max_semantic_depth: 2 })

## Counts and prefix sums produce occurrence ranges without sorting fragments.
expect {
	plan = KernelSemantics.Plan.build(test_store, 1, 1, test_limits)?
	store = KernelSemantics.Plan.store(plan)
	first = list_at(store.occurrences, 0).fragments
	second = list_at(store.occurrences, 1).fragments
	actual = List.map(store.occurrence_fragments, |fragment| fragment.index())

	first.start() == 0 and first.length() == 2 and second.start() == 2 and second.length() == 1 and actual == [1, 2, 0]
}

## Semantic work is linear in nodes, content, occurrences, and fragments.
expect {
	plan = KernelSemantics.Plan.build(test_store, 1, 1, test_limits)?
	work = KernelSemantics.Plan.work(plan)

	work.node_visits == 2 and work.content_visits == 4 and work.occurrence_visits == 2 and work.fragment_count_visits == 3 and work.prefix_steps == 2 and work.reverse_writes == 3 and work.max_semantic_depth == 2
}

## The top-level semantic root must be the PDF 2.0 Document role.
expect {
	root = list_at(test_store.nodes, 0)
	nodes = list_set(test_store.nodes, 0, { ..root, role: { ..root.role, local_name: "P" } })
	bad = { ..test_store, nodes }

	match KernelSemantics.Plan.build(bad, 1, 1, test_limits) {
		Err(UnsupportedRole({ node: 0 })) => True
		_ => False
	}
}

## Text authoring adds the grouping, block, inline, list, and table roles
## without widening the tagged-visual subset; unknown, non-root Document, and
## non-PDF-2.0 roles stay unsupported.
expect {
	paragraph = list_at(test_store.nodes, 1)
	with_role = |name| { ..paragraph, role: { ..paragraph.role, local_name: name } }
	text_roles = ["Title", "H2", "LBody", "Span", "Part", "Sect", "Div", "DocumentFragment", "Caption", "Em", "Strong", "Code", "Quote", "Table", "THead", "TBody", "TFoot", "TR", "TH", "TD"]
	text_enabled = text_roles.all(|name| valid_role(with_role(name), False, True, False))
	visual_disabled = text_roles.all(|name| !valid_role(with_role(name), False, False, False))
	foreign = { ..paragraph, role: { local_name: "Sect", namespace: Semantics.NamespaceId.from_index(1) } }

	valid_role(paragraph, False, False, False) and
		text_enabled and
			visual_disabled and
				!valid_role(with_role("Formula"), False, True, False) and
					!valid_role(with_role("H7"), False, True, False) and
						!valid_role(with_role("Document"), False, True, False) and
							!valid_role(foreign, False, True, False)
}

## Fragment occurrence identities are checked before prefix-sum indexing.
expect {
	fragments = list_set(test_store.fragments, 0, { ..test_fragment(0, 1), occurrence: Semantics.OccurrenceId.from_index(2) })
	bad = { ..test_store, fragments }

	match KernelSemantics.Plan.build(bad, 1, 1, test_limits) {
		Err(IndexOutOfRange({ available: 2, index: 2, kind: OccurrenceIndex })) => True
		_ => False
	}
}

## Fragment identities remain dense before any reverse-index write.
expect {
	fragments = list_set(test_store.fragments, 0, { ..test_fragment(0, 1), id: Semantics.FragmentId.from_index(3) })
	bad = { ..test_store, fragments }

	match KernelSemantics.Plan.build(bad, 1, 1, test_limits) {
		Err(NonDenseIdentity({ actual: 3, expected: 0, kind: FragmentIndex })) => True
		_ => False
	}
}

## Fragment content-stream identities are checked before ParentTree planning.
expect {
	fragments = list_set(test_store.fragments, 0, { ..test_fragment(0, 1), content_stream: Semantics.ContentStreamId.from_index(1) })
	bad = { ..test_store, fragments }

	match KernelSemantics.Plan.build(bad, 1, 1, test_limits) {
		Err(IndexOutOfRange({ available: 1, index: 1, kind: FragmentIndex })) => True
		_ => False
	}
}

## Contextual Artifact structure attributes cannot leak onto ordinary nodes.
expect {
	root = list_at(test_store.nodes, 0)
	nodes = list_set(test_store.nodes, 0, { ..root, attributes: Semantics.Range.from_start_and_length(0, 1) })
	artifact = list_at(test_store.contextual_artifacts, 0)
	contextual_artifacts = list_set(test_store.contextual_artifacts, 0, { ..artifact, attributes: empty_range })
	bad = { ..test_store, contextual_artifacts, nodes }

	match KernelSemantics.Plan.build(bad, 1, 1, test_limits) {
		Err(InvalidContextualArtifactAttribute({ artifact: 0, attribute: 0 })) => True
		_ => False
	}
}

navigation_annotation : Semantics.Annotation
navigation_annotation = { id: Semantics.AnnotationId.from_index(0), logical_order: 0, owner: Semantics.NodeId.from_index(1) }

navigation_store : Semantics.Store
navigation_store = {
	..test_store,
	annotations: [navigation_annotation],
	content_spine: [ChildNode(Semantics.NodeId.from_index(1)), ContextualArtifact(Semantics.ContextualArtifactId.from_index(0)), ContentOccurrence(Semantics.OccurrenceId.from_index(0)), ContentOccurrence(Semantics.OccurrenceId.from_index(1)), AnnotationOccurrence(Semantics.AnnotationId.from_index(0))],
	nodes: [
		{ attributes: empty_range, content: Semantics.Range.from_start_and_length(0, 2), element_identifier: NoElementIdentifier, id: Semantics.NodeId.from_index(0), language: Inherited, parent: DocumentRoot, role: { local_name: "Document", namespace: Semantics.NamespaceId.from_index(0) }, structure_element: Semantics.StructureElementId.from_index(0), text_properties: empty_range },
		{ attributes: empty_range, content: Semantics.Range.from_start_and_length(2, 3), element_identifier: NoElementIdentifier, id: Semantics.NodeId.from_index(1), language: Inherited, parent: ParentNode(Semantics.NodeId.from_index(0)), role: { local_name: "Link", namespace: Semantics.NamespaceId.from_index(0) }, structure_element: Semantics.StructureElementId.from_index(1), text_properties: empty_range },
	],
}

navigation_limits : KernelSemantics.Limits
navigation_limits = KernelSemantics.Limits.make({ max_attributes: 1, max_content_spine: 5, max_fragments: 3, max_namespaces: 1, max_nodes: 2, max_occurrences: 2, max_semantic_depth: 2 })

## Navigation-enabled validation accepts annotation spine occurrences with
## exact annotation work, while the plain subset keeps rejecting them.
expect {
	plan = KernelSemantics.Plan.build_navigation(navigation_store, 1, 1, navigation_limits)?
	rejected = match KernelSemantics.Plan.build(navigation_store, 1, 1, navigation_limits) {
		Err(UnsupportedStoreContent) => True
		_ => False
	}

	KernelSemantics.Plan.work(plan).annotation_visits == 2 and rejected
}

## The Link role is accepted only when navigation is enabled.
expect {
	link_node = list_at(navigation_store.nodes, 1)

	valid_role(link_node, False, False, True) and !valid_role(link_node, False, False, False)
}

## An annotation occurrence inside a node other than the annotation's owner
## is a stable ownership rejection.
expect {
	annotations = [{ ..navigation_annotation, owner: Semantics.NodeId.from_index(0) }]
	bad = { ..navigation_store, annotations }

	match KernelSemantics.Plan.build_navigation(bad, 1, 1, navigation_limits) {
		Err(AnnotationOwnerMismatch({ annotation: 0, occurrence_owner: 1, owner: 0 })) => True
		_ => False
	}
}

## Logical order must equal the annotation's rank among spine occurrences.
expect {
	annotations = [{ ..navigation_annotation, logical_order: 3 }]
	bad = { ..navigation_store, annotations }

	match KernelSemantics.Plan.build_navigation(bad, 1, 1, navigation_limits) {
		Err(AnnotationLogicalOrderInvalid({ actual: 3, annotation: 0, expected: 0 })) => True
		_ => False
	}
}

## An annotation without a spine occurrence is orphaned, and one occurring
## twice fails the rank check on its second occurrence (the graph's
## duplicate-ownership check remains as defense in depth behind it).
expect {
	orphan_spine = [ChildNode(Semantics.NodeId.from_index(1)), ContextualArtifact(Semantics.ContextualArtifactId.from_index(0)), ContentOccurrence(Semantics.OccurrenceId.from_index(0)), ContentOccurrence(Semantics.OccurrenceId.from_index(1))]
	orphan_nodes = list_set(navigation_store.nodes, 1, { ..list_at(navigation_store.nodes, 1), content: Semantics.Range.from_start_and_length(2, 2) })
	orphan = { ..navigation_store, content_spine: orphan_spine, nodes: orphan_nodes }

	duplicate_spine = [ChildNode(Semantics.NodeId.from_index(1)), ContextualArtifact(Semantics.ContextualArtifactId.from_index(0)), ContentOccurrence(Semantics.OccurrenceId.from_index(0)), AnnotationOccurrence(Semantics.AnnotationId.from_index(0)), AnnotationOccurrence(Semantics.AnnotationId.from_index(0))]
	duplicate = { ..navigation_store, content_spine: duplicate_spine, occurrences: [test_occurrence(0)], fragments: [test_fragment(0, 0), test_fragment(1, 0), test_fragment(2, 0)] }
	duplicate_limits = KernelSemantics.Limits.make({ max_attributes: 1, max_content_spine: 5, max_fragments: 3, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 })

	orphaned = match KernelSemantics.Plan.build_navigation(orphan, 1, 1, navigation_limits) {
		Err(Orphaned({ index: 0, kind: AnnotationIndex })) => True
		_ => False
	}
	duplicated = match KernelSemantics.Plan.build_navigation(duplicate, 1, 1, duplicate_limits) {
		Err(AnnotationLogicalOrderInvalid({ actual: 0, annotation: 0, expected: 1 })) => True
		_ => False
	}
	orphaned and duplicated
}

## Annotation identities stay dense and owners stay in range.
expect {
	non_dense = { ..navigation_store, annotations: [{ ..navigation_annotation, id: Semantics.AnnotationId.from_index(4) }] }
	bad_owner = { ..navigation_store, annotations: [{ ..navigation_annotation, owner: Semantics.NodeId.from_index(7) }] }

	dense = match KernelSemantics.Plan.build_navigation(non_dense, 1, 1, navigation_limits) {
		Err(NonDenseIdentity({ actual: 4, expected: 0, kind: AnnotationIndex })) => True
		_ => False
	}
	owner = match KernelSemantics.Plan.build_navigation(bad_owner, 1, 1, navigation_limits) {
		Err(IndexOutOfRange({ available: 2, index: 7, kind: NodeIndex })) => True
		_ => False
	}
	dense and owner
}

## A text-subset store whose node `index` has the given role and parent
## (node 0 is the Document root). Every node lists its children in index
## order, and the node named by `owner` also owns one non-text occurrence.
shaped_store : List({ parent : U64, role : Str }), U64 -> Semantics.Store
shaped_store = |shape, owner| {
	var $spine = []
	var $nodes = []
	var $index = 0
	while $index < shape.len() {
		entry = list_at(shape, $index)
		start = $spine.len()
		var $child = 0
		while $child < shape.len() {
			if $child != 0 and list_at(shape, $child).parent == $index {
				$spine = $spine.append(ChildNode(Semantics.NodeId.from_index($child)))
			}
			$child = $child + 1
		}
		if $index == owner {
			$spine = $spine.append(ContentOccurrence(Semantics.OccurrenceId.from_index(0)))
		}
		$nodes = $nodes.append({
			attributes: empty_range,
			content: Semantics.Range.from_start_and_length(start, $spine.len() - start),
			element_identifier: NoElementIdentifier,
			id: Semantics.NodeId.from_index($index),
			language: Inherited,
			parent: if $index == 0 DocumentRoot else ParentNode(Semantics.NodeId.from_index(entry.parent)),
			role: { local_name: entry.role, namespace: Semantics.NamespaceId.from_index(0) },
			structure_element: Semantics.StructureElementId.from_index($index),
			text_properties: empty_range,
		})
		$index = $index + 1
	}
	{
		..test_store,
		attributes: [],
		content_spine: $spine,
		contextual_artifacts: [],
		fragments: [],
		nodes: $nodes,
		non_text_sources: [[]],
		occurrences: [test_occurrence(0)],
	}
}

shaped_limits : KernelSemantics.Limits
shaped_limits = KernelSemantics.Limits.make({ max_attributes: 16, max_content_spine: 64, max_fragments: 0, max_namespaces: 1, max_nodes: 32, max_occurrences: 1, max_semantic_depth: 16 })

build_shaped : Semantics.Store -> Try(KernelSemantics.Plan, KernelSemantics.Error)
build_shaped = |store| KernelSemantics.Plan.build_text_validated(store, [], 1, 1, shaped_limits)

## The containment table: legal and illegal parent/child pairs taken from
## ISO/TS 32005:2023 Table 5, including every grouping pair the facade emits.
expect {
	allows = |parent, child| may_contain(role_index(parent), role_index(child))
	legal = [
		("Document", "Part"),
		("Document", "Sect"),
		("Document", "Div"),
		("Document", "DocumentFragment"),
		("Document", "Title"),
		("Document", "H1"),
		("Document", "P"),
		("Document", "L"),
		("Document", "Figure"),
		("Document", "Link"),
		("Document", "Table"),
		("Part", "Sect"),
		("Part", "Part"),
		("Part", "Span"),
		("Sect", "Sect"),
		("Sect", "Div"),
		("Sect", "Part"),
		("Sect", "H2"),
		("Sect", "P"),
		("Sect", "L"),
		("Sect", "Figure"),
		("Sect", "Table"),
		("Div", "Part"),
		("Div", "TD"),
		("P", "Link"),
		("P", "Span"),
		("P", "Em"),
		("P", "Strong"),
		("P", "Code"),
		("P", "Quote"),
		("Span", "Em"),
		("Quote", "Span"),
		("L", "LI"),
		("L", "L"),
		("L", "Caption"),
		("LI", "Lbl"),
		("LI", "LBody"),
		("LBody", "P"),
		("LBody", "L"),
		("Figure", "Caption"),
		("Table", "Caption"),
		("Table", "THead"),
		("Table", "TBody"),
		("Table", "TFoot"),
		("Table", "TR"),
		("THead", "TR"),
		("TBody", "TR"),
		("TFoot", "TR"),
		("TR", "TH"),
		("TR", "TD"),
		("TD", "P"),
		("TH", "Span"),
		("Caption", "P"),
	]
	illegal = [
		("Sect", "Document"),
		("Sect", "LI"),
		("Sect", "Span"),
		("Document", "Span"),
		("Document", "LI"),
		("Document", "Caption"),
		("Document", "TR"),
		("P", "P"),
		("P", "Sect"),
		("P", "Div"),
		("P", "H1"),
		("Span", "P"),
		("Em", "Sect"),
		("Quote", "P"),
		("H1", "P"),
		("H1", "H2"),
		("Title", "Title"),
		("L", "P"),
		("L", "LBody"),
		("LI", "P"),
		("LI", "LI"),
		("Lbl", "P"),
		("Table", "TD"),
		("Table", "P"),
		("TBody", "TD"),
		("THead", "TH"),
		("TR", "P"),
		("TR", "TR"),
		("TD", "TR"),
		("TD", "Caption"),
		("Link", "Document"),
		("Caption", "Caption"),
		("Figure", "Title"),
	]
	legal.all(|(parent, child)| allows(parent, child)) and illegal.all(|(parent, child)| !allows(parent, child))
}

## Nested grouping elements validate with one containment check per edge.
expect {
	shape = [{ parent: 0, role: "Document" }, { parent: 0, role: "Part" }, { parent: 1, role: "Sect" }, { parent: 2, role: "Div" }, { parent: 3, role: "Sect" }, { parent: 4, role: "H2" }, { parent: 4, role: "P" }]
	plan = build_shaped(shaped_store(shape, 6))?
	work = KernelSemantics.Plan.work(plan)

	work.containment_edges == 6 and work.max_semantic_depth == 6 and work.node_visits == 7
}

## An illegal edge is rejected at the child with its parent, never flattened.
expect {
	shape = [{ parent: 0, role: "Document" }, { parent: 0, role: "P" }, { parent: 1, role: "Sect" }]
	match build_shaped(shaped_store(shape, 1)) {
		Err(IllegalContainment({ child: 2, parent: 1 })) => True
		_ => False
	}
}

## Document, Sect, L, LI, Table, and row groups cannot own content items.
expect {
	sect = shaped_store([{ parent: 0, role: "Document" }, { parent: 0, role: "Sect" }], 1)
	item = shaped_store([{ parent: 0, role: "Document" }, { parent: 0, role: "L" }, { parent: 1, role: "LI" }], 2)
	part = shaped_store([{ parent: 0, role: "Document" }, { parent: 0, role: "Part" }], 1)
	sect_rejected = match build_shaped(sect) {
		Err(IllegalContentItem({ content: 1, node: 1 })) => True
		_ => False
	}
	item_rejected = match build_shaped(item) {
		Err(IllegalContentItem({ content: 2, node: 2 })) => True
		_ => False
	}
	part_accepted = match build_shaped(part) {
		Ok(_) => True
		Err(_) => False
	}
	sect_rejected and item_rejected and part_accepted
}

## At-most-one child rules and the first-or-last Caption rule.
expect {
	two_heads = shaped_store([{ parent: 0, role: "Document" }, { parent: 0, role: "Table" }, { parent: 1, role: "THead" }, { parent: 1, role: "THead" }, { parent: 2, role: "TR" }, { parent: 4, role: "TD" }], 5)
	middle_caption = shaped_store([{ parent: 0, role: "Document" }, { parent: 0, role: "Table" }, { parent: 1, role: "TR" }, { parent: 1, role: "Caption" }, { parent: 1, role: "TR" }, { parent: 2, role: "TD" }], 5)
	last_caption = shaped_store([{ parent: 0, role: "Document" }, { parent: 0, role: "Table" }, { parent: 1, role: "TR" }, { parent: 1, role: "Caption" }, { parent: 2, role: "TD" }], 4)
	duplicate = match build_shaped(two_heads) {
		Err(DuplicateChildRole({ child: 3, parent: 1 })) => True
		_ => False
	}
	middle = match build_shaped(middle_caption) {
		Err(CaptionPosition({ caption: 3, parent: 1 })) => True
		_ => False
	}
	last = match build_shaped(last_caption) {
		Ok(_) => True
		Err(_) => False
	}
	duplicate and middle and last
}

## A header/data table fixture with element identifiers, typed Table
## attributes, and a typed header relationship.
table_store : Semantics.Store
table_store = {
	store = shaped_store([{ parent: 0, role: "Document" }, { parent: 0, role: "Table" }, { parent: 1, role: "TR" }, { parent: 2, role: "TH" }, { parent: 2, role: "TD" }], 4)
	header = list_at(store.nodes, 3)
	cell = list_at(store.nodes, 4)
	nodes = list_set(
		list_set(store.nodes, 3, { ..header, attributes: Semantics.Range.from_start_and_length(0, 1), element_identifier: HasElementIdentifier(Semantics.ElementId.from_index(1)) }),
		4,
		{ ..cell, attributes: Semantics.Range.from_start_and_length(1, 1), element_identifier: HasElementIdentifier(Semantics.ElementId.from_index(0)), language: Language("fr-CA") },
	)
	{
		..store,
		attributes: [
			{ applicability: Family(TableRoles), name: Standard("Scope"), owner: Table, value: Name("Column") },
			{ applicability: Family(TableRoles), name: Standard("Headers"), owner: Table, value: Names(["hdr"]) },
		],
		element_identifiers: [{ id: Semantics.ElementId.from_index(0), value: "cell" }, { id: Semantics.ElementId.from_index(1), value: "hdr" }],
		nodes,
		relationships: [HeaderFor({ cell: Semantics.ElementId.from_index(0), header: Semantics.ElementId.from_index(1) })],
	}
}

expect {
	plan = build_shaped(table_store)?
	work = KernelSemantics.Plan.work(plan)

	work.identifier_visits == 2 and work.relationship_visits == 1 and work.attribute_visits == 5
}

## Element identifiers are unique, ordered, non-empty, and owned exactly once.
expect {
	duplicate = { ..table_store, element_identifiers: [{ id: Semantics.ElementId.from_index(0), value: "hdr" }, { id: Semantics.ElementId.from_index(1), value: "hdr" }] }
	unordered = { ..table_store, element_identifiers: [{ id: Semantics.ElementId.from_index(0), value: "zz" }, { id: Semantics.ElementId.from_index(1), value: "hdr" }], attributes: [] }
	orphan = { ..table_store, element_identifiers: table_store.element_identifiers.append({ id: Semantics.ElementId.from_index(2), value: "orphan" }) }
	empty = { ..table_store, element_identifiers: [{ id: Semantics.ElementId.from_index(0), value: "" }, { id: Semantics.ElementId.from_index(1), value: "hdr" }] }
	stripped = |store| { ..store, attributes: [], nodes: store.nodes.map(|node| { ..node, attributes: empty_range }), relationships: [] }

	duplicated = match build_shaped(duplicate) {
		Err(DuplicateElementIdentifier({ first: 0, second: 1 })) => True
		_ => False
	}
	ordered = match build_shaped(stripped(unordered)) {
		Err(ElementIdentifierOrder({ element: 1 })) => True
		_ => False
	}
	orphaned = match build_shaped(orphan) {
		Err(Orphaned({ index: 2, kind: ElementIdentifierIndex })) => True
		_ => False
	}
	nonempty = match build_shaped(stripped(empty)) {
		Err(EmptyElementIdentifier({ element: 0 })) => True
		_ => False
	}
	duplicated and ordered and orphaned and nonempty
}

## Dangling `/Headers` targets, mistyped attributes, and ill-typed relations.
expect {
	dangling = { ..table_store, attributes: list_set(table_store.attributes, 1, { applicability: Family(TableRoles), name: Standard("Headers"), owner: Table, value: Names(["missing"]) }) }
	scope_on_cell = { ..table_store, attributes: list_set(table_store.attributes, 1, { applicability: Family(TableRoles), name: Standard("Scope"), owner: Table, value: Name("Row") }) }
	bad_scope = { ..table_store, attributes: list_set(table_store.attributes, 0, { applicability: Family(TableRoles), name: Standard("Scope"), owner: Table, value: Name("Diagonal") }) }
	list_owned = { ..table_store, attributes: list_set(table_store.attributes, 0, { applicability: Family(ListRoles), name: Standard("ListNumbering"), owner: List, value: Name("Disc") }) }
	reversed = { ..table_store, relationships: [HeaderFor({ cell: Semantics.ElementId.from_index(1), header: Semantics.ElementId.from_index(0) })] }
	out_of_range = { ..table_store, relationships: [HeaderFor({ cell: Semantics.ElementId.from_index(0), header: Semantics.ElementId.from_index(7) })] }
	caption = { ..table_store, relationships: [CaptionFor({ caption: Semantics.NodeId.from_index(3), target: Semantics.NodeId.from_index(1) })] }
	note = { ..table_store, relationships: [NoteFor({ note: Semantics.NodeId.from_index(3), target: Semantics.NodeId.from_index(1) })] }

	checks = [
		match build_shaped(dangling) {
			Err(UnknownAttributeTarget({ attribute: 1, node: 4 })) => True
			_ => False
		},
		match build_shaped(scope_on_cell) {
			Err(InvalidAttribute({ attribute: 1, node: 4 })) => True
			_ => False
		},
		match build_shaped(bad_scope) {
			Err(InvalidAttribute({ attribute: 0, node: 3 })) => True
			_ => False
		},
		match build_shaped(list_owned) {
			Err(InvalidAttribute({ attribute: 0, node: 3 })) => True
			_ => False
		},
		match build_shaped(reversed) {
			Err(InvalidRelationship({ relationship: 0 })) => True
			_ => False
		},
		match build_shaped(out_of_range) {
			Err(InvalidRelationship({ relationship: 0 })) => True
			_ => False
		},
		match build_shaped(caption) {
			Err(InvalidRelationship({ relationship: 0 })) => True
			_ => False
		},
		match build_shaped(note) {
			Err(InvalidRelationship({ relationship: 0 })) => True
			_ => False
		},
	]
	checks.all(|passed| passed)
}

## A Caption relation names a Caption inside, or beside, an element that may
## contain one; ListNumbering is typed on L.
expect {
	store = shaped_store([{ parent: 0, role: "Document" }, { parent: 0, role: "Figure" }, { parent: 1, role: "Caption" }, { parent: 0, role: "L" }, { parent: 3, role: "LI" }, { parent: 4, role: "LBody" }], 2)
	list_node = list_at(store.nodes, 3)
	captioned = {
		..store,
		attributes: [{ applicability: Family(ListRoles), name: Standard("ListNumbering"), owner: List, value: Name("Disc") }],
		nodes: list_set(store.nodes, 3, { ..list_node, attributes: Semantics.Range.from_start_and_length(0, 1) }),
		relationships: [CaptionFor({ caption: Semantics.NodeId.from_index(2), target: Semantics.NodeId.from_index(1) })],
	}
	bad_numbering = { ..captioned, attributes: [{ applicability: Family(ListRoles), name: Standard("ListNumbering"), owner: List, value: Name("Bullets") }] }
	accepted = match build_shaped(captioned) {
		Ok(_) => True
		Err(_) => False
	}
	rejected = match build_shaped(bad_numbering) {
		Err(InvalidAttribute({ attribute: 0, node: 3 })) => True
		_ => False
	}
	accepted and rejected
}

## Nested languages must be well-formed tags; node text properties are
## limited to one each of ActualText, Alt, and E.
expect {
	cell = list_at(table_store.nodes, 4)
	bad_language = { ..table_store, nodes: list_set(table_store.nodes, 4, { ..cell, language: Language("fr_CA") }) }
	with_properties = |properties| {
		..table_store,
		nodes: list_set(table_store.nodes, 4, { ..cell, text_properties: Semantics.Range.from_start_and_length(0, properties.len()) }),
		text_properties: properties,
	}
	language = match build_shaped(bad_language) {
		Err(InvalidLanguage({ node: 4 })) => True
		_ => False
	}
	accepted = match build_shaped(with_properties([ActualText("cell"), AlternativeText("A cell"), ExpandedText("the cell")])) {
		Ok(_) => True
		Err(_) => False
	}
	phoneme = match build_shaped(with_properties([Phoneme("sel")])) {
		Err(InvalidNodeTextProperty({ node: 4, property: 0 })) => True
		_ => False
	}
	twice = match build_shaped(with_properties([AlternativeText("A"), AlternativeText("B")])) {
		Err(InvalidNodeTextProperty({ node: 4, property: 1 })) => True
		_ => False
	}
	language and accepted and phoneme and twice and valid_language_tag("en-AU") and valid_language_tag("zh-Hant-TW") and !valid_language_tag("en--AU") and !valid_language_tag("1en") and !valid_language_tag("toolongtag")
}

## A language repeated from the nearest explicit ancestor is inherited and
## needs no second check; a differing nested language is validated.
expect {
	store = shaped_store([{ parent: 0, role: "Document" }, { parent: 0, role: "P" }, { parent: 1, role: "Span" }, { parent: 2, role: "Em" }], 3)
	with_languages = |span, emphasis| {
		..store,
		nodes: list_set(list_set(store.nodes, 2, { ..list_at(store.nodes, 2), language: Language(span) }), 3, { ..list_at(store.nodes, 3), language: Language(emphasis) }),
	}
	repeated = match build_shaped(with_languages("fr-CA", "fr-CA")) {
		Ok(_) => True
		Err(_) => False
	}
	nested = match build_shaped(with_languages("fr-CA", "fr")) {
		Ok(_) => True
		Err(_) => False
	}
	malformed = match build_shaped(with_languages("fr-CA", "fr_CA")) {
		Err(InvalidLanguage({ node: 3 })) => True
		_ => False
	}
	repeated and nested and malformed and repeats_language(with_languages("fr-CA", "fr-CA"), 2, "fr-CA") and !repeats_language(store, U64.highest, "fr-CA")
}
