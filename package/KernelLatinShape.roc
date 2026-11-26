import KernelFont
import KernelUnicode
import Text
import shaping.Font as OpenType
import unicode.ByteRange
import unicode.Scalar

KernelLatinShape :: [].{
	Error : [
		FontDisagreement,
		FontRejected,
		InvalidProviderInput,
		InvalidProviderOutput,
		MissingGlyph({ byte : U64 }),
		ShapeBudget(List(OpenType.Budget)),
		UnsupportedGlyph({ byte : U64 }),
	]

	Plan :: { font : OpenType, plan : OpenType.ShapePlan }

	ScalarAt : { offset : U64, scalar : U32 }

	Glyph : {
		advance : I32,
		id : U32,
		kind : Text.ClusterKind,
		offset : I32,
		range : KernelUnicode.UnicodeRange,
	}

	eligible_face : KernelFont.Inspection -> Bool
	eligible_face = |inspection| inspection.digest == inter_regular_sha256

	## This initial horizontal English run policy covers printable ASCII and
	## the literal right arrow. Other text uses the existing coverage path.
	input : Str, KernelUnicode.UnicodeAnalysis -> [Eligible(List(ScalarAt)), OutsidePolicy]
	input = |source, analysis| {
		if analysis.graphemes.len() != analysis.work.scalar_visits {
			return OutsidePolicy
		}
		var $scalars = List.with_capacity(analysis.work.scalar_visits)
		for located in Scalar.iter(source) {
			scalar = Scalar.to_u32(located.scalar)
			if (scalar < 0x20 or scalar > 0x7e) and scalar != 0x2192 {
				return OutsidePolicy
			}
			$scalars = $scalars.append({ scalar, offset: ByteRange.start(located.byte_range) })
		}
		Eligible($scalars)
	}

	## The PDF font planner has already validated the font, its rights and its
	## identity. OpenType owns shaping data and retained feature lookups only.
	prepare : KernelFont.Inspection -> Try(Plan, Error)
	prepare = |inspection| {
		if !eligible_face(inspection) {
			return Err(FontDisagreement)
		}
		font = OpenType.from_bytes(inspection.bytes, OpenType.ReadOptions.{ strict: True }) ? |_| FontRejected
		if OpenType.units_per_em(font) != inspection.metrics.units_per_em or OpenType.glyph_count(font).to_u64() != inspection.metrics.glyph_count {
			return Err(FontDisagreement)
		}
		Ok(Plan.{ font, plan: OpenType.plan(font, OpenType.ShapeOptions.{ script: "Latn", language: "en", direction: LeftToRight, clusters: Characters }) })
	}

	## A prospective cut inside a ligature or at an unsafe provider boundary
	## needs both sides reshaped. If one exists, shape independently between
	## all legal boundaries before accepting advances. Fitting then uses only
	## the final runs and can never reuse cross-boundary glyphs or advances.
	## The checked provider sees at most twice the input scalars in total.
	shape : Plan, KernelFont.Inspection, List(ScalarAt), KernelUnicode.UnicodeAnalysis -> Try({ glyphs : List(Glyph), scalar_visits : U64 }, Error)
	shape = |plan, inspection, scalars, analysis| {
		if scalars.is_empty() or scalars.len() != analysis.graphemes.len() or analysis.line_boundaries.len() != scalars.len() + 1 {
			return Err(InvalidProviderInput)
		}
		traced = shape_checked(plan, scalars)?
		if !needs_isolation(traced.run, analysis.line_boundaries) {
			glyphs = adapt_glyphs(inspection, traced, analysis.graphemes, 0, scalars.len())?
			return Ok({ glyphs, scalar_visits: scalars.len() })
		}
		var $glyphs = List.with_capacity(scalars.len())
		var $start = 0
		for boundary in analysis.line_boundaries {
			if boundary.decision != Prohibited {
				end = boundary.scalar_offset
				if end <= $start or end > scalars.len() {
					return Err(InvalidProviderInput)
				}
				segment = scalars.sublist({ start: $start, len: end - $start })
				shaped = shape_checked(plan, segment)?
				adapted = adapt_glyphs(inspection, shaped, analysis.graphemes, $start, end)?
				for glyph in adapted {
					$glyphs = $glyphs.append(glyph)
				}
				$start = end
			}
		}
		if $start != scalars.len() {
			return Err(InvalidProviderInput)
		}
		Ok({ glyphs: $glyphs, scalar_visits: scalars.len() * 2 })
	}
}

Traced : { run : OpenType.Run, origins : List(OpenType.GlyphOrigin) }

