import Document
import KernelFacadeSources
import KernelNavigation
import KernelSemantics
import KernelTextSemantics
import KernelUnicode
import Semantics

KernelFacadeSemantics :: [].{
	Dimension : [ContentSpine, Nodes, Occurrences, Properties, SourceInputs]
	Error : [
		ArithmeticOverflow,
		ContainerDepthExceeded({ attempted : U64, group : U64, limit : U64 }),

		## A custom block holds something other than paragraphs and rich
		## paragraphs (`child` is its authored position), or stands in the
		## first page's lead region (`child` is `NoChild`).
		CustomContent({ child : [Child(U64), NoChild], custom : U64 }),

		## A custom block's panel is not a supported panel drawing.
		CustomDrawing({ custom : U64, reason : Str }),

		## A custom block's measured box is not positive, or its inset leaves
		## no content box.
		CustomMeasure({ custom : U64 }),

		## A custom block's name is empty.
		CustomName({ custom : U64 }),
		EmptyContainer({ group : U64 }),

		## A decoration's drawing is not a supported flow drawing.
		DecorationDrawing({ decoration : U64, reason : Str }),

		## A decoration with no following flow block, or inside a lead
		## region.
		DecorationPosition({ decoration : U64 }),
		EmptyInline({ block : U64, inline : U64 }),
		EmptyKeep({ group : U64 }),
		EmptyScope({ group : U64 }),
		EmptyLanguage,
		EmptyLinkText({ block : U64, inline : U64 }),
		EmptyList({ group : U64 }),
		EmptyListItem({ group : U64 }),
		EmptyMetadataTitle,
		EmptyRichParagraph({ block : U64 }),

		## A figure's alternative text is empty.
		FigureAlternativeEmpty({ block : U64 }),

		## A figure's visible caption is empty.
		FigureCaptionEmpty({ block : U64 }),

		## A figure's drawing is not a supported flow drawing.
		FigureDrawing({ block : U64, reason : Str }),

		## A figure's fit floor is above 100 percent.
		FigureFitInvalid({ block : U64 }),

		## A page field or reserved width in body content: page fields are
		## page furniture only.
		FurnitureInline({ block : U64, inline : U64 }),
		InlineDepthExceeded({ attempted : U64, block : U64, inline : U64, limit : U64 }),
		InvalidInlineLanguage({ block : U64, inline : U64 }),
		InvalidInlineUri({ block : U64, error : Document.NavigationError, inline : U64 }),
		InvalidList({ block : U64 }),
		LineBreakPosition({ block : U64, line_break : U64 }),
		ListDepthExceeded({ attempted : U64, group : U64, limit : U64 }),
		ListItemBlock({ block : U64 }),
		ListItemBreak({ page_break : U64 }),
		ListItemDecoration({ decoration : U64 }),
		ListItemGroup({ group : U64 }),
		ListItemSpacer({ spacer : U64 }),
		ListItemStart({ group : U64 }),
		ListNumbering({ group : U64 }),
		NegativeSpacer({ spacer : U64 }),
		NestedLink({ block : U64, inline : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),

		## A content bound crossed while planning authored leaf `block`: the
		## facade's documented size bounds, located at the first block that
		## exceeds them.
		BlockLimitExceeded({ attempted : U64, block : U64, dimension : Dimension, limit : U64 }),
		Source(KernelFacadeSources.Error),
		TableCellEmpty({ block : U64 }),
		TableEmpty({ group : U64 }),
		TableGridMismatch({ columns : U64, group : U64, spanned : U64 }),
		TableHeaderMissing({ group : U64 }),
		TableRowSpan({ block : U64 }),
		TextSemantics(KernelTextSemantics.Error),
		UnsupportedHeadingLevel({ block : U64, level : U8 }),

		## A numbered heading more than one level deeper than the heading
		## before it in reading order (`semantics.heading_skip`).
		HeadingSkip({ block : U64, previous : U64 }),
	]
	Limits :: {
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

	## A rich paragraph owns a dense occurrence range, one occurrence per text
	## leaf in logical order, over its one interned source or, with explicit
	## line breaks, over one interned source per segment. `label` is the
	## generated list label painted on the block's first line, and `level`
	## the block's list nesting level (zero outside lists), which decides its
	## indentation.
	BlockOwnership : [RichTextBlock({ label : [Label(Semantics.OccurrenceId), NoLabel], level : U64, occurrences : Semantics.Range }), TextBlock({ body : Semantics.OccurrenceId, label : [Label(Semantics.OccurrenceId), NoLabel], level : U64 })]

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
		container_nodes : U64,
		content_writes : U64,
		header_association_edges : U64,
		inline_elements : U64,
		inline_leaves : U64,
		list_items : U64,
		lists : U64,
		node_writes : U64,
		occurrence_writes : U64,
		property_writes : U64,
		source_inputs : U64,
		table_cells : U64,
		tables : U64,
	}

	## A number in a generated number style: decimal digits, bijective
	## base-26 letters (`1` is `a`), or Roman numerals up to 3999. Shared by
	## list labels and page fields.
	number_text : Document.NumberStyle, U64 -> Str
	number_text = |style, value| number_digits(style, value)

	Plan :: {
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
	attribute_count : U64,
	cell_headers : List(U64),
	content_count : U64,
	destinations : List(KernelFacadeSemantics.DestinationRecord),
	group_nodes : List(U64),
	header_ranges : List(Semantics.Range),
	inline_elements : U64,
	inline_leaves : U64,
	links : List(KernelFacadeSemantics.LinkRecord),
	list_count : U64,
	list_item_count : U64,
	node_count : U64,
	occurrence_count : U64,
	property_count : U64,
	relationship_count : U64,
	source_inputs : List(Str),
	table_count : U64,
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
			authoring,
			block_ownership: built.block_ownership,
			destinations: planning.destinations,
			links: planning.links,
			preliminary,
			sources,
			work: {
				container_nodes: planning.group_nodes.len(),
				content_writes: built.store.content_spine.len(),
				header_association_edges: planning.relationship_count - captioned_figures(authoring.figures),
				inline_elements: planning.inline_elements,
				inline_leaves: planning.inline_leaves,
				list_items: planning.list_item_count,
				lists: planning.list_count,
				node_writes: built.store.nodes.len(),
				occurrence_writes: built.store.occurrences.len(),
				property_writes: built.store.text_properties.len(),
				source_inputs: planning.source_inputs.len(),
				table_cells: planning.header_ranges.len(),
				tables: planning.table_count,
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
	check_heading_progression(blocks)?
	source_bound = if blocks.len() > U64.highest / 2 U64.highest else blocks.len() * 2
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
	var $attribute_count = 0
	var $break_cursor = 0
	var $cell_cursor = 0
	var $cell_headers = []
	var $header_ranges = if authoring.cells.is_empty() [] else List.with_capacity(authoring.cells.len())
	var $relationship_count = 0
	var $table_count = 0
	var $block_index = 0
	check_limit($next_node, limits.max_nodes, Nodes)?

	## One flat loop merges container openings into the block walk: a
	## container opens immediately before its first descendant block, or at
	## the end for containers that close the document.
	while $block_index < blocks.len() or $next_group < groups.len() {
		if $next_group < groups.len() and ($block_index >= blocks.len() or list_at(groups, $next_group).first_block <= $block_index) {
			group = list_at(groups, $next_group)
			in_item = in_list_item(groups, group.parent)
			match group.kind {
				Container(_) | Custom(_) | LeadRegion | FigureGroup(_) => {
					if in_item {
						return Err(ListItemGroup({ group: $next_group }))
					}
					if group.depth > limits.max_container_depth {
						return Err(ContainerDepthExceeded({ attempted: group.depth, group: $next_group, limit: limits.max_container_depth }))
					}
					attempted_nodes = checked_add($next_node, 1)?
					attempted_content = checked_add($content_count, 1)?
					check_at(attempted_nodes, limits.max_nodes, Nodes, $block_index)?
					check_at(attempted_content, limits.max_content_spine, ContentSpine, $block_index)?
					$group_nodes = $group_nodes.append($next_node)
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: semantic_code(groups, group.parent) })
					$next_node = attempted_nodes
					$content_count = attempted_content
				}
				Scope(_) => {
					if in_item {
						return Err(ListItemGroup({ group: $next_group }))
					}
					if group.first_block >= group.block_end {
						return Err(EmptyScope({ group: $next_group }))
					}

					## A scope has no structure element either: it only
					## recolors inline text inside it.
					$group_nodes = $group_nodes.append(parent_node(group.parent, $group_nodes).index())
				}
				KeepTogether | KeepWithNext(_) => {
					if in_item {
						return Err(ListItemGroup({ group: $next_group }))
					}
					if group.first_block >= group.block_end {
						return Err(EmptyKeep({ group: $next_group }))
					}

					## A keep has no structure element: its children belong to
					## the nearest semantic ancestor.
					$group_nodes = $group_nodes.append(parent_node(group.parent, $group_nodes).index())
				}
				ItemList(list_index) => {
					if group.depth > list_depth_limit {
						return Err(ListDepthExceeded({ attempted: group.depth, group: $next_group, limit: list_depth_limit }))
					}
					if group.group_end == $next_group + 1 {
						return Err(EmptyList({ group: $next_group }))
					}
					check_numbering(list_at(authoring.lists, list_index.to_u64()), $next_group)?
					attempted_nodes = checked_add($next_node, 1)?
					attempted_content = checked_add($content_count, 1)?
					check_at(attempted_nodes, limits.max_nodes, Nodes, $block_index)?
					check_at(attempted_content, limits.max_content_spine, ContentSpine, $block_index)?
					$group_nodes = $group_nodes.append($next_node)
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: semantic_code(groups, group.parent) })
					$next_node = attempted_nodes
					$content_count = attempted_content
					$attribute_count = checked_add($attribute_count, 1)?
					$list_count = checked_add($list_count, 1)?
				}
				Table(table_index) => {
					if in_item {
						return Err(ListItemGroup({ group: $next_group }))
					}

					## A table plans its whole subtree at once: its rows and
					## cells are fixed-depth descendants, so the walk resumes
					## after the table's last group and leaf.
					planned = plan_table(
						authoring,
						$next_group,
						table_index.to_u64(),
						{ break_cursor: $break_cursor, cell: $cell_cursor, header_base: $cell_headers.len(), node: $next_node, occurrence: $next_occurrence },
						limits.max_inline_depth,
					)?
					attempted_nodes = checked_add($next_node, planned.nodes)?
					attempted_occurrences = checked_add($next_occurrence, planned.occurrences)?
					attempted_content = checked_add($content_count, planned.content)?
					attempted_properties = checked_add($property_count, planned.expansions)?
					check_at(attempted_nodes, limits.max_nodes, Nodes, group.first_block)?
					check_at(attempted_occurrences, limits.max_occurrences, Occurrences, group.first_block)?
					check_at(attempted_content, limits.max_content_spine, ContentSpine, group.first_block)?
					check_at(attempted_properties, limits.max_properties, Properties, group.first_block)?
					check_at(checked_add($sources.len(), planned.buffers.sources.len())?, limits.max_source_inputs, SourceInputs, group.first_block)?
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: semantic_code(groups, group.parent) })

					## The table's own buffers are appended to the document's
					## accumulators, which stay uniquely owned here: handing
					## them to `plan_table` and splitting them back out of its
					## result would copy every one of them once per table.
					for value in planned.buffers.group_nodes {
						$group_nodes = $group_nodes.append(value)
					}
					for value in planned.buffers.headers {
						$cell_headers = $cell_headers.append(value)
					}
					for value in planned.buffers.links {
						$links = $links.append(value)
					}
					for value in planned.buffers.ranges {
						$header_ranges = $header_ranges.append(value)
					}
					for value in planned.buffers.sources {
						$sources = $sources.append(value)
					}
					$next_node = attempted_nodes
					$next_occurrence = attempted_occurrences
					$content_count = attempted_content
					$property_count = attempted_properties
					$attribute_count = checked_add($attribute_count, planned.attributes)?
					$relationship_count = checked_add($relationship_count, planned.relationships)?
					$inline_elements = checked_add($inline_elements, planned.elements)?
					$inline_leaves = checked_add($inline_leaves, planned.leaves)?
					$break_cursor = $break_cursor + planned.breaks
					$cell_cursor = $cell_cursor + planned.cells
					$table_count = $table_count + 1
					$block_index = group.block_end
					$next_group = group.group_end - 1
				}
				TableRow(_) => {
					crash "normalized table row escaped its table"
				}
				ListItem(ordinal) => {
					if group.first_block >= group.block_end {
						return Err(EmptyListItem({ group: $next_group }))
					}
					first = list_at(blocks, group.first_block)
					starts_with_paragraph = first.parent == $next_group + 1 and (match first.kind {
						Paragraph | RichParagraph(_) => True
						_ => False
					})
					if !starts_with_paragraph {
						return Err(ListItemStart({ group: $next_group }))
					}
					label = item_label(authoring, group.parent, ordinal)
					attempted_nodes = checked_add($next_node, 3)?
					attempted_occurrences = checked_add($next_occurrence, 1)?
					attempted_content = checked_add($content_count, 4)?
					attempted_properties = checked_add($property_count, 1)?
					attempted_sources = checked_add($sources.len(), 1)?
					check_at(attempted_nodes, limits.max_nodes, Nodes, $block_index)?
					check_at(attempted_occurrences, limits.max_occurrences, Occurrences, $block_index)?
					check_at(attempted_content, limits.max_content_spine, ContentSpine, $block_index)?
					check_at(attempted_properties, limits.max_properties, Properties, $block_index)?
					check_at(attempted_sources, limits.max_source_inputs, SourceInputs, $block_index)?

					## `LI` joins its list's span; the item's children join
					## `LBody`, which the item group resolves to.
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: group.parent })
					$group_nodes = $group_nodes.append($next_node + 2)
					$sources = $sources.append(label)
					$next_node = attempted_nodes
					$next_occurrence = attempted_occurrences
					$content_count = attempted_content
					$property_count = attempted_properties
					$list_item_count = checked_add($list_item_count, 1)?
				}
			}
			$list_state = NoActiveList
			$next_group = $next_group + 1
		} else {
			block = list_at(blocks, $block_index)
			if in_list_item(groups, block.parent) {
				match block.kind {
					Paragraph | RichParagraph(_) => {}
					_ => return Err(ListItemBlock({ block: $block_index }))
				}
			}
			match block.kind {
				Bullet({ item, list }) => {
					node_increment = if item == 0 4 else 3
					content_increment = if item == 0 6 else 5
					attempted_nodes = checked_add($next_node, node_increment)?
					attempted_occurrences = checked_add($next_occurrence, 2)?
					attempted_content = checked_add($content_count, content_increment)?
					attempted_properties = checked_add($property_count, 1)?
					attempted_sources = checked_add($sources.len(), 2)?
					check_at(attempted_nodes, limits.max_nodes, Nodes, $block_index)?
					check_at(attempted_occurrences, limits.max_occurrences, Occurrences, $block_index)?
					check_at(attempted_content, limits.max_content_spine, ContentSpine, $block_index)?
					check_at(attempted_properties, limits.max_properties, Properties, $block_index)?
					check_at(attempted_sources, limits.max_source_inputs, SourceInputs, $block_index)?
					_list_node = if item == 0 {
						if list != $next_list {
							return Err(InvalidList({ block: $block_index }))
						}
						node = $next_node
						$next_node = checked_add($next_node, 1)?
						$next_list = checked_add($next_list, 1)?
						$list_count = checked_add($list_count, 1)?
						$attribute_count = checked_add($attribute_count, 1)?
						$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index(node), parent: semantic_code(groups, block.parent) })
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
					check_at(attempted_nodes, limits.max_nodes, Nodes, $block_index)?
					check_at(attempted_occurrences, limits.max_occurrences, Occurrences, $block_index)?
					check_at(attempted_content, limits.max_content_spine, ContentSpine, $block_index)?
					check_at(attempted_sources, limits.max_source_inputs, SourceInputs, $block_index)?
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: semantic_code(groups, block.parent) })
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
					check_at(attempted_nodes, limits.max_nodes, Nodes, $block_index)?
					check_at(attempted_occurrences, limits.max_occurrences, Occurrences, $block_index)?
					check_at(attempted_content, limits.max_content_spine, ContentSpine, $block_index)?
					check_at(attempted_sources, limits.max_source_inputs, SourceInputs, $block_index)?
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: semantic_code(groups, block.parent) })
					$sources = $sources.append(block.text)
					$next_node = checked_add($next_node, 1)?
					$next_occurrence = checked_add($next_occurrence, 1)?
					$content_count = attempted_content
					$list_state = NoActiveList
				}
				Figure(figure_index) => {
					check_figure(list_at(authoring.figures, figure_index), $block_index)?
					attempted_nodes = checked_add($next_node, 1)?
					attempted_occurrences = checked_add($next_occurrence, 1)?
					attempted_content = checked_add($content_count, 2)?
					attempted_sources = checked_add($sources.len(), 1)?
					attempted_properties = checked_add($property_count, 1)?
					check_at(attempted_nodes, limits.max_nodes, Nodes, $block_index)?
					check_at(attempted_occurrences, limits.max_occurrences, Occurrences, $block_index)?
					check_at(attempted_content, limits.max_content_spine, ContentSpine, $block_index)?
					check_at(attempted_sources, limits.max_source_inputs, SourceInputs, $block_index)?
					check_at(attempted_properties, limits.max_properties, Properties, $block_index)?
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: semantic_code(groups, block.parent) })
					$sources = $sources.append(block.text)
					$next_node = attempted_nodes
					$next_occurrence = attempted_occurrences
					$content_count = attempted_content
					$property_count = attempted_properties
					$list_state = NoActiveList
				}

				## A caption is `Caption > P` beside its figure, with one
				## `CaptionFor` relationship from the caption to the figure.
				FigureCaption(_) => {
					if block.text.is_empty() {
						return Err(FigureCaptionEmpty({ block: $block_index }))
					}
					attempted_nodes = checked_add($next_node, 2)?
					attempted_occurrences = checked_add($next_occurrence, 1)?
					attempted_content = checked_add($content_count, 3)?
					attempted_sources = checked_add($sources.len(), 1)?
					check_at(attempted_nodes, limits.max_nodes, Nodes, $block_index)?
					check_at(attempted_occurrences, limits.max_occurrences, Occurrences, $block_index)?
					check_at(attempted_content, limits.max_content_spine, ContentSpine, $block_index)?
					check_at(attempted_sources, limits.max_source_inputs, SourceInputs, $block_index)?
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: semantic_code(groups, block.parent) })
					$sources = $sources.append(block.text)
					$next_node = attempted_nodes
					$next_occurrence = attempted_occurrences
					$content_count = attempted_content
					$relationship_count = checked_add($relationship_count, 1)?
					$list_state = NoActiveList
				}
				DestinationHeading({ level, name }) => {
					_role = heading_role(level, $block_index)?
					attempted_nodes = checked_add($next_node, 1)?
					attempted_occurrences = checked_add($next_occurrence, 1)?
					attempted_content = checked_add($content_count, 2)?
					attempted_sources = checked_add($sources.len(), 1)?
					check_at(attempted_nodes, limits.max_nodes, Nodes, $block_index)?
					check_at(attempted_occurrences, limits.max_occurrences, Occurrences, $block_index)?
					check_at(attempted_content, limits.max_content_spine, ContentSpine, $block_index)?
					check_at(attempted_sources, limits.max_source_inputs, SourceInputs, $block_index)?
					$destinations = $destinations.append({ anchor: Semantics.OccurrenceId.from_index($next_occurrence), name, target: Semantics.NodeId.from_index($next_node) })
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: semantic_code(groups, block.parent) })
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
					check_at(attempted_nodes, limits.max_nodes, Nodes, $block_index)?
					check_at(attempted_occurrences, limits.max_occurrences, Occurrences, $block_index)?
					check_at(attempted_content, limits.max_content_spine, ContentSpine, $block_index)?
					check_at(attempted_sources, limits.max_source_inputs, SourceInputs, $block_index)?
					$destinations = $destinations.append({ anchor: Semantics.OccurrenceId.from_index($next_occurrence), name, target: Semantics.NodeId.from_index($next_node) })
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: semantic_code(groups, block.parent) })
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
					check_at(attempted_nodes, limits.max_nodes, Nodes, $block_index)?
					check_at(attempted_occurrences, limits.max_occurrences, Occurrences, $block_index)?
					check_at(attempted_content, limits.max_content_spine, ContentSpine, $block_index)?
					check_at(attempted_sources, limits.max_source_inputs, SourceInputs, $block_index)?
					$links = $links.append({ node: Semantics.NodeId.from_index($next_node + 1), occurrences: Semantics.Range.from_start_and_length($next_occurrence, 1), target: Uri(uri) })
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: semantic_code(groups, block.parent) })
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
					check_at(attempted_nodes, limits.max_nodes, Nodes, $block_index)?
					check_at(attempted_occurrences, limits.max_occurrences, Occurrences, $block_index)?
					check_at(attempted_content, limits.max_content_spine, ContentSpine, $block_index)?
					check_at(attempted_sources, limits.max_source_inputs, SourceInputs, $block_index)?
					$links = $links.append({ node: Semantics.NodeId.from_index($next_node + 1), occurrences: Semantics.Range.from_start_and_length($next_occurrence, 1), target: InternalDestination(destination) })
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: semantic_code(groups, block.parent) })
					$sources = $sources.append(block.text)
					$next_node = attempted_nodes
					$next_occurrence = checked_add($next_occurrence, 1)?
					$content_count = attempted_content
					$list_state = NoActiveList
				}
				RichParagraph(paragraph) => {
					rich = list_at(authoring.rich_paragraphs, paragraph)
					checked = check_rich(authoring.inlines, rich, $block_index, limits.max_inline_depth)?
					breaks = paragraph_breaks(authoring.line_breaks, $break_cursor, paragraph)
					check_breaks(authoring.line_breaks, $break_cursor, breaks, rich, $block_index)?
					attempted_nodes = checked_add($next_node, checked_add(rich.elements, 1)?)?
					attempted_occurrences = checked_add($next_occurrence, rich.leaves)?
					attempted_content = checked_add($content_count, checked_add(rich.length, 1)?)?
					attempted_properties = checked_add($property_count, checked.expansions)?
					attempted_sources = checked_add($sources.len(), checked_add(breaks, 1)?)?
					check_at(attempted_nodes, limits.max_nodes, Nodes, $block_index)?
					check_at(attempted_occurrences, limits.max_occurrences, Occurrences, $block_index)?
					check_at(attempted_content, limits.max_content_spine, ContentSpine, $block_index)?
					check_at(attempted_properties, limits.max_properties, Properties, $block_index)?
					check_at(attempted_sources, limits.max_source_inputs, SourceInputs, $block_index)?
					if checked.links != 0 {
						$links = append_rich_links($links, authoring.inlines, rich, $next_node, $next_occurrence)
					}
					$top_nodes = $top_nodes.append({ node: Semantics.NodeId.from_index($next_node), parent: semantic_code(groups, block.parent) })
					$sources = if breaks == 0 $sources.append(block.text) else append_segment_sources($sources.append(block.text), authoring.line_breaks, $break_cursor, breaks)
					$break_cursor = $break_cursor + breaks
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
	check_layout_items(authoring)?
	check_customs(authoring)?
	check_decorations(authoring)?
	Ok({ attribute_count: $attribute_count, cell_headers: $cell_headers, content_count: $content_count, destinations: $destinations, group_nodes: $group_nodes, header_ranges: $header_ranges, inline_elements: $inline_elements, inline_leaves: $inline_leaves, links: $links, list_count: $list_count, list_item_count: $list_item_count, node_count: $next_node, occurrence_count: $next_occurrence, property_count: $property_count, relationship_count: $relationship_count, source_inputs: $sources, table_count: $table_count, top_nodes: $top_nodes })
}

