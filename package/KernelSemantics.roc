import Semantics

KernelSemantics :: [].{
	Dimension : [Attributes, ContentSpine, Fragments, Namespaces, Nodes, Occurrences, SemanticDepth]
	IndexKind : [AttributeIndex, ContentIndex, ContextualArtifactIndex, FragmentIndex, NamespaceIndex, NodeIndex, NonTextSourceIndex, OccurrenceIndex, StructureElementIndex, TextSourceIndex]
	Error : [
		ArithmeticOverflow,
		DuplicateOwnership({ index : U64, kind : IndexKind }),
		FragmentRangeOutsideOccurrence({ fragment : U64 }),
		IndexOutOfRange({ available : U64, index : U64, kind : IndexKind }),
		InvalidContextualArtifactAttribute({ artifact : U64, attribute : U64 }),
		InvalidDocumentRoot({ node : U64 }),
		InvalidParent({ actual : U64, expected : U64, node : U64 }),
		InvalidPdf20Namespace,
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		NonDenseIdentity({ actual : U64, expected : U64, kind : IndexKind }),
		Orphaned({ index : U64, kind : IndexKind }),
		SpanOutOfRange({ available : U64, kind : IndexKind, length : U64, owner : U64, start : U64 }),
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
		attribute_visits : U64,
		content_visits : U64,
		fragment_count_visits : U64,
		fragment_validation_visits : U64,
		max_semantic_depth : U64,
		namespace_visits : U64,
		node_visits : U64,
		occurrence_visits : U64,
		prefix_steps : U64,
		reverse_writes : U64,
	}

	Plan :: { content_stream_count : U64, page_count : U64, store : Semantics.Store, work : Work }.{
		build : Semantics.Store, U64, U64, Limits -> Try(Plan, Error)
		build = |store, page_count, content_stream_count, limits| build_plan(store, page_count, content_stream_count, limits)

		build_text_validated : Semantics.Store, List(TextSourceFact), U64, U64, Limits -> Try(Plan, Error)
		build_text_validated = |store, text_source_facts, page_count, content_stream_count, limits| build_text_plan(store, text_source_facts, page_count, content_stream_count, limits)

		content_stream_count : Plan -> U64
		content_stream_count = |plan| plan.content_stream_count

		page_count : Plan -> U64
		page_count = |plan| plan.page_count

		store : Plan -> Semantics.Store
		store = |plan| plan.store

		work : Plan -> Work
		work = |plan| plan.work
	}

}

NodeFrame := { depth : U64, node : Semantics.NodeId }

build_plan : Semantics.Store, U64, U64, KernelSemantics.Limits -> Try(KernelSemantics.Plan, KernelSemantics.Error)
build_plan = |store, page_count, content_stream_count, limits| {
	validate_gate_2_subset(store)?
	check_limit(store.attributes.len(), limits.max_attributes, Attributes)?
	check_limit(store.content_spine.len(), limits.max_content_spine, ContentSpine)?
	check_limit(store.fragments.len(), limits.max_fragments, Fragments)?
	check_limit(store.namespaces.len(), limits.max_namespaces, Namespaces)?
	check_limit(store.nodes.len(), limits.max_nodes, Nodes)?
	check_limit(store.occurrences.len(), limits.max_occurrences, Occurrences)?

	namespace_work = validate_namespaces(store.namespaces)?
	occurrence_work = validate_occurrences(store, [], False)?
	fragment_work = validate_fragments(store, [], page_count, content_stream_count)?
	reverse = build_reverse_index(store.occurrences, store.fragments)?
	normalized = { ..store, occurrence_fragments: reverse.fragment_ids, occurrences: reverse.occurrences }
	graph_work = validate_graph(normalized, limits.max_semantic_depth, False)?

	Ok(
		KernelSemantics.Plan.{
			content_stream_count,
			page_count,
			store: normalized,
			work: {
				attribute_visits: graph_work.attribute_visits,
				content_visits: graph_work.content_visits,
				fragment_count_visits: reverse.count_visits,
				fragment_validation_visits: fragment_work,
				max_semantic_depth: graph_work.max_depth,
				namespace_visits: namespace_work,
				node_visits: graph_work.node_visits,
				occurrence_visits: occurrence_work,
				prefix_steps: reverse.prefix_steps,
				reverse_writes: reverse.reverse_writes,
			},
		},
	)
}

