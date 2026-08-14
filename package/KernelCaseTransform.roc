import Semantics
import unicode.ByteRange
import unicode.Case
import unicode.ScalarRange
import unicode.TextRange
import unicode.UnicodeVersion

## The project-side case-transformation boundary over the pinned Unicode
## package's source-mapped case conversion.
##
## This module owns no case data. It requests one transformation under an
## explicit profile and finite budgets, then validates the returned mapping
## facts locally before any later stage may consume them: the facts must
## partition the source and the output exactly, in order, with lengths their
## declared shape allows, at the pinned Unicode version. It retains one
## transformed `Str` and one flat fact buffer; the source stays owned by its
## occurrence, and mapping records use scalar and byte coordinates only.
## Rejection is transactional — no partial text or fact buffer escapes.
KernelCaseTransform :: [].{
	Dimension : [Facts, InputBytes, InputScalars, OutputBytes, OutputScalars]
	Operation : [Fold, Lower, Title, Upper]
	Shape : [Expanded, Removed, Simple, Unchanged]

	## Upstream failures are projected onto a stable project discriminant so
	## no dependency error payload leaks into later stages.
	CaseFailure : [
		CoordinateOverflow,
		InternalEncodingFault,
		LimitExceeded({ dimension : Dimension, limit : U64, required : U64 }),
	]

	Limits :: {
		max_input_bytes : U64,
		max_input_scalars : U64,
		max_mapping_facts : U64,
		max_output_bytes : U64,
		max_output_scalars : U64,
	}.{
		make : {
			max_input_bytes : U64,
			max_input_scalars : U64,
			max_mapping_facts : U64,
			max_output_bytes : U64,
			max_output_scalars : U64,
		} -> Limits
		make = |limits| Limits.(limits)
	}

	## One input scalar's mapping. `input` is always exactly one scalar; the
	## output span is what the mapping produced for it, which may be empty.
	MappingFact : {
		contextual : Bool,
		input : Semantics.TextRange,
		output : Semantics.TextRange,
		shape : Shape,
	}

	Work : { fact_visits : U64, input_scalar_visits : U64, output_scalar_visits : U64 }

	Result : {
		facts : List(MappingFact),
		operation : Operation,
		profile_revision : [None, Some(Str)],
		text : Str,
		unicode_version : Str,
		work : Work,
	}

	Error : [
		FactCoverageInvalid({ fact : U64 }),
		FactShapeInvalid({ fact : U64 }),
		IncompleteCoverage({ facts : U64 }),
		UnexpectedUnicodeVersion(Str),
		Unicode(CaseFailure),
	]

	## Full Unicode default uppercase. The profile is explicit: no locale is
	## inferred, and a locale-sensitive profile is a separate reviewed row.
	to_upper : Str, Limits -> Try(Result, Error)
	to_upper = |source, limits| transform(source, limits)
}

