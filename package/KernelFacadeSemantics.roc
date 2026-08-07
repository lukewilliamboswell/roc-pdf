import Document
import KernelFacadeSources
import KernelSemantics
import KernelTextSemantics
import Semantics

KernelFacadeSemantics :: [].{
	Dimension : [Artifacts, ContentSpine, Nodes, Occurrences, Properties, SourceInputs]
	Error : [
		ArithmeticOverflow,
		EmptyLanguage,
		EmptyMetadataTitle,
		InvalidList({ block : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		Source(KernelFacadeSources.Error),
		TextSemantics(KernelTextSemantics.Error),
		UnsupportedHeadingLevel({ block : U64, level : U8 }),
	]
	Limits :: {
		max_artifacts : U64,
		max_content_spine : U64,
		max_nodes : U64,
		max_occurrences : U64,
		max_properties : U64,
		max_source_inputs : U64,
		semantics : KernelSemantics.Limits,
		sources : KernelFacadeSources.Limits,
		text_semantics : KernelTextSemantics.Limits,
	}.{
		make : {
			max_artifacts : U64,
			max_content_spine : U64,
			max_nodes : U64,
			max_occurrences : U64,
			max_properties : U64,
			max_source_inputs : U64,
			semantics : KernelSemantics.Limits,
			sources : KernelFacadeSources.Limits,
			text_semantics : KernelTextSemantics.Limits,
		} -> Limits
		make = |limits| Limits.(limits)
	}
	Artifact : { block : U64, kind : Document.PageArtifactKind, text : Str }
	BlockOwnership : [ArtifactBlock(U64), TextBlock({ body : Semantics.OccurrenceId, label : [Label(Semantics.OccurrenceId), NoLabel] })]
	Work : {
		artifacts : U64,
		content_writes : U64,
		list_items : U64,
		lists : U64,
		node_writes : U64,
		occurrence_writes : U64,
		property_writes : U64,
		source_inputs : U64,
	}
	Plan :: {
		artifacts : List(Artifact),
		authoring : Document.NormalizedAuthoring,
		block_ownership : List(BlockOwnership),
		preliminary : KernelTextSemantics.Plan,
		sources : KernelFacadeSources.Plan,
		work : Work,
	}.{
		build : Document.NormalizedAuthoring, Limits -> Try(Plan, Error)
		build = |authoring, limits| build_plan(authoring, limits)

		artifacts : Plan -> List(Artifact)
		artifacts = |plan| plan.artifacts

		authoring : Plan -> Document.NormalizedAuthoring
		authoring = |plan| plan.authoring

		block_ownership : Plan -> List(BlockOwnership)
		block_ownership = |plan| plan.block_ownership

		preliminary : Plan -> KernelTextSemantics.Plan
		preliminary = |plan| plan.preliminary

		sources : Plan -> KernelFacadeSources.Plan
		sources = |plan| plan.sources

		work : Plan -> Work
		work = |plan| plan.work
	}
}

ListState : [ActiveList({ expected_item : U64, list : U64, node : U64 }), NoActiveList]

Planning : {
	artifacts : List(KernelFacadeSemantics.Artifact),
	content_count : U64,
	list_count : U64,
	list_item_count : U64,
	node_count : U64,
	occurrence_count : U64,
	property_count : U64,
	source_inputs : List(Str),
	top_nodes : List(Semantics.NodeId),
}

build_plan : Document.NormalizedAuthoring, KernelFacadeSemantics.Limits -> Try(KernelFacadeSemantics.Plan, KernelFacadeSemantics.Error)
build_plan = |authoring, limits| {
	if authoring.language.is_empty() {
		return Err(EmptyLanguage)
	}
	if authoring.metadata_title.is_empty() {
		return Err(EmptyMetadataTitle)
	}
	planning = plan_blocks(authoring.blocks, limits)?
	sources = KernelFacadeSources.Plan.build(planning.source_inputs, limits.sources) ? Source
	built = build_store(authoring.language, authoring.blocks, planning, sources)?
	check_limit(built.store.content_spine.len(), limits.max_content_spine, ContentSpine)?
	check_limit(built.store.text_properties.len(), limits.max_properties, Properties)?
	preliminary = KernelTextSemantics.Plan.build(built.store, 0, 0, limits.semantics, limits.text_semantics) ? TextSemantics
	Ok(
		KernelFacadeSemantics.Plan.{
			artifacts: planning.artifacts,
			authoring,
			block_ownership: built.block_ownership,
			preliminary,
			sources,
			work: {
				artifacts: planning.artifacts.len(),
				content_writes: built.store.content_spine.len(),
				list_items: planning.list_item_count,
				lists: planning.list_count,
				node_writes: built.store.nodes.len(),
				occurrence_writes: built.store.occurrences.len(),
				property_writes: built.store.text_properties.len(),
				source_inputs: planning.source_inputs.len(),
			},
		},
	)
}

plan_blocks : List(Document.NormalizedBlock), KernelFacadeSemantics.Limits -> Try(Planning, KernelFacadeSemantics.Error)
plan_blocks = |blocks, limits| {
	source_bound = if blocks.len() > U64.highest / 2 U64.highest else blocks.len() * 2
	var $artifacts = List.with_capacity(U64.min(blocks.len(), limits.max_artifacts))
	var $sources = List.with_capacity(U64.min(source_bound, limits.max_source_inputs))
	var $top_nodes = List.with_capacity(U64.min(blocks.len(), limits.max_nodes))
	var $content_count = 0
	var $list_count = 0
	var $list_item_count = 0
	var $next_node = 1
	var $next_occurrence = 0
	var $property_count = 0
	var $next_list = 0
	var $list_state = NoActiveList
	var $block_index = 0
	check_limit($next_node, limits.max_nodes, Nodes)?
	while $block_index < blocks.len() {
		block = list_at(blocks, $block_index)
		match block.kind {
			PageArtifact(kind) => {
				artifact_count = checked_add($artifacts.len(), 1)?
				check_limit(artifact_count, limits.max_artifacts, Artifacts)?
				$artifacts = $artifacts.append({ block: $block_index, kind, text: block.text })
				$list_state = NoActiveList
			}
			Bullet({ item, list }) => {
				node_increment = if item == 0 4 else 3
				content_increment = if item == 0 6 else 5
				attempted_nodes = checked_add($next_node, node_increment)?
				attempted_occurrences = checked_add($next_occurrence, 2)?
				attempted_content = checked_add($content_count, content_increment)?
				attempted_properties = checked_add($property_count, 1)?
				attempted_sources = checked_add($sources.len(), 2)?
				check_limit(attempted_nodes, limits.max_nodes, Nodes)?
				check_limit(attempted_occurrences, limits.max_occurrences, Occurrences)?
				check_limit(attempted_content, limits.max_content_spine, ContentSpine)?
				check_limit(attempted_properties, limits.max_properties, Properties)?
				check_limit(attempted_sources, limits.max_source_inputs, SourceInputs)?
				_list_node = if item == 0 {
					if list != $next_list {
						return Err(InvalidList({ block: $block_index }))
					}
					node = $next_node
					$next_node = checked_add($next_node, 1)?
					$next_list = checked_add($next_list, 1)?
					$list_count = checked_add($list_count, 1)?
					$top_nodes = $top_nodes.append(Semantics.NodeId.from_index(node))
					$list_state = ActiveList({ expected_item: 1, list, node })
					node
				} else {
					match $list_state {
						ActiveList(state) => if state.list == list and state.expected_item == item {
							$list_state = ActiveList({ ..state, expected_item: checked_add(item, 1)? })
							state.node
						} else {
							return Err(InvalidList({ block: $block_index }))
						}
						NoActiveList => return Err(InvalidList({ block: $block_index }))
					}
				}
				item_node = $next_node
				$next_node = checked_add(item_node, 3)?
				label_occurrence = $next_occurrence
				$next_occurrence = checked_add(label_occurrence, 2)?
				$content_count = attempted_content
				$property_count = attempted_properties
				$list_item_count = checked_add($list_item_count, 1)?
				$sources = $sources.append("•").append(block.text)
			}
			Heading(level) => {
				_role = heading_role(level, $block_index)?
				attempted_nodes = checked_add($next_node, 1)?
				attempted_occurrences = checked_add($next_occurrence, 1)?
				attempted_content = checked_add($content_count, 2)?
				attempted_sources = checked_add($sources.len(), 1)?
				check_limit(attempted_nodes, limits.max_nodes, Nodes)?
				check_limit(attempted_occurrences, limits.max_occurrences, Occurrences)?
				check_limit(attempted_content, limits.max_content_spine, ContentSpine)?
				check_limit(attempted_sources, limits.max_source_inputs, SourceInputs)?
				$top_nodes = $top_nodes.append(Semantics.NodeId.from_index($next_node))
				$sources = $sources.append(block.text)
				$next_node = checked_add($next_node, 1)?
				$next_occurrence = checked_add($next_occurrence, 1)?
				$content_count = attempted_content
				$list_state = NoActiveList
			}
			Paragraph | Title => {
				attempted_nodes = checked_add($next_node, 1)?
				attempted_occurrences = checked_add($next_occurrence, 1)?
				attempted_content = checked_add($content_count, 2)?
				attempted_sources = checked_add($sources.len(), 1)?
				check_limit(attempted_nodes, limits.max_nodes, Nodes)?
				check_limit(attempted_occurrences, limits.max_occurrences, Occurrences)?
				check_limit(attempted_content, limits.max_content_spine, ContentSpine)?
				check_limit(attempted_sources, limits.max_source_inputs, SourceInputs)?
				$top_nodes = $top_nodes.append(Semantics.NodeId.from_index($next_node))
				$sources = $sources.append(block.text)
				$next_node = checked_add($next_node, 1)?
				$next_occurrence = checked_add($next_occurrence, 1)?
				$content_count = attempted_content
				$list_state = NoActiveList
			}
		}
		$block_index = $block_index + 1
	}
	Ok({ artifacts: $artifacts, content_count: $content_count, list_count: $list_count, list_item_count: $list_item_count, node_count: $next_node, occurrence_count: $next_occurrence, property_count: $property_count, source_inputs: $sources, top_nodes: $top_nodes })
}

heading_role : U8, U64 -> Try(Str, KernelFacadeSemantics.Error)
heading_role = |level, block| match level {
	1 => Ok("H1")
	2 => Ok("H2")
	3 => Ok("H3")
	4 => Ok("H4")
	5 => Ok("H5")
	6 => Ok("H6")
	_ => Err(UnsupportedHeadingLevel({ block, level }))
}

build_store : Str, List(Document.NormalizedBlock), Planning, KernelFacadeSources.Plan -> Try({ block_ownership : List(KernelFacadeSemantics.BlockOwnership), store : Semantics.Store }, KernelFacadeSemantics.Error)
build_store = |language, blocks, planning, source_plan| {
	var $content = List.with_capacity(planning.content_count)
	for node in planning.top_nodes {
		$content = $content.append(ChildNode(node))
	}
	empty = Semantics.Range.from_start_and_length(0, 0)
	dummy = make_node(0, DocumentRoot, "Document", empty, Language(language))
	var $nodes = List.repeat(dummy, planning.node_count)
	$nodes = list_set($nodes, 0, make_node(0, DocumentRoot, "Document", Semantics.Range.from_start_and_length(0, planning.top_nodes.len()), Language(language)))
	var $occurrences = List.with_capacity(planning.occurrence_count)
	var $properties = List.with_capacity(planning.property_count)
	var $ownership = List.repeat(ArtifactBlock(0), blocks.len())
	var $artifact = 0
	var $index = 0
	var $next_node = 1
	var $next_occurrence = 0
	var $source_input = 0
	while $index < blocks.len() {
		block = list_at(blocks, $index)
		match block.kind {
			PageArtifact(_) => {
				$ownership = list_set($ownership, $index, ArtifactBlock($artifact))
				$artifact = checked_add($artifact, 1)?
				$index = $index + 1
			}
			Heading(level) => {
				role = heading_role(level, $index)?
				start = $content.len()
				$content = $content.append(ContentOccurrence(Semantics.OccurrenceId.from_index($next_occurrence)))
				$nodes = list_set($nodes, $next_node, make_node($next_node, ParentNode(Semantics.NodeId.from_index(0)), role, Semantics.Range.from_start_and_length(start, 1), Inherited))
				$occurrences = $occurrences.append(make_occurrence($next_occurrence, $source_input, source_plan, language, empty))
				$ownership = list_set($ownership, $index, TextBlock({ body: Semantics.OccurrenceId.from_index($next_occurrence), label: NoLabel }))
				$next_node = checked_add($next_node, 1)?
				$next_occurrence = checked_add($next_occurrence, 1)?
				$source_input = checked_add($source_input, 1)?
				$index = $index + 1
			}
			Paragraph | Title => {
				role = match block.kind {
					Paragraph => "P"
					Title => "Title"
					_ => ""
				}
				start = $content.len()
				$content = $content.append(ContentOccurrence(Semantics.OccurrenceId.from_index($next_occurrence)))
				$nodes = list_set($nodes, $next_node, make_node($next_node, ParentNode(Semantics.NodeId.from_index(0)), role, Semantics.Range.from_start_and_length(start, 1), Inherited))
				$occurrences = $occurrences.append(make_occurrence($next_occurrence, $source_input, source_plan, language, empty))
				$ownership = list_set($ownership, $index, TextBlock({ body: Semantics.OccurrenceId.from_index($next_occurrence), label: NoLabel }))
				$next_node = checked_add($next_node, 1)?
				$next_occurrence = checked_add($next_occurrence, 1)?
				$source_input = checked_add($source_input, 1)?
				$index = $index + 1
			}
			Bullet({ item, list }) => {
				if item != 0 {
					crash "validated facade list start escaped"
				}
				list_node = $next_node
				$next_node = checked_add($next_node, 1)?
				group_start = $index
				var $group_end = $index
				while $group_end < blocks.len() and same_normalized_list(list_at(blocks, $group_end), list) {
					$group_end = $group_end + 1
				}
				list_content = $content.len()
				var $item_node = $next_node
				var $item_index = group_start
				while $item_index < $group_end {
					$content = $content.append(ChildNode(Semantics.NodeId.from_index($item_node)))
					$item_node = checked_add($item_node, 3)?
					$item_index = $item_index + 1
				}
				$nodes = list_set($nodes, list_node, make_node(list_node, ParentNode(Semantics.NodeId.from_index(0)), "L", Semantics.Range.from_start_and_length(list_content, $group_end - group_start), Inherited))
				$item_index = group_start
				while $item_index < $group_end {
					item_node = $next_node
					label_node = checked_add(item_node, 1)?
					body_node = checked_add(item_node, 2)?
					label_occurrence = $next_occurrence
					body_occurrence = checked_add(label_occurrence, 1)?
					item_content = $content.len()
					$content = $content.append(ChildNode(Semantics.NodeId.from_index(label_node))).append(ChildNode(Semantics.NodeId.from_index(body_node)))
					$nodes = list_set($nodes, item_node, make_node(item_node, ParentNode(Semantics.NodeId.from_index(list_node)), "LI", Semantics.Range.from_start_and_length(item_content, 2), Inherited))
					label_content = $content.len()
					$content = $content.append(ContentOccurrence(Semantics.OccurrenceId.from_index(label_occurrence)))
					$nodes = list_set($nodes, label_node, make_node(label_node, ParentNode(Semantics.NodeId.from_index(item_node)), "Lbl", Semantics.Range.from_start_and_length(label_content, 1), Inherited))
					label_property = $properties.len()
					label_range = source_range($source_input, source_plan)
					$properties = $properties.append(SourceToPresentation({ kind: GeneratedText, presentation: "•", source: label_range }))
					$occurrences = $occurrences.append(make_occurrence(label_occurrence, $source_input, source_plan, language, Semantics.Range.from_start_and_length(label_property, 1)))
					body_content = $content.len()
					$content = $content.append(ContentOccurrence(Semantics.OccurrenceId.from_index(body_occurrence)))
					$nodes = list_set($nodes, body_node, make_node(body_node, ParentNode(Semantics.NodeId.from_index(item_node)), "LBody", Semantics.Range.from_start_and_length(body_content, 1), Inherited))
					body_source_input = checked_add($source_input, 1)?
					$occurrences = $occurrences.append(make_occurrence(body_occurrence, body_source_input, source_plan, language, empty))
					$ownership = list_set($ownership, $item_index, TextBlock({ body: Semantics.OccurrenceId.from_index(body_occurrence), label: Label(Semantics.OccurrenceId.from_index(label_occurrence)) }))
					$next_node = checked_add($next_node, 3)?
					$next_occurrence = checked_add($next_occurrence, 2)?
					$source_input = checked_add($source_input, 2)?
					$item_index = $item_index + 1
				}
				$index = $group_end
			}
		}
	}
	unique_sources = KernelFacadeSources.Plan.sources(source_plan).map(|source| { unicode: source.unicode })
	if $artifact != planning.artifacts.len() or $next_node != planning.node_count or $next_occurrence != planning.occurrence_count or $source_input != planning.source_inputs.len() or $content.len() != planning.content_count or $properties.len() != planning.property_count {
		crash "facade semantic planning count escaped"
	}
	store = {
		annotations: [],
		assertions: [],
		attribute_roles: [],
		attributes: [],
		content_spine: $content,
		contextual_artifacts: [],
		document_root: Semantics.NodeId.from_index(0),
		element_identifiers: [],
		fragments: [],
		mathml_subtrees: [],
		namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
		nodes: $nodes,
		non_text_sources: [],
		occurrence_fragments: [],
		occurrences: $occurrences,
		relationships: [],
		role_mappings: [],
		text_properties: $properties,
		text_sources: unique_sources,
	}
	Ok({ block_ownership: $ownership, store })
}

make_node : U64, Semantics.NodeParent, Str, Semantics.Range, Semantics.Language -> Semantics.Node
make_node = |index, parent, role, content, language| {
	attributes: Semantics.Range.from_start_and_length(0, 0),
	content,
	element_identifier: NoElementIdentifier,
	id: Semantics.NodeId.from_index(index),
	language,
	parent,
	role: { local_name: role, namespace: Semantics.NamespaceId.from_index(0) },
	structure_element: Semantics.StructureElementId.from_index(index),
	text_properties: Semantics.Range.from_start_and_length(0, 0),
}

make_occurrence : U64, U64, KernelFacadeSources.Plan, Str, Semantics.Range -> Semantics.ContentOccurrence
make_occurrence = |index, source_input, sources, language, properties| {
	source_id = list_at(KernelFacadeSources.Plan.input_sources(sources), source_input)
	{
		fragments: Semantics.Range.from_start_and_length(0, 0),
		id: Semantics.OccurrenceId.from_index(index),
		language: Language(language),
		source: Text(source_id, UnicodeRange(source_range(source_input, sources))),
		text_properties: properties,
	}
}

source_range : U64, KernelFacadeSources.Plan -> Semantics.TextRange
source_range = |input, plan| {
	source_id = list_at(KernelFacadeSources.Plan.input_sources(plan), input)
	source = list_at(KernelFacadeSources.Plan.sources(plan), source_id.index())
	{
		scalars: Semantics.Range.from_start_and_length(0, source.analysis.work.scalar_visits),
		utf8_bytes: Semantics.Range.from_start_and_length(0, source.unicode.count_utf8_bytes()),
	}
}

same_normalized_list : Document.NormalizedBlock, U64 -> Bool
same_normalized_list = |block, list| match block.kind {
	Bullet(item) => item.list == list
	_ => False
}

check_limit : U64, U64, KernelFacadeSemantics.Dimension -> Try({}, KernelFacadeSemantics.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelFacadeSemantics.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(_) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated facade semantic index escaped"
	}
	Ok(value) => value
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated facade semantic write escaped"
	}
	Ok(updated) => updated
}

