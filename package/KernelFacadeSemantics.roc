import Document
import KernelFacadeSources
import KernelNavigation
import KernelSemantics
import KernelTextSemantics
import KernelUnicode
import Semantics

KernelFacadeSemantics :: [].{
	Dimension : [Artifacts, ContentSpine, Nodes, Occurrences, Properties, SourceInputs]
	Error : [
		ArithmeticOverflow,
		ContainerDepthExceeded({ attempted : U64, group : U64, limit : U64 }),
		EmptyContainer({ group : U64 }),
		EmptyInline({ block : U64, inline : U64 }),
		EmptyLanguage,
		EmptyLinkText({ block : U64, inline : U64 }),
		EmptyMetadataTitle,
		EmptyRichParagraph({ block : U64 }),
		InlineDepthExceeded({ attempted : U64, block : U64, inline : U64, limit : U64 }),
		InvalidInlineLanguage({ block : U64, inline : U64 }),
		InvalidInlineUri({ block : U64, error : Document.NavigationError, inline : U64 }),
		InvalidList({ block : U64 }),
		NestedLink({ block : U64, inline : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		Source(KernelFacadeSources.Error),
		TextSemantics(KernelTextSemantics.Error),
		UnsupportedHeadingLevel({ block : U64, level : U8 }),
	]
	Limits :: {
		max_artifacts : U64,
		max_container_depth : U64,
		max_content_spine : U64,
		max_inline_depth : U64,
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
			max_container_depth : U64,
			max_content_spine : U64,
			max_inline_depth : U64,
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

	## A rich paragraph owns a dense occurrence range, one occurrence per text
	## leaf in logical order, all ranges of the paragraph's one interned source.
	BlockOwnership : [ArtifactBlock(U64), RichTextBlock({ occurrences : Semantics.Range }), TextBlock({ body : Semantics.OccurrenceId, label : [Label(Semantics.OccurrenceId), NoLabel] })]

	## One authored destination declaration: the block's semantic node is the
	## structure target and its content occurrence is the explicit layout
	## anchor.
	DestinationRecord : { anchor : Semantics.OccurrenceId, name : Str, target : Semantics.NodeId }

	## One authored link: its Link structure node, the dense range of text
	## occurrences whose painted runs its annotations cover, and the closed
	## authored target. A link block owns one occurrence; an inline link owns
	## the contiguous occurrences of the text leaves inside it.
	LinkRecord : { node : Semantics.NodeId, occurrences : Semantics.Range, target : [InternalDestination(Str), Uri(Str)] }
	Work : {
		artifacts : U64,
		container_nodes : U64,
		content_writes : U64,
		inline_elements : U64,
		inline_leaves : U64,
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
		destinations : List(DestinationRecord),
		links : List(LinkRecord),
		preliminary : KernelTextSemantics.Plan,
		sources : KernelFacadeSources.Plan,
		work : Work,
	}.{
		build : Document.NormalizedAuthoring, Limits -> Try(Plan, Error)
		build = |authoring, limits| build_plan(authoring, limits)

		artifacts : Plan -> List(Artifact)
		artifacts = |plan| plan.artifacts

		destinations : Plan -> List(DestinationRecord)
		destinations = |plan| plan.destinations

		links : Plan -> List(LinkRecord)
		links = |plan| plan.links

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

## A semantic child of the Document root (`parent` 0) or of normalized
## group `parent - 1`, in preorder.
ChildEntry : { node : Semantics.NodeId, parent : U64 }

Planning : {
	artifacts : List(KernelFacadeSemantics.Artifact),
	content_count : U64,
	destinations : List(KernelFacadeSemantics.DestinationRecord),
	group_nodes : List(U64),
	inline_elements : U64,
	inline_leaves : U64,
	links : List(KernelFacadeSemantics.LinkRecord),
	list_count : U64,
	list_item_count : U64,
	node_count : U64,
	occurrence_count : U64,
	property_count : U64,
	source_inputs : List(Str),
	top_nodes : List(ChildEntry),
}

build_plan : Document.NormalizedAuthoring, KernelFacadeSemantics.Limits -> Try(KernelFacadeSemantics.Plan, KernelFacadeSemantics.Error)
build_plan = |authoring, limits| {
	if authoring.language.is_empty() {
		return Err(EmptyLanguage)
	}
	if authoring.metadata_title.is_empty() {
		return Err(EmptyMetadataTitle)
	}
	planning = plan_blocks(authoring, limits)?
	sources = KernelFacadeSources.Plan.build(planning.source_inputs, limits.sources) ? Source
	built = build_store(authoring, planning, sources)?
	check_limit(built.store.content_spine.len(), limits.max_content_spine, ContentSpine)?
	check_limit(built.store.text_properties.len(), limits.max_properties, Properties)?
	navigated = !planning.links.is_empty() or !planning.destinations.is_empty()
	preliminary = (
		if navigated {
			KernelTextSemantics.Plan.build_navigation(built.store, 0, 0, limits.semantics, limits.text_semantics)
		} else {
			KernelTextSemantics.Plan.build(built.store, 0, 0, limits.semantics, limits.text_semantics)
		}
	) ? TextSemantics
	Ok(
		KernelFacadeSemantics.Plan.{
			artifacts: planning.artifacts,
			authoring,
			block_ownership: built.block_ownership,
			destinations: planning.destinations,
			links: planning.links,
			preliminary,
			sources,
			work: {
				artifacts: planning.artifacts.len(),
				container_nodes: planning.group_nodes.len(),
				content_writes: built.store.content_spine.len(),
				inline_elements: planning.inline_elements,
				inline_leaves: planning.inline_leaves,
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

## Node identities follow authored preorder: a container's node is allocated
## immediately before its first descendant, so documents without containers
## keep their exact node, content, and structure-element numbering.
plan_blocks : Document.NormalizedAuthoring, KernelFacadeSemantics.Limits -> Try(Planning, KernelFacadeSemantics.Error)
plan_blocks = |authoring, limits| {
	blocks = authoring.blocks
	groups = authoring.groups
	source_bound = if blocks.len() > U64.highest / 2 U64.highest else blocks.len() * 2
	var $artifacts = List.with_capacity(U64.min(blocks.len(), limits.max_artifacts))
	var $destinations = []
	var $links = []
	var $sources = List.with_capacity(U64.min(source_bound, limits.max_source_inputs))
	var $top_nodes = List.with_capacity(U64.min(checked_add(blocks.len(), groups.len())?, limits.max_nodes))
	var $group_nodes = if groups.is_empty() [] else List.with_capacity(groups.len())
	var $next_group = 0
	var $content_count = 0
	var $list_count = 0
	var $list_item_count = 0
	var $inline_elements = 0
	var $inline_leaves = 0
	var $next_node = 1
	var $next_occurrence = 0
	var $property_count = 0
	var $next_list = 0
	var $list_state = NoActiveList
	var $block_index = 0
	check_limit($next_node, limits.max_nodes, Nodes)?

	## One flat loop merges container openings into the block walk: a
	## container opens immediately before its first descendant block, or at
	## the end for containers that close the document.
	while $block_index < blocks.len() or $next_group < groups.len() {
		if $next_group < groups.len() and ($block_index >= blocks.len() or list_at(groups, $next_group).first_block <= $block_index) {
			group = list_at(groups, $next_group)
			if group.depth > limits.max_container_depth {
				return Err(ContainerDepthExceeded({ attempted: group.depth, group: $next_group, limit: limits.max_container_depth }))
			}
			attempted_nodes = checked_add($next_node, 1)?
			attempted_content = checked_add($content_count, 1)?
			check_limit(attempted_nodes, limits.max_nodes, Nodes)?
			check_limit(attempted_content, limits.max_content_spine, ContentSpine)?
			$group_nodes = $group_nodes.append($next_node)
			$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: group.parent })
			$next_node = attempted_nodes
			$content_count = attempted_content
			$list_state = NoActiveList
			$next_group = $next_group + 1
		} else {
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
						$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index(node), parent: block.parent })
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
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: block.parent })
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
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: block.parent })
					$sources = $sources.append(block.text)
					$next_node = checked_add($next_node, 1)?
					$next_occurrence = checked_add($next_occurrence, 1)?
					$content_count = attempted_content
					$list_state = NoActiveList
				}
				Figure(_) => {
					attempted_nodes = checked_add($next_node, 1)?
					attempted_occurrences = checked_add($next_occurrence, 1)?
					attempted_content = checked_add($content_count, 2)?
					attempted_sources = checked_add($sources.len(), 1)?
					attempted_properties = checked_add($property_count, 1)?
					check_limit(attempted_nodes, limits.max_nodes, Nodes)?
					check_limit(attempted_occurrences, limits.max_occurrences, Occurrences)?
					check_limit(attempted_content, limits.max_content_spine, ContentSpine)?
					check_limit(attempted_sources, limits.max_source_inputs, SourceInputs)?
					check_limit(attempted_properties, limits.max_properties, Properties)?
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: block.parent })
					$sources = $sources.append(block.text)
					$next_node = attempted_nodes
					$next_occurrence = attempted_occurrences
					$content_count = attempted_content
					$property_count = attempted_properties
					$list_state = NoActiveList
				}
				DestinationHeading({ level, name }) => {
					_role = heading_role(level, $block_index)?
					attempted_nodes = checked_add($next_node, 1)?
					attempted_occurrences = checked_add($next_occurrence, 1)?
					attempted_content = checked_add($content_count, 2)?
					attempted_sources = checked_add($sources.len(), 1)?
					check_limit(attempted_nodes, limits.max_nodes, Nodes)?
					check_limit(attempted_occurrences, limits.max_occurrences, Occurrences)?
					check_limit(attempted_content, limits.max_content_spine, ContentSpine)?
					check_limit(attempted_sources, limits.max_source_inputs, SourceInputs)?
					$destinations = $destinations.append({ anchor: Semantics.OccurrenceId.from_index($next_occurrence), name, target: Semantics.NodeId.from_index($next_node) })
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: block.parent })
					$sources = $sources.append(block.text)
					$next_node = checked_add($next_node, 1)?
					$next_occurrence = checked_add($next_occurrence, 1)?
					$content_count = attempted_content
					$list_state = NoActiveList
				}
				DestinationParagraph({ name }) => {
					attempted_nodes = checked_add($next_node, 1)?
					attempted_occurrences = checked_add($next_occurrence, 1)?
					attempted_content = checked_add($content_count, 2)?
					attempted_sources = checked_add($sources.len(), 1)?
					check_limit(attempted_nodes, limits.max_nodes, Nodes)?
					check_limit(attempted_occurrences, limits.max_occurrences, Occurrences)?
					check_limit(attempted_content, limits.max_content_spine, ContentSpine)?
					check_limit(attempted_sources, limits.max_source_inputs, SourceInputs)?
					$destinations = $destinations.append({ anchor: Semantics.OccurrenceId.from_index($next_occurrence), name, target: Semantics.NodeId.from_index($next_node) })
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: block.parent })
					$sources = $sources.append(block.text)
					$next_node = checked_add($next_node, 1)?
					$next_occurrence = checked_add($next_occurrence, 1)?
					$content_count = attempted_content
					$list_state = NoActiveList
				}
				Link({ uri }) => {
					attempted_nodes = checked_add($next_node, 2)?
					attempted_occurrences = checked_add($next_occurrence, 1)?
					attempted_content = checked_add($content_count, 3)?
					attempted_sources = checked_add($sources.len(), 1)?
					check_limit(attempted_nodes, limits.max_nodes, Nodes)?
					check_limit(attempted_occurrences, limits.max_occurrences, Occurrences)?
					check_limit(attempted_content, limits.max_content_spine, ContentSpine)?
					check_limit(attempted_sources, limits.max_source_inputs, SourceInputs)?
					$links = $links.append({ node: Semantics.NodeId.from_index($next_node + 1), occurrences: Semantics.Range.from_start_and_length($next_occurrence, 1), target: Uri(uri) })
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: block.parent })
					$sources = $sources.append(block.text)
					$next_node = attempted_nodes
					$next_occurrence = checked_add($next_occurrence, 1)?
					$content_count = attempted_content
					$list_state = NoActiveList
				}
				InternalLink({ destination }) => {
					attempted_nodes = checked_add($next_node, 2)?
					attempted_occurrences = checked_add($next_occurrence, 1)?
					attempted_content = checked_add($content_count, 3)?
					attempted_sources = checked_add($sources.len(), 1)?
					check_limit(attempted_nodes, limits.max_nodes, Nodes)?
					check_limit(attempted_occurrences, limits.max_occurrences, Occurrences)?
					check_limit(attempted_content, limits.max_content_spine, ContentSpine)?
					check_limit(attempted_sources, limits.max_source_inputs, SourceInputs)?
					$links = $links.append({ node: Semantics.NodeId.from_index($next_node + 1), occurrences: Semantics.Range.from_start_and_length($next_occurrence, 1), target: InternalDestination(destination) })
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: block.parent })
					$sources = $sources.append(block.text)
					$next_node = attempted_nodes
					$next_occurrence = checked_add($next_occurrence, 1)?
					$content_count = attempted_content
					$list_state = NoActiveList
				}
				RichParagraph(paragraph) => {
					rich = list_at(authoring.rich_paragraphs, paragraph)
					checked = check_rich(authoring.inlines, rich, $block_index, limits.max_inline_depth)?
					attempted_nodes = checked_add($next_node, checked_add(rich.elements, 1)?)?
					attempted_occurrences = checked_add($next_occurrence, rich.leaves)?
					attempted_content = checked_add($content_count, checked_add(rich.length, 1)?)?
					attempted_properties = checked_add($property_count, checked.expansions)?
					attempted_sources = checked_add($sources.len(), 1)?
					check_limit(attempted_nodes, limits.max_nodes, Nodes)?
					check_limit(attempted_occurrences, limits.max_occurrences, Occurrences)?
					check_limit(attempted_content, limits.max_content_spine, ContentSpine)?
					check_limit(attempted_properties, limits.max_properties, Properties)?
					check_limit(attempted_sources, limits.max_source_inputs, SourceInputs)?
					if checked.links != 0 {
						$links = append_rich_links($links, authoring.inlines, rich, $next_node, $next_occurrence)
					}
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: block.parent })
					$sources = $sources.append(block.text)
					$next_node = attempted_nodes
					$next_occurrence = attempted_occurrences
					$content_count = attempted_content
					$property_count = attempted_properties
					$inline_elements = checked_add($inline_elements, rich.elements)?
					$inline_leaves = checked_add($inline_leaves, rich.leaves)?
					$list_state = NoActiveList
				}
			}
			$block_index = $block_index + 1
		}
	}
	Ok({ artifacts: $artifacts, content_count: $content_count, destinations: $destinations, group_nodes: $group_nodes, inline_elements: $inline_elements, inline_leaves: $inline_leaves, links: $links, list_count: $list_count, list_item_count: $list_item_count, node_count: $next_node, occurrence_count: $next_occurrence, property_count: $property_count, source_inputs: $sources, top_nodes: $top_nodes })
}

