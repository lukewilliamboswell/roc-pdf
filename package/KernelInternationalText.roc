import KernelBidiBoundary
import KernelUnicode
import Semantics
import unicode.ByteRange
import unicode.Scalar

## Paragraph facts are prepared once before any font or line is selected.
## Direction comes from UAX #9 revision 52. Language and logical ownership
## come from the author's occurrences. UAX #24 script facts come from
## KernelUnicode's explicitly itemized runs.
KernelInternationalText :: [].{
	Repertoire : [UnpointedHebrewLatin]

	Limits : { max_clusters : U64, max_items : U64, max_scalars : U64 }

	Error : [
		Bidi(KernelBidiBoundary.Error),
		FactMismatch({ scalar_index : U64 }),
		ItemLimit({ attempted : U64, limit : U64 }),
		UnsupportedCluster({ scalar_index : U64 }),
		UnsupportedControl({ scalar : U32, scalar_index : U64 }),
		UnsupportedScalar({ scalar : U32, scalar_index : U64 }),
		UnsupportedScript({ script : Str, scalar_index : U64 }),
	]

	ScalarAt : { offset : U64, scalar : U32 }

	Occurrence : { id : Semantics.OccurrenceId, language : Semantics.Language, source : Semantics.TextRange }

	Item : {
		direction : KernelBidiBoundary.Direction,
		language : Semantics.Language,
		level : U8,
		occurrence : Semantics.OccurrenceId,
		script : Str,
		source : Semantics.TextRange,
	}

	Work : { clusters : U64, items : U64, occurrences : U64, script_runs : U64 }

	Plan : { bidi : KernelBidiBoundary.Paragraph, items : List(Item), scalars : List(ScalarAt), work : Work }

	## Form maximal items within one resolved embedding level, one script
	## and one authored occurrence. Every boundary comes from the earlier
	## facts. The items partition logical source; their order is not paint
	## order. Font choice consumes these item ranges in the next stage.
	plan : Str, KernelUnicode.UnicodeAnalysis, KernelBidiBoundary.BaseDirection, List(Occurrence), Repertoire, Limits -> Try(Plan, Error)
	plan = |source, analysis, base, occurrences, repertoire, limits| {
		bidi = KernelBidiBoundary.analyze_paragraph(source, analysis, base, bidi_limits(limits)) ? Bidi
		from_paragraph(source, analysis, bidi, occurrences, repertoire, limits)
	}

	## Paragraph resolution can share the same immutable analysis across
	## occurrences of one interned source. Itemization still reads each
	## occurrence's own exact ranges and language.
	from_paragraph : Str, KernelUnicode.UnicodeAnalysis, KernelBidiBoundary.Paragraph, List(Occurrence), Repertoire, Limits -> Try(Plan, Error)
	from_paragraph = |source, analysis, bidi, occurrences, repertoire, limits| {
		cluster_count = analysis.graphemes.len()
		if analysis.work.scalar_visits != bidi.entries.len() or bidi.logical_source.utf8_bytes.length() != source.count_utf8_bytes() {
			return Err(FactMismatch({ scalar_index: 0 }))
		}
		if cluster_count != analysis.work.scalar_visits {
			index = first_multi_scalar(analysis.graphemes)
			return Err(UnsupportedCluster({ scalar_index: index }))
		}
		if cluster_count > limits.max_clusters {
			return Err(Bidi(LimitExceeded({ attempted: cluster_count, dimension: Clusters, limit: limits.max_clusters })))
		}
		if cluster_count == 0 or occurrences.is_empty() or analysis.script_runs.is_empty() {
			return Err(FactMismatch({ scalar_index: 0 }))
		}

		var $items = []
		var $scalars = List.with_capacity(cluster_count)
		var $original = list_at(occurrences, 0)
		var $original_scalar_end = end($original.source.scalars)?
		var $original_byte_end = end($original.source.utf8_bytes)?
		var $occurrence_index = 0
		var $script = list_at(analysis.script_runs, 0)
		var $script_index = 0
		if $original.source.scalars.start() != 0 or $original.source.utf8_bytes.start() != 0 or $script.range.scalar_start != 0 or $script.range.byte_start != 0 {
			return Err(FactMismatch({ scalar_index: 0 }))
		}
		var $level = 0
		var $space = False
		var $item_start = 0
		var $item_byte = 0
		var $byte = 0
		var $index = 0
		for located in Scalar.iter(source) {
			if $index >= cluster_count {
				return Err(FactMismatch({ scalar_index: $index }))
			}
			byte_start = ByteRange.start(located.byte_range)
			byte_end = ByteRange.end(located.byte_range)
			cluster = list_at(analysis.graphemes, $index)
			if located.scalar_index != $index or byte_start != $byte or cluster.scalar_start != $index or cluster.scalar_end != $index + 1 or cluster.byte_start != byte_start or cluster.byte_end != byte_end {
				return Err(FactMismatch({ scalar_index: $index }))
			}
			value = Scalar.to_u32(located.scalar)
			bidi_entry = list_at(bidi.entries, $index)
			level = match bidi_entry.level {
				RemovedByX9 => return Err(UnsupportedControl({ scalar: value, scalar_index: $index }))
				Level(actual) if !bidi_entry.non_rendering => actual
				Level(_) => return Err(UnsupportedControl({ scalar: value, scalar_index: $index }))
			}
			next_original = $index == $original_scalar_end
			next_script = $index == $script.range.scalar_end
			# A line's trailing spaces can later acquire the paragraph level
			# under L1. A separate unit lets final ordering move that space
			# without reshaping a neighboring word.
			space = value == 0x20 or value == 0xa0
			if $index > 0 and (next_original or next_script or level != $level or space != $space) {
				check_items($items.len(), limits.max_items)?
				$items = $items.append(item($original, $script.script, $level, $item_start, $index, $item_byte, byte_start))
				$item_start = $index
				$item_byte = byte_start
			}
			if next_original {
				$occurrence_index = $occurrence_index + 1
				if $occurrence_index >= occurrences.len() or $original_byte_end != byte_start {
					return Err(FactMismatch({ scalar_index: $index }))
				}
				$original = list_at(occurrences, $occurrence_index)
				$original_scalar_end = end($original.source.scalars)?
				$original_byte_end = end($original.source.utf8_bytes)?
				if $original.source.scalars.start() != $index or $original.source.utf8_bytes.start() != byte_start {
					return Err(FactMismatch({ scalar_index: $index }))
				}
			}
			if next_script {
				$script_index = $script_index + 1
				if $script_index >= analysis.script_runs.len() or $script.range.byte_end != byte_start {
					return Err(FactMismatch({ scalar_index: $index }))
				}
				$script = list_at(analysis.script_runs, $script_index)
				if $script.range.scalar_start != $index or $script.range.byte_start != byte_start {
					return Err(FactMismatch({ scalar_index: $index }))
				}
			}
			if !supported_script(repertoire, $script.script) {
				return Err(UnsupportedScript({ script: $script.script, scalar_index: $index }))
			}
			if !supported_scalar(repertoire, value) {
				return Err(UnsupportedScalar({ scalar: value, scalar_index: $index }))
			}
			if $index < $original.source.scalars.start() or $index >= $original_scalar_end or byte_end > $original_byte_end or $index < $script.range.scalar_start or $index >= $script.range.scalar_end or byte_end > $script.range.byte_end {
				return Err(FactMismatch({ scalar_index: $index }))
			}
			$scalars = $scalars.append({ offset: byte_start, scalar: value })
			$level = level
			$space = space
			$byte = byte_end
			$index = $index + 1
		}
		if $index != cluster_count or $original.source.scalars.start() > $item_start or $original_scalar_end != $index or $original_byte_end != $byte or $occurrence_index + 1 != occurrences.len() or $script_index + 1 != analysis.script_runs.len() or $script.range.scalar_end != $index or $script.range.byte_end != $byte {
			return Err(FactMismatch({ scalar_index: $index }))
		}
		check_items($items.len(), limits.max_items)?
		$items = $items.append(item($original, $script.script, $level, $item_start, $index, $item_byte, $byte))
		Ok({ bidi, items: $items, scalars: $scalars, work: { clusters: cluster_count, items: $items.len(), occurrences: occurrences.len(), script_runs: analysis.script_runs.len() } })
	}
}

