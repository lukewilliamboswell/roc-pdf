import unicode.ByteRange
import unicode.Grapheme
import unicode.LineBreak
import unicode.Scalar
import unicode.Script
import unicode.ScriptItemization
import unicode.TextPosition
import unicode.TextRange
import unicode.UnicodeVersion

KernelUnicode :: [].{
	UnicodeLimits : {
		max_graphemes : U64,
		max_line_boundaries : U64,
		max_scalars : U64,
		max_script_runs : U64,
	}

	UnicodeRange : {
		byte_end : U64,
		byte_start : U64,
		scalar_end : U64,
		scalar_start : U64,
	}

	LineBoundary : {
		authority : [NonTailorable, Tailorable],
		byte_offset : U64,
		decision : [Allowed, Mandatory, Prohibited],
		scalar_offset : U64,
	}

	ScriptRun : {
		range : UnicodeRange,
		script : Str,
	}

	UnicodeWork : {
		grapheme_visits : U64,
		line_boundary_visits : U64,
		scalar_visits : U64,
		script_run_visits : U64,
	}

	UnicodeAnalysis : {
		graphemes : List(UnicodeRange),
		line_boundaries : List(LineBoundary),
		script_runs : List(ScriptRun),
		work : UnicodeWork,
	}

	UnicodeError : [
		GraphemeLimitExceeded({ limit : U64, required : U64 }),
		InconsistentGraphemeRange({ byte_end : U64, byte_start : U64 }),
		LineBoundaryLimitExceeded({ limit : U64, required : U64 }),
		ScalarLimitExceeded({ limit : U64, required : U64 }),
		ScriptRunLimitExceeded({ limit : U64, required : U64 }),
	]

	## The released package tag resolves to this reviewed source identity. Its
	## immutable archive URL and digest are recorded with the Gate 3 evidence.
	source_revision : Str
	source_revision = "b689986172679aa9fbdcd7890e3031a48b1c582f"

	version : Str
	version = UnicodeVersion.to_str(UnicodeVersion.current)

	default_limits : UnicodeLimits
	default_limits = {
		max_graphemes: 1000000,
		max_line_boundaries: 1000001,
		max_scalars: 1000000,
		max_script_runs: 1000000,
	}

	## Analyze one immutable source into flat, source-relative Unicode facts.
	## The four package algorithms scan the source independently and linearly;
	## returned ranges never retain source substrings. All retained lists are
	## bounded before append, and no partial analysis escapes on failure.
	analyze : Str, UnicodeLimits -> Try(UnicodeAnalysis, UnicodeError)
	analyze = |source, limits| {
		raw_graphemes = collect_grapheme_ranges(source, limits.max_graphemes)?
		graphemes_and_scalars = attach_scalar_ranges(source, raw_graphemes, limits.max_scalars)?
		line_boundaries = collect_line_boundaries(source, limits.max_line_boundaries)?
		script_runs = collect_script_runs(source, limits.max_script_runs)?

		Ok({
			graphemes: graphemes_and_scalars.graphemes,
			line_boundaries,
			script_runs,
			work: {
				grapheme_visits: raw_graphemes.len(),
				line_boundary_visits: line_boundaries.len(),
				scalar_visits: graphemes_and_scalars.scalars,
				script_run_visits: script_runs.len(),
			},
		})
	}

	collect_grapheme_ranges : Str, U64 -> Try(List(ByteRange), UnicodeError)
	collect_grapheme_ranges = |source, limit| {
		var $ranges = []
		for range in Grapheme.iter_ranges(source) {
			required = $ranges.len() + 1
			if required > limit {
				return Err(GraphemeLimitExceeded({ limit, required }))
			}
			$ranges = $ranges.append(range)
		}
		Ok($ranges)
	}

	attach_scalar_ranges : Str, List(ByteRange), U64 -> Try({ graphemes : List(UnicodeRange), scalars : U64 }, UnicodeError)
	attach_scalar_ranges = |source, ranges, scalar_limit| {
		var $graphemes = []
		var $range_index = 0
		var $scalar_start = 0
		var $scalar_count = 0

		for located in Scalar.iter(source) {
			required = $scalar_count + 1
			if required > scalar_limit {
				return Err(ScalarLimitExceeded({ limit: scalar_limit, required }))
			}
			$scalar_count = required

			match ranges.get($range_index) {
				Err(OutOfBounds) => return Err(
					InconsistentGraphemeRange({
						byte_start: ByteRange.start(located.byte_range),
						byte_end: ByteRange.end(located.byte_range),
					}),
				)
				Ok(range) => {
					if ByteRange.end(located.byte_range) == ByteRange.end(range) {
						$graphemes = $graphemes.append({
							byte_start: ByteRange.start(range),
							byte_end: ByteRange.end(range),
							scalar_start: $scalar_start,
							scalar_end: required,
						})
						$range_index = $range_index + 1
						$scalar_start = required
					} else if ByteRange.end(located.byte_range) > ByteRange.end(range) {
						return Err(
							InconsistentGraphemeRange({
								byte_start: ByteRange.start(range),
								byte_end: ByteRange.end(range),
							}),
						)
					}
				}
			}
		}

		if $range_index != ranges.len() {
			match ranges.get($range_index) {
				Err(OutOfBounds) => Ok({ graphemes: $graphemes, scalars: $scalar_count })
				Ok(range) => Err(
					InconsistentGraphemeRange({
						byte_start: ByteRange.start(range),
						byte_end: ByteRange.end(range),
					}),
				)
			}
		} else {
			Ok({ graphemes: $graphemes, scalars: $scalar_count })
		}
	}

	collect_line_boundaries : Str, U64 -> Try(List(LineBoundary), UnicodeError)
	collect_line_boundaries = |source, limit| {
		var $boundaries = []
		for boundary in LineBreak.iter_boundaries(source) {
			required = $boundaries.len() + 1
			if required > limit {
				return Err(LineBoundaryLimitExceeded({ limit, required }))
			}
			$boundaries = $boundaries.append({
				authority: match boundary.authority {
					NonTailorable => NonTailorable
					Tailorable => Tailorable
				},
				byte_offset: TextPosition.byte_offset(boundary.at),
				decision: match boundary.decision {
					Allowed => Allowed
					Mandatory => Mandatory
					Prohibited => Prohibited
				},
				scalar_offset: TextPosition.scalar_offset(boundary.at),
			})
		}
		Ok($boundaries)
	}

	collect_script_runs : Str, U64 -> Try(List(ScriptRun), UnicodeError)
	collect_script_runs = |source, limit| {
		var $runs = []
		for run in ScriptItemization.iter_runs(source, ScriptItemization.default) {
			required = $runs.len() + 1
			if required > limit {
				return Err(ScriptRunLimitExceeded({ limit, required }))
			}
			start = TextRange.start(run.range)
			end = TextRange.end(run.range)
			$runs = $runs.append({
				range: {
					byte_start: TextPosition.byte_offset(start),
					byte_end: TextPosition.byte_offset(end),
					scalar_start: TextPosition.scalar_offset(start),
					scalar_end: TextPosition.scalar_offset(end),
				},
				script: Script.short_alias(run.script),
			})
		}
		Ok($runs)
	}

	expect version == "17.0.0"

	## Combining sequences stay atomic, scalar and byte coordinates agree, and
	## script itemization is a separate explicit fact.
	expect {
		analysis = analyze("é漢", default_limits)?

		analysis.graphemes == [
			{ byte_start: 0, byte_end: 3, scalar_start: 0, scalar_end: 2 },
			{ byte_start: 3, byte_end: 6, scalar_start: 2, scalar_end: 3 },
		] and analysis.script_runs == [
			{ range: { byte_start: 0, byte_end: 3, scalar_start: 0, scalar_end: 2 }, script: "Latn" },
			{ range: { byte_start: 3, byte_end: 6, scalar_start: 2, scalar_end: 3 }, script: "Hani" },
		]
	}

	## Every UAX #14 boundary is retained, including prohibited boundaries and the
	## mandatory end boundary needed by deterministic line selection.
	expect {
		analysis = analyze("a b", default_limits)?

		analysis.line_boundaries.map(
			|boundary| {
				byte_offset: boundary.byte_offset,
				decision: boundary.decision,
			},
		) == [
			{ byte_offset: 0, decision: Prohibited },
			{ byte_offset: 1, decision: Prohibited },
			{ byte_offset: 2, decision: Allowed },
			{ byte_offset: 3, decision: Mandatory },
		]
	}

	## Limits reject atomically at the first crossing item.
	expect match analyze("ab", { ..default_limits, max_graphemes: 1 }) {
		Err(GraphemeLimitExceeded({ limit: 1, required: 2 })) => Bool.True
		_ => Bool.False
	}
}