## Validate one rich paragraph's inline span in preorder; the first failure
## in authored order wins. Every text leaf is non-empty, every element holds
## text, inline elements nest at most `max_depth` deep, links never contain
## links, language tags are well formed, and URIs pass the navigation URI
## grammar. Returns the counts semantic planning reserves.
check_rich : List(Document.NormalizedInline), Document.NormalizedRich, U64, U64 -> Try({ expansions : U64, links : U64 }, KernelFacadeSemantics.Error)
check_rich = |inlines, rich, block, max_depth| {
	if rich.leaves == 0 {
		return Err(EmptyRichParagraph({ block: block }))
	}
	var $expansions = 0
	var $links = 0
	var $index = rich.inlines
	end = rich.inlines + rich.length
	while $index < end {
		record = list_at(inlines, $index)
		match record.kind {
			Text({ byte_length, byte_start: _, text: _ }) => if byte_length == 0 {
				return Err(EmptyInline({ block, inline: $index }))
			}
			kind => {
				if record.depth > max_depth {
					return Err(InlineDepthExceeded({ attempted: record.depth, block, inline: $index, limit: max_depth }))
				}
				linked = match kind {
					Link(_) | InternalLink(_) => True
					_ => False
				}
				if record.leaf_end == record.first_leaf {
					return if linked Err(EmptyLinkText({ block, inline: $index })) else Err(EmptyInline({ block, inline: $index }))
				}
				if linked {
					if inside_link(inlines, record.parent) {
						return Err(NestedLink({ block, inline: $index }))
					}
					$links = $links + 1
				}
				match kind {
					InLanguage(tag) => if !KernelSemantics.language_tag_valid(tag) {
						return Err(InvalidInlineLanguage({ block, inline: $index }))
					}
					Link(uri) => match KernelNavigation.check_uri(uri) {
						Ok(_) => {}
						Err(error) => return Err(InvalidInlineUri({ block, error, inline: $index }))
					}
					Expansion(expanded) => {
						if expanded.is_empty() {
							return Err(EmptyInline({ block, inline: $index }))
						}
						$expansions = $expansions + 1
					}
					_ => {}
				}
			}
		}
		$index = $index + 1
	}
	Ok({ expansions: $expansions, links: $links })
}

