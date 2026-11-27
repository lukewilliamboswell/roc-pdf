import KernelFont
import KernelInternationalText
import Semantics
import shaping.Font as OpenType

## The provider sees one font, resolved direction, authored language, script,
## and stable paragraph offsets. The output's cluster list is logical order
## and its glyph list is provider paint order. The line materializer consumes
## both orders explicitly after committing the line.
KernelInternationalShape :: [].{
	Error : [
		FontDisagreement,
		FontRejected,
		GlyphLimit({ attempted : U64, limit : U64 }),
		InvalidCluster({ byte : U64 }),
		InvalidItem,
		InvalidProviderInput,
		InvalidProviderOutput,
		MissingGlyph({ byte : U64 }),
		ShapeBudget(List(OpenType.Budget)),
	]

	Face :: { font : OpenType, glyph_count : U64 }
	Program :: { plan : OpenType.ShapePlan, face : Face, options : Options }
	Options : { direction : [LeftToRight, RightToLeft], language : Semantics.Language, script : Str }

	Glyph : {
		id : U32,
		advance : { x : I32, y : I32 },
		offset : { x : I32, y : I32 },
		origin : OpenType.GlyphOrigin,
	}

	Cluster : { glyphs : Semantics.IndexRange, source : Semantics.TextRange, unsafe_before : Bool }

	Shaped : { clusters : List(Cluster), glyphs : List(Glyph), source : Semantics.TextRange }

	## Retain the provider inspection once per *already validated* font. Its
	## parser supplies shape tables. PDF eligibility and embedding rights
	## remain facts of the earlier KernelFont inspection.
	prepare : KernelFont.Inspection -> Try(Face, Error)
	prepare = |inspection| {
		font = OpenType.from_bytes(inspection.bytes, OpenType.ReadOptions.{ strict: True }) ? |_| FontRejected
		if OpenType.units_per_em(font) != inspection.metrics.units_per_em or OpenType.glyph_count(font).to_u64() != inspection.metrics.glyph_count {
			return Err(FontDisagreement)
		}
		Ok(Face.{ font, glyph_count: inspection.metrics.glyph_count })
	}

	program : Face, Options -> Program
	program = |face, options| {
		language = match options.language {
			Language(tag) => tag
			Inherited => ""
		}
		direction = match options.direction {
			LeftToRight => LeftToRight
			RightToLeft => RightToLeft
		}
		plan = OpenType.plan(face.font, OpenType.ShapeOptions.{ script: options.script, language, direction })
		Program.{ face, plan, options }
	}

	shape : Program, KernelInternationalText.Item, List(KernelInternationalText.ScalarAt), U64 -> Try(Shaped, Error)
	shape = |provider, item, scalars, max_glyphs| {
		if provider.options.direction != item.direction or provider.options.language != item.language or provider.options.script != item.script {
			return Err(InvalidItem)
		}
		source = item.source
		start = source.scalars.start()
		length = source.scalars.length()
		if length == 0 or start > scalars.len() or length > scalars.len() - start {
			return Err(InvalidItem)
		}
		slice = scalars.sublist({ start, len: length })
		byte_end = range_end(source.utf8_bytes)?
		if list_at(slice, 0).offset != source.utf8_bytes.start() or list_at(slice, length - 1).offset >= byte_end {
			return Err(InvalidItem)
		}
		traced = OpenType.shape_scalars_traced(provider.face.font, provider.plan, slice) ? |error| match error {
			InvalidInput(_) => InvalidProviderInput
			OverBudget({ budgets, run: _, origins: _ }) => ShapeBudget(budgets)
		}
		run = traced.run
		glyph_count = run.glyphs.len()
		if glyph_count > max_glyphs {
			return Err(GlyphLimit({ attempted: glyph_count, limit: max_glyphs }))
		}
		if glyph_count == 0 or run.advances.len() != glyph_count or run.clusters.len() != glyph_count or run.flags.len() != glyph_count or run.offsets.len() != glyph_count or traced.origins.len() != glyph_count {
			return Err(InvalidProviderOutput)
		}
		var $glyphs = List.with_capacity(glyph_count)
		var $index = 0
		while $index < glyph_count {
			glyph = list_at(run.glyphs, $index)
			if glyph == 0 or OpenType.is_missing(list_at(run.flags, $index)) {
				return Err(MissingGlyph({ byte: list_at(run.clusters, $index) }))
			}
			advance = list_at(run.advances, $index)
			if glyph.to_u64() >= provider.face.glyph_count or advance.x < 0 or advance.y != 0 {
				return Err(InvalidProviderOutput)
			}
			$glyphs = $glyphs.append({ id: glyph, advance, offset: list_at(run.offsets, $index), origin: list_at(traced.origins, $index) })
			$index = $index + 1
		}
		clusters = adapt_clusters(run, item, slice, byte_end)?
		Ok({ clusters, glyphs: $glyphs, source })
	}
}