bidi_limits : KernelInternationalText.Limits -> KernelBidiBoundary.Limits
bidi_limits = |limits| KernelBidiBoundary.Limits.make({ max_clusters: limits.max_clusters, max_scalars: limits.max_scalars, max_visual_order: limits.max_clusters })

first_multi_scalar : List(KernelUnicode.UnicodeRange) -> U64
first_multi_scalar = |clusters| {
	for cluster in clusters {
		if cluster.scalar_end != cluster.scalar_start + 1 {
			return cluster.scalar_start
		}
	}
	0
}

check_items : U64, U64 -> Try({}, KernelInternationalText.Error)
check_items = |count, limit| if (count >= limit) Err(ItemLimit({ attempted: count + 1, limit })) else Ok({})

supported_script : KernelInternationalText.Repertoire, Str -> Bool
supported_script = |UnpointedHebrewLatin, script| script == "Hebr" or script == "Latn" or script == "Zyyy"

supported_scalar : KernelInternationalText.Repertoire, U32 -> Bool
supported_scalar = |UnpointedHebrewLatin, value| {
	(value >= 0x20 and value <= 0x7e) or (value >= 0xa0 and value <= 0xff) or (value >= 0x5d0 and value <= 0x5ea) or value == 0x5f3 or value == 0x5f4
}