## Whether an inline's ancestor chain (`parent` encoded `0` or `i + 1`)
## contains a link. Chains are bounded by the validated inline depth.
inside_link : List(Document.NormalizedInline), U64 -> Bool
inside_link = |inlines, parent| {
	var $cursor = parent
	var $found = False
	while $cursor != 0 and !$found {
		record = list_at(inlines, $cursor - 1)
		$found = match record.kind {
			Link(_) | InternalLink(_) => True
			_ => False
		}
		$cursor = record.parent
	}
	$found
}

## One link record per inline link: its node follows the paragraph node in
## element preorder and its occurrences are the leaves below it.
append_rich_links : List(KernelFacadeSemantics.LinkRecord), List(Document.NormalizedInline), Document.NormalizedRich, U64, U64 -> List(KernelFacadeSemantics.LinkRecord)
append_rich_links = |links, inlines, rich, paragraph_node, first_occurrence| {
	var $links = links
	var $index = rich.inlines
	end = rich.inlines + rich.length
	while $index < end {
		record = list_at(inlines, $index)
		target = match record.kind {
			Link(uri) => Linked(Uri(uri))
			InternalLink(destination) => Linked(InternalDestination(destination))
			_ => NotLinked
		}
		match target {
			Linked(value) => {
				$links = $links.append({
					node: Semantics.NodeId.from_index(paragraph_node + 1 + record.element),
					occurrences: Semantics.Range.from_start_and_length(first_occurrence + record.first_leaf, record.leaf_end - record.first_leaf),
					target: value,
				})
			}
			NotLinked => {}
		}
		$index = $index + 1
	}
	$links
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

## The content spine starts with the Document's child list followed by each
## container's child list in group order; a stable counting sort by parent
## builds those contiguous spans in O(children + groups). Leaf content
## follows in block order exactly as before, so a document without
## containers keeps its exact spine.
build_store : Document.NormalizedAuthoring, Planning, KernelFacadeSources.Plan -> Try({ block_ownership : List(KernelFacadeSemantics.BlockOwnership), store : Semantics.Store }, KernelFacadeSemantics.Error)
build_store = |authoring, planning, source_plan| {
	language = authoring.language
	blocks = authoring.blocks
	groups = authoring.groups
	figures = authoring.figures
	empty = Semantics.Range.from_start_and_length(0, 0)
	dummy = make_node(0, DocumentRoot, "Document", empty, Language(language))
	var $nodes = List.repeat(dummy, planning.node_count)
	var $content = List.with_capacity(planning.content_count)
	if groups.is_empty() {
		for entry in planning.top_nodes {
			$content = $content.append(ChildNode(entry.node))
		}
		$nodes = list_set($nodes, 0, make_node(0, DocumentRoot, "Document", Semantics.Range.from_start_and_length(0, planning.top_nodes.len()), Language(language)))
	} else {
		spans = child_spans(planning.top_nodes, groups.len())
		for node in spans.ordered {
			$content = $content.append(ChildNode(node))
		}
		root_children = list_at(spans.counts, 0)
		$nodes = list_set($nodes, 0, make_node(0, DocumentRoot, "Document", Semantics.Range.from_start_and_length(0, root_children), Language(language)))
		var $span_start = root_children
		var $group = 0
		while $group < groups.len() {
			group = list_at(groups, $group)
			children = list_at(spans.counts, $group + 1)
			if children == 0 {
				return Err(EmptyContainer({ group: $group }))
			}
			node_index = list_at(planning.group_nodes, $group)
			$nodes = list_set($nodes, node_index, make_node(node_index, ParentNode(parent_node(group.parent, planning.group_nodes)), container_role(group.kind), Semantics.Range.from_start_and_length($span_start, children), Inherited))
			$span_start = $span_start + children
			$group = $group + 1
		}
	}
	var $occurrences = List.with_capacity(planning.occurrence_count)
	var $properties = List.with_capacity(planning.property_count)
	var $ownership = List.repeat(ArtifactBlock(0), blocks.len())
	var $artifact = 0
	var $index = 0
	var $next_node = 1
	var $next_occurrence = 0
	var $source_input = 0
	var $next_group = 0
	while $index < blocks.len() {
		while $next_group < groups.len() and list_at(groups, $next_group).first_block <= $index {
			$next_node = checked_add($next_node, 1)?
			$next_group = $next_group + 1
		}
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
				$nodes = list_set($nodes, $next_node, make_node($next_node, ParentNode(parent_node(block.parent, planning.group_nodes)), role, Semantics.Range.from_start_and_length(start, 1), Inherited))
				$occurrences = $occurrences.append(make_occurrence($next_occurrence, $source_input, source_plan, language, empty))
				$ownership = list_set($ownership, $index, TextBlock({ body: Semantics.OccurrenceId.from_index($next_occurrence), label: NoLabel }))
				$next_node = checked_add($next_node, 1)?
				$next_occurrence = checked_add($next_occurrence, 1)?
				$source_input = checked_add($source_input, 1)?
				$index = $index + 1
			}
			Paragraph | Title | DestinationParagraph(_) => {
				role = match block.kind {
					Paragraph | DestinationParagraph(_) => "P"
					Title => "Title"
					_ => ""
				}
				start = $content.len()
				$content = $content.append(ContentOccurrence(Semantics.OccurrenceId.from_index($next_occurrence)))
				$nodes = list_set($nodes, $next_node, make_node($next_node, ParentNode(parent_node(block.parent, planning.group_nodes)), role, Semantics.Range.from_start_and_length(start, 1), Inherited))
				$occurrences = $occurrences.append(make_occurrence($next_occurrence, $source_input, source_plan, language, empty))
				$ownership = list_set($ownership, $index, TextBlock({ body: Semantics.OccurrenceId.from_index($next_occurrence), label: NoLabel }))
				$next_node = checked_add($next_node, 1)?
				$next_occurrence = checked_add($next_occurrence, 1)?
				$source_input = checked_add($source_input, 1)?
				$index = $index + 1
			}
			Figure(figure_index) => {
				figure = list_at(figures, figure_index)
				start = $content.len()
				property_start = $properties.len()
				$content = $content.append(ContentOccurrence(Semantics.OccurrenceId.from_index($next_occurrence)))
				$properties = $properties.append(AlternativeText(figure.alternative))
				node = make_node($next_node, ParentNode(parent_node(block.parent, planning.group_nodes)), "Figure", Semantics.Range.from_start_and_length(start, 1), Inherited)
				$nodes = list_set($nodes, $next_node, { ..node, text_properties: Semantics.Range.from_start_and_length(property_start, 1) })
				$occurrences = $occurrences.append(make_occurrence($next_occurrence, $source_input, source_plan, language, empty))
				$ownership = list_set($ownership, $index, TextBlock({ body: Semantics.OccurrenceId.from_index($next_occurrence), label: NoLabel }))
				$next_node = checked_add($next_node, 1)?
				$next_occurrence = checked_add($next_occurrence, 1)?
				$source_input = checked_add($source_input, 1)?
				$index = $index + 1
			}
			DestinationHeading({ level, name: _ }) => {
				role = heading_role(level, $index)?
				start = $content.len()
				$content = $content.append(ContentOccurrence(Semantics.OccurrenceId.from_index($next_occurrence)))
				$nodes = list_set($nodes, $next_node, make_node($next_node, ParentNode(parent_node(block.parent, planning.group_nodes)), role, Semantics.Range.from_start_and_length(start, 1), Inherited))
				$occurrences = $occurrences.append(make_occurrence($next_occurrence, $source_input, source_plan, language, empty))
				$ownership = list_set($ownership, $index, TextBlock({ body: Semantics.OccurrenceId.from_index($next_occurrence), label: NoLabel }))
				$next_node = checked_add($next_node, 1)?
				$next_occurrence = checked_add($next_occurrence, 1)?
				$source_input = checked_add($source_input, 1)?
				$index = $index + 1
			}
			Link(_) | InternalLink(_) => {

				## A link block is a paragraph-shaped wrapper: a P node under
				## the root containing one Link node that owns the link text.
				## Per-page annotation occurrences join the Link node's spine
				## after pagination.
				wrapper_node = $next_node
				link_node = checked_add(wrapper_node, 1)?
				wrapper_start = $content.len()
				$content = $content.append(ChildNode(Semantics.NodeId.from_index(link_node)))
				link_start = $content.len()
				$content = $content.append(ContentOccurrence(Semantics.OccurrenceId.from_index($next_occurrence)))
				$nodes = list_set($nodes, wrapper_node, make_node(wrapper_node, ParentNode(parent_node(block.parent, planning.group_nodes)), "P", Semantics.Range.from_start_and_length(wrapper_start, 1), Inherited))
				$nodes = list_set($nodes, link_node, make_node(link_node, ParentNode(Semantics.NodeId.from_index(wrapper_node)), "Link", Semantics.Range.from_start_and_length(link_start, 1), Inherited))
				$occurrences = $occurrences.append(make_occurrence($next_occurrence, $source_input, source_plan, language, empty))
				$ownership = list_set($ownership, $index, TextBlock({ body: Semantics.OccurrenceId.from_index($next_occurrence), label: NoLabel }))
				$next_node = checked_add(link_node, 1)?
				$next_occurrence = checked_add($next_occurrence, 1)?
				$source_input = checked_add($source_input, 1)?
				$index = $index + 1
			}
			RichParagraph(paragraph) => {
				rich = list_at(authoring.rich_paragraphs, paragraph)
				placed = place_rich(
					{ content: $content, nodes: $nodes, occurrences: $occurrences, properties: $properties },
					authoring,
					rich,
					{ language, node: $next_node, occurrence: $next_occurrence, parent: parent_node(block.parent, planning.group_nodes), source_input: $source_input },
					source_plan,
				)?
				$content = placed.content
				$nodes = placed.nodes
				$occurrences = placed.occurrences
				$properties = placed.properties
				$ownership = list_set($ownership, $index, RichTextBlock({ occurrences: Semantics.Range.from_start_and_length($next_occurrence, rich.leaves) }))
				$next_node = checked_add($next_node, rich.elements + 1)?
				$next_occurrence = checked_add($next_occurrence, rich.leaves)?
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
				$nodes = list_set($nodes, list_node, make_node(list_node, ParentNode(parent_node(block.parent, planning.group_nodes)), "L", Semantics.Range.from_start_and_length(list_content, $group_end - group_start), Inherited))
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
	$next_node = checked_add($next_node, groups.len() - $next_group)?
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

StoreBuffers : { content : List(Semantics.ContentSpineItem), nodes : List(Semantics.Node), occurrences : List(Semantics.ContentOccurrence), properties : List(Semantics.TextProperty) }

## Place one rich paragraph: its `P` node, one node per inline element in
## preorder, and one occurrence per text leaf over an exact sub-range of the
## paragraph's interned source. The paragraph's spine span is reserved first
## and each item is written at its authored position, so every node owns one
## contiguous span. A leaf occurrence carries the language of its nearest
## `in_language` span, which is also the effective language of the node
## that owns it: a node-level `/Lang` on that `Span` therefore describes all
## of its marked content, and no content item differs from its owner.
place_rich : StoreBuffers, Document.NormalizedAuthoring, Document.NormalizedRich, { language : Str, node : U64, occurrence : U64, parent : Semantics.NodeId, source_input : U64 }, KernelFacadeSources.Plan -> Try(StoreBuffers, KernelFacadeSemantics.Error)
place_rich = |buffers, authoring, rich, at, source_plan| {
	inlines = authoring.inlines
	base = buffers.content.len()
	var $content = buffers.content
	var $slot = 0
	while $slot < rich.length {
		$content = $content.append(ChildNode(Semantics.NodeId.from_index(0)))
		$slot = $slot + 1
	}
	var $nodes = list_set(buffers.nodes, at.node, make_node(at.node, ParentNode(at.parent), "P", Semantics.Range.from_start_and_length(base, rich.children), Inherited))
	var $occurrences = buffers.occurrences
	var $properties = buffers.properties
	source_id = list_at(KernelFacadeSources.Plan.input_sources(source_plan), at.source_input)
	source = list_at(KernelFacadeSources.Plan.sources(source_plan), source_id.index())
	boundaries = source.analysis.line_boundaries
	var $boundary = 0
	var $index = rich.inlines
	end = rich.inlines + rich.length
	while $index < end {
		record = list_at(inlines, $index)
		owner_spine = if record.parent == 0 base else base + list_at(inlines, record.parent - 1).spine
		owner_node = if record.parent == 0 at.node else at.node + 1 + list_at(inlines, record.parent - 1).element
		position = owner_spine + record.position
		match record.kind {
			Text({ byte_length, byte_start, text: _ }) => {
				start = scalar_at(boundaries, $boundary, byte_start)?
				finish = scalar_at(boundaries, start.index, byte_start + byte_length)?
				$boundary = finish.index
				occurrence = at.occurrence + record.first_leaf
				$content = list_set($content, position, ContentOccurrence(Semantics.OccurrenceId.from_index(occurrence)))
				$occurrences = $occurrences.append({
					fragments: Semantics.Range.from_start_and_length(0, 0),
					id: Semantics.OccurrenceId.from_index(occurrence),
					language: Language(leaf_language(inlines, record.language, at.language)),
					source: Text(
						source_id,
						UnicodeRange({
							scalars: Semantics.Range.from_start_and_length(start.index, finish.index - start.index),
							utf8_bytes: Semantics.Range.from_start_and_length(byte_start, byte_length),
						}),
					),
					text_properties: Semantics.Range.from_start_and_length(0, 0),
				})
			}
			kind => {
				node_index = at.node + 1 + record.element
				$content = list_set($content, position, ChildNode(Semantics.NodeId.from_index(node_index)))
				node = make_node(node_index, ParentNode(Semantics.NodeId.from_index(owner_node)), inline_role(kind), Semantics.Range.from_start_and_length(base + record.spine, record.children), inline_language(kind))
				match kind {
					Expansion(expanded) => {
						property = $properties.len()
						$properties = $properties.append(ExpandedText(expanded))
						$nodes = list_set($nodes, node_index, { ..node, text_properties: Semantics.Range.from_start_and_length(property, 1) })
					}
					_ => {
						$nodes = list_set($nodes, node_index, node)
					}
				}
			}
		}
		$index = $index + 1
	}
	Ok({ content: $content, nodes: $nodes, occurrences: $occurrences, properties: $properties })
}

## The scalar offset at a UTF-8 byte offset, walking the dense per-scalar
## boundary facts forward from `from`; leaves arrive in byte order, so one
## paragraph costs O(scalars).
scalar_at : List(KernelUnicode.LineBoundary), U64, U64 -> Try({ index : U64 }, KernelFacadeSemantics.Error)
scalar_at = |boundaries, from, byte_offset| {
	var $cursor = from
	while $cursor < boundaries.len() and list_at(boundaries, $cursor).byte_offset < byte_offset {
		$cursor = $cursor + 1
	}
	if $cursor >= boundaries.len() or list_at(boundaries, $cursor).byte_offset != byte_offset {
		crash "rich paragraph leaf boundary escaped its source"
	}
	Ok({ index: $cursor })
}

leaf_language : List(Document.NormalizedInline), U64, Str -> Str
leaf_language = |inlines, owner, document_language| if owner == 0 {
	document_language
} else {
	match list_at(inlines, owner - 1).kind {
		InLanguage(tag) => tag
		_ => crash "normalized inline language owner escaped"
	}
}

inline_role : Document.NormalizedInlineKind -> Str
inline_role = |kind| match kind {
	Code => "Code"
	Emphasis => "Em"
	Expansion(_) | InLanguage(_) => "Span"
	InternalLink(_) | Link(_) => "Link"
	Quote => "Quote"
	Strong => "Strong"
	Text(_) => "Span"
}

inline_language : Document.NormalizedInlineKind -> Semantics.Language
inline_language = |kind| match kind {
	InLanguage(tag) => Language(tag)
	_ => Inherited
}

container_role : Document.ContainerKind -> Str
container_role = |kind| match kind {
	Division => "Div"
	Part => "Part"
	Section => "Sect"
}

parent_node : U64, List(U64) -> Semantics.NodeId
parent_node = |parent, group_nodes| if parent == 0 Semantics.NodeId.from_index(0) else Semantics.NodeId.from_index(list_at(group_nodes, parent - 1))

child_spans : List(ChildEntry), U64 -> { counts : List(U64), ordered : List(Semantics.NodeId) }
child_spans = |entries, group_count| {
	var $counts = List.repeat(0, group_count + 1)
	for entry in entries {
		$counts = list_set($counts, entry.parent, list_at($counts, entry.parent) + 1)
	}
	var $cursors = List.repeat(0, group_count + 1)
	var $total = 0
	var $index = 0
	while $index <= group_count {
		$cursors = list_set($cursors, $index, $total)
		$total = $total + list_at($counts, $index)
		$index = $index + 1
	}
	var $ordered = List.repeat(Semantics.NodeId.from_index(0), entries.len())
	for entry in entries {
		at = list_at($cursors, entry.parent)
		$ordered = list_set($ordered, at, entry.node)
		$cursors = list_set($cursors, entry.parent, at + 1)
	}
	{ counts: $counts, ordered: $ordered }
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
	max_container_depth: 2,
	max_inline_depth: 8,
	max_content_spine: 32,
	max_nodes: 16,
	max_occurrences: 12,
	max_properties: 4,
	max_source_inputs: 12,
	semantics: KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 32, max_fragments: 0, max_namespaces: 1, max_nodes: 16, max_occurrences: 12, max_semantic_depth: 8 }),
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
		{ kind: Title, parent: 0, text: "Report" },
		{ kind: Heading(1), parent: 0, text: "Summary" },
		{ kind: Paragraph, parent: 0, text: "Body" },
		{ kind: Bullet({ item: 0, list: 0 }), parent: 0, text: "One" },
		{ kind: Bullet({ item: 1, list: 0 }), parent: 0, text: "Two" },
		{ kind: PageArtifact(Header), parent: 0, text: "Header" },
	],
	figures: [],
	groups: [],
	inlines: [],
	language: "en-AU",
	metadata_title: "Report",
	outline: [],
	page_labels: [],
	rich_paragraphs: [],
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
	bad_blocks = [{ kind: Bullet({ item: 1, list: 0 }), parent: 0, text: "Orphan" }]
	match KernelFacadeSemantics.Plan.build({ ..test_authoring, blocks: bad_blocks }, test_limits) {
		Err(InvalidList({ block: 0 })) => True
		_ => False
	}
}