TableCursor : { break_cursor : U64, cell : U64, header_base : U64, node : U64, occurrence : U64 }

TableBuffers : { group_nodes : List(U64), headers : List(U64), links : List(KernelFacadeSemantics.LinkRecord), ranges : List(Semantics.Range), sources : List(Str) }

TablePlan : { attributes : U64, breaks : U64, buffers : TableBuffers, cells : U64, content : U64, elements : U64, expansions : U64, leaves : U64, nodes : U64, occurrences : U64, relationships : U64 }

## Validate and count one table in authored order: a table needs columns
## and a body row; each cell has non-empty inline content and no row span;
## each row's column spans sum to the column count; and at least one cell is
## a header cell. Nodes are numbered in preorder: `Table`, the optional
## `Caption > P`, then each present section (`THead`, `TBody`, `TFoot`)
## before its rows, each `TR` before its cells, and each cell before its
## inline elements. The `Headers` of every data cell are derived here from
## declared scopes, never from geometry: the `Column`- or `Both`-scoped
## header cells of earlier rows in the columns it spans (ascending cell
## order), then the `Row`- or `Both`-scoped header cells of its own row.
## Header cells carry no `Headers`. Each cell's range into the flattened
## header list is recorded in table order, one per cell.
plan_table : Document.NormalizedAuthoring, U64, U64, TableCursor, U64 -> Try(TablePlan, KernelFacadeSemantics.Error)
plan_table = |authoring, group_index, table_index, at, max_depth| {
	group = list_at(authoring.groups, group_index)
	table = list_at(authoring.tables, table_index)
	columns = table.columns.len()
	if columns == 0 or table.body_rows == 0 {
		return Err(TableEmpty({ group: group_index }))
	}
	caption_nodes = if table.caption 2 else 0
	sections = (if table.header_rows > 0 1 else 0) + 1 + (if table.footer_rows > 0 1 else 0)

	## Fresh table-sized buffers; the caller appends them to its own.
	var $group_nodes = List.with_capacity(group.group_end - group_index).append(at.node)
	var $headers = []
	var $links = []
	var $ranges = List.with_capacity(group.block_end - group.first_block)
	var $sources = List.with_capacity(group.block_end - group.first_block)
	var $next_node = at.node + 1 + caption_nodes
	var $content = 1 + (if table.caption 1 else 0) + sections + caption_nodes
	var $occurrences = 0
	var $attributes = 0
	var $relationships = 0
	var $expansions = 0
	var $elements = 0
	var $leaves = 0
	var $breaks = 0
	if table.caption {
		$sources = $sources.append(list_at(authoring.blocks, group.first_block).text)
		$occurrences = 1
	}
	var $column_headers = List.repeat([], columns)
	var $row_headers = []
	var $has_header = False
	var $cell = at.cell
	var $row_ordinal = 0
	var $row_group = group_index + 1
	while $row_group < group.group_end {
		row = list_at(authoring.groups, $row_group)

		## A section element precedes its first row.
		if ($row_ordinal == 0 and table.header_rows > 0) or $row_ordinal == table.header_rows or ($row_ordinal == table.header_rows + table.body_rows and table.footer_rows > 0) {
			$next_node = $next_node + 1
		}
		$group_nodes = $group_nodes.append($next_node)
		$next_node = $next_node + 1
		$content = $content + 1 + (row.block_end - row.first_block)
		$row_headers = $row_headers.take_first(0)
		first_cell = $cell
		var $spanned = 0
		var $block = row.first_block
		while $block < row.block_end {
			record = list_at(authoring.cells, $cell)
			if record.row_span != 1 {
				return Err(TableRowSpan({ block: $block }))
			}
			if record.column_span == 0 {
				return Err(TableGridMismatch({ columns, group: $row_group, spanned: $spanned }))
			}
			paragraph = match list_at(authoring.blocks, $block).kind {
				RichParagraph(value) => value
				_ => crash "normalized table cell escaped its rich paragraph"
			}
			rich = list_at(authoring.rich_paragraphs, paragraph)
			checked = match check_rich(authoring.inlines, rich, $block, max_depth) {
				Ok(value) => value
				Err(EmptyRichParagraph({ block: empty })) => return Err(TableCellEmpty({ block: empty }))
				Err(error) => return Err(error)
			}
			cursor = at.break_cursor + $breaks
			cell_breaks = paragraph_breaks(authoring.line_breaks, cursor, paragraph)
			check_breaks(authoring.line_breaks, cursor, cell_breaks, rich, $block)?
			if checked.links != 0 {
				$links = append_rich_links($links, authoring.inlines, rich, $next_node, at.occurrence + $occurrences)
			}
			$sources = if cell_breaks == 0 $sources.append(list_at(authoring.blocks, $block).text) else append_segment_sources($sources.append(list_at(authoring.blocks, $block).text), authoring.line_breaks, cursor, cell_breaks)
			$breaks = $breaks + cell_breaks
			$next_node = $next_node + 1 + rich.elements
			$content = $content + rich.length
			$occurrences = $occurrences + rich.leaves
			$expansions = $expansions + checked.expansions
			$elements = $elements + rich.elements
			$leaves = $leaves + rich.leaves
			$spanned = $spanned + record.column_span.to_u64()
			if record.column_span > 1 {
				$attributes = $attributes + 1
			}
			match record.kind {
				HeaderCell(scope) => {
					$has_header = True
					$attributes = $attributes + 1
					if scope != Column {
						$row_headers = $row_headers.append($cell)
					}
				}
				DataCell => {}
			}
			$cell = $cell + 1
			$block = $block + 1
		}
		if $spanned != columns {
			return Err(TableGridMismatch({ columns, group: $row_group, spanned: $spanned }))
		}

		## Every row's header cells are known before its data cells'
		## associations are derived; column headers come from earlier rows.
		var $column = 0
		var $index = first_cell
		while $index < $cell {
			record = list_at(authoring.cells, $index)
			local_start = $headers.len()
			start = at.header_base + local_start
			match record.kind {
				DataCell => {
					$headers = if record.column_span == 1 {
						append_all($headers, list_at($column_headers, $column))
					} else {
						append_spanned_headers($headers, $column_headers, $column, record.column_span.to_u64())
					}
					$headers = append_all($headers, $row_headers)
				}
				HeaderCell(_) => {}
			}
			count = $headers.len() - local_start
			if count != 0 {
				$attributes = $attributes + 1
				$relationships = $relationships + count
			}
			$ranges = $ranges.append(Semantics.Range.from_start_and_length(start, count))
			$column = $column + record.column_span.to_u64()
			$index = $index + 1
		}
		$column = 0
		$index = first_cell
		while $index < $cell {
			record = list_at(authoring.cells, $index)
			match record.kind {
				HeaderCell(scope) => if scope != Row {
					var $spanned_column = $column
					while $spanned_column < $column + record.column_span.to_u64() {
						$column_headers = list_set($column_headers, $spanned_column, list_at($column_headers, $spanned_column).append($index))
						$spanned_column = $spanned_column + 1
					}
				}
				DataCell => {}
			}
			$column = $column + record.column_span.to_u64()
			$index = $index + 1
		}
		$row_ordinal = $row_ordinal + 1
		$row_group = $row_group + 1
	}
	if !$has_header {
		return Err(TableHeaderMissing({ group: group_index }))
	}
	Ok({
		attributes: $attributes,
		breaks: $breaks,
		buffers: { group_nodes: $group_nodes, headers: $headers, links: $links, ranges: $ranges, sources: $sources },
		cells: $cell - at.cell,
		content: $content,
		elements: $elements,
		expansions: $expansions,
		leaves: $leaves,
		nodes: $next_node - at.node,
		occurrences: $occurrences,
		relationships: $relationships,
	})
}

