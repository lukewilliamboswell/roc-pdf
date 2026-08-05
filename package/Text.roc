import Font
import Layout
import Semantics

Text :: [].{
	RunId :: U64.{
		from_index : U64 -> RunId
		from_index = |index| RunId.(index)

		index : RunId -> U64
		index = |RunId.(index)| index
	}

	GlyphId :: U32.{
		from_raw : U32 -> GlyphId
		from_raw = |raw| GlyphId.(raw)

		raw : GlyphId -> U32
		raw = |GlyphId.(raw)| raw
	}

	FeatureTag :: U32.{
		from_raw : U32 -> FeatureTag
		from_raw = |raw| FeatureTag.(raw)

		raw : FeatureTag -> U32
		raw = |FeatureTag.(raw)| raw
	}

	FeaturePolicyId :: U64.{
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
		BuiltInShaping({ scripts : Semantics.Range }),
		PackagedFontCoverage({ faces : Semantics.Range }),
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
		Ligature,
		ManyToMany,
		ManyToOne,
		OneToMany,
		OneToOne,
		Reordered,
	]

	## `glyphs` is a range into Store.glyph_indices. `source` is relative to
	## the owning occurrence's Unicode and can represent combining and reordering.
	Cluster : {
		glyphs : Semantics.Range,
		kind : ClusterKind,
		source : Semantics.TextRange,
	}

	Substitution : {
		feature : FeatureTag,
		glyphs : Semantics.Range,
		source : Semantics.TextRange,
	}

	TransformationEvidence : {
		glyphs : Semantics.Range,
		kind : Semantics.PresentationTransformation,
		source : Semantics.TextRange,
	}

	ActualTextEvidence : [FromOccurrence, SemanticOverride(Semantics.TextPropertyId)]

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
		clusters : Semantics.Range,
		direction : Direction,
		glyphs : Semantics.Range,
		id : RunId,
		instance : Font.InstanceId,
		language : Semantics.Language,
		occurrence : Semantics.OccurrenceId,
		script : Font.Script,
		source : Semantics.TextRange,
		substitutions : Semantics.Range,
		transformations : Semantics.Range,
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

## Shaped-run IDs preserve their dense index.
expect Text.RunId.from_index(7).index() == 7

## Glyph IDs remain compact opaque U32 values.
expect Text.GlyphId.from_raw(41).raw() == 41

## OpenType feature tags remain compact opaque U32 values.
expect Text.FeatureTag.from_raw(0x6B65726E).raw() == 0x6B65726E

## Feature-policy IDs preserve their dense cache-key index.
expect Text.FeaturePolicyId.from_index(9).index() == 9