expect {
	bad_blocks = [{ kind: Heading(7), parent: 0, text: "Too deep" }]
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
		max_container_depth: 4,
		max_content_spine: 32,
		max_inline_depth: 8,
		max_nodes: 1,
		max_occurrences: 12,
		max_properties: 4,
		max_source_inputs: 12,
		semantics: test_limits.semantics,
		sources: test_limits.sources,
		text_semantics: test_limits.text_semantics,
	})
	blocks = [{ kind: Paragraph, parent: 0, text: "Bounded" }]
	match KernelFacadeSemantics.Plan.build({ ..test_authoring, blocks }, limits) {
		Err(LimitExceeded({ attempted: 2, dimension: Nodes, limit: 1 })) => True
		_ => False
	}
}

nested_authoring : Document.NormalizedAuthoring
nested_authoring = {
	..test_authoring,
	blocks: [
		{ kind: Title, parent: 0, text: "Report" },
		{ kind: Heading(1), parent: 1, text: "Summary" },
		{ kind: Paragraph, parent: 1, text: "Body" },
		{ kind: Bullet({ item: 0, list: 0 }), parent: 2, text: "One" },
		{ kind: Bullet({ item: 1, list: 0 }), parent: 2, text: "Two" },
	],
	groups: [
		{ block_end: 5, depth: 1, first_block: 1, group_end: 2, kind: Section, parent: 0, position: 1 },
		{ block_end: 5, depth: 2, first_block: 3, group_end: 2, kind: Division, parent: 1, position: 2 },
	],
}

