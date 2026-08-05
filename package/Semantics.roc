Semantics :: [].{
	NodeId :: U64.{
		from_index : U64 -> NodeId
		from_index = |index| NodeId.(index)

		index : NodeId -> U64
		index = |NodeId.(index)| index
	}

	OccurrenceId :: U64.{
		from_index : U64 -> OccurrenceId
		from_index = |index| OccurrenceId.(index)

		index : OccurrenceId -> U64
		index = |OccurrenceId.(index)| index
	}

	FragmentId :: U64.{
		from_index : U64 -> FragmentId
		from_index = |index| FragmentId.(index)

		index : FragmentId -> U64
		index = |FragmentId.(index)| index
	}

	NamespaceId :: U64.{
		from_index : U64 -> NamespaceId
		from_index = |index| NamespaceId.(index)

		index : NamespaceId -> U64
		index = |NamespaceId.(index)| index
	}

	AnnotationId :: U64.{
		from_index : U64 -> AnnotationId
		from_index = |index| AnnotationId.(index)

		index : AnnotationId -> U64
		index = |AnnotationId.(index)| index
	}

	ContextualArtifactId :: U64.{
		from_index : U64 -> ContextualArtifactId
		from_index = |index| ContextualArtifactId.(index)

		index : ContextualArtifactId -> U64
		index = |ContextualArtifactId.(index)| index
	}

	TextSourceId :: U64.{
		from_index : U64 -> TextSourceId
		from_index = |index| TextSourceId.(index)

		index : TextSourceId -> U64
		index = |TextSourceId.(index)| index
	}

	TextPropertyId :: U64.{
		from_index : U64 -> TextPropertyId
		from_index = |index| TextPropertyId.(index)

		index : TextPropertyId -> U64
		index = |TextPropertyId.(index)| index
	}

	NonTextSourceId :: U64.{
		from_index : U64 -> NonTextSourceId
		from_index = |index| NonTextSourceId.(index)

		index : NonTextSourceId -> U64
		index = |NonTextSourceId.(index)| index
	}

	PageId :: U64.{
		from_index : U64 -> PageId
		from_index = |index| PageId.(index)

		index : PageId -> U64
		index = |PageId.(index)| index
	}

	ContentStreamId :: U64.{
		from_index : U64 -> ContentStreamId
		from_index = |index| ContentStreamId.(index)

		index : ContentStreamId -> U64
		index = |ContentStreamId.(index)| index
	}

	Range :: { length : U64, start : U64 }.{
		from_start_and_length : U64, U64 -> Range
		from_start_and_length = |start, length| Range.{ start, length }

		length : Range -> U64
		length = |range| range.length

		start : Range -> U64
		start = |range| range.start
	}

	## Namespace objects have identity independent of URI equality.
	Namespace : { id : NamespaceId, kind : NamespaceKind, uri : Str }
	NamespaceKind : [Extension(Str), MathMl, Pdf17, Pdf20]
	Role : { local_name : Str, namespace : NamespaceId }

	NodeParent : [DocumentRoot, ParentNode(NodeId)]

	## One flat buffer stores this mixed order for all nodes. `content` is the
	## exact span belonging to a node and is the source of PDF `/K` order.
	ContentSpineItem : [
		AnnotationOccurrence(AnnotationId),
		ChildNode(NodeId),
		ContentOccurrence(OccurrenceId),
		ContextualArtifact(ContextualArtifactId),
	]

	Node : {
		attributes : Range,
		content : Range,
		id : NodeId,
		language : Language,
		parent : NodeParent,
		role : Role,
		text_properties : Range,
	}

	Language : [Inherited, Language(Str)]

	TextRange : {
		scalars : Range,
		utf8_bytes : Range,
	}
	SourceRange : [ByteRange(Range), UnicodeRange(TextRange)]

	OccurrenceSource : [
		NonText(NonTextSourceId, SourceRange),
		Text(TextSourceId, SourceRange),
	]

	ContentOccurrence : {
		fragments : Range,
		id : OccurrenceId,
		language : Language,
		source : OccurrenceSource,
		text_properties : Range,
	}

	## Source Unicode is owned exactly once in this dense store.
	TextSource : { unicode : Str }

	TextProperty : [
		ActualText(Str),
		AlternativeText(Str),
		ExpandedText(Str),
		Phoneme(Str),
		PhoneticAlphabet(Str),
		ReplacementText(Str),
		SourceToPresentation(
			{
				kind : PresentationTransformation,
				presentation : Str,
				source : TextRange,
			},
		),
	]

	PresentationTransformation : [
		BidirectionalReordering,
		CaseMapping,
		GeneratedText,
		InsertedDiscretionaryHyphen,
		Ligature,
		SuppressedSoftHyphen,
	]

	AttributeOwner : [Artifact, Layout, List, Namespace(NamespaceId), Table]
	AttributeValue : [Integer(I64), Name(Str), Names(List(Str)), Text(Str)]
	StructureAttribute : {
		name : Str,
		owner : AttributeOwner,
		value : AttributeValue,
	}

	ContextualArtifact : {
		attributes : Range,
		id : ContextualArtifactId,
		parent : NodeId,
	}

	Annotation : {
		id : AnnotationId,
		logical_order : U64,
		owner : NodeId,
	}

	Relationship : [
		CaptionFor({ caption : NodeId, target : NodeId }),
		DestinationTarget({ source : NodeId, target : NodeId }),
		HeaderFor({ cell : NodeId, header : NodeId }),
		LabelFor({ label : NodeId, target : NodeId }),
		NoteFor({ note : NodeId, target : NodeId }),
	]

	LayoutFragment : {
		content_stream : ContentStreamId,
		continuation_index : U64,
		id : FragmentId,
		occurrence : OccurrenceId,
		page : PageId,
		source_range : SourceRange,
	}

	## Fixed-shape records and variable data are kept in separate dense buffers.
	## `occurrence_fragments` is the counts/prefix-sum reverse index; fragments
	## themselves are never duplicated.
	Store : {
		annotations : List(Annotation),
		attributes : List(StructureAttribute),
		content_spine : List(ContentSpineItem),
		contextual_artifacts : List(ContextualArtifact),
		document_root : NodeId,
		fragments : List(LayoutFragment),
		namespaces : List(Namespace),
		nodes : List(Node),
		non_text_sources : List(List(U8)),
		occurrence_fragments : List(FragmentId),
		occurrences : List(ContentOccurrence),
		relationships : List(Relationship),
		text_properties : List(TextProperty),
		text_sources : List(TextSource),
	}
}

## Semantic node IDs preserve their dense index.
expect Semantics.NodeId.from_index(7).index() == 7

## Content occurrence IDs preserve their dense index.
expect Semantics.OccurrenceId.from_index(11).index() == 11

## Layout fragment IDs preserve their dense index.
expect Semantics.FragmentId.from_index(13).index() == 13

## Ranges preserve their exact start offset.
expect Semantics.Range.from_start_and_length(5, 8).start() == 5

## Ranges preserve their exact length.
expect Semantics.Range.from_start_and_length(5, 8).length() == 8

## Nested public type modules construct opaque node IDs directly.
expect Semantics.NodeId.from_index(17).index() == 17

## Nested public type modules construct exact ranges directly.
expect Semantics.Range.from_start_and_length(2, 3).length() == 3