test_limits : KernelFacadeSemantics.Limits
test_limits = KernelFacadeSemantics.Limits.make({
	max_artifacts: 2,
	max_content_spine: 32,
	max_nodes: 16,
	max_occurrences: 12,
	max_properties: 4,
	max_source_inputs: 12,
	semantics: KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 32, max_fragments: 0, max_namespaces: 1, max_nodes: 16, max_occurrences: 12, max_semantic_depth: 4 }),
	sources: KernelFacadeSources.Limits.make({
		max_hash_probes: 64,
		max_inputs: 12,
		max_source_bytes: 64,
		max_source_scalars: 64,
		max_table_slots: 32,
		max_unique_sources: 12,
		unicode: { max_graphemes: 16, max_line_boundaries: 17, max_scalars: 16, max_script_runs: 8 },
	}),
	text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 4, max_text_property_bytes: 8, max_text_source_bytes: 64, max_text_source_scalars: 64, max_text_sources: 12 }),
})

test_authoring : Document.NormalizedAuthoring
test_authoring = {
	blocks: [
		{ kind: Title, text: "Report" },
		{ kind: Heading(1), text: "Summary" },
		{ kind: Paragraph, text: "Body" },
		{ kind: Bullet({ item: 0, list: 0 }), text: "One" },
		{ kind: Bullet({ item: 1, list: 0 }), text: "Two" },
		{ kind: PageArtifact(Header), text: "Header" },
	],
	language: "en-AU",
	metadata_title: "Report",
}