## Containers allocate their nodes in authored preorder and own contiguous
## child spans: Document -> [Title, Sect], Sect -> [H1, P, Div], Div -> [L].
expect {
	plan = KernelFacadeSemantics.Plan.build(nested_authoring, test_limits)?
	store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(plan)))
	roles = store.nodes.map(|node| node.role.local_name)
	root = list_at(store.nodes, 0)
	section = list_at(store.nodes, 2)
	division = list_at(store.nodes, 5)
	heading = list_at(store.nodes, 3)
	list_node = list_at(store.nodes, 6)
	children = |node| store.content_spine.sublist({ start: node.content.start(), len: node.content.length() }).map(
		|item| match item {
			ChildNode(child) => child.index()
			_ => 99
		},
	)
	parent_of = |node| match node.parent {
		ParentNode(parent) => parent.index()
		DocumentRoot => 99
	}
	work = KernelFacadeSemantics.Plan.work(plan)

	roles == ["Document", "Title", "Sect", "H1", "P", "Div", "L", "LI", "Lbl", "LBody", "LI", "Lbl", "LBody"] and
		children(root) == [1, 2] and
			children(section) == [3, 4, 5] and
				children(division) == [6] and
					parent_of(section) == 0 and parent_of(heading) == 2 and parent_of(division) == 2 and parent_of(list_node) == 5 and
						work.container_nodes == 2 and work.node_writes == 13
}

