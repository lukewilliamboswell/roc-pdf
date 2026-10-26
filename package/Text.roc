import Font
import Layout
import Semantics

Text :: [].{
	RunId :: U64.{
		is_eq : _
		to_hash : _

		from_index : U64 -> RunId
		from_index = |index| RunId.(index)

		index : RunId -> U64
		index = |RunId.(index)| index
	}

	## The baseline segment origin and accepted prefix advance before a
	## paint-only subdivision. This preserves the original text-position
	## rounding phase without copying or remeasuring preceding glyphs.
	PaintPhase : { run : RunId, advance : Layout.Unit, origin : Layout.Point }

	GlyphId :: U32.{
		is_eq : _
		to_hash : _

		from_raw : U32 -> GlyphId
		from_raw = |raw| GlyphId.(raw)

		raw : GlyphId -> U32
		raw = |GlyphId.(raw)| raw
	}

	FeatureTag :: U32.{
		is_eq : _
		to_hash : _

		from_raw : U32 -> FeatureTag
		from_raw = |raw| FeatureTag.(raw)

		raw : FeatureTag -> U32
		raw = |FeatureTag.(raw)| raw
	}

	FeaturePolicyId :: U64.{
		is_eq : _
		to_hash : _

		from_index : U64 -> FeaturePolicyId
		from_index = |index| FeaturePolicyId.(index)

		index : FeaturePolicyId -> U64
		index = |FeaturePolicyId.(index)| index
	}

	Direction : [LeftToRight, RightToLeft]
	WritingMode : [Horizontal, Vertical]

	## These are distinct integration promises. Exact packaged coverage is a
	## font-selection fact and does not imply built-in shaping support.
	InputCapability : [
		AdvancedShapedRuns,
		BuiltInShaping({ scripts : Semantics.IndexRange }),
		PackagedFontCoverage({ faces : Semantics.IndexRange }),
	]

	Glyph : {
		advance_x : Layout.Unit,
		advance_y : Layout.Unit,
		id : GlyphId,
		offset_x : Layout.Unit,
		offset_y : Layout.Unit,
	}

	ClusterKind : [
		Contextual,

		## A caller-selected external discretionary opportunity has no logical
		## source scalar. Its one visible hyphen glyph is tied to an owned
		## semantic SourceToPresentation property and a transformation record;
		## lowering must use that typed fact rather than infer Unicode from the
		## glyph ID.
		GeneratedDiscretionaryHyphen({ property : Semantics.TextPropertyId, transformation : U64 }),
		Ligature,
		ManyToMany,
		ManyToOne,
		OneToMany,
		OneToOne,
		Reordered,
	]

	## `glyphs` is a range into Store.glyph_indices. `source` is relative to
	## the run's Unicode (its occurrence or artifact source) and can represent
	## combining and reordering.
	Cluster : {
		glyphs : Semantics.IndexRange,
		kind : ClusterKind,
		source : Semantics.TextRange,
	}

	Substitution : {
		feature : FeatureTag,
		glyphs : Semantics.IndexRange,
		source : Semantics.TextRange,
	}

	TransformationEvidence : {
		glyphs : Semantics.IndexRange,
		kind : Semantics.PresentationTransformation,
		source : Semantics.TextRange,
	}

	## An explicit byte slice of an owned ActualText property. Boxed so the
	## evidence union and ordinary Run records retain their existing size.
	ActualTextSlice :: Box({ property : Semantics.TextPropertyId, utf8_bytes : Semantics.IndexRange }).{
		make : Semantics.TextPropertyId, Semantics.IndexRange -> ActualTextSlice
		make = |property, utf8_bytes| ActualTextSlice.(Box.box({ property, utf8_bytes }))
		value : ActualTextSlice -> { property : Semantics.TextPropertyId, utf8_bytes : Semantics.IndexRange }
		value = |ActualTextSlice.(boxed)| Box.unbox(boxed)
		is_eq : ActualTextSlice, ActualTextSlice -> Bool
		is_eq = |ActualTextSlice.(left), ActualTextSlice.(right)| Box.unbox(left) == Box.unbox(right)
	}
	ActualTextEvidence : [FromOccurrence, SemanticOverride(Semantics.TextPropertyId), SemanticOverrideSlice(ActualTextSlice)]

	## An authored break immediately following an occurrence. The semantic
	## stage owns ActualText(source + U+0020); materialization partitions that
	## exact property across physical runs and appends its separator once.
	OccurrenceSeparator : { occurrence : Semantics.OccurrenceId, property : Semantics.TextPropertyId, source_utf8_bytes : U64 }

	## The Unicode a run's `source` range indexes. A semantic run shapes the
	## text of its content occurrence and is painted by that occurrence's
	## layout fragments. An artifact run shapes an artifact text source, such
	## as page furniture resolved after pagination: it belongs to no structure
	## element, is painted only by a page-artifact scene group, and carries no
	## text properties. `FromOccurrence` evidence of an artifact run reads its
	## artifact source.
	RunUnicode : [ArtifactText(Semantics.TextSourceId), OccurrenceText(Semantics.OccurrenceId)]

	## Every field that can affect joining, substitution, placement, or extraction
	## participates in the cache identity. Empty context ranges are explicit.
	ShapeKey : {
		after : Semantics.TextRange,
		before : Semantics.TextRange,
		direction : Direction,
		features : FeaturePolicyId,
		instance : Font.InstanceId,
		language : Semantics.Language,
		occurrence : Semantics.OccurrenceId,
		script : Font.Script,
		source : Semantics.TextRange,
		writing_mode : WritingMode,
	}

	Run : {
		actual_text : ActualTextEvidence,
		clusters : Semantics.IndexRange,
		direction : Direction,
		glyphs : Semantics.IndexRange,
		id : RunId,
		instance : Font.InstanceId,
		language : Semantics.Language,
		script : Font.Script,
		size : Layout.Unit,
		source : Semantics.TextRange,
		substitutions : Semantics.IndexRange,
		transformations : Semantics.IndexRange,
		unicode : RunUnicode,
		writing_mode : WritingMode,
	}

	## Variable relationships live in flat buffers. Runs and clusters carry
	## scalar ranges and never duplicate source Unicode or glyph payload lists.
	Store : {
		clusters : List(Cluster),
		glyph_indices : List(U64),
		glyphs : List(Glyph),
		runs : List(Run),
		substitutions : List(Substitution),
		transformations : List(TransformationEvidence),
	}
}

# Shaped-run IDs preserve their dense index.
expect Text.RunId.from_index(7).index() == 7

# Glyph IDs remain compact opaque U32 values.
expect Text.GlyphId.from_raw(41).raw() == 41

# OpenType feature tags remain compact opaque U32 values.
expect Text.FeatureTag.from_raw(0x6B65726E).raw() == 0x6B65726E

# Feature-policy IDs preserve their dense cache-key index.
expect Text.FeaturePolicyId.from_index(9).index() == 9