## A provider cluster offset refers to the first scalar contributing to
## it, including ligatures and canonical forms. Derive range endpoints
## from adjacent supplied offsets and prove the entire source partition.
## PDF lowering later uses these ranges for ISO 32000-2:2020 9.10 and 14.9.
adapt_clusters : OpenType.Run, KernelInternationalText.Item, List(KernelInternationalText.ScalarAt), U64 -> Try(List(KernelInternationalShape.Cluster), KernelInternationalShape.Error)
adapt_clusters = |run, item, scalars, byte_end| {
	rtl = item.direction == RightToLeft
	paint_count = run.glyphs.len()
	var $clusters = List.with_capacity(U64.min(paint_count, scalars.len()))
	var $scalar = 0
	var $scan = 0
	while $scan < paint_count {
		start = $scan
		first = paint_index(start, paint_count, rtl)
		offset = list_at(run.clusters, first)
		if $scalar >= scalars.len() or list_at(scalars, $scalar).offset != offset {
			return Err(InvalidCluster({ byte: offset }))
		}
		var $unsafe = False
		while $scan < paint_count and list_at(run.clusters, paint_index($scan, paint_count, rtl)) == offset {
			$unsafe = $unsafe or OpenType.is_unsafe_to_break(list_at(run.flags, paint_index($scan, paint_count, rtl)))
			$scan = $scan + 1
		}
		ending = if ($scan == paint_count) byte_end else list_at(run.clusters, paint_index($scan, paint_count, rtl))
		if ending <= offset or ending > byte_end {
			return Err(InvalidCluster({ byte: offset }))
		}
		scalar_start = $scalar
		while $scalar < scalars.len() and list_at(scalars, $scalar).offset < ending {
			$scalar = $scalar + 1
		}
		if ($scalar == scalars.len() and ending != byte_end) or ($scalar < scalars.len() and list_at(scalars, $scalar).offset != ending) {
			return Err(InvalidCluster({ byte: ending }))
		}
		$clusters = $clusters.append({
			glyphs: Semantics.IndexRange.from_start_and_length({ start: if (rtl) paint_count - $scan else start, length: $scan - start }),
			source: {
				scalars: Semantics.IndexRange.from_start_and_length({ start: item.source.scalars.start() + scalar_start, length: $scalar - scalar_start }),
				utf8_bytes: Semantics.IndexRange.from_start_and_length({ start: offset, length: ending - offset }),
			},
			unsafe_before: $unsafe,
		})
	}
	if $scalar != scalars.len() {
		return Err(InvalidProviderOutput)
	}
	Ok($clusters)
}

paint_index : U64, U64, Bool -> U64
paint_index = |logical, count, rtl| if (rtl) count - 1 - logical else logical

range_end : Semantics.IndexRange -> Try(U64, KernelInternationalShape.Error)
range_end = |range| match U64.plus_try(range.start(), range.length()) {
	Ok(ending) => Ok(ending)
	Err(Overflow) => Err(InvalidItem)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(_) => crash "international glyph index escaped its validated span"
}