item : KernelInternationalText.Occurrence, Str, U8, U64, U64, U64, U64 -> KernelInternationalText.Item
item = |owner, script, level, start, stop, byte_start, byte_end| {
	direction: if (level % 2 == 0) LeftToRight else RightToLeft,
	language: owner.language,
	level,
	occurrence: owner.id,
	script,
	source: {
		scalars: Semantics.IndexRange.from_start_and_length({ start, length: stop - start }),
		utf8_bytes: Semantics.IndexRange.from_start_and_length({ start: byte_start, length: byte_end - byte_start }),
	},
}

end : Semantics.IndexRange -> Try(U64, KernelInternationalText.Error)
end = |range| match U64.plus_try(range.start(), range.length()) {
	Ok(stop) => Ok(stop)
	Err(Overflow) => Err(FactMismatch({ scalar_index: range.start() }))
}

list_at : List(a), U64 -> a
list_at = |values, index| match values.get(index) {
	Ok(value) => value
	Err(_) => crash "international itemization escaped its validated source"
}

test_limits : KernelInternationalText.Limits
test_limits = { max_clusters: 32, max_items: 16, max_scalars: 32 }

owned : U64, Str, U64, U64, U64, U64 -> KernelInternationalText.Occurrence
owned = |id, language, scalar_start, scalar_length, byte_start, byte_length| {
	id: Semantics.OccurrenceId.from_index(id),
	language: Language(language),
	source: {
		scalars: Semantics.IndexRange.from_start_and_length({ start: scalar_start, length: scalar_length }),
		utf8_bytes: Semantics.IndexRange.from_start_and_length({ start: byte_start, length: byte_length }),
	},
}

## UAX #9 P2, N1 and I2 resolve an RTL paragraph with two LTR
## occurrence ranges. Their language is authored independently of level.
expect {
	source = "אב AV PV"
	analysis = KernelUnicode.analyze(source, KernelUnicode.default_limits)?
	owners = [owned(0, "he", 0, 3, 0, 5), owned(1, "en", 3, 3, 5, 3), owned(2, "fr", 6, 2, 8, 2)]
	view = KernelInternationalText.plan(source, analysis, Auto, owners, UnpointedHebrewLatin, test_limits)?
	items = view.items.map(|one| (one.occurrence.index(), one.language, one.level, one.source.scalars.start(), one.source.scalars.length()))
	view.bidi.base_level == 1 and
		items == [(0, Language("he"), 1, 0, 2), (0, Language("he"), 1, 2, 1), (1, Language("en"), 2, 3, 2), (1, Language("en"), 2, 5, 1), (2, Language("fr"), 2, 6, 2)] and
			view.work.clusters == 8 and view.work.occurrences == 3 and view.work.items == 5
}

expect {
	source = "אב AV"
	analysis = KernelUnicode.analyze(source, KernelUnicode.default_limits)?
	owners = [owned(0, "he", 0, 3, 0, 5), owned(1, "en", 3, 2, 5, 2)]
	match KernelInternationalText.plan(source, analysis, Auto, owners, UnpointedHebrewLatin, { ..test_limits, max_items: 1 }) {
		Err(ItemLimit({ attempted: 2, limit: 1 })) => True
		_ => False
	}
}

expect {
	pointed = "שָ"
	analysis = KernelUnicode.analyze(pointed, KernelUnicode.default_limits)?
	match KernelInternationalText.plan(pointed, analysis, Auto, [owned(0, "he", 0, 2, 0, 4)], UnpointedHebrewLatin, test_limits) {
		Err(UnsupportedCluster({ scalar_index: 0 })) => True
		_ => False
	}
}

expect {
	source = "a\u(2067)ב\u(2069)"
	analysis = KernelUnicode.analyze(source, KernelUnicode.default_limits)?
	match KernelInternationalText.plan(source, analysis, Auto, [owned(0, "en", 0, 4, 0, 9)], UnpointedHebrewLatin, test_limits) {
		Err(UnsupportedControl({ scalar: 0x2067, scalar_index: 1 })) => True
		_ => False
	}
}