## Nesting beyond the container depth bound and empty containers are stable
## rejections before any store is built.
expect {
	deep = { ..nested_authoring, groups: nested_authoring.groups.map(|group| { ..group, depth: group.depth + 1 }) }
	empty = {
		..nested_authoring,
		blocks: nested_authoring.blocks.map(|block| if block.parent == 2 { ..block, parent: 1 } else block),
		groups: [
			{ block_end: 5, depth: 1, first_block: 1, group_end: 2, kind: Section, parent: 0, position: 1 },
			{ block_end: 5, depth: 2, first_block: 5, group_end: 2, kind: Part, parent: 1, position: 4 },
		],
	}
	depth_rejected = match KernelFacadeSemantics.Plan.build(deep, test_limits) {
		Err(ContainerDepthExceeded({ attempted: 3, group: 1, limit: 2 })) => True
		_ => False
	}
	empty_rejected = match KernelFacadeSemantics.Plan.build(empty, test_limits) {
		Err(EmptyContainer({ group: 1 })) => True
		_ => False
	}
	depth_rejected and empty_rejected
}

rich_authoring : List(Document.Inline) -> Document.NormalizedAuthoring
rich_authoring = |inlines| Document.normalize(Document.from_blocks({ contents: [Document.rich_paragraph(inlines)], language: "en-AU", title: "Rich" }))