## Facade semantics are planned before layout, with a PDF 2.0 Title and a
## proper L -> LI -> (Lbl, LBody) hierarchy in explicit reading order.
expect {
	plan = KernelFacadeSemantics.Plan.build(test_authoring, test_limits)?
	text_plan = KernelFacadeSemantics.Plan.preliminary(plan)
	store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(text_plan))
	work = KernelFacadeSemantics.Plan.work(plan)
	retained_authoring = KernelFacadeSemantics.Plan.authoring(plan)
	root = list_at(store.nodes, 0)
	title = list_at(store.nodes, 1)
	list = list_at(store.nodes, 4)
	first_item = list_at(store.nodes, 5)
	first_label = list_at(store.nodes, 6)
	first_body = list_at(store.nodes, 7)

	retained_authoring.metadata_title == "Report" and retained_authoring.language == "en-AU" and retained_authoring.blocks.len() == 6 and
		store.nodes.len() == 11 and store.occurrences.len() == 7 and store.content_spine.len() == 17 and
			root.role.local_name == "Document" and root.content.start() == 0 and root.content.length() == 4 and
				title.role.local_name == "Title" and list.role.local_name == "L" and list.content.start() == 7 and list.content.length() == 2 and
					first_item.role.local_name == "LI" and first_label.role.local_name == "Lbl" and first_body.role.local_name == "LBody" and
						work.node_writes == 11 and work.occurrence_writes == 7 and work.content_writes == 17 and work.lists == 1 and work.list_items == 2
}

