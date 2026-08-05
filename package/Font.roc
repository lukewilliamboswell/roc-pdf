import Semantics

Font :: [].{
	ResourceId :: U64.{
		from_index : U64 -> ResourceId
		from_index = |index| ResourceId.(index)

		index : ResourceId -> U64
		index = |ResourceId.(index)| index
	}

	FaceId :: U64.{
		from_index : U64 -> FaceId
		from_index = |index| FaceId.(index)

		index : FaceId -> U64
		index = |FaceId.(index)| index
	}

	InstanceId :: U64.{
		from_index : U64 -> InstanceId
		from_index = |index| InstanceId.(index)

		index : InstanceId -> U64
		index = |InstanceId.(index)| index
	}

	PolicyId :: U64.{
		from_index : U64 -> PolicyId
		from_index = |index| PolicyId.(index)

		index : PolicyId -> U64
		index = |PolicyId.(index)| index
	}

	Script :: Str.{
		from_iso15924 : Str -> Script
		from_iso15924 = |value| Script.(value)

		as_str : Script -> Str
		as_str = |Script.(value)| value
	}

	ScalarSpan : { first : U32, last : U32 }

	Format : [OpenTypeTrueType]

	EmbeddingRights : [Editable, Installable, PreviewAndPrint, Restricted]

	## These alternatives are capability facts, not fallback levels. Packaged
	## coverage does not imply that the built-in shaper supports the script.
	ShapingProvision : [
		AdvancedRunsRequired,
		BuiltIn,
		PackagedCoverageOnly,
	]

	Resource : {
		bytes : List(U8),
		id : ResourceId,
	}

	## Coverage and script fields are exact ranges into their respective flat
	## store buffers. A validated face never consults a system font registry.
	Face : {
		coverage : Semantics.Range,
		embedding_rights : EmbeddingRights,
		format : Format,
		id : FaceId,
		provision : ShapingProvision,
		resource : ResourceId,
		scripts : Semantics.Range,
	}

	## Gate 0 accepts only static instances. A future variable-font capability
	## can extend InstanceKind without changing face or plan identity.
	InstanceKind : [Static]
	Instance : {
		face : FaceId,
		id : InstanceId,
		kind : InstanceKind,
	}
	InstanceKey : { face : FaceId, kind : InstanceKind }

	Policy : {

		## Ordered exact instances are the complete selection search space.
		id : PolicyId,
		instances : List(InstanceId),
	}

	SourceCluster : {
		source : Semantics.TextRange,
	}

	PlanRequest : {
		clusters : List(SourceCluster),
		language : Semantics.Language,
		policy : PolicyId,
		script : Script,
		source : Semantics.TextSourceId,
	}

	## Resource and face identities are exact-byte and exact-face cache keys.
	ParseKey : { resource : ResourceId }
	CoverageKey : { face : FaceId }
	PlanKey : {
		language : Semantics.Language,
		policy : PolicyId,
		script : Script,
		source : Semantics.TextSourceId,
		source_range : Semantics.TextRange,
	}

	## A face range covers whole grapheme clusters; it cannot split one to
	## select a different font for an independent scalar.
	FaceRange : {
		clusters : Semantics.Range,
		instance : InstanceId,
	}

	PlanWork : {
		coverage_span_visits : U64,
		face_visits : U64,
		grapheme_visits : U64,
	}

	Plan : {
		face_ranges : List(FaceRange),
		work : PlanWork,
	}

	PlanError : [
		EmbeddingProhibited(FaceId),
		MissingCoverage({ cluster : U64, source : Semantics.TextRange }),
		UnsupportedBuiltInShaping({ cluster : U64, script : Script }),
	]

	## Rejection is transactional and never carries a partial usable plan.
	PlanResult : [Complete(Plan), Rejected(List(PlanError))]

	Store : {
		coverage_spans : List(ScalarSpan),
		faces : List(Face),
		instances : List(Instance),
		resources : List(Resource),
		scripts : List(Script),
	}
}

## Font resource IDs preserve their dense index.
expect Font.ResourceId.from_index(2).index() == 2

## Font face IDs preserve their dense index.
expect Font.FaceId.from_index(3).index() == 3

## Static font instance IDs preserve their dense index.
expect Font.InstanceId.from_index(5).index() == 5

## Font policy IDs preserve their dense index.
expect Font.PolicyId.from_index(6).index() == 6

## Script tags retain their exact source spelling for later validation.
expect Font.Script.from_iso15924("Latn").as_str() == "Latn"