## The union of the column headers of a spanning data cell's columns, in
## ascending cell order and without repeats (a spanning header cell heads
## every column it spans).
append_spanned_headers : List(U64), List(List(U64)), U64, U64 -> List(U64)
append_spanned_headers = |headers, column_headers, column, span| {
	var $merged = []
	var $index = column
	while $index < column + span {
		$merged = append_all($merged, list_at(column_headers, $index))
		$index = $index + 1
	}
	sorted = $merged.sort_with(|left, right| if left < right Before else if left > right After else Same)
	var $headers = headers
	var $previous = U64.highest
	for value in sorted {
		if value != $previous {
			$headers = $headers.append(value)
			$previous = value
		}
	}
	$headers
}

## Lists nest at most four deep. With 16 containers, a list level's
## `L > LI > LBody`, the paragraph, and 8 inline elements, the deepest
## facade chain stays below the kernel semantic depth bound.
list_depth_limit : U64
list_depth_limit = 4

## Whether group code `code` (`0` or `g + 1`) names a list item.
in_list_item : List(Document.NormalizedGroup), U64 -> Bool
in_list_item = |groups, code| if code == 0 {
	False
} else {
	match list_at(groups, code - 1).kind {
		ListItem(_) => True
		_ => False
	}
}

## The nearest semantic group code at or above `code`: keep groups are
## layout-only, so their children belong to the group around them.
semantic_code : List(Document.NormalizedGroup), U64 -> U64
semantic_code = |groups, code| {
	var $code = code
	var $searching = True
	while $searching and $code != 0 {
		group = list_at(groups, $code - 1)
		match group.kind {
			KeepTogether | KeepWithNext(_) | Scope(_) => {
				$code = group.parent
			}
			_ => {
				$searching = False
			}
		}
	}
	$code
}