## Generated list labels retain an explicit source-to-presentation fact, and
## repeated bullets share one immutable Unicode source analysis.
expect {
	plan = KernelFacadeSemantics.Plan.build(test_authoring, test_limits)?
	text_plan = KernelFacadeSemantics.Plan.preliminary(plan)
	store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(text_plan))
	source_plan = KernelFacadeSemantics.Plan.sources(plan)
	first_label = list_at(store.occurrences, 3)
	second_label = list_at(store.occurrences, 5)
	property = list_at(store.text_properties, 0)
	labels_share_source = match (first_label.source, second_label.source) {
		(Text(first_source, _), Text(second_source, _)) => first_source.index() == second_source.index()
		_ => False
	}
	generated = match property {
		SourceToPresentation({ kind: GeneratedText, presentation, source }) => presentation == "•" and source.scalars.length() == 1
		_ => False
	}

	KernelFacadeSources.Plan.sources(source_plan).len() == 6 and store.text_properties.len() == 2 and labels_share_source and generated
}

## Page artifacts stay outside the semantic tree and retain typed ownership.
expect {
	plan = KernelFacadeSemantics.Plan.build(test_authoring, test_limits)?
	artifacts = KernelFacadeSemantics.Plan.artifacts(plan)
	owners = KernelFacadeSemantics.Plan.block_ownership(plan)
	match (list_at(artifacts, 0), list_at(owners, 5)) {
		({ block, kind: Header, text }, ArtifactBlock(artifact)) => block == 5 and text == "Header" and artifact == 0
		_ => False
	}
}