## A rich paragraph plans one `P`, one node per inline element in preorder,
## and one occurrence per text leaf over an exact sub-range of its single
## interned source; every node owns one contiguous spine span in authored
## order, and an inline language becomes the leaf occurrence's language.
expect {
	authoring = rich_authoring([
		Document.plain_text("Ab "),
		Document.emphasis([Document.plain_text("cd "), Document.strong([Document.in_language("fr", [Document.plain_text("é")])])]),
		Document.plain_text(" f"),
	])
	plan = KernelFacadeSemantics.Plan.build(authoring, test_limits)?
	store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(plan)))
	spine = |index| {
		node = list_at(store.nodes, index)
		store.content_spine.sublist({ start: node.content.start(), len: node.content.length() }).map(
			|item| match item {
				ChildNode(child) => child.index() * 10
				ContentOccurrence(occurrence) => occurrence.index() * 10 + 1
				_ => 99
			},
		)
	}
	ranges = store.occurrences.map(
		|occurrence| match occurrence.source {
			Text(_, UnicodeRange(range)) => [range.scalars.start(), range.scalars.length(), range.utf8_bytes.start(), range.utf8_bytes.length()]
			_ => []
		},
	)
	french = match list_at(store.occurrences, 2).language {
		Language(tag) => tag == "fr"
		Inherited => False
	}
	work = KernelFacadeSemantics.Plan.work(plan)

	store.nodes.map(|node| node.role.local_name) == ["Document", "P", "Em", "Strong", "Span"]
		and spine(1) == [1, 20, 31]
			and spine(2) == [11, 30]
				and spine(3) == [40]
					and spine(4) == [21]
						and ranges == [[0, 3, 0, 3], [3, 3, 3, 3], [6, 1, 6, 2], [7, 2, 8, 2]]
							and french
								and list_at(store.nodes, 4).language == Language("fr")
									and work.inline_elements == 3
										and work.inline_leaves == 4
											and (match KernelFacadeSemantics.Plan.block_ownership(plan) {
												[RichTextBlock({ occurrences })] => occurrences.start() == 0 and occurrences.length() == 4
												_ => False
											})
}