transform : Str, KernelCaseTransform.Limits -> Try(KernelCaseTransform.Result, KernelCaseTransform.Error)
transform = |source, limits| {
	budget = Case.limits(limits.max_input_bytes, limits.max_input_scalars, limits.max_output_bytes, limits.max_output_scalars, limits.max_mapping_facts)
	result = Case.to_upper(source, Case.unicode_default, budget) ? map_case_error
	version = UnicodeVersion.to_str(Case.result_unicode_version(result))
	if version != pinned_unicode_version {
		return Err(UnexpectedUnicodeVersion(version))
	}
	facts = Case.result_facts(result)
	text = Case.result_text(result)
	source_bytes = source.count_utf8_bytes()
	output_bytes = text.count_utf8_bytes()

	## The facts must partition both sides exactly and in order: one input
	## scalar each, contiguous input and output coordinates, and a length the
	## declared shape allows. A gap, an overlap, or a shape whose lengths
	## disagree means the mapping cannot be trusted to relate presentation
	## back to source, so nothing is returned.
	var $projected = List.with_capacity(facts.len())
	var $input_scalar_cursor = 0
	var $input_byte_cursor = 0
	var $output_scalar_cursor = 0
	var $output_byte_cursor = 0
	var $index = 0
	while $index < facts.len() {
		fact = list_at(facts, $index)
		input = project_range(fact.input)
		output = project_range(fact.output)
		if input.scalars.start() != $input_scalar_cursor or input.scalars.length() != 1 or input.utf8_bytes.start() != $input_byte_cursor or input.utf8_bytes.length() == 0 {
			return Err(FactCoverageInvalid({ fact: $index }))
		}
		if output.scalars.start() != $output_scalar_cursor or output.utf8_bytes.start() != $output_byte_cursor {
			return Err(FactCoverageInvalid({ fact: $index }))
		}
		input_byte_end = input.utf8_bytes.start() + input.utf8_bytes.length()
		output_byte_end = output.utf8_bytes.start() + output.utf8_bytes.length()
		if input_byte_end > source_bytes or output_byte_end > output_bytes {
			return Err(FactCoverageInvalid({ fact: $index }))
		}
		shape = project_shape(fact.shape)
		shape_agrees = match shape {
			Unchanged => output.scalars.length() == 1 and output.utf8_bytes.length() == input.utf8_bytes.length()
			Simple => output.scalars.length() == 1
			Expanded => output.scalars.length() > 1
			Removed => output.scalars.length() == 0 and output.utf8_bytes.length() == 0
		}
		if !shape_agrees {
			return Err(FactShapeInvalid({ fact: $index }))
		}
		$projected = $projected.append({ contextual: fact.contextual, input, output, shape })
		$input_scalar_cursor = $input_scalar_cursor + 1
		$input_byte_cursor = input_byte_end
		$output_scalar_cursor = $output_scalar_cursor + output.scalars.length()
		$output_byte_cursor = output_byte_end
		$index = $index + 1
	}
	if $input_byte_cursor != source_bytes or $output_byte_cursor != output_bytes {
		return Err(IncompleteCoverage({ facts: facts.len() }))
	}
	Ok({
		facts: $projected,
		operation: match Case.result_operation(result) {
			Fold => Fold
			Lower => Lower
			Title => Title
			Upper => Upper
		},
		profile_revision: match Case.result_profile_revision(result) {
			NoProfileRevision => None
			MappingTurkicV1 => Some("MappingTurkicV1")
			MappingLithuanianV1 => Some("MappingLithuanianV1")
			FoldSimpleV1 => Some("FoldSimpleV1")
			FoldTurkicV1 => Some("FoldTurkicV1")
		},
		text,
		unicode_version: version,
		work: {
			fact_visits: facts.len(),
			input_scalar_visits: $input_scalar_cursor,
			output_scalar_visits: $output_scalar_cursor,
		},
	})
}

## The pinned Unicode data version. A dependency that reports a different
## version is a reviewed provenance change, not a silent upgrade.
pinned_unicode_version : Str
pinned_unicode_version = "17.0.0"

project_range : TextRange -> Semantics.TextRange
project_range = |range| {
	scalars = TextRange.scalar_range(range)
	bytes = TextRange.byte_range(range)
	{
		scalars: Semantics.Range.from_start_and_length(ScalarRange.start(scalars), ScalarRange.len(scalars)),
		utf8_bytes: Semantics.Range.from_start_and_length(ByteRange.start(bytes), ByteRange.len(bytes)),
	}
}

project_shape : Case.Shape -> KernelCaseTransform.Shape
project_shape = |shape| match shape {
	Unchanged => Unchanged
	Simple => Simple
	Expanded => Expanded
	Removed => Removed
}

map_case_error : Case.Error -> KernelCaseTransform.Error
map_case_error = |error| match error {
	LimitExceeded({ resource, limit, required }) => {
		dimension = match resource {
			InputBytes => InputBytes
			InputScalars => InputScalars
			OutputBytes => OutputBytes
			OutputScalars => OutputScalars
			Facts => Facts
		}
		Unicode(LimitExceeded({ dimension, limit, required }))
	}
	CoordinateOverflow(_) => Unicode(CoordinateOverflow)
	InternalEncodingFault => Unicode(InternalEncodingFault)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "KernelCaseTransform validated list index"
}