shape_checked : KernelLatinShape.Plan, List(KernelLatinShape.ScalarAt) -> Try(Traced, KernelLatinShape.Error)
shape_checked = |plan, scalars| {
	traced = OpenType.shape_scalars_traced(plan.font, plan.plan, scalars) ? |error| match error {
		InvalidInput(_) => InvalidProviderInput
		OverBudget({ budgets, run: _, origins: _ }) => ShapeBudget(budgets)
	}
	run = traced.run
	count = run.glyphs.len()
	if count == 0 or count > scalars.len() or run.clusters.len() != count or run.flags.len() != count or run.advances.len() != count or run.offsets.len() != count or traced.origins.len() != count {
		return Err(InvalidProviderOutput)
	}
	var $index = 0
	while $index < count {
		if OpenType.is_missing(list_at(run.flags, $index)) or list_at(run.glyphs, $index) == 0 {
			return Err(MissingGlyph({ byte: list_at(run.clusters, $index) }))
		}
		$index = $index + 1
	}
	Ok(traced)
}

needs_isolation : OpenType.Run, List(KernelUnicode.LineBoundary) -> Bool
needs_isolation = |run, boundaries| {
	var $cluster = 0
	var $index = 1
	while $index + 1 < boundaries.len() {
		boundary = list_at(boundaries, $index)
		if boundary.decision != Prohibited {
			while $cluster < run.clusters.len() and list_at(run.clusters, $cluster) < boundary.byte_offset {
				$cluster = $cluster + 1
			}
			if $cluster == run.clusters.len() or list_at(run.clusters, $cluster) != boundary.byte_offset or OpenType.is_unsafe_to_break(list_at(run.flags, $cluster)) {
				return True
			}
		}
		$index = $index + 1
	}
	False
}

## OpenType 1.9.1 GSUB and GPOS decide glyph substitutions and positions.
## In this closed path each cluster must draw one glyph. Check that provider
## offsets partition the earlier UAX #29 ranges and that a many-scalar cluster
## carries the matching trace kind. Keep the classification and full source
## range for ISO 32000-2:2020 9.10.3 and 14.9.4 mapping at PDF lowering.
adapt_glyphs : KernelFont.Inspection, Traced, List(KernelUnicode.UnicodeRange), U64, U64 -> Try(List(KernelLatinShape.Glyph), KernelLatinShape.Error)
adapt_glyphs = |inspection, traced, graphemes, start, end| {
	run = traced.run
	end_byte = list_at(graphemes, end - 1).byte_end
	var $glyphs = List.with_capacity(run.glyphs.len())
	var $scalar = start
	var $index = 0
	while $index < run.glyphs.len() {
		byte_start = list_at(run.clusters, $index)
		byte_end = if ($index + 1 == run.glyphs.len()) end_byte else list_at(run.clusters, $index + 1)
		if $scalar >= end or list_at(graphemes, $scalar).byte_start != byte_start or byte_end <= byte_start {
			return Err(InvalidProviderOutput)
		}
		scalar_start = $scalar
		while $scalar < end and list_at(graphemes, $scalar).byte_end <= byte_end {
			$scalar = $scalar + 1
		}
		if $scalar == scalar_start or list_at(graphemes, $scalar - 1).byte_end != byte_end {
			return Err(InvalidProviderOutput)
		}
		kind : Text.ClusterKind
		kind = match list_at(traced.origins, $index) {
			Mapped if $scalar - scalar_start == 1 => OneToOne
			Substituted(_) if $scalar - scalar_start == 1 => Contextual
			Ligature({ components, feature: _ }) if components >= 2 and components.to_u64() == $scalar - scalar_start => Ligature
			_ => return Err(UnsupportedGlyph({ byte: byte_start }))
		}
		id = list_at(run.glyphs, $index)
		advance = list_at(run.advances, $index)
		offset = list_at(run.offsets, $index)
		if id.to_u64() >= inspection.metrics.glyph_count or advance.x < 0 or advance.y != 0 or offset.y != 0 {
			return Err(UnsupportedGlyph({ byte: byte_start }))
		}
		$glyphs = $glyphs.append({ advance: advance.x, id, kind, offset: offset.x, range: { byte_end, byte_start, scalar_end: $scalar, scalar_start } })
		$index = $index + 1
	}
	if $scalar == end {
		Ok($glyphs)
	} else {
		Err(InvalidProviderOutput)
	}
}

inter_regular_sha256 : List(U8)
inter_regular_sha256 = [0x40, 0xd6, 0x92, 0xfc, 0xe1, 0x88, 0xe4, 0x47, 0x1e, 0x2b, 0x3c, 0xba, 0x93, 0x7b, 0xe9, 0x67, 0x87, 0x8f, 0x63, 0x1a, 0xd3, 0xeb, 0xbb, 0xdc, 0xd5, 0x87, 0x68, 0x7c, 0x7e, 0xbe, 0x0c, 0x82]

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(_) => crash "validated Latin shape index escaped its range"
}