## A block's list nesting level: the depth of the list item that directly
## holds it (list items hold only paragraphs and lists), else zero.
block_level : List(Document.NormalizedGroup), U64 -> U64
block_level = |groups, code| if code == 0 {
	0
} else {
	group = list_at(groups, code - 1)
	match group.kind {
		ListItem(_) => group.depth
		_ => 0
	}
}

## Page breaks and spacers are flow constructs of the block level; a list
## item holds only paragraphs and lists. A spacer's height is never
## negative.
check_layout_items : Document.NormalizedAuthoring -> Try({}, KernelFacadeSemantics.Error)
check_layout_items = |authoring| {
	var $index = 0
	while $index < authoring.page_breaks.len() {
		if in_list_item(authoring.groups, list_at(authoring.page_breaks, $index).parent) {
			return Err(ListItemBreak({ page_break: $index }))
		}
		$index = $index + 1
	}
	$index = 0
	while $index < authoring.spacers.len() {
		spacer = list_at(authoring.spacers, $index)
		if in_list_item(authoring.groups, spacer.parent) {
			return Err(ListItemSpacer({ spacer: $index }))
		}
		if spacer.amount.raw() < 0 {
			return Err(NegativeSpacer({ spacer: $index }))
		}
		$index = $index + 1
	}
	Ok({})
}

## The number of figures with a caption, each adding one `CaptionFor`.
captioned_figures : List(Document.NormalizedFigure) -> U64
captioned_figures = |figures| {
	var $count = 0
	for figure in figures {
		if figure.captioned {
			$count = $count + 1
		}
	}
	$count
}

## A figure has non-empty alternative text, a valid flow drawing, and a fit
## floor of at most 100 percent.
check_figure : Document.NormalizedFigure, U64 -> Try({}, KernelFacadeSemantics.Error)
check_figure = |figure, block| {
	if figure.alternative.is_empty() {
		return Err(FigureAlternativeEmpty({ block: block }))
	}
	match figure.drawing {
		InvalidDrawing(reason) => return Err(FigureDrawing({ block, reason }))
		ValidDrawing(_) => {}
	}
	match figure.fit {
		ExactFit => Ok({})
		ScaleFit(floor) => if floor > 100 Err(FigureFitInvalid({ block: block })) else Ok({})
	}
}

## A custom block (v1 of the seam) holds only paragraphs and rich
## paragraphs directly: no nested groups, decorations, spacers, or page
## breaks, which would need layout inside the extension's measured box. It
## is a body-flow block, never in the lead region. Its name is non-empty
## and its panel a valid flow drawing of solid paths only (no images) that
## lies inside its box. O(customs + leaves + flow items).
check_customs : Document.NormalizedAuthoring -> Try({}, KernelFacadeSemantics.Error)
check_customs = |authoring| {
	if authoring.customs.is_empty() {
		return Ok({})
	}
	var $index = 0
	while $index < authoring.customs.len() {
		custom = list_at(authoring.customs, $index)
		group = list_at(authoring.groups, custom.group)
		code = custom.group + 1
		if in_lead_region(authoring.groups, group.parent) {
			return Err(CustomContent({ child: NoChild, custom: $index }))
		}
		if group.group_end > custom.group + 1 {
			return Err(CustomContent({ child: Child(list_at(authoring.groups, custom.group + 1).position), custom: $index }))
		}
		var $block = group.first_block
		while $block < group.block_end {
			match list_at(authoring.blocks, $block).kind {
				Paragraph | RichParagraph(_) => {}
				_ => return Err(CustomContent({ child: Child(custom_child_position(authoring, $block)), custom: $index }))
			}
			$block = $block + 1
		}
		for decoration in authoring.decorations {
			if decoration.parent == code {
				return Err(CustomContent({ child: Child(decoration.position), custom: $index }))
			}
		}
		for spacer in authoring.spacers {
			if spacer.parent == code {
				return Err(CustomContent({ child: Child(spacer.position), custom: $index }))
			}
		}
		for page_break in authoring.page_breaks {
			if page_break.parent == code {
				return Err(CustomContent({ child: Child(page_break.position), custom: $index }))
			}
		}
		if custom.name.is_empty() {
			return Err(CustomName({ custom: $index }))
		}
		inset = custom.inset.raw()
		if custom.width.raw() <= 0 or custom.height.raw() <= 0 or inset <= 0 or inset > (custom.width.raw() - 1) // 2 or inset > (custom.height.raw() - 1) // 2 {
			return Err(CustomMeasure({ custom: $index }))
		}
		match custom.panel {
			InvalidDrawing(reason) => return Err(CustomDrawing({ custom: $index, reason }))
			ValidDrawing(drawing) => {
				if !drawing.images.is_empty() {
					return Err(CustomDrawing({ custom: $index, reason: "a custom block panel holds solid paths only, no images" }))
				}
				if drawing.width > custom.width.raw().to_u64_wrap() or drawing.height > custom.height.raw().to_u64_wrap() {
					return Err(CustomDrawing({ custom: $index, reason: "the panel extends beyond the custom block's measured box" }))
				}
			}
		}
		$index = $index + 1
	}
	Ok({})
}

## The authored position of a leaf inside its custom block: a rich
## paragraph records it; any other leaf is located by counting the leaves
## before it in the block, which holds no other children when it is valid.
custom_child_position : Document.NormalizedAuthoring, U64 -> U64
custom_child_position = |authoring, block| {
	record = list_at(authoring.blocks, block)
	match record.kind {
		RichParagraph(paragraph) => list_at(authoring.rich_paragraphs, paragraph).position
		_ => {
			group = list_at(authoring.groups, record.parent - 1)
			block - group.first_block
		}
	}
}

## A decoration is a block-level flow construct: never in a list item or a
## lead region, always followed by a flow block, and with a valid drawing.
check_decorations : Document.NormalizedAuthoring -> Try({}, KernelFacadeSemantics.Error)
check_decorations = |authoring| {
	var $index = 0
	while $index < authoring.decorations.len() {
		decoration = list_at(authoring.decorations, $index)
		if in_list_item(authoring.groups, decoration.parent) {
			return Err(ListItemDecoration({ decoration: $index }))
		}
		if decoration.block >= authoring.blocks.len() or in_lead_region(authoring.groups, decoration.parent) {
			return Err(DecorationPosition({ decoration: $index }))
		}
		match decoration.drawing {
			InvalidDrawing(reason) => return Err(DecorationDrawing({ decoration: $index, reason }))
			ValidDrawing(_) => {}
		}
		$index = $index + 1
	}
	Ok({})
}

## Whether group code `code` lies inside the first page's lead region.
in_lead_region : List(Document.NormalizedGroup), U64 -> Bool
in_lead_region = |groups, code| {
	var $code = code
	while $code != 0 {
		group = list_at(groups, $code - 1)
		match group.kind {
			LeadRegion => return True
			_ => {
				$code = group.parent
			}
		}
	}
	False
}

## Every generated number must be representable in its style: letters and
## Roman numerals start at 1, and Roman numerals stop at 3999.
check_numbering : Document.NormalizedList, U64 -> Try({}, KernelFacadeSemantics.Error)
check_numbering = |list, group| match list.marker {
	Bullet => Ok({})
	Numbered({ start, style }) => {
		valid = match U64.plus_try(start, list.items - 1) {
			Err(_) => False
			Ok(last) => match style {
				Decimal => True
				LowerAlpha | UpperAlpha => start >= 1
				LowerRoman | UpperRoman => start >= 1 and last <= 3999
			}
		}
		if valid Ok({}) else Err(ListNumbering({ group: group }))
	}
}

## The generated label text of item `ordinal` in the list group `list_code`.
item_label : Document.NormalizedAuthoring, U64, U32 -> Str
item_label = |authoring, list_code, ordinal| match list_at(authoring.groups, list_code - 1).kind {
	ItemList(index) => list_label(list_at(authoring.lists, index.to_u64()).marker, ordinal.to_u64())
	_ => crash "validated list item parent escaped"
}

## A bullet is `•`; a number is its value in the list's style followed by a
## full stop, such as `3.`, `c.`, or `iv.`.
list_label : Document.ListMarker, U64 -> Str
list_label = |marker, ordinal| match marker {
	Bullet => "•"
	Numbered({ start, style }) => {
		digits = number_digits(style, start + ordinal)
		"${digits}."
	}
}

number_digits : Document.NumberStyle, U64 -> Str
number_digits = |style, value| match style {
	Decimal => value.to_str()
	LowerAlpha => alphabetic(value, 97)
	UpperAlpha => alphabetic(value, 65)
	LowerRoman => roman(value, Lower)
	UpperRoman => roman(value, Upper)
}

## Bijective base-26 letters: 1 is `a`, 26 is `z`, 27 is `aa`.
alphabetic : U64, U8 -> Str
alphabetic = |value, base| {
	var $remaining = value
	var $reversed = []
	while $remaining > 0 {
		$remaining = $remaining - 1
		$reversed = $reversed.append(base + ($remaining % 26).to_u8_wrap())
		$remaining = $remaining // 26
	}
	var $bytes = List.with_capacity($reversed.len())
	var $index = $reversed.len()
	while $index > 0 {
		$index = $index - 1
		$bytes = $bytes.append(list_at($reversed, $index))
	}
	match Str.from_utf8($bytes) {
		Ok(text) => text
		Err(_) => crash "generated list letters escaped ASCII"
	}
}

