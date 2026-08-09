import KernelUnicode
import Semantics
import unicode.ByteRange
import unicode.Scalar

## This private boundary keeps line-break opportunity discovery separate from
## formatter choice and from shaped presentation. It owns no source payload:
## every range is a scalar/UTF-8 coordinate into the semantic source.
KernelDiscretionaryHyphen :: [].{
	OpportunityId :: U64.{
		from_index : U64 -> OpportunityId
		from_index = |index| OpportunityId.(index)

		index : OpportunityId -> U64
		index = |OpportunityId.(index)| index
	}

	OpportunityKind : [ExplicitSoftHyphen, ExternalHyphenation]
	Selection : [NotSelected, SelectVisibleHyphen]

	Opportunity : {
		id : OpportunityId,
		kind : OpportunityKind,

		## An explicit SHY owns its one source scalar. An externally supplied
		## opportunity names its zero-width insertion boundary.
		source : Semantics.TextRange,
	}

	Selected : {
		kind : OpportunityKind,
		source : Semantics.TextRange,
	}

	Error : [
		ArithmeticOverflow,
		ExternalPresentationUnsupported({ opportunity : U64 }),
		InvalidExplicitSoftHyphen({ opportunity : U64 }),
		InvalidOpportunityId({ actual : U64, expected : U64 }),
		InvalidSourceRange({ opportunity : U64 }),
		MissingLineBoundary({ opportunity : U64 }),
		SelectionWithoutOpportunity({ opportunity : U64 }),
		UnselectedOpportunity({ opportunity : U64 }),
	]

	Plan :: { opportunities : List(Opportunity), selections : List(Selection), source : Str }.{
		build : Str, KernelUnicode.UnicodeAnalysis, List(Opportunity), List(Selection) -> Try(Plan, Error)
		build = |source, analysis, opportunities, selections| build_plan(source, analysis, opportunities, selections)

		## A selected explicit soft hyphen becomes a source-preserving shaping
		## transformation. It forces ActualText at PDF lowering so a visible
		## hyphen glyph never substitutes for the original U+00AD source fact.
		selected : Plan, OpportunityId -> Try(Selected, Error)
		selected = |plan, opportunity| selected_opportunity(plan, opportunity)
	}
}

build_plan : Str, KernelUnicode.UnicodeAnalysis, List(KernelDiscretionaryHyphen.Opportunity), List(KernelDiscretionaryHyphen.Selection) -> Try(KernelDiscretionaryHyphen.Plan, KernelDiscretionaryHyphen.Error)
build_plan = |source, analysis, opportunities, selections| {
	if opportunities.len() != selections.len() {
		return Err(SelectionWithoutOpportunity({ opportunity: selections.len() }))
	}
	var $index = 0
	while $index < opportunities.len() {
		opportunity = list_at(opportunities, $index)
		if opportunity.id.index() != $index {
			return Err(InvalidOpportunityId({ actual: opportunity.id.index(), expected: $index }))
		}
		validate_range(opportunity, source, analysis)?
		$index = $index + 1
	}
	Ok({ opportunities, selections, source })
}

selected_opportunity : KernelDiscretionaryHyphen.Plan, KernelDiscretionaryHyphen.OpportunityId -> Try(KernelDiscretionaryHyphen.Selected, KernelDiscretionaryHyphen.Error)
selected_opportunity = |plan, opportunity_id| {
	index = opportunity_id.index()
	if index >= plan.opportunities.len() {
		return Err(SelectionWithoutOpportunity({ opportunity: index }))
	}
	opportunity = list_at(plan.opportunities, index)
	selection = list_at(plan.selections, index)
	match selection {
		NotSelected => Err(UnselectedOpportunity({ opportunity: index }))
		SelectVisibleHyphen => match opportunity.kind {
			ExplicitSoftHyphen => Ok({ kind: ExplicitSoftHyphen, source: opportunity.source })

			## There is deliberately no implicit source scalar for a dictionary
			## insertion. The current advanced shaping boundary requires every
			## painted glyph to own a nonempty source range, so callers receive a
			## typed rejection until that boundary can represent a generated glyph.
			ExternalHyphenation => Err(ExternalPresentationUnsupported({ opportunity: index }))
		}
	}
}

validate_range : KernelDiscretionaryHyphen.Opportunity, Str, KernelUnicode.UnicodeAnalysis -> Try({}, KernelDiscretionaryHyphen.Error)
validate_range = |opportunity, source, analysis| {
	range = opportunity.source
	scalar_end = U64.plus_try(range.scalars.start(), range.scalars.length()) ? |_| ArithmeticOverflow
	byte_end = U64.plus_try(range.utf8_bytes.start(), range.utf8_bytes.length()) ? |_| ArithmeticOverflow
	if !has_boundary(analysis.line_boundaries, range.scalars.start(), range.utf8_bytes.start()) or !has_boundary(analysis.line_boundaries, scalar_end, byte_end) {
		return Err(MissingLineBoundary({ opportunity: opportunity.id.index() }))
	}
	match opportunity.kind {
		ExplicitSoftHyphen => validate_explicit_soft_hyphen(opportunity, source)
		ExternalHyphenation => {
			if range.scalars.length() != 0 or range.utf8_bytes.length() != 0 {
				Err(InvalidSourceRange({ opportunity: opportunity.id.index() }))
			} else {
				Ok({})
			}
		}
	}
}

validate_explicit_soft_hyphen : KernelDiscretionaryHyphen.Opportunity, Str -> Try({}, KernelDiscretionaryHyphen.Error)
validate_explicit_soft_hyphen = |opportunity, source| {
	range = opportunity.source
	if range.scalars.length() != 1 or range.utf8_bytes.length() != 2 {
		return Err(InvalidExplicitSoftHyphen({ opportunity: opportunity.id.index() }))
	}
	var $scalar_index = 0
	for located in Scalar.iter(source) {
		if $scalar_index == range.scalars.start() {
			byte_range = located.byte_range
			if Scalar.to_u32(located.scalar) == 0x00ad and range.utf8_bytes.start() == ByteRange.start(byte_range) and range.utf8_bytes.length() == ByteRange.end(byte_range) - ByteRange.start(byte_range) {
				return Ok({})
			}
			return Err(InvalidExplicitSoftHyphen({ opportunity: opportunity.id.index() }))
		}
		$scalar_index = $scalar_index + 1
	}
	Err(InvalidExplicitSoftHyphen({ opportunity: opportunity.id.index() }))
}

has_boundary : List(KernelUnicode.LineBoundary), U64, U64 -> Bool
has_boundary = |boundaries, scalar_offset, byte_offset| {
	var $index = 0
	while $index < boundaries.len() {
		boundary = list_at(boundaries, $index)
		if boundary.scalar_offset == scalar_offset and boundary.byte_offset == byte_offset {
			return Bool.True
		}
		$index = $index + 1
	}
	Bool.False
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "validated discretionary-hyphen index escaped"
}