expect match KernelFacadeSemantics.Plan.build({ ..test_authoring, language: "" }, test_limits) {
	Err(EmptyLanguage) => True
	_ => False
}

expect match KernelFacadeSemantics.Plan.build({ ..test_authoring, metadata_title: "" }, test_limits) {
	Err(EmptyMetadataTitle) => True
	_ => False
}

expect {
	bad_blocks = [{ kind: Bullet({ item: 1, list: 0 }), text: "Orphan" }]
	match KernelFacadeSemantics.Plan.build({ ..test_authoring, blocks: bad_blocks }, test_limits) {
		Err(InvalidList({ block: 0 })) => True
		_ => False
	}
}

expect {
	bad_blocks = [{ kind: Heading(7), text: "Too deep" }]
	match KernelFacadeSemantics.Plan.build({ ..test_authoring, blocks: bad_blocks }, test_limits) {
		Err(UnsupportedHeadingLevel({ block: 0, level: 7 })) => True
		_ => False
	}
}

## The first node crossing is rejected before its planned node/content buffers
## are appended.
expect {
	limits = KernelFacadeSemantics.Limits.make({
		max_artifacts: 2,
		max_content_spine: 32,
		max_nodes: 1,
		max_occurrences: 12,
		max_properties: 4,
		max_source_inputs: 12,
		semantics: test_limits.semantics,
		sources: test_limits.sources,
		text_semantics: test_limits.text_semantics,
	})
	blocks = [{ kind: Paragraph, text: "Bounded" }]
	match KernelFacadeSemantics.Plan.build({ ..test_authoring, blocks }, limits) {
		Err(LimitExceeded({ attempted: 2, dimension: Nodes, limit: 1 })) => True
		_ => False
	}
}