build_text_plan : Semantics.Store, List(KernelSemantics.TextSourceFact), U64, U64, KernelSemantics.Limits -> Try(KernelSemantics.Plan, KernelSemantics.Error)
build_text_plan = |store, text_source_facts, page_count, content_stream_count, limits| {
	validate_text_subset(store)?
	check_limit(store.attributes.len(), limits.max_attributes, Attributes)?
	check_limit(store.content_spine.len(), limits.max_content_spine, ContentSpine)?
	check_limit(store.fragments.len(), limits.max_fragments, Fragments)?
	check_limit(store.namespaces.len(), limits.max_namespaces, Namespaces)?
	check_limit(store.nodes.len(), limits.max_nodes, Nodes)?
	check_limit(store.occurrences.len(), limits.max_occurrences, Occurrences)?

	namespace_work = validate_namespaces(store.namespaces)?
	occurrence_work = validate_occurrences(store, text_source_facts, True)?
	fragment_work = validate_fragments(store, text_source_facts, page_count, content_stream_count)?
	reverse = build_reverse_index(store.occurrences, store.fragments)?
	normalized = { ..store, occurrence_fragments: reverse.fragment_ids, occurrences: reverse.occurrences }
	graph_work = validate_graph(normalized, limits.max_semantic_depth, True)?
	Ok(
		KernelSemantics.Plan.{
			content_stream_count,
			page_count,
			store: normalized,
			work: {
				attribute_visits: graph_work.attribute_visits,
				content_visits: graph_work.content_visits,
				fragment_count_visits: reverse.count_visits,
				fragment_validation_visits: fragment_work,
				max_semantic_depth: graph_work.max_depth,
				namespace_visits: namespace_work,
				node_visits: graph_work.node_visits,
				occurrence_visits: occurrence_work,
				prefix_steps: reverse.prefix_steps,
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

validate_gate_2_subset : Semantics.Store -> Try({}, KernelSemantics.Error)
validate_gate_2_subset = |store| {
	validate_text_subset(store)?
	if !store.text_properties.is_empty() or !store.text_sources.is_empty() {
		Err(UnsupportedStoreContent)
	} else {
		Ok({})
	}
}

validate_text_subset : Semantics.Store -> Try({}, KernelSemantics.Error)
validate_text_subset = |store| {
	if !store.annotations.is_empty() or
		!store.assertions.is_empty() or
			!store.attribute_roles.is_empty() or
				!store.element_identifiers.is_empty() or
					!store.mathml_subtrees.is_empty() or
						!store.relationships.is_empty() or
							!store.role_mappings.is_empty() {
		Err(UnsupportedStoreContent)
	} else {
		Ok({})
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

validate_graph : Semantics.Store, U64, Bool -> Try({ attribute_visits : U64, content_visits : U64, max_depth : U64, node_visits : U64 }, KernelSemantics.Error)
validate_graph = |store, max_depth, text_allowed| {
	if store.nodes.len() == 0 or store.document_root.index() >= store.nodes.len() {
		Err(InvalidDocumentRoot({ node: store.document_root.index() }))
	} else {
		identity_check = validate_dense_graph_identities(store)?
		_ = identity_check
		var $node_owners = List.repeat(0, store.nodes.len())
		var $content_owners = List.repeat(0, store.content_spine.len())
		var $occurrence_owners = List.repeat(0, store.occurrences.len())
		var $artifact_owners = List.repeat(0, store.contextual_artifacts.len())
		var $attribute_owners = List.repeat(0, store.attributes.len())
		var $frames = [NodeFrame.{ depth: 1, node: store.document_root }]
		var $frame_index = 0
		var $content_visits = 0
		var $attribute_visits = 0
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
					if !valid_role(node, node_index == store.document_root.index(), text_allowed) {
						$error = Invalid(UnsupportedRole({ node: node_index }))
					} else if (node.text_properties.length() != 0 and !text_allowed) or node.element_identifier != NoElementIdentifier {
						$error = Invalid(UnsupportedStoreContent)
					} else if node_index == store.document_root.index() and node.parent != DocumentRoot {
						$error = Invalid(InvalidDocumentRoot({ node: node_index }))
					} else {
						$maximum_depth = U64.max($maximum_depth, frame.depth)
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
										while $content_index < span.end and $error == NoError {
											if list_at($content_owners, $content_index) != 0 {
												$error = Invalid(DuplicateOwnership({ index: $content_index, kind: ContentIndex }))
											} else {
												$content_owners = list_set($content_owners, $content_index, 1)
												item = list_at(store.content_spine, $content_index)
												match item {
													AnnotationOccurrence(_) => {
														$error = Invalid(UnsupportedAnnotation({ content: $content_index }))
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
																	depth = U64.plus_try(frame.depth, 1) ? |_| ArithmeticOverflow
																	$frames = $frames.append(NodeFrame.{ depth, node: child })
																}
															}
														}
													}
													ContentOccurrence(occurrence) => {
														occurrence_index = occurrence.index()
														if occurrence_index >= $occurrence_owners.len() {
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
				ensure_all_owned($artifact_owners, ContextualArtifactIndex)?
				ensure_all_owned($attribute_owners, AttributeIndex)?
				Ok({ attribute_visits: $attribute_visits, content_visits: $content_visits, max_depth: $maximum_depth, node_visits: $node_visits })
			}
		}
	}
}

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

valid_role : Semantics.Node, Bool, Bool -> Bool
valid_role = |node, is_root, gate_3_text| {
	if node.role.namespace.index() != 0 {
		False
	} else if is_root {
		node.role.local_name == "Document"
	} else if gate_3_text {
		name = node.role.local_name
		name == "Title" or
			name == "P" or
				name == "H" or
					name == "H1" or
						name == "H2" or
							name == "H3" or
								name == "H4" or
									name == "H5" or
										name == "H6" or
											name == "L" or
												name == "LI" or
													name == "Lbl" or
														name == "LBody"
	} else {
		node.role.local_name == "P"
	}
}

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

## Gate 3 text authoring adds block roles without widening the Gate 2 subset.
expect {
	paragraph = list_at(test_store.nodes, 1)
	title = { ..paragraph, role: { ..paragraph.role, local_name: "Title" } }
	heading = { ..paragraph, role: { ..paragraph.role, local_name: "H2" } }
	list_body = { ..paragraph, role: { ..paragraph.role, local_name: "LBody" } }
	span = { ..paragraph, role: { ..paragraph.role, local_name: "Span" } }

	valid_role(paragraph, False, False) and
		!valid_role(title, False, False) and
			!valid_role(heading, False, False) and
				valid_role(title, False, True) and
					valid_role(heading, False, True) and
						valid_role(list_body, False, True) and
							!valid_role(span, False, True)
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