## Roman numerals from 1 to 3999 in subtractive notation.
roman : U64, [Lower, Upper] -> Str
roman = |value, case| {
	symbols = match case {
		Upper => [("M", 1000), ("CM", 900), ("D", 500), ("CD", 400), ("C", 100), ("XC", 90), ("L", 50), ("XL", 40), ("X", 10), ("IX", 9), ("V", 5), ("IV", 4), ("I", 1)]
		Lower => [("m", 1000), ("cm", 900), ("d", 500), ("cd", 400), ("c", 100), ("xc", 90), ("l", 50), ("xl", 40), ("x", 10), ("ix", 9), ("v", 5), ("iv", 4), ("i", 1)]
	}
	var $remaining = value
	var $text = ""
	for (symbol, amount) in symbols {
		while $remaining >= amount {
			$text = $text.concat(symbol)
			$remaining = $remaining - amount
		}
	}
	$text
}

## A paragraph's later segment texts, one source input each.
append_segment_sources : List(Str), List(Document.NormalizedLineBreak), U64, U64 -> List(Str)
append_segment_sources = |sources, line_breaks, cursor, count| {
	var $sources = sources
	var $segment = 0
	while $segment < count {
		$sources = $sources.append(list_at(line_breaks, cursor + $segment).text)
		$segment = $segment + 1
	}
	$sources
}

## The number of line breaks of rich paragraph `paragraph`, which start at
## `cursor` in the paragraph-ordered break arena.
paragraph_breaks : List(Document.NormalizedLineBreak), U64, U64 -> U64
paragraph_breaks = |line_breaks, cursor, paragraph| {
	var $end = cursor
	while $end < line_breaks.len() and list_at(line_breaks, $end).paragraph == paragraph {
		$end = $end + 1
	}
	$end - cursor
}

## A line break separates text: every segment it bounds holds a text leaf,
## so a break at either end of the paragraph or directly after another is
## rejected, naming the break.
check_breaks : List(Document.NormalizedLineBreak), U64, U64, Document.NormalizedRich, U64 -> Try({}, KernelFacadeSemantics.Error)
check_breaks = |line_breaks, cursor, count, rich, block| {
	var $previous = 0
	var $index = 0
	while $index < count {
		record = list_at(line_breaks, cursor + $index)
		if record.leaf <= $previous or record.leaf >= rich.leaves {
			return Err(LineBreakPosition({ block, line_break: cursor + $index }))
		}
		$previous = record.leaf
		$index = $index + 1
	}
	Ok({})
}

