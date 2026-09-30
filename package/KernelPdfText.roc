import Font
import KernelContent
import KernelFontPlan
import KernelResourceName
import KernelLex
import KernelPdfFont
import KernelTagged
import KernelTextOwnership
import Layout
import Semantics
import Text
import unicode.Scalar

KernelPdfText :: [].{
	Dimension : [ActualTextScalars, ContentBytes, Mappings, Placements, SourceScalars]
	Error : [
		ActualTextRequired({ run : U64 }),
		ArithmeticOverflow,
		ClusterInvalid({ cluster : U64, run : U64 }),
		FontPlanInvalid({ font : U64 }),
		GlyphNotRetained({ glyph : U32, run : U64 }),
		IncompleteUnicodeMapping({ cid : U32, font : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		OccurrenceInvalid({ occurrence : U64, run : U64 }),
		PlacementInvalid({ placement : U64 }),
		RunInvalid({ run : U64 }),
		UnicodeMappingConflict({ cid : U32, font : U64 }),
	]

	Limits :: { max_actual_text_scalars : U64, max_content_bytes : U64, max_mappings : U64, max_placements : U64, max_source_scalars : U64 }.{
		make : { max_actual_text_scalars : U64, max_content_bytes : U64, max_mappings : U64, max_placements : U64, max_source_scalars : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	Placement : { origin : Layout.Point, run : Text.RunId }

	Work : {
		actual_text_runs : U64,
		actual_text_scalars : U64,
		content_bytes : U64,
		glyph_visits : U64,
		mapping_conflicts_resolved : U64,
		mappings : U64,
		placement_visits : U64,
		run_visits : U64,
		source_scalar_visits : U64,
	}

	Plan :: { bytes : List(U8), mappings : List(List(KernelPdfFont.UnicodeMapping)), work : Work }.{
		build : Semantics.Store, Text.Store, List(KernelFontPlan.Plan), List(Placement), Limits -> Try(Plan, Error)
		build = |semantics, text, fonts, placements, limits| build_plan(semantics, text, fonts, placements, limits)

		bytes : Plan -> List(U8)
		bytes = |plan| plan.bytes

		mappings : Plan -> List(List(KernelPdfFont.UnicodeMapping))
		mappings = |plan| plan.mappings

		work : Plan -> Work
		work = |plan| plan.work
	}

	## Scene lowering prepares one local-coordinate text object per validated run.
	## Placement and marked-content ownership remain facts of the scene/tagged plans.
	## The first run, in dense run order, whose ActualText replacement carries
	## a Private Use Area scalar. It is a Unicode fact of the prepared text,
	## recorded where the replacement is materialized so later profile
	## validation never re-reads content streams.
	ActualTextPrivateUse : [NoPrivateUse, PrivateUseInRun(U64)]

	ScenePlan :: { actual_text_private_use : ActualTextPrivateUse, content : KernelContent.TextPlan, mappings : List(List(KernelPdfFont.UnicodeMapping)), work : Work }.{
		build : KernelTextOwnership.Plan, List(KernelFontPlan.Plan), Limits -> Try(ScenePlan, Error)
		build = |ownership, fonts, limits| build_scene_plan(ownership, fonts, limits)

		actual_text_private_use : ScenePlan -> ActualTextPrivateUse
		actual_text_private_use = |plan| plan.actual_text_private_use

		content : ScenePlan -> KernelContent.TextPlan
		content = |plan| plan.content

		mappings : ScenePlan -> List(List(KernelPdfFont.UnicodeMapping))
		mappings = |plan| plan.mappings

		run : ScenePlan, Text.RunId -> KernelContent.TextRun
		run = |plan, run| KernelContent.TextPlan.run(plan.content, run.index())

		run_count : ScenePlan -> U64
		run_count = |plan| KernelContent.TextPlan.run_count(plan.content)

		work : ScenePlan -> Work
		work = |plan| plan.work
	}
}

MappingSlot := [Mapped(List(U32)), Unmapped]

FontState := { mappings : List(MappingSlot), plan : KernelFontPlan.Plan }

ScalarCache := { starts : List(U64), values : List(U32) }

ActualText := [NoActualText, UseActualText(List(U32))]

RunSource := { id : Semantics.TextSourceId, properties : Semantics.Range, range : Semantics.TextRange }

build_plan : Semantics.Store, Text.Store, List(KernelFontPlan.Plan), List(KernelPdfText.Placement), KernelPdfText.Limits -> Try(KernelPdfText.Plan, KernelPdfText.Error)
build_plan = |semantics, text, fonts, placements, limits| {
	check_limit(placements.len(), limits.max_placements, Placements)?
	states = initialize_fonts(fonts)?
	scalars = build_scalar_cache(semantics.text_sources, limits.max_source_scalars)?
	var $states = states
	var $placed = List.repeat(False, text.runs.len())
	var $bytes = List.with_capacity(U64.min(limits.max_content_bytes, initial_capacity))
	var $actual_text_runs = 0
	var $actual_text_scalars = 0
	var $glyph_visits = 0
	var $mapping_conflicts = 0
	var $placement_index = 0
	while $placement_index < placements.len() {
		placement = list_at(placements, $placement_index)
		run_index = placement.run.index()
		if run_index >= text.runs.len() or list_at($placed, run_index) {
			return Err(PlacementInvalid({ placement: $placement_index }))
		}
		run = list_at(text.runs, run_index)
		if run.id.index() != run_index or run.size.raw() <= 0 or run.glyphs.length() == 0 or run.glyphs.start() > text.glyphs.len() or run.glyphs.length() > text.glyphs.len() - run.glyphs.start() {
			return Err(RunInvalid({ run: run_index }))
		}
		font_index = run.instance.index()
		if font_index >= $states.len() {
			return Err(FontPlanInvalid({ font: font_index }))
		}
		actual_text = actual_text_for_run(semantics, scalars, text, run, run_index, $actual_text_scalars, limits.max_actual_text_scalars)?
		actual_length = match actual_text {
			NoActualText => 0
			UseActualText(values) => values.len()
		}
		if actual_length > 0 {
			$actual_text_runs = checked_add($actual_text_runs, 1)?
			$actual_text_scalars = checked_add($actual_text_scalars, actual_length)?
			check_limit($actual_text_scalars, limits.max_actual_text_scalars, ActualTextScalars)?
		}
		collected = collect_run_mappings($states, font_index, semantics, scalars, text, run, run_index, actual_length > 0)?
		$states = collected.states
		$mapping_conflicts = checked_add($mapping_conflicts, collected.conflicts)?
		emitted = emit_run($bytes, text, run, placement.origin, list_at($states, font_index).plan, actual_text, limits.max_content_bytes)?
		$bytes = emitted.bytes
		$glyph_visits = checked_add($glyph_visits, emitted.glyphs)?
		$placed = list_set($placed, run_index, True)
		$placement_index = $placement_index + 1
	}
	var $run_index = 0
	while $run_index < $placed.len() {
		if !list_at($placed, $run_index) {
			return Err(RunInvalid({ run: $run_index }))
		}
		$run_index = $run_index + 1
	}
	finished = finish_mappings($states, limits.max_mappings)?
	Ok(
		KernelPdfText.Plan.{
			bytes: $bytes,
			mappings: finished.mappings,
			work: {
				actual_text_runs: $actual_text_runs,
				actual_text_scalars: $actual_text_scalars,
				content_bytes: $bytes.len(),
				glyph_visits: $glyph_visits,
				mapping_conflicts_resolved: $mapping_conflicts,
				mappings: finished.count,
				placement_visits: placements.len(),
				run_visits: text.runs.len(),
				source_scalar_visits: scalars.values.len(),
			},
		},
	)
}

build_scene_plan : KernelTextOwnership.Plan, List(KernelFontPlan.Plan), KernelPdfText.Limits -> Try(KernelPdfText.ScenePlan, KernelPdfText.Error)
build_scene_plan = |ownership, fonts, limits| {
	text = KernelTextOwnership.Plan.text(ownership)
	semantics = KernelTagged.Plan.semantics(KernelTextOwnership.Plan.tagged(ownership))
	states = initialize_fonts(fonts)?
	scalars = build_scalar_cache(semantics.text_sources, limits.max_source_scalars)?
	var $states = states
	var $runs = List.with_capacity(text.runs.len())
	var $actual_text_runs = 0
	var $actual_text_scalars = 0
	var $content_bytes = 0
	var $glyph_visits = 0
	var $mapping_conflicts = 0
	var $private_use = NoPrivateUse
	var $run_index = 0
	while $run_index < text.runs.len() {
		run = list_at(text.runs, $run_index)
		if run.id.index() != $run_index or run.size.raw() <= 0 or run.glyphs.length() == 0 or run.glyphs.start() > text.glyphs.len() or run.glyphs.length() > text.glyphs.len() - run.glyphs.start() {
			return Err(RunInvalid({ run: $run_index }))
		}
		font_index = run.instance.index()
		if font_index >= $states.len() {
			return Err(FontPlanInvalid({ font: font_index }))
		}
		actual_text = actual_text_for_run(semantics, scalars, text, run, $run_index, $actual_text_scalars, limits.max_actual_text_scalars)?
		actual_length = match actual_text {
			NoActualText => 0
			UseActualText(values) => values.len()
		}
		if actual_length > 0 {
			$actual_text_runs = checked_add($actual_text_runs, 1)?
			$actual_text_scalars = checked_add($actual_text_scalars, actual_length)?
			check_limit($actual_text_scalars, limits.max_actual_text_scalars, ActualTextScalars)?
		}
		collected = collect_run_mappings($states, font_index, semantics, scalars, text, run, $run_index, actual_length > 0)?
		$states = collected.states
		$mapping_conflicts = checked_add($mapping_conflicts, collected.conflicts)?
		remaining = if $content_bytes > limits.max_content_bytes 0 else limits.max_content_bytes - $content_bytes
		actual_text_begin = match actual_text {
			NoActualText => []
			UseActualText(values) => append_actual_text_begin([], values, run.id.index(), remaining)?
		}
		if $private_use == NoPrivateUse and has_private_use(actual_text) {
			$private_use = PrivateUseInRun($run_index)
		}
		remaining_body = remaining - actual_text_begin.len()

		## The prepared body carries only the glyph operators: the font
		## selection is resource naming, so content lowering emits the `Tf`
		## operator through its authored-to-canonical name map, and the run
		## records the authored font ordinal and exact size that map needs.
		emitted = emit_run_glyphs([], text, run, { x: Layout.Unit.from_raw(0), y: Layout.Unit.from_raw(0) }, list_at($states, font_index).plan, remaining_body)?
		run_bytes = checked_add(actual_text_begin.len(), emitted.bytes.len())?
		$content_bytes = checked_add($content_bytes, run_bytes)?
		check_limit($content_bytes, limits.max_content_bytes, ContentBytes)?
		$runs = $runs.append({ actual_text_begin, body: emitted.bytes, close_actual_text: actual_length > 0, font: font_index, size: run.size })
		$glyph_visits = checked_add($glyph_visits, emitted.glyphs)?
		$run_index = $run_index + 1
	}
	finished = finish_mappings($states, limits.max_mappings)?
	Ok(
		KernelPdfText.ScenePlan.{
			actual_text_private_use: $private_use,
			content: KernelContent.TextPlan.make($runs),
			mappings: finished.mappings,
			work: {
				actual_text_runs: $actual_text_runs,
				actual_text_scalars: $actual_text_scalars,
				content_bytes: $content_bytes,
				glyph_visits: $glyph_visits,
				mapping_conflicts_resolved: $mapping_conflicts,
				mappings: finished.count,
				placement_visits: 0,
				run_visits: text.runs.len(),
				source_scalar_visits: scalars.values.len(),
			},
		},
	)
}

initialize_fonts : List(KernelFontPlan.Plan) -> Try(List(FontState), KernelPdfText.Error)
initialize_fonts = |fonts| {
	var $states = List.with_capacity(fonts.len())
	var $font_index = 0
	while $font_index < fonts.len() {
		plan = list_at(fonts, $font_index)
		if plan.entries.len() == 0 or plan.entries.len() > 65535 {
			return Err(FontPlanInvalid({ font: $font_index }))
		}
		var $entry_index = 0
		while $entry_index < plan.entries.len() {
			entry = list_at(plan.entries, $entry_index)
			if entry.cid.to_u64() != $entry_index or entry.subset_glyph != entry.cid {
				return Err(FontPlanInvalid({ font: $font_index }))
			}
			$entry_index = $entry_index + 1
		}
		$states = $states.append({ mappings: List.repeat(Unmapped, plan.entries.len()), plan })
		$font_index = $font_index + 1
	}
	Ok($states)
}

build_scalar_cache : List(Semantics.TextSource), U64 -> Try(ScalarCache, KernelPdfText.Error)
build_scalar_cache = |sources, limit| {
	var $starts = List.with_capacity(sources.len() + 1)
	var $values = []
	var $source_index = 0
	while $source_index < sources.len() {
		$starts = $starts.append($values.len())
		for located in Scalar.iter(list_at(sources, $source_index).unicode) {
			required = checked_add($values.len(), 1)?
			check_limit(required, limit, SourceScalars)?
			$values = $values.append(Scalar.to_u32(located.scalar))
		}
		$source_index = $source_index + 1
	}
	$starts = $starts.append($values.len())
	Ok({ starts: $starts, values: $values })
}

run_source : Semantics.Store, ScalarCache, Text.Run, U64 -> Try(RunSource, KernelPdfText.Error)
run_source = |semantics, scalars, run, run_index| {
	source = match run.unicode {
		OccurrenceText(occurrence_id) => {
			if occurrence_id.index() >= semantics.occurrences.len() {
				return Err(OccurrenceInvalid({ occurrence: occurrence_id.index(), run: run_index }))
			}
			occurrence = list_at(semantics.occurrences, occurrence_id.index())
			if occurrence.id != occurrence_id {
				return Err(OccurrenceInvalid({ occurrence: occurrence_id.index(), run: run_index }))
			}
			match occurrence.source {
				Text(source_id, UnicodeRange(range)) => if source_id.index() < semantics.text_sources.len() {
					{ id: source_id, properties: occurrence.text_properties, range }
				} else {
					return Err(OccurrenceInvalid({ occurrence: occurrence_id.index(), run: run_index }))
				}
				_ => return Err(OccurrenceInvalid({ occurrence: occurrence_id.index(), run: run_index }))
			}
		}

		## An artifact run indexes its whole artifact text source and owns no
		## text property.
		ArtifactText(source_id) => {
			if source_id.index() >= semantics.text_sources.len() {
				return Err(RunInvalid({ run: run_index }))
			}
			unicode = list_at(semantics.text_sources, source_id.index()).unicode
			scalar_count = list_at(scalars.starts, source_id.index() + 1) - list_at(scalars.starts, source_id.index())
			{
				id: source_id,
				properties: Semantics.Range.from_start_and_length(0, 0),
				range: {
					scalars: Semantics.Range.from_start_and_length(0, scalar_count),
					utf8_bytes: Semantics.Range.from_start_and_length(0, unicode.count_utf8_bytes()),
				},
			}
		}
	}
	if !relative_text_range_fits(run.source, source.range) {
		return Err(RunInvalid({ run: run_index }))
	}
	Ok(source)
}

relative_text_range_fits : Semantics.TextRange, Semantics.TextRange -> Bool
relative_text_range_fits = |inner, outer| relative_range_fits(inner.scalars, outer.scalars) and relative_range_fits(inner.utf8_bytes, outer.utf8_bytes)

relative_range_fits : Semantics.Range, Semantics.Range -> Bool
relative_range_fits = |inner, outer| inner.start() <= outer.length() and inner.length() <= outer.length() - inner.start()

## Private Use Area planes: U+E000..U+F8FF, plane 15, and plane 16.
has_private_use : ActualText -> Bool
has_private_use = |actual_text| match actual_text {
	NoActualText => False
	UseActualText(values) => {
		var $index = 0
		var $found = False
		while !$found and $index < values.len() {
			value = list_at(values, $index)
			$found = (value >= 0xE000 and value <= 0xF8FF) or (value >= 0xF0000 and value <= 0xFFFFD) or (value >= 0x100000 and value <= 0x10FFFD)
			$index = $index + 1
		}
		$found
	}
}

actual_text_for_run : Semantics.Store, ScalarCache, Text.Store, Text.Run, U64, U64, U64 -> Try(ActualText, KernelPdfText.Error)
actual_text_for_run = |semantics, scalars, text, run, run_index, used, limit| {
	source = run_source(semantics, scalars, run, run_index)?
	match run.actual_text {
		FromOccurrence => {
			if !requires_actual_text(text, run, run_index)? {
				return Ok(NoActualText)
			}
			attempted = checked_add(used, run.source.scalars.length())?
			check_limit(attempted, limit, ActualTextScalars)?
			start = checked_add(source.range.scalars.start(), run.source.scalars.start())?
			values = source_scalars(scalars, source.id, start, run.source.scalars.length(), run_index)?
			if values.len() == 0 {
				Err(ActualTextRequired({ run: run_index }))
			} else {
				Ok(UseActualText(values))
			}
		}
		SemanticOverride(property_id) => {
			property_index = property_id.index()
			property_start = source.properties.start()
			property_length = source.properties.length()
			if property_index < property_start or property_index - property_start >= property_length or property_index >= semantics.text_properties.len() {
				return Err(ActualTextRequired({ run: run_index }))
			}
			value = match list_at(semantics.text_properties, property_index) {
				ActualText(actual) => actual
				_ => return Err(ActualTextRequired({ run: run_index }))
			}
			var $values = []
			for located in Scalar.iter(value) {
				attempted = checked_add(used, checked_add($values.len(), 1)?)?
				check_limit(attempted, limit, ActualTextScalars)?
				$values = $values.append(Scalar.to_u32(located.scalar))
			}
			if $values.len() == 0 {
				Err(ActualTextRequired({ run: run_index }))
			} else {
				Ok(UseActualText($values))
			}
		}
	}
}

requires_actual_text : Text.Store, Text.Run, U64 -> Try(Bool, KernelPdfText.Error)
requires_actual_text = |text, run, run_index| {
	if run.direction == RightToLeft or run.transformations.length() > 0 {
		return Ok(True)
	}
	if run.clusters.start() > text.clusters.len() or run.clusters.length() > text.clusters.len() - run.clusters.start() {
		return Err(RunInvalid({ run: run_index }))
	}
	var $cluster_index = run.clusters.start()
	cluster_end = run.clusters.start() + run.clusters.length()
	while $cluster_index < cluster_end {
		cluster = list_at(text.clusters, $cluster_index)
		if cluster.glyphs.length() != 1 {
			return Ok(True)
		}
		match cluster.kind {
			Contextual | Ligature | Reordered => return Ok(True)
			_ => {}
		}
		$cluster_index = $cluster_index + 1
	}
	Ok(False)
}

collect_run_mappings : List(FontState), U64, Semantics.Store, ScalarCache, Text.Store, Text.Run, U64, Bool -> Try({ conflicts : U64, states : List(FontState) }, KernelPdfText.Error)
collect_run_mappings = |states, font_index, semantics, scalars, text, run, run_index, allow_conflicts| {
	if run.clusters.start() > text.clusters.len() or run.clusters.length() > text.clusters.len() - run.clusters.start() {
		return Err(RunInvalid({ run: run_index }))
	}
	source = run_source(semantics, scalars, run, run_index)?
	state = list_at(states, font_index)
	var $slots = state.mappings
	var $conflicts = 0
	var $cluster_index = run.clusters.start()
	cluster_end = run.clusters.start() + run.clusters.length()
	while $cluster_index < cluster_end {
		cluster = list_at(text.clusters, $cluster_index)
		if cluster.glyphs.length() == 0 or cluster.glyphs.start() > text.glyph_indices.len() or cluster.glyphs.length() > text.glyph_indices.len() - cluster.glyphs.start() or !relative_text_range_fits(cluster.source, source.range) {
			return Err(ClusterInvalid({ cluster: $cluster_index, run: run_index }))
		}
		mapping = match cluster.kind {
			GeneratedDiscretionaryHyphen({ property, transformation: _ }) => {
				if cluster.source.scalars.length() != 0 or cluster.source.utf8_bytes.length() != 0 or !generated_discretionary_property(source.properties, semantics.text_properties, property, cluster.source) {
					return Err(ClusterInvalid({ cluster: $cluster_index, run: run_index }))
				}
				[0x002d]
			}
			_ => {
				if cluster.source.scalars.length() == 0 {
					return Err(ClusterInvalid({ cluster: $cluster_index, run: run_index }))
				}
				source_start = checked_add(source.range.scalars.start(), cluster.source.scalars.start())?
				source_scalars(scalars, source.id, source_start, cluster.source.scalars.length(), run_index)?
			}
		}
		var $glyph_reference = cluster.glyphs.start()
		glyph_reference_end = cluster.glyphs.start() + cluster.glyphs.length()
		while $glyph_reference < glyph_reference_end {
			glyph_index = list_at(text.glyph_indices, $glyph_reference)
			if glyph_index < run.glyphs.start() or glyph_index >= run.glyphs.start() + run.glyphs.length() {
				return Err(ClusterInvalid({ cluster: $cluster_index, run: run_index }))
			}
			glyph = list_at(text.glyphs, glyph_index).id.raw()
			cid = cid_for_glyph(state.plan, glyph, run_index)?
			match list_at($slots, cid.to_u64()) {
				Unmapped => {
					$slots = list_set($slots, cid.to_u64(), Mapped(mapping))
				}
				Mapped(existing) => if existing != mapping {
					if allow_conflicts {
						$conflicts = checked_add($conflicts, 1)?
					} else {
						return Err(UnicodeMappingConflict({ cid, font: font_index }))
					}
				}
			}
			$glyph_reference = $glyph_reference + 1
		}
		$cluster_index = $cluster_index + 1
	}
	Ok({ conflicts: $conflicts, states: list_set(states, font_index, { mappings: $slots, plan: state.plan }) })
}

generated_discretionary_property : Semantics.Range, List(Semantics.TextProperty), Semantics.TextPropertyId, Semantics.TextRange -> Bool
generated_discretionary_property = |range, properties, property_id, source| {
	index = property_id.index()
	if index < range.start() or index >= properties.len() or index - range.start() >= range.length() {
		return False
	}
	match list_at(properties, index) {
		SourceToPresentation({ kind: InsertedDiscretionaryHyphen, presentation, source: property_source }) => presentation == "-" and property_source == source
		_ => False
	}
}

source_scalars : ScalarCache, Semantics.TextSourceId, U64, U64, U64 -> Try(List(U32), KernelPdfText.Error)
source_scalars = |cache, source, start, length, run| {
	begin = list_at(cache.starts, source.index())
	end = list_at(cache.starts, source.index() + 1)
	if start > end - begin or length > end - begin - start {
		return Err(RunInvalid({ run: run }))
	}
	var $values = List.with_capacity(length)
	var $index = 0
	while $index < length {
		$values = $values.append(list_at(cache.values, begin + start + $index))
		$index = $index + 1
	}
	Ok($values)
}

cid_for_glyph : KernelFontPlan.Plan, U32, U64 -> Try(U32, KernelPdfText.Error)
cid_for_glyph = |plan, glyph, run| {
	if glyph.to_u64() >= plan.original_to_subset.len() {
		return Err(GlyphNotRetained({ glyph, run }))
	}
	cid = list_at(plan.original_to_subset, glyph.to_u64())
	if cid == 0xffffffff or cid == 0 or cid.to_u64() >= plan.entries.len() or list_at(plan.entries, cid.to_u64()).original_glyph != glyph {
		Err(GlyphNotRetained({ glyph, run }))
	} else {
		Ok(cid)
	}
}

finish_mappings : List(FontState), U64 -> Try({ count : U64, mappings : List(List(KernelPdfFont.UnicodeMapping)) }, KernelPdfText.Error)
finish_mappings = |states, limit| {
	var $all = List.with_capacity(states.len())
	var $count = 0
	var $font_index = 0
	while $font_index < states.len() {
		state = list_at(states, $font_index)
		var $font_mappings = []
		var $entry_index = 0
		while $entry_index < state.plan.entries.len() {
			entry = list_at(state.plan.entries, $entry_index)
			match list_at(state.mappings, $entry_index) {
				Unmapped => if entry.content {
					return Err(IncompleteUnicodeMapping({ cid: entry.cid, font: $font_index }))
				}
				Mapped(values) => {
					if !entry.content {
						return Err(FontPlanInvalid({ font: $font_index }))
					}
					$count = checked_add($count, 1)?
					check_limit($count, limit, Mappings)?
					$font_mappings = $font_mappings.append({ cid: entry.cid, scalars: values })
				}
			}
			$entry_index = $entry_index + 1
		}
		$all = $all.append($font_mappings)
		$font_index = $font_index + 1
	}
	Ok({ count: $count, mappings: $all })
}

emit_run : List(U8), Text.Store, Text.Run, Layout.Point, KernelFontPlan.Plan, ActualText, U64 -> Try({ bytes : List(U8), glyphs : U64 }, KernelPdfText.Error)
emit_run = |bytes, text, run, origin, font, actual_text, limit| {
	var $out = match actual_text {
		NoActualText => bytes
		UseActualText(values) => append_actual_text_begin(bytes, values, run.id.index(), limit)?
	}
	$out = append_literal($out, "BT\n", limit)?
	emitted = emit_run_body($out, text, run, origin, font, limit)?
	$out = append_literal(emitted.bytes, "ET\n", limit)?
	$out = match actual_text {
		NoActualText => $out
		UseActualText(_) => append_literal($out, "EMC\n", limit)?
	}
	Ok({ bytes: $out, glyphs: emitted.glyphs })
}

emit_run_body : List(U8), Text.Store, Text.Run, Layout.Point, KernelFontPlan.Plan, U64 -> Try({ bytes : List(U8), glyphs : U64 }, KernelPdfText.Error)
emit_run_body = |bytes, text, run, origin, font, limit| {
	font_index = run.instance.index()
	var $out = append_literal(bytes, "/", limit)?
	$out = append_bytes($out, KernelResourceName.bytes("F", font_index), limit)?
	$out = append_literal($out, " ", limit)?
	$out = append_layout($out, run.size, limit)?
	$out = append_literal($out, " Tf\n", limit)?
	emit_run_glyphs($out, text, run, origin, font, limit)
}

## TJ adjustments are written with `adjustment_digits` fractional digits,
## so one adjustment step is 10^-digits thousandths of text space. One digit
## keeps every glyph within 0.00005 em of its layout position (0.0006 pt at
## 12 pt); whole thousandths would allow 0.0005 em for about 1% less output
## (docs/performance/output-size.md, step 3).
adjustment_digits : U8
adjustment_digits = 1

## Adjustment steps per thousandth of text space: 10^`adjustment_digits`.
adjustment_scale : I64
adjustment_scale = pow10(adjustment_digits)

pow10 : U8 -> I64
pow10 = |digits| {
	var $value = 1
	var $index = 0
	while $index < digits {
		$value = $value * 10
		$index = $index + 1
	}
	$value
}

## Writes one prepared glyph run as baseline segments.
##
## Each segment starts at the exact layout position of its first glyph with
## one `Td`, relative to the previous segment's start (a run's first segment
## is relative to the text object's origin and omits a zero move), and shows
## the segment's glyphs in one `TJ` array. A glyph whose vertical offset
## differs from the current segment's starts a new segment, so every glyph
## keeps its exact baseline.
##
## Inside a segment the reader advances the pen by each glyph's emitted `/W`
## width. Before every later glyph the array carries the adjustment that
## returns the pen to that glyph's exact layout position, rounded to the
## nearest 1/`adjustment_scale` thousandth of text space (halves round up).
## The pen is tracked exactly in units of 1/(1000 * `adjustment_scale`)
## layout units, so each glyph's rounding error is at most half an
## adjustment step, 0.0005 em at scale 1, and never accumulates along the
## segment. All arithmetic is checked `I64` integer arithmetic.
emit_run_glyphs : List(U8), Text.Store, Text.Run, Layout.Point, KernelFontPlan.Plan, U64 -> Try({ bytes : List(U8), glyphs : U64 }, KernelPdfText.Error)
emit_run_glyphs = |bytes, text, run, origin, font, limit| {
	size = run.size.raw()
	if size <= 0 {
		return Err(RunInvalid({ run: run.id.index() }))
	}
	var $out = bytes
	var $cursor_x = 0
	var $segment_x = 0
	var $segment_y = 0
	var $pen = 0
	var $previous_width = 0
	var $open = False
	var $glyph_index = run.glyphs.start()
	glyph_end = run.glyphs.start() + run.glyphs.length()
	while $glyph_index < glyph_end {
		glyph = list_at(text.glyphs, $glyph_index)
		if glyph.advance_x.raw() < 0 or glyph.advance_y.raw() != 0 {
			return Err(RunInvalid({ run: run.id.index() }))
		}
		x = checked_i64_add(origin.x.raw(), checked_i64_add($cursor_x, glyph.offset_x.raw())?)?
		y = checked_i64_add(origin.y.raw(), glyph.offset_y.raw())?
		cid = cid_for_glyph(font, glyph.id.raw(), run.id.index())?
		width = emitted_width(font, cid)?
		if $open == False or y != $segment_y {
			if $open {
				$out = append_literal($out, ">] TJ\n", limit)?
			}
			dx = checked_i64_sub(x, $segment_x)?
			dy = checked_i64_sub(y, $segment_y)?
			if dx != 0 or dy != 0 {
				$out = append_layout($out, Layout.Unit.from_raw(dx), limit)?
				$out = append_literal($out, " ", limit)?
				$out = append_layout($out, Layout.Unit.from_raw(dy), limit)?
				$out = append_literal($out, " Td\n", limit)?
			}
			$out = append_literal($out, "[<", limit)?
			$segment_x = x
			$segment_y = y
			$pen = 0
			$open = True
		} else {
			advance = checked_i64_times(checked_i64_times($previous_width, adjustment_scale)?, size)?
			nominal = checked_i64_add($pen, advance)?
			target = checked_i64_times(checked_i64_sub(x, $segment_x)?, checked_i64_times(1000, adjustment_scale)?)?
			steps = round_half_up(checked_i64_sub(nominal, target)?, size)?
			$pen = checked_i64_sub(nominal, checked_i64_times(steps, size)?)?
			if steps != 0 {
				$out = append_literal($out, "> ", limit)?
				$out = append_adjustment($out, steps, limit)?
				$out = append_literal($out, " <", limit)?
			}
		}
		$out = append_hex_u16($out, cid.to_u16_wrap(), limit)?
		$previous_width = width
		$cursor_x = checked_i64_add($cursor_x, glyph.advance_x.raw())?
		$glyph_index = $glyph_index + 1
	}
	if $open {
		$out = append_literal($out, ">] TJ\n", limit)?
	}
	Ok({ bytes: $out, glyphs: run.glyphs.length() })
}

## The `/W` value the font lowering emits for a CID: its advance scaled to
## thousandths of an em by the same shared rounding.
emitted_width : KernelFontPlan.Plan, U32 -> Try(I64, KernelPdfText.Error)
emitted_width = |font, cid| {
	entry = list_at(font.entries, cid.to_u64())
	match KernelPdfFont.scaled_unsigned_metric(entry.width, font.units_per_em) {
		Ok(width) => if width > I64.highest.to_u64_wrap() Err(ArithmeticOverflow) else Ok(width.to_i64_wrap())
		Err(_) => Err(FontPlanInvalid({ font: 0 }))
	}
}

## floor(numerator / denominator + 1/2) for a positive denominator.
round_half_up : I64, I64 -> Try(I64, KernelPdfText.Error)
round_half_up = |numerator, denominator| {
	twice = checked_i64_times(numerator, 2)?
	floor_div(checked_i64_add(twice, denominator)?, checked_i64_times(denominator, 2)?)
}

floor_div : I64, I64 -> Try(I64, KernelPdfText.Error)
floor_div = |numerator, denominator| {
	quotient = I64.div_trunc_by(numerator, denominator)
	remainder = I64.rem_by(numerator, denominator)
	if remainder != 0 and numerator < 0 {
		checked_i64_sub(quotient, 1)
	} else {
		Ok(quotient)
	}
}

## A TJ number: `steps` / `adjustment_scale` thousandths of text space, in
## canonical decimal form.
append_adjustment : List(U8), I64, U64 -> Try(List(U8), KernelPdfText.Error)
append_adjustment = |bytes, steps, limit| append_bytes(bytes, KernelLex.append_decimal_digits([], steps, adjustment_digits), limit)

append_actual_text_begin : List(U8), List(U32), U64, U64 -> Try(List(U8), KernelPdfText.Error)
append_actual_text_begin = |bytes, scalars, run, limit| {
	var $out = append_literal(bytes, "/Span <</ActualText <FEFF", limit)?
	var $index = 0
	while $index < scalars.len() {
		$out = append_utf16_scalar($out, list_at(scalars, $index), run, limit)?
		$index = $index + 1
	}
	append_literal($out, ">>> BDC\n", limit)
}

append_utf16_scalar : List(U8), U32, U64, U64 -> Try(List(U8), KernelPdfText.Error)
append_utf16_scalar = |bytes, scalar, run, limit| {
	if scalar > 0x10ffff or (scalar >= 0xd800 and scalar <= 0xdfff) {
		return Err(
			RunInvalid(
				{ run: run },
			),
		)
	}
	if scalar <= 0xffff {
		append_hex_u16(bytes, scalar.to_u16_wrap(), limit)
	} else {
		adjusted = scalar - 0x10000
		high = 0xd800 + adjusted.shr_wrap(10)
		low = 0xdc00 + adjusted.bitwise_and(0x3ff)
		with_high = append_hex_u16(bytes, high.to_u16_wrap(), limit)?
		append_hex_u16(with_high, low.to_u16_wrap(), limit)
	}
}

append_layout : List(U8), Layout.Unit, U64 -> Try(List(U8), KernelPdfText.Error)
append_layout = |bytes, value, limit| append_bytes(bytes, KernelLex.append_thousandths([], value.raw()), limit)

append_hex_u16 : List(U8), U16, U64 -> Try(List(U8), KernelPdfText.Error)
append_hex_u16 = |bytes, value, limit| {
	check_room(bytes.len(), 4, limit)?
	var $out = bytes
	$out = $out.append(hex_digit(value.shr_wrap(12).to_u8_wrap()))
	$out = $out.append(hex_digit(value.shr_wrap(8).bitwise_and(0xf).to_u8_wrap()))
	$out = $out.append(hex_digit(value.shr_wrap(4).bitwise_and(0xf).to_u8_wrap()))
	Ok($out.append(hex_digit(value.bitwise_and(0xf).to_u8_wrap())))
}

hex_digit : U8 -> U8
hex_digit = |value| if value < 10 0x30 + value else 0x41 + value - 10

append_literal : List(U8), Str, U64 -> Try(List(U8), KernelPdfText.Error)
append_literal = |bytes, literal, limit| append_bytes(bytes, Str.to_utf8(literal), limit)

append_bytes : List(U8), List(U8), U64 -> Try(List(U8), KernelPdfText.Error)
append_bytes = |bytes, added, limit| {
	check_room(bytes.len(), added.len(), limit)?
	var $out = bytes
	var $index = 0
	while $index < added.len() {
		$out = $out.append(list_at(added, $index))
		$index = $index + 1
	}
	Ok($out)
}

## Checks that `additional` more bytes fit the content limit. It takes only
## the length and reserves nothing: an explicit `List.reserve` sizes the
## allocation exactly, and a list returned through `?` and then appended to
## was copied per token by the pinned dev backend
## (docs/performance/lowering-uniqueness.md).
check_room : U64, U64, U64 -> Try({}, KernelPdfText.Error)
check_room = |length, additional, limit| {
	if length > limit or additional > limit - length {
		attempted = match U64.plus_try(length, additional) {
			Err(Overflow) => U64.highest
			Ok(value) => value
		}
		Err(LimitExceeded({ attempted, dimension: ContentBytes, limit }))
	} else {
		Ok({})
	}
}

check_limit : U64, U64, KernelPdfText.Dimension -> Try({}, KernelPdfText.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelPdfText.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_i64_add : I64, I64 -> Try(I64, KernelPdfText.Error)
checked_i64_add = |left, right| match I64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_i64_sub : I64, I64 -> Try(I64, KernelPdfText.Error)
checked_i64_sub = |left, right| match I64.minus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_i64_times : I64, I64 -> Try(I64, KernelPdfText.Error)
checked_i64_times = |left, right| match I64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated PDF text index escaped"
	}
	Ok(value) => value
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated PDF text update escaped"
	}
	Ok(updated) => updated
}

initial_capacity : U64
initial_capacity = 1024

content : ScenePlan -> KernelContent.TextPlan
content = |plan| plan.content

# Adjustment rounding is floor(n / d + 1/2) for both signs.
expect round_half_up(5, 10) == Ok(1) and
	round_half_up(-5, 10) == Ok(0) and
		round_half_up(-6, 10) == Ok(-1) and
			round_half_up(14, 10) == Ok(1) and
				round_half_up(-15, 10) == Ok(-1) and
					round_half_up(0, 7) == Ok(0)

# One-digit adjustments print as canonical decimals.
expect append_adjustment([], -3, 16) == Ok(Str.to_utf8("-0.3")) and
	append_adjustment([], 25, 16) == Ok(Str.to_utf8("2.5")) and
		append_adjustment([], 40, 16) == Ok(Str.to_utf8("4"))