## Inline rejections name the paragraph block and the inline's arena index.
expect {
	empty = KernelFacadeSemantics.Plan.build(rich_authoring([Document.plain_text("a"), Document.strong([])]), test_limits)
	nested = KernelFacadeSemantics.Plan.build(rich_authoring([Document.inline_link([Document.inline_link([Document.plain_text("b")], "https://example.org")], "https://example.org")]), test_limits)
	language = KernelFacadeSemantics.Plan.build(rich_authoring([Document.in_language("fr_CA", [Document.plain_text("b")])]), test_limits)
	uri = KernelFacadeSemantics.Plan.build(rich_authoring([Document.inline_link([Document.plain_text("b")], "no scheme")]), test_limits)
	blank = KernelFacadeSemantics.Plan.build(rich_authoring([]), test_limits)
	deep = KernelFacadeSemantics.Plan.build(
		rich_authoring([Document.emphasis([Document.emphasis([Document.emphasis([Document.emphasis([Document.emphasis([Document.emphasis([Document.emphasis([Document.emphasis([Document.emphasis([Document.plain_text("x")])])])])])])])])])]),
		test_limits,
	)
	match (empty, nested, language, uri, blank, deep) {
		(Err(EmptyInline({ block: 0, inline: 1 })), Err(NestedLink({ block: 0, inline: 1 })), Err(InvalidInlineLanguage({ block: 0, inline: 0 })), Err(InvalidInlineUri({ block: 0, error: UriMissingScheme(_), inline: 0 })), Err(EmptyRichParagraph({ block: 0 })), Err(InlineDepthExceeded({ attempted: 9, block: 0, inline: 8, limit: 8 }))) => True
		_ => False
	}
}