## Validate one rich paragraph's inline span in preorder; the first failure
## in authored order wins. Every text leaf is non-empty, every element holds
## text, inline elements nest at most `max_depth` deep, links never contain
## links, language tags are well formed, and URIs pass the navigation URI
## grammar. Returns the counts semantic planning reserves.
check_rich : List(Document.NormalizedInline), Document.NormalizedRich, U64, U64 -> Try({ expansions : U64, links : U64 }, KernelFacadeSemantics.Error)
check_rich = |inlines, rich, block, max_depth| {
	## A page field or reserved width in body content is rejected first,
	## with its inline path; it holds no text, so the emptiness checks
	## below would otherwise misname it.
	var $scan = rich.inlines
	while $scan < rich.inlines + rich.length {
		match list_at(inlines, $scan).kind {
			FurnitureOnly => return Err(FurnitureInline({ block, inline: $scan }))
			_ => {}
		}
		$scan = $scan + 1
	}
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

## Numbered headings never skip a level downward: each heading is at most
## one level deeper than the heading before it in reading order (the first
## heading may have any level). Levels outside 1..6 are left to
## `heading_role`. One pass over the normalized blocks, O(blocks).
check_heading_progression : List(Document.NormalizedBlock) -> Try({}, KernelFacadeSemantics.Error)
check_heading_progression = |blocks| {
	var $previous = U64.highest
	var $previous_level = 0
	var $index = 0
	for block in blocks {
		level = match block.kind {
			Heading(value) => value
			DestinationHeading({ level: value, name: _ }) => value
			_ => 0
		}
		if level >= 1 and level <= 6 {
			if $previous != U64.highest and level > $previous_level + 1 {
				return Err(HeadingSkip({ block: $index, previous: $previous }))
			}
			$previous = $index
			$previous_level = level
		}
		$index = $index + 1
	}
	Ok({})
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
	var $attributes = if planning.attribute_count == 0 [] else List.with_capacity(planning.attribute_count)
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
			node_index = list_at(planning.group_nodes, $group)
			span = Semantics.Range.from_start_and_length($span_start, children)
			match group.kind {
				Container(kind) => {
					if children == 0 {
						return Err(EmptyContainer({ group: $group }))
					}
					$nodes = list_set($nodes, node_index, make_node(node_index, ParentNode(parent_node(group.parent, planning.group_nodes)), container_role(kind), span, Inherited))
				}

				## A custom block is a `Div` of its paragraphs.
				Custom(_) => {
					if children == 0 {
						return Err(EmptyContainer({ group: $group }))
					}
					$nodes = list_set($nodes, node_index, make_node(node_index, ParentNode(parent_node(group.parent, planning.group_nodes)), container_role(Division), span, Inherited))
				}

				## The first page's lead region is a `Div` of semantic
				## letterhead content, first in reading order.
				LeadRegion => {
					if children == 0 {
						return Err(EmptyContainer({ group: $group }))
					}
					$nodes = list_set($nodes, node_index, make_node(node_index, ParentNode(parent_node(group.parent, planning.group_nodes)), container_role(Division), span, Inherited))
				}

				## A captioned figure is a `Sect` of its `Figure` and its
				## `Caption`. `Div` and `Part` are transparent grouping
				## elements for PDF/UA-2 8.2.5.27 (a Caption is the first or
				## last child of its parent), so inside one the caption would
				## sit among the enclosing element's children.
				FigureGroup(_) => {
					$nodes = list_set($nodes, node_index, make_node(node_index, ParentNode(parent_node(group.parent, planning.group_nodes)), container_role(Section), span, Inherited))
				}
				KeepTogether | KeepWithNext(_) | Scope(_) => {}
				ItemList(list_index) => {
					attribute = $attributes.len()
					$attributes = $attributes.append(list_numbering(list_at(authoring.lists, list_index.to_u64()).marker))
					node = make_node(node_index, ParentNode(parent_node(group.parent, planning.group_nodes)), "L", span, Inherited)
					$nodes = list_set($nodes, node_index, { ..node, attributes: Semantics.Range.from_start_and_length(attribute, 1) })
				}
				ListItem(_) => {
					$nodes = list_set($nodes, node_index, make_node(node_index, ParentNode(Semantics.NodeId.from_index(node_index - 2)), "LBody", span, Inherited))
				}

				## A table places its whole subtree in the block walk below.
				Table(_) | TableRow(_) => {}
			}
			$span_start = $span_start + children
			$group = $group + 1
		}
	}
	var $occurrences = List.with_capacity(planning.occurrence_count)
	var $properties = List.with_capacity(planning.property_count)
	var $identifiers = if planning.header_ranges.is_empty() [] else List.with_capacity(planning.header_ranges.len())
	var $relationships = if planning.relationship_count == 0 [] else List.with_capacity(planning.relationship_count)
	var $ownership = List.repeat(TextBlock({ body: Semantics.OccurrenceId.from_index(0), label: NoLabel, level: 0 }), blocks.len())
	var $index = 0
	var $next_node = 1
	var $next_occurrence = 0
	var $source_input = 0
	var $next_group = 0
	var $break_cursor = 0
	var $pending_label = NoLabel
	while $index < blocks.len() {
		if $next_group < groups.len() and list_at(groups, $next_group).first_block <= $index {
			group = list_at(groups, $next_group)
			match group.kind {
				Container(_) | Custom(_) | ItemList(_) | LeadRegion | FigureGroup(_) => {
					$next_node = checked_add($next_node, 1)?
				}
				KeepTogether | KeepWithNext(_) | Scope(_) => {}
				Table(table_index) => {
					## The result is destructured in one pattern, so each
					## accumulator moves out of it: projecting the fields of a
					## still-live `placed` record left every document-sized
					## list shared and copied it once per table.
					{ attributes: placed_attributes, break_cursor: placed_break_cursor, buffers: { content: placed_content, nodes: placed_nodes, occurrences: placed_occurrences, properties: placed_properties }, identifiers: placed_identifiers, node: placed_node, occurrence: placed_occurrence, ownership: placed_ownership, relationships: placed_relationships, source_input: placed_source_input } = place_table(
						$attributes,
						{ content: $content, nodes: $nodes, occurrences: $occurrences, properties: $properties },
						$identifiers,
						$ownership,
						$relationships,
						authoring,
						planning,
						{ break_cursor: $break_cursor, group: $next_group, language, node: $next_node, occurrence: $next_occurrence, source_input: $source_input, table: table_index.to_u64() },
						source_plan,
					)?
					$attributes = placed_attributes
					$content = placed_content
					$nodes = placed_nodes
					$occurrences = placed_occurrences
					$properties = placed_properties
					$identifiers = placed_identifiers
					$ownership = placed_ownership
					$relationships = placed_relationships
					$next_node = placed_node
					$next_occurrence = placed_occurrence
					$source_input = placed_source_input
					$break_cursor = placed_break_cursor
					$index = group.block_end
					$next_group = group.group_end - 1
				}
				TableRow(_) => {
					crash "normalized table row escaped its table"
				}
				ListItem(ordinal) => {
					## `LI` owns `[Lbl, LBody]`; `Lbl` owns the generated label
					## occurrence, whose source-to-presentation fact names its
					## whole label source. The label paints on the item's
					## first paragraph line.
					item_node = $next_node
					label_node = checked_add(item_node, 1)?
					body_node = checked_add(item_node, 2)?
					item_content = $content.len()
					$content = $content.append(ChildNode(Semantics.NodeId.from_index(label_node))).append(ChildNode(Semantics.NodeId.from_index(body_node)))
					$nodes = list_set($nodes, item_node, make_node(item_node, ParentNode(Semantics.NodeId.from_index(list_at(planning.group_nodes, group.parent - 1))), "LI", Semantics.Range.from_start_and_length(item_content, 2), Inherited))
					label_content = $content.len()
					$content = $content.append(ContentOccurrence(Semantics.OccurrenceId.from_index($next_occurrence)))
					$nodes = list_set($nodes, label_node, make_node(label_node, ParentNode(Semantics.NodeId.from_index(item_node)), "Lbl", Semantics.Range.from_start_and_length(label_content, 1), Inherited))
					label_property = $properties.len()
					$properties = $properties.append(SourceToPresentation({ kind: GeneratedText, presentation: item_label(authoring, group.parent, ordinal), source: source_range($source_input, source_plan) }))
					$occurrences = $occurrences.append(make_occurrence($next_occurrence, $source_input, source_plan, language, Semantics.Range.from_start_and_length(label_property, 1)))
					$pending_label = Label(Semantics.OccurrenceId.from_index($next_occurrence))
					$next_occurrence = checked_add($next_occurrence, 1)?
					$source_input = checked_add($source_input, 1)?
					$next_node = checked_add($next_node, 3)?
				}
			}
			$next_group = $next_group + 1
		} else {
			block = list_at(blocks, $index)
			list_level = block_level(groups, block.parent)
			match block.kind {
				Heading(level) => {
					role = heading_role(level, $index)?
					start = $content.len()
					$content = $content.append(ContentOccurrence(Semantics.OccurrenceId.from_index($next_occurrence)))
					$nodes = list_set($nodes, $next_node, make_node($next_node, ParentNode(parent_node(block.parent, planning.group_nodes)), role, Semantics.Range.from_start_and_length(start, 1), Inherited))
					$occurrences = $occurrences.append(make_occurrence($next_occurrence, $source_input, source_plan, language, empty))
					$ownership = list_set($ownership, $index, TextBlock({ body: Semantics.OccurrenceId.from_index($next_occurrence), label: NoLabel, level: list_level }))
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
					$ownership = list_set($ownership, $index, TextBlock({ body: Semantics.OccurrenceId.from_index($next_occurrence), label: $pending_label, level: list_level }))
					$pending_label = NoLabel
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
					$ownership = list_set($ownership, $index, TextBlock({ body: Semantics.OccurrenceId.from_index($next_occurrence), label: NoLabel, level: list_level }))
					$next_node = checked_add($next_node, 1)?
					$next_occurrence = checked_add($next_occurrence, 1)?
					$source_input = checked_add($source_input, 1)?
					$index = $index + 1
				}

				## The caption follows its figure leaf in the figure's `Sect`,
				## so the figure's node is the one allocated just before it.
				FigureCaption(_) => {
					caption_node = $next_node
					paragraph_node = checked_add(caption_node, 1)?
					caption_start = $content.len()
					$content = $content.append(ChildNode(Semantics.NodeId.from_index(paragraph_node)))
					paragraph_start = $content.len()
					$content = $content.append(ContentOccurrence(Semantics.OccurrenceId.from_index($next_occurrence)))
					$nodes = list_set($nodes, caption_node, make_node(caption_node, ParentNode(parent_node(block.parent, planning.group_nodes)), "Caption", Semantics.Range.from_start_and_length(caption_start, 1), Inherited))
					$nodes = list_set($nodes, paragraph_node, make_node(paragraph_node, ParentNode(Semantics.NodeId.from_index(caption_node)), "P", Semantics.Range.from_start_and_length(paragraph_start, 1), Inherited))
					$relationships = $relationships.append(CaptionFor({ caption: Semantics.NodeId.from_index(caption_node), target: Semantics.NodeId.from_index(caption_node - 1) }))
					$occurrences = $occurrences.append(make_occurrence($next_occurrence, $source_input, source_plan, language, empty))
					$ownership = list_set($ownership, $index, TextBlock({ body: Semantics.OccurrenceId.from_index($next_occurrence), label: NoLabel, level: list_level }))
					$next_node = checked_add($next_node, 2)?
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
					$ownership = list_set($ownership, $index, TextBlock({ body: Semantics.OccurrenceId.from_index($next_occurrence), label: NoLabel, level: list_level }))
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
					$ownership = list_set($ownership, $index, TextBlock({ body: Semantics.OccurrenceId.from_index($next_occurrence), label: NoLabel, level: list_level }))
					$next_node = checked_add(link_node, 1)?
					$next_occurrence = checked_add($next_occurrence, 1)?
					$source_input = checked_add($source_input, 1)?
					$index = $index + 1
				}
				RichParagraph(paragraph) => {
					rich = list_at(authoring.rich_paragraphs, paragraph)
					breaks = paragraph_breaks(authoring.line_breaks, $break_cursor, paragraph)
					placed = place_rich(
						{ content: $content, nodes: $nodes, occurrences: $occurrences, properties: $properties },
						authoring,
						rich,
						{ attributes: Semantics.Range.from_start_and_length(0, 0), breaks: $break_cursor, element_identifier: NoElementIdentifier, language, node: $next_node, occurrence: $next_occurrence, parent: parent_node(block.parent, planning.group_nodes), role: "P", segments: breaks + 1, source_input: $source_input },
						source_plan,
					)?
					$content = placed.content
					$nodes = placed.nodes
					$occurrences = placed.occurrences
					$properties = placed.properties
					$ownership = list_set($ownership, $index, RichTextBlock({ label: $pending_label, level: list_level, occurrences: Semantics.Range.from_start_and_length($next_occurrence, rich.leaves) }))
					$pending_label = NoLabel
					$next_node = checked_add($next_node, rich.elements + 1)?
					$next_occurrence = checked_add($next_occurrence, rich.leaves)?
					$source_input = checked_add($source_input, breaks + 1)?
					$break_cursor = $break_cursor + breaks
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
					list_attribute = $attributes.len()
					$attributes = $attributes.append(list_numbering(Bullet))
					bullet_list = make_node(list_node, ParentNode(parent_node(block.parent, planning.group_nodes)), "L", Semantics.Range.from_start_and_length(list_content, $group_end - group_start), Inherited)
					$nodes = list_set($nodes, list_node, { ..bullet_list, attributes: Semantics.Range.from_start_and_length(list_attribute, 1) })
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
						$ownership = list_set($ownership, $item_index, TextBlock({ body: Semantics.OccurrenceId.from_index(body_occurrence), label: Label(Semantics.OccurrenceId.from_index(label_occurrence)), level: 1 }))
						$next_node = checked_add($next_node, 3)?
						$next_occurrence = checked_add($next_occurrence, 2)?
						$source_input = checked_add($source_input, 2)?
						$item_index = $item_index + 1
					}
					$index = $group_end
				}
			}
		}
	}
	while $next_group < groups.len() {
		$next_node = match list_at(groups, $next_group).kind {
			KeepTogether | KeepWithNext(_) | Scope(_) | Table(_) | TableRow(_) => $next_node
			ListItem(_) => checked_add($next_node, 3)?
			_ => checked_add($next_node, 1)?
		}
		$next_group = $next_group + 1
	}
	unique_sources = KernelFacadeSources.Plan.sources(source_plan).map(|source| { unicode: source.unicode })
	if $identifiers.len() != planning.header_ranges.len() or $relationships.len() != planning.relationship_count or $attributes.len() != planning.attribute_count or $next_node != planning.node_count or $next_occurrence != planning.occurrence_count or $source_input != planning.source_inputs.len() or $content.len() != planning.content_count or $properties.len() != planning.property_count {
		crash "facade semantic planning count escaped"
	}
	store = {
		annotations: [],
		assertions: [],
		attribute_roles: [],
		attributes: $attributes,
		content_spine: $content,
		contextual_artifacts: [],
		document_root: Semantics.NodeId.from_index(0),
		element_identifiers: $identifiers,
		fragments: [],
		mathml_subtrees: [],
		namespaces: if $nodes.any(|node| node.role.namespace.index() == 1) standard_namespaces_with_pdf17 else standard_namespaces,
		nodes: $nodes,
		non_text_sources: [],
		occurrence_fragments: [],
		occurrences: $occurrences,
		relationships: $relationships,
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
place_rich : StoreBuffers, Document.NormalizedAuthoring, Document.NormalizedRich, { attributes : Semantics.Range, breaks : U64, element_identifier : [HasElementIdentifier(Semantics.ElementId), NoElementIdentifier], language : Str, node : U64, occurrence : U64, parent : Semantics.NodeId, role : Str, segments : U64, source_input : U64 }, KernelFacadeSources.Plan -> Try(StoreBuffers, KernelFacadeSemantics.Error)
place_rich = |buffers, authoring, rich, at, source_plan| {
	inlines = authoring.inlines
	base = buffers.content.len()
	var $content = buffers.content
	var $slot = 0
	while $slot < rich.length {
		$content = $content.append(ChildNode(Semantics.NodeId.from_index(0)))
		$slot = $slot + 1
	}

	## A table cell's attributes and identifier are written with its node
	## here, so the caller never updates a node list it received through
	## `?` (docs/performance/lowering-uniqueness.md).
	var $nodes = list_set(buffers.nodes, at.node, { ..make_node(at.node, ParentNode(at.parent), at.role, Semantics.Range.from_start_and_length(base, rich.children), Inherited), attributes: at.attributes, element_identifier: at.element_identifier })
	var $occurrences = buffers.occurrences
	var $properties = buffers.properties
	input_sources = KernelFacadeSources.Plan.input_sources(source_plan)
	sources = KernelFacadeSources.Plan.sources(source_plan)
	var $segment = 0
	var $source_id = list_at(input_sources, at.source_input)
	var $boundaries = list_at(sources, $source_id.index()).analysis.line_boundaries
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
				## A leaf after a line break starts the next segment's source.
				## Validated breaks separate text, so one leaf crosses at most
				## one break.
				if $segment + 1 < at.segments and list_at(authoring.line_breaks, at.breaks + $segment).leaf <= record.first_leaf {
					$segment = $segment + 1
					$source_id = list_at(input_sources, at.source_input + $segment)
					$boundaries = list_at(sources, $source_id.index()).analysis.line_boundaries
					$boundary = 0
				}
				start = scalar_at($boundaries, $boundary, byte_start)?
				finish = scalar_at($boundaries, start.index, byte_start + byte_length)?
				$boundary = finish.index
				occurrence = at.occurrence + record.first_leaf
				$content = list_set($content, position, ContentOccurrence(Semantics.OccurrenceId.from_index(occurrence)))
				$occurrences = $occurrences.append({
					fragments: Semantics.Range.from_start_and_length(0, 0),
					id: Semantics.OccurrenceId.from_index(occurrence),
					language: Language(leaf_language(inlines, record.language, at.language)),
					source: Text(
						$source_id,
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

TableStore : { attributes : List(Semantics.StructureAttribute), buffers : StoreBuffers, identifiers : List(Semantics.ElementIdentifier), ownership : List(KernelFacadeSemantics.BlockOwnership), relationships : List(Semantics.Relationship) }

TablePlaced : { attributes : List(Semantics.StructureAttribute), break_cursor : U64, buffers : StoreBuffers, identifiers : List(Semantics.ElementIdentifier), node : U64, occurrence : U64, ownership : List(KernelFacadeSemantics.BlockOwnership), relationships : List(Semantics.Relationship), source_input : U64 }

## Place one planned table in preorder. The content spine receives, in
## order, the `Table` span (`Caption`, then each present section), the
## caption's `Caption > P` spans, and for each section its `TR` span followed
## by each row's cell span and each cell's rich span. Every cell carries its
## generated element identifier (`c` and its six-digit cell ordinal, so
## identifier order is byte order); only identifiers a `/Headers` names lower
## to `/ID` (`KernelTagged.lowered_identifiers`); a header cell carries `Scope`, a data
## cell with associations `Headers` and one `HeaderFor` relationship per
## header in the same order, and a spanning cell `ColSpan`. A cell's text is
## a rich paragraph owned by its `TH` or `TD` directly.
place_table : List(Semantics.StructureAttribute), StoreBuffers, List(Semantics.ElementIdentifier), List(KernelFacadeSemantics.BlockOwnership), List(Semantics.Relationship), Document.NormalizedAuthoring, Planning, { break_cursor : U64, group : U64, language : Str, node : U64, occurrence : U64, source_input : U64, table : U64 }, KernelFacadeSources.Plan -> Try(TablePlaced, KernelFacadeSemantics.Error)
place_table = |attributes, { content, nodes, occurrences, properties }, identifiers, ownership, relationships, authoring, planning, at, source_plan| {
	group = list_at(authoring.groups, at.group)
	table = list_at(authoring.tables, at.table)
	empty = Semantics.Range.from_start_and_length(0, 0)
	table_node = at.node
	caption_nodes = if table.caption 2 else 0
	var $attributes = attributes
	var $content = content
	var $nodes = nodes
	var $occurrences = occurrences
	var $properties = properties
	var $identifiers = identifiers
	var $ownership = ownership
	var $relationships = relationships
	var $occurrence = at.occurrence
	var $source_input = at.source_input
	var $break_cursor = at.break_cursor

	## Section nodes: the first row of each present section is preceded by
	## its section element.
	header_rows = table.header_rows
	body_start = at.group + 1 + header_rows
	footer_start = body_start + table.body_rows
	head_node = table_node + 1 + caption_nodes
	body_node = if header_rows > 0 list_at(planning.group_nodes, body_start) - 1 else head_node
	foot_node = if table.footer_rows > 0 list_at(planning.group_nodes, footer_start) - 1 else 0
	table_children = $content.len()
	if table.caption {
		$content = $content.append(ChildNode(Semantics.NodeId.from_index(table_node + 1)))
	}
	if header_rows > 0 {
		$content = $content.append(ChildNode(Semantics.NodeId.from_index(head_node)))
	}
	$content = $content.append(ChildNode(Semantics.NodeId.from_index(body_node)))
	if table.footer_rows > 0 {
		$content = $content.append(ChildNode(Semantics.NodeId.from_index(foot_node)))
	}
	$nodes = list_set($nodes, table_node, make_node(table_node, ParentNode(parent_node(group.parent, planning.group_nodes)), "Table", Semantics.Range.from_start_and_length(table_children, $content.len() - table_children), Inherited))
	if table.caption {
		caption_block = group.first_block
		caption_span = $content.len()
		$content = $content.append(ChildNode(Semantics.NodeId.from_index(table_node + 2)))
		paragraph_span = $content.len()
		$content = $content.append(ContentOccurrence(Semantics.OccurrenceId.from_index($occurrence)))
		$nodes = list_set($nodes, table_node + 1, make_node(table_node + 1, ParentNode(Semantics.NodeId.from_index(table_node)), "Caption", Semantics.Range.from_start_and_length(caption_span, 1), Inherited))
		$nodes = list_set($nodes, table_node + 2, make_node(table_node + 2, ParentNode(Semantics.NodeId.from_index(table_node + 1)), "P", Semantics.Range.from_start_and_length(paragraph_span, 1), Inherited))
		$occurrences = $occurrences.append(make_occurrence($occurrence, $source_input, source_plan, at.language, empty))
		$ownership = list_set($ownership, caption_block, TextBlock({ body: Semantics.OccurrenceId.from_index($occurrence), label: NoLabel, level: 0 }))
		$occurrence = $occurrence + 1
		$source_input = $source_input + 1
	}
	var $row_group = at.group + 1
	while $row_group < group.group_end {
		section_end = if $row_group < body_start body_start else if $row_group < footer_start footer_start else group.group_end
		section_node = if $row_group < body_start head_node else if $row_group < footer_start body_node else foot_node
		section_role = if $row_group < body_start "THead" else if $row_group < footer_start "TBody" else "TFoot"
		section_span = $content.len()
		var $member = $row_group
		while $member < section_end {
			$content = $content.append(ChildNode(Semantics.NodeId.from_index(list_at(planning.group_nodes, $member))))
			$member = $member + 1
		}
		$nodes = list_set($nodes, section_node, make_node(section_node, ParentNode(Semantics.NodeId.from_index(table_node)), section_role, Semantics.Range.from_start_and_length(section_span, section_end - $row_group), Inherited))
		while $row_group < section_end {
			row = list_at(authoring.groups, $row_group)
			row_node = list_at(planning.group_nodes, $row_group)
			row_span = $content.len()
			var $cell_node = row_node + 1
			var $block = row.first_block
			while $block < row.block_end {
				$content = $content.append(ChildNode(Semantics.NodeId.from_index($cell_node)))
				rich = list_at(authoring.rich_paragraphs, rich_index(authoring, $block))
				$cell_node = $cell_node + 1 + rich.elements
				$block = $block + 1
			}
			$nodes = list_set($nodes, row_node, make_node(row_node, ParentNode(Semantics.NodeId.from_index(section_node)), "TR", Semantics.Range.from_start_and_length(row_span, row.block_end - row.first_block), Inherited))
			$cell_node = row_node + 1
			$block = row.first_block
			while $block < row.block_end {
				paragraph = rich_index(authoring, $block)
				rich = list_at(authoring.rich_paragraphs, paragraph)
				ordinal = cell_ordinal(authoring.cells, $block)
				record = list_at(authoring.cells, ordinal)
				breaks = paragraph_breaks(authoring.line_breaks, $break_cursor, paragraph)
				role = match record.kind {
					HeaderCell(_) => "TH"
					DataCell => "TD"
				}
				attribute_start = $attributes.len()
				if record.column_span > 1 {
					$attributes = $attributes.append({ applicability: Family(TableRoles), name: Standard("ColSpan"), owner: Table, value: Integer(record.column_span.to_i64()) })
				}
				associations = list_at(planning.header_ranges, ordinal)
				if associations.length() != 0 {
					var $names = List.with_capacity(associations.length())
					var $edge = associations.start()
					while $edge < associations.start() + associations.length() {
						header = list_at(planning.cell_headers, $edge)
						$names = $names.append(cell_identifier(header))
						$relationships = $relationships.append(HeaderFor({ cell: Semantics.ElementId.from_index(ordinal), header: Semantics.ElementId.from_index(header) }))
						$edge = $edge + 1
					}
					$attributes = $attributes.append({ applicability: Family(TableRoles), name: Standard("Headers"), owner: Table, value: Names($names) })
				}
				match record.kind {
					HeaderCell(scope) => {
						$attributes = $attributes.append({ applicability: Family(TableRoles), name: Standard("Scope"), owner: Table, value: Name(scope_name(scope)) })
					}
					DataCell => {}
				}
				placed = place_rich(
					{ content: $content, nodes: $nodes, occurrences: $occurrences, properties: $properties },
					authoring,
					rich,
					{
						attributes: Semantics.Range.from_start_and_length(attribute_start, $attributes.len() - attribute_start),
						breaks: $break_cursor,
						element_identifier: HasElementIdentifier(Semantics.ElementId.from_index(ordinal)),
						language: at.language,
						node: $cell_node,
						occurrence: $occurrence,
						parent: Semantics.NodeId.from_index(row_node),
						role,
						segments: breaks + 1,
						source_input: $source_input,
					},
					source_plan,
				)?
				$content = placed.content
				$nodes = placed.nodes
				$occurrences = placed.occurrences
				$properties = placed.properties
				$identifiers = $identifiers.append({ id: Semantics.ElementId.from_index(ordinal), value: cell_identifier(ordinal) })
				$ownership = list_set($ownership, $block, RichTextBlock({ label: NoLabel, level: 0, occurrences: Semantics.Range.from_start_and_length($occurrence, rich.leaves) }))
				$occurrence = $occurrence + rich.leaves
				$source_input = $source_input + breaks + 1
				$break_cursor = $break_cursor + breaks
				$cell_node = $cell_node + 1 + rich.elements
				$block = $block + 1
			}
			$row_group = $row_group + 1
		}
	}
	last_row = list_at(authoring.groups, group.group_end - 1)
	last_node = list_at(planning.group_nodes, group.group_end - 1) + 1 + subtree_elements(authoring, last_row)
	Ok({
		attributes: $attributes,
		break_cursor: $break_cursor,
		buffers: { content: $content, nodes: $nodes, occurrences: $occurrences, properties: $properties },
		identifiers: $identifiers,
		node: last_node,
		occurrence: $occurrence,
		ownership: $ownership,
		relationships: $relationships,
		source_input: $source_input,
	})
}

## The nodes of a row's cells and their inline elements.
subtree_elements : Document.NormalizedAuthoring, Document.NormalizedGroup -> U64
subtree_elements = |authoring, row| {
	var $count = 0
	var $block = row.first_block
	while $block < row.block_end {
		$count = $count + 1 + list_at(authoring.rich_paragraphs, rich_index(authoring, $block)).elements
		$block = $block + 1
	}
	$count
}

rich_index : Document.NormalizedAuthoring, U64 -> U64
rich_index = |authoring, block| match list_at(authoring.blocks, block).kind {
	RichParagraph(value) => value
	_ => crash "normalized table cell escaped its rich paragraph"
}

## The cell ordinal of cell leaf `block`: cells are stored in leaf order,
## so a binary search over their block indexes finds it.
cell_ordinal : List(Document.NormalizedCell), U64 -> U64
cell_ordinal = |cells, block| {
	var $low = 0
	var $high = cells.len()
	while $low < $high {
		middle = $low + ($high - $low) // 2
		if list_at(cells, middle).block < block {
			$low = middle + 1
		} else {
			$high = middle
		}
	}
	if $low >= cells.len() or list_at(cells, $low).block != block {
		crash "normalized table cell escaped the cell arena"
	}
	$low
}

## The generated element identifier of cell ordinal `ordinal`: `c` and the
## one-based ordinal in six zero-padded digits, so byte order is cell order.
cell_identifier : U64 -> Str
cell_identifier = |ordinal| {
	digits = (1000000 + ordinal + 1).to_str()
	match Str.from_utf8(Str.to_utf8(digits).drop_first(1)) {
		Ok(text) => "c${text}"
		Err(_) => crash "generated cell identifier escaped ASCII"
	}
}

scope_name : Document.HeaderScope -> Str
scope_name = |scope| match scope {
	Both => "Both"
	Column => "Column"
	Row => "Row"
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
	FurnitureOnly => crash "furniture-only inline escaped semantic validation"
}

inline_language : Document.NormalizedInlineKind -> Semantics.Language
inline_language = |kind| match kind {
	InLanguage(tag) => Language(tag)
	_ => Inherited
}

## The List-owned `ListNumbering` attribute of an `L`: `/Disc` for bullets,
## else the number style (ISO 32000-2 Table 380).
list_numbering : Document.ListMarker -> Semantics.StructureAttribute
list_numbering = |marker| {
	value = match marker {
		Bullet => "Disc"
		Numbered({ start: _, style }) => match style {
			Decimal => "Decimal"
			LowerAlpha => "LowerAlpha"
			LowerRoman => "LowerRoman"
			UpperAlpha => "UpperAlpha"
			UpperRoman => "UpperRoman"
		}
	}
	{ applicability: Family(ListRoles), name: Standard("ListNumbering"), owner: List, value: Name(value) }
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

standard_namespaces : List(Semantics.Namespace)
standard_namespaces = [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }]

## The PDF 1.7 standard structure namespace is declared only when a `Code`
## or `Quote` element needs it.
standard_namespaces_with_pdf17 : List(Semantics.Namespace)
standard_namespaces_with_pdf17 = [
	{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" },
	{ id: Semantics.NamespaceId.from_index(1), kind: Pdf17, uri: "http://iso.org/pdf/ssn" },
]

## `Code` and `Quote` are PDF 1.7 standard structure types (ISO 32000-2
## 14.8.6); every other facade role is in the PDF 2.0 namespace.
role_namespace : Str -> Semantics.NamespaceId
role_namespace = |role| if role == "Code" or role == "Quote" Semantics.NamespaceId.from_index(1) else Semantics.NamespaceId.from_index(0)

make_node : U64, Semantics.NodeParent, Str, Semantics.Range, Semantics.Language -> Semantics.Node
make_node = |index, parent, role, content, language| {
	attributes: Semantics.Range.from_start_and_length(0, 0),
	content,
	element_identifier: NoElementIdentifier,
	id: Semantics.NodeId.from_index(index),
	language,
	parent,
	role: { local_name: role, namespace: role_namespace(role) },
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

## A facade content bound checked at authored leaf `block`.
check_at : U64, U64, KernelFacadeSemantics.Dimension, U64 -> Try({}, KernelFacadeSemantics.Error)
check_at = |attempted, limit, dimension, block| if attempted > limit Err(BlockLimitExceeded({ attempted, block, dimension, limit })) else Ok({})

check_limit : U64, U64, KernelFacadeSemantics.Dimension -> Try({}, KernelFacadeSemantics.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelFacadeSemantics.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(_) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

## Appends every element of `source`. `List.concat` sizes its result
## exactly, so an accumulator grown by `concat` in a loop was reallocated,
## and copied, on every call; `append` grows geometrically
## (docs/performance/emission-linearity.md).
append_all : List(a), List(a) -> List(a)
append_all = |target, source| {
	var $out = target
	var $index = 0
	while $index < source.len() {
		$out = $out.append(list_at(source, $index))
		$index = $index + 1
	}
	$out
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
test_limits = KernelFacadeSemantics.Limits.make(test_limits_record)

test_limits_record = {
	max_container_depth: 2,
	max_inline_depth: 8,
	max_content_spine: 32,
	max_nodes: 16,
	max_occurrences: 12,
	max_properties: 4,
	max_source_inputs: 12,
	semantics: KernelSemantics.Limits.make({ max_attributes: 4, max_content_spine: 32, max_fragments: 0, max_namespaces: 1, max_nodes: 16, max_occurrences: 12, max_semantic_depth: 8 }),
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
}

test_authoring : Document.NormalizedAuthoring
test_authoring = {
	blocks: [
		{ kind: Title, parent: 0, text: "Report" },
		{ kind: Heading(1), parent: 0, text: "Summary" },
		{ kind: Paragraph, parent: 0, text: "Body" },
		{ kind: Bullet({ item: 0, list: 0 }), parent: 0, text: "One" },
		{ kind: Bullet({ item: 1, list: 0 }), parent: 0, text: "Two" },
	],
	cells: [],
	customs: [],
	decorations: [],
	figures: [],
	groups: [],
	inlines: [],
	language: "en-AU",
	line_breaks: [],
	lists: [],
	metadata_title: "Report",
	outline: [],
	page_breaks: [],
	page_labels: [],
	rich_paragraphs: [],
	scopes: [],
	spacers: [],
	tables: [],
	templates: NoTemplates,
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

	retained_authoring.metadata_title == "Report" and retained_authoring.language == "en-AU" and retained_authoring.blocks.len() == 5 and
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

## A heading may rise any number of levels but descend only one at a time;
## destination headings take part, and the first heading has no predecessor.
expect {
	skipped = [
		{ kind: Heading(1), parent: 0, text: "Summary" },
		{ kind: Paragraph, parent: 0, text: "Body" },
		{ kind: DestinationHeading({ level: 3, name: "detail" }), parent: 0, text: "Detail" },
	]
	stepped = [
		{ kind: Heading(2), parent: 0, text: "Start" },
		{ kind: Heading(3), parent: 0, text: "Down" },
		{ kind: Heading(1), parent: 0, text: "Up" },
		{ kind: DestinationHeading({ level: 2, name: "down" }), parent: 0, text: "Down" },
	]
	check_heading_progression(skipped) == Err(HeadingSkip({ block: 2, previous: 0 })) and check_heading_progression(stepped) == Ok({})
}

## The first node crossing is rejected before its planned node/content buffers
## are appended.
expect {
	limits = KernelFacadeSemantics.Limits.make({
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
		Err(BlockLimitExceeded({ attempted: 2, block: 0, dimension: Nodes, limit: 1 })) => True
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
		{ block_end: 5, depth: 1, first_block: 1, group_end: 2, kind: Container(Section), parent: 0, position: 1 },
		{ block_end: 5, depth: 2, first_block: 3, group_end: 2, kind: Container(Division), parent: 1, position: 2 },
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
			{ block_end: 5, depth: 1, first_block: 1, group_end: 2, kind: Container(Section), parent: 0, position: 1 },
			{ block_end: 5, depth: 2, first_block: 5, group_end: 2, kind: Container(Part), parent: 1, position: 4 },
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
												[RichTextBlock({ label: NoLabel, level: 0, occurrences })] => occurrences.start() == 0 and occurrences.length() == 4
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

table_authoring : Document.NormalizedAuthoring
table_authoring = Document.normalize(
	Document.from_blocks({
		contents: [
			Document.table({
				body_rows: [
					Document.row([Document.header_cell(Row, [Document.plain_text("A")]), Document.cell([Document.plain_text("1")])]),
					Document.row([Document.spanning(2, Document.cell([Document.plain_text("Wide")]))]),
				],
				caption: Document.caption("Cap"),
				columns: [{ align: Start, width: Content }, { align: End, width: Share(1) }],
				footer_rows: [],
				header_rows: [Document.row([Document.header_cell(Both, [Document.plain_text("Key")]), Document.header_cell(Column, [Document.plain_text("Value")])])],
				row_split: KeepRows,
			}),
		],
		language: "en-AU",
		title: "Table",
	}),
)

## A table plans `Table > (Caption > P, THead, TBody)` in preorder with one
## `TR` per row and one `TH`/`TD` per cell. Every cell has an element
## identifier in cell order, and a data cell's `Headers` are the column
## headers above it in its columns followed by its row headers, each with a
## `HeaderFor` relationship in the same order.
expect {
	limits = KernelFacadeSemantics.Limits.make({ ..test_limits_record, max_nodes: 64, max_content_spine: 64, semantics: KernelSemantics.Limits.make({ max_attributes: 32, max_content_spine: 64, max_fragments: 0, max_namespaces: 1, max_nodes: 64, max_occurrences: 12, max_semantic_depth: 16 }) })
	plan = KernelFacadeSemantics.Plan.build(table_authoring, limits)?
	store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(plan)))
	roles = store.nodes.map(|node| node.role.local_name)
	headers = store.attributes.keep_if(|attribute| attribute.name == Standard("Headers")).map(|attribute| attribute.value)
	work = KernelFacadeSemantics.Plan.work(plan)

	roles == ["Document", "Table", "Caption", "P", "THead", "TR", "TH", "TH", "TBody", "TR", "TH", "TD", "TR", "TD"]
		and store.element_identifiers.map(|identifier| identifier.value) == ["c000001", "c000002", "c000003", "c000004", "c000005"]
			and headers == [Names(["c000002", "c000003"]), Names(["c000001", "c000002"])]
				and store.relationships.len() == 4
					and work.tables == 1 and work.table_cells == 5 and work.header_association_edges == 4
}

## Table rejections name the table, the row, or the cell.
expect {
	limits = KernelFacadeSemantics.Limits.make({ ..test_limits_record, max_nodes: 64, max_content_spine: 64 })
	table = |spec| Document.normalize(Document.from_blocks({ contents: [Document.table(spec)], language: "en-AU", title: "Table" }))
	header = Document.row([Document.header_cell(Column, [Document.plain_text("H")])])
	base = { body_rows: [Document.row([Document.cell([Document.plain_text("x")])])], caption: NoCaption, columns: [{ align: Start, width: Content }], footer_rows: [], header_rows: [header], row_split: KeepRows }
	empty = KernelFacadeSemantics.Plan.build(table({ ..base, body_rows: [] }), limits)
	grid = KernelFacadeSemantics.Plan.build(table({ ..base, body_rows: [Document.row([Document.cell([Document.plain_text("x")]), Document.cell([Document.plain_text("y")])])] }), limits)
	missing = KernelFacadeSemantics.Plan.build(table({ ..base, header_rows: [] }), limits)
	spanned = KernelFacadeSemantics.Plan.build(table({ ..base, body_rows: [Document.row([Document.row_spanning(2, Document.cell([Document.plain_text("x")]))])] }), limits)
	match (empty, grid, missing, spanned) {
		(Err(TableEmpty({ group: 0 })), Err(TableGridMismatch({ columns: 1, group: 2, spanned: 2 })), Err(TableHeaderMissing({ group: 0 })), Err(TableRowSpan({ block: 1 }))) => True
		_ => False
	}
}
