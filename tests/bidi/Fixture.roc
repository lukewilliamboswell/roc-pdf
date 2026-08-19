import pdf.KernelBidiBoundary
import pdf.KernelEmit
import pdf.KernelStructure
import pdf.KernelUnicode
import pdf.Semantics
import pdf.Text

## Pinned UAX #9 revision-51 regression seam.
##
## Every expectation below is transcribed from the normative Unicode 17.0.0
## `BidiCharacterTest.txt` conformance file: its resolved paragraph level,
## its per-scalar resolved levels (`x` becomes `RemovedByX9`), and its
## display order of logical indices. Nothing here is derived from this
## project's own output. The multi-line rows are the only computed rows, and
## they apply UAX #9 L1/L2 to the same normative levels over a sub-line
## range, because the conformance file pins whole-paragraph lines only.
##
## This is a seam over the pipeline's exact handoff, not a re-hosting of the
## upstream corpus: `roc-lang/unicode` owns full conformance and its Unicode
## version upgrades.
Fixture :: [].{
	uax9_vectors : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	uax9_vectors = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}

		## Isolate initiator and PDI stay in the display sequence; the RLE
		## between them is removed by X9 and is therefore never painted.
		isolate_embedding = verify_vector(isolate_embedding_source, LeftToRight, 0, [1, 1, -1, 1, 1], [4, 3, 1, 0], 1)?

		## A right-to-left paragraph whose isolate raises an inner run to
		## resolved level 4, with the LRE removed by X9.
		nested_isolate = verify_vector(nested_isolate_source, RightToLeft, 1, [1, 1, -1, 4], [3, 1, 0], 1)?

		## Arabic letter with European numbers separated by a common
		## separator: number handling never reorders inside the numeric run.
		numbers = verify_vector(number_source, LeftToRight, 0, [1, 2, 2, 2], [1, 2, 3, 0], 0)?

		## The UAX #9 bracket-pair example, in both paragraph directions. The
		## right-to-left resolution keeps each Latin pair in logical order
		## inside the reversed context and mirrors all four brackets.
		brackets_rtl = verify_vector(bracket_source, RightToLeft, 1, [1, 1, 1, 1, 1, 1, 1, 2, 2, 1, 1, 1, 2, 2], [12, 13, 11, 10, 9, 7, 8, 6, 5, 4, 3, 2, 1, 0], 0)?
		brackets_ltr = verify_vector(bracket_source, LeftToRight, 0, [1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0], [1, 0, 2, 4, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13], 0)?

		## L1/L2 are defined at real line boundaries, so one analyzed
		## paragraph reorders each selected line independently. The two
		## expectations apply L2 to the same normative levels over each
		## sub-range; their concatenation is the whole-line order above,
		## which no single-line resolution could produce by itself.
		multi_line = verify_lines(bracket_source, RightToLeft, 7, [6, 5, 4, 3, 2, 1, 0], [12, 13, 11, 10, 9, 7, 8])?

		## The mirrored presentation is a resolved fact, not a font feature:
		## every bracket of the right-to-left resolution requests its
		## mirrored partner scalar.
		mirrors = bracket_mirror_facts({})?

		rejections = rejection_facts({})?
		blank = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(blank) ? |_| EvidenceFailure
		Ok({
			bytes,
			work: [
				7,
				isolate_embedding.scalar_visits + nested_isolate.scalar_visits + numbers.scalar_visits + brackets_rtl.scalar_visits + brackets_ltr.scalar_visits + multi_line.scalar_visits,
				isolate_embedding.cluster_visits + nested_isolate.cluster_visits + numbers.cluster_visits + brackets_rtl.cluster_visits + brackets_ltr.cluster_visits + multi_line.cluster_visits,
				isolate_embedding.visual_writes + nested_isolate.visual_writes + numbers.visual_writes + brackets_rtl.visual_writes + brackets_ltr.visual_writes + multi_line.visual_writes,
				isolate_embedding.removed_clusters + nested_isolate.removed_clusters + numbers.removed_clusters + brackets_rtl.removed_clusters + brackets_ltr.removed_clusters + multi_line.removed_clusters,
				isolate_embedding.visual_runs + nested_isolate.visual_runs + numbers.visual_runs + brackets_rtl.visual_runs + brackets_ltr.visual_runs + multi_line.visual_runs,
				mirrors,
				rejections,
				bytes.len(),
			],
		})
	}
}

VectorWork := {
	cluster_visits : U64,
	removed_clusters : U64,
	scalar_visits : U64,
	visual_runs : U64,
	visual_writes : U64,
}

## The normative rows this seam pins. Each is the exact scalar sequence of a
## `BidiCharacterTest.txt` row.
isolate_embedding_source : Str
isolate_embedding_source = "א\u(2066)\u(202B)\u(2069)ב"

nested_isolate_source : Str
nested_isolate_source = "א\u(2067)\u(202A)A"

number_source : Str
number_source = "ت1/2"

bracket_source : Str
bracket_source = "אב(גד[&ef].)gh"

verify_vector : Str, KernelBidiBoundary.BaseDirection, U8, List(I64), List(U64), U64 -> Try(VectorWork, [EvidenceFailure, InvalidRuntimeGuard])
verify_vector = |source, base, expected_level, expected_levels, expected_visual, expected_removed| {
	analysis = unicode_analysis(source)?
	paragraph = KernelBidiBoundary.analyze_paragraph(source, analysis, base, vector_limits) ? |_| EvidenceFailure
	if paragraph.base_level != expected_level or !levels_match(paragraph.entries, expected_levels) {
		return Err(EvidenceFailure)
	}
	clusters = clusters_from_analysis(analysis)

	## The seam compares scalar-indexed normative expectations, so each
	## vector must segment one grapheme per scalar; anything else would make
	## the comparison meaningless rather than merely different.
	if clusters.len() != analysis.work.scalar_visits {
		return Err(EvidenceFailure)
	}
	order = KernelBidiBoundary.resolve_line(paragraph, whole_line(analysis, source), clusters, vector_limits) ? |_| EvidenceFailure
	if order.visual_clusters != expected_visual or order.removed_clusters != expected_removed or order.paragraph_level != expected_level {
		return Err(EvidenceFailure)
	}
	Ok(
		VectorWork.(
			{
				cluster_visits: order.work.cluster_visits,
				removed_clusters: order.removed_clusters,
				scalar_visits: paragraph.work.scalar_visits + order.work.scalar_visits,
				visual_runs: order.visual_runs.len(),
				visual_writes: order.work.visual_writes,
			},
		),
	)
}

## One analyzed paragraph, two independently reordered lines.
verify_lines : Str, KernelBidiBoundary.BaseDirection, U64, List(U64), List(U64) -> Try(VectorWork, [EvidenceFailure, InvalidRuntimeGuard])
verify_lines = |source, base, split, expected_first, expected_second| {
	analysis = unicode_analysis(source)?
	paragraph = KernelBidiBoundary.analyze_paragraph(source, analysis, base, vector_limits) ? |_| EvidenceFailure
	clusters = clusters_from_analysis(analysis)
	if clusters.len() != analysis.work.scalar_visits or split >= clusters.len() {
		return Err(EvidenceFailure)
	}
	first = KernelBidiBoundary.resolve_line(paragraph, line_selection(clusters, 0, split), clusters, vector_limits) ? |_| EvidenceFailure
	second = KernelBidiBoundary.resolve_line(paragraph, line_selection(clusters, split, clusters.len()), clusters, vector_limits) ? |_| EvidenceFailure
	if first.visual_clusters != expected_first or second.visual_clusters != expected_second {
		return Err(EvidenceFailure)
	}
	Ok(
		VectorWork.(
			{
				cluster_visits: first.work.cluster_visits + second.work.cluster_visits,
				removed_clusters: first.removed_clusters + second.removed_clusters,
				scalar_visits: paragraph.work.scalar_visits + first.work.scalar_visits + second.work.scalar_visits,
				visual_runs: first.visual_runs.len() + second.visual_runs.len(),
				visual_writes: first.work.visual_writes + second.work.visual_writes,
			},
		),
	)
}

## Every bracket of the right-to-left bracket-pair resolution requests the
## mirrored partner recorded by the dependency's mirroring data.
bracket_mirror_facts : {} -> Try(U64, [EvidenceFailure, InvalidRuntimeGuard])
bracket_mirror_facts = |_| {
	analysis = unicode_analysis(bracket_source)?
	paragraph = KernelBidiBoundary.analyze_paragraph(bracket_source, analysis, RightToLeft, vector_limits) ? |_| EvidenceFailure
	clusters = clusters_from_analysis(analysis)
	order = KernelBidiBoundary.resolve_line(paragraph, whole_line(analysis, bracket_source), clusters, vector_limits) ? |_| EvidenceFailure
	var $mirrored = 0
	var $visual_index = 0
	while $visual_index < order.visual_clusters.len() {
		logical = list_at(order.visual_clusters, $visual_index)
		mirror = list_at(order.mirrors, $visual_index)
		expected_glyph = expected_mirror(logical)
		match (mirror.needs_glyph, mirror.glyph, expected_glyph) {
			(Bool.True, Some(actual), Some(wanted)) => {
				if actual != wanted {
					return Err(EvidenceFailure)
				}
				$mirrored = $mirrored + 1
			}
			(Bool.False, None, None) => {}
			_ => return Err(EvidenceFailure)
		}
		$visual_index = $visual_index + 1
	}
	if $mirrored != 4 {
		return Err(EvidenceFailure)
	}
	Ok($mirrored)
}

## Logical indices 2, 5, 9 and 11 are the four brackets; at odd resolved
## level each paints the glyph of its mirrored partner.
expected_mirror : U64 -> [Some(U32), None]
expected_mirror = |logical| {
	if logical == 2 {
		Some(0x0029)
	} else if logical == 5 {
		Some(0x005D)
	} else if logical == 9 {
		Some(0x005B)
	} else if logical == 11 {
		Some(0x0028)
	} else {
		None
	}
}

## Atomic rejections: a mutated paragraph fact, a line range outside the
## paragraph, and a crossed scalar bound. None yields a usable order.
rejection_facts : {} -> Try(U64, [EvidenceFailure, InvalidRuntimeGuard])
rejection_facts = |_| {
	analysis = unicode_analysis(bracket_source)?
	paragraph = KernelBidiBoundary.analyze_paragraph(bracket_source, analysis, RightToLeft, vector_limits) ? |_| EvidenceFailure
	clusters = clusters_from_analysis(analysis)
	mutated = { ..paragraph, base_level: 0 }
	fact_rejected = match KernelBidiBoundary.validate_paragraph(bracket_source, analysis, RightToLeft, mutated, vector_limits) {
		Err(ParagraphFactsMismatch) => Bool.True
		_ => Bool.False
	}
	oversized = {
		clusters: Semantics.Range.from_start_and_length(0, clusters.len()),
		source: {
			scalars: Semantics.Range.from_start_and_length(0, analysis.work.scalar_visits + 1),
			utf8_bytes: Semantics.Range.from_start_and_length(0, bracket_source.count_utf8_bytes()),
		},
	}
	range_rejected = match KernelBidiBoundary.resolve_line(paragraph, oversized, clusters, vector_limits) {
		Err(InvalidLineRange) => Bool.True
		_ => Bool.False
	}
	bounded = KernelBidiBoundary.Limits.make({ max_clusters: 2, max_scalars: 1000, max_visual_order: 1000 })
	limit_rejected = match KernelBidiBoundary.resolve_line(paragraph, whole_line(analysis, bracket_source), clusters, bounded) {
		Err(LimitExceeded({ attempted: 14, dimension: Clusters, limit: 2 })) => Bool.True
		_ => Bool.False
	}
	if !fact_rejected or !range_rejected or !limit_rejected {
		Err(EvidenceFailure)
	} else {
		Ok(3)
	}
}

vector_limits : KernelBidiBoundary.Limits
vector_limits = KernelBidiBoundary.Limits.make({ max_clusters: 64, max_scalars: 64, max_visual_order: 64 })

unicode_analysis : Str -> Try(KernelUnicode.UnicodeAnalysis, [EvidenceFailure, InvalidRuntimeGuard])
unicode_analysis = |source| {
	match KernelUnicode.analyze(source, { max_graphemes: 64, max_line_boundaries: 65, max_scalars: 64, max_script_runs: 64 }) {
		Err(_) => Err(EvidenceFailure)
		Ok(analysis) => Ok(analysis)
	}
}

whole_line : KernelUnicode.UnicodeAnalysis, Str -> KernelBidiBoundary.LineSelection
whole_line = |analysis, source| {
	{
		clusters: Semantics.Range.from_start_and_length(0, analysis.graphemes.len()),
		source: {
			scalars: Semantics.Range.from_start_and_length(0, analysis.work.scalar_visits),
			utf8_bytes: Semantics.Range.from_start_and_length(0, source.count_utf8_bytes()),
		},
	}
}

line_selection : List(Text.Cluster), U64, U64 -> KernelBidiBoundary.LineSelection
line_selection = |clusters, start, end| {
	first = list_at(clusters, start)
	last = list_at(clusters, end - 1)
	scalar_end = last.source.scalars.start() + last.source.scalars.length()
	byte_end = last.source.utf8_bytes.start() + last.source.utf8_bytes.length()
	{
		clusters: Semantics.Range.from_start_and_length(start, end - start),
		source: {
			scalars: Semantics.Range.from_start_and_length(first.source.scalars.start(), scalar_end - first.source.scalars.start()),
			utf8_bytes: Semantics.Range.from_start_and_length(first.source.utf8_bytes.start(), byte_end - first.source.utf8_bytes.start()),
		},
	}
}

clusters_from_analysis : KernelUnicode.UnicodeAnalysis -> List(Text.Cluster)
clusters_from_analysis = |analysis| {
	var $items = List.with_capacity(analysis.graphemes.len())
	var $index = 0
	while $index < analysis.graphemes.len() {
		grapheme = list_at(analysis.graphemes, $index)
		$items = $items.append({
			glyphs: Semantics.Range.from_start_and_length($index, 1),
			kind: Reordered,
			source: {
				scalars: Semantics.Range.from_start_and_length(grapheme.scalar_start, grapheme.scalar_end - grapheme.scalar_start),
				utf8_bytes: Semantics.Range.from_start_and_length(grapheme.byte_start, grapheme.byte_end - grapheme.byte_start),
			},
		})
		$index = $index + 1
	}
	$items
}

## `-1` is the conformance file's `x`: a scalar removed by X9.
levels_match : List(KernelBidiBoundary.ScalarFact), List(I64) -> Bool
levels_match = |facts, expected| {
	if facts.len() != expected.len() {
		return Bool.False
	}
	var $index = 0
	while $index < facts.len() {
		wanted = list_at(expected, $index)
		agrees = match list_at(facts, $index).level {
			Level(value) => wanted >= 0 and value.to_i64() == wanted
			RemovedByX9 => wanted < 0
		}
		if !agrees {
			return Bool.False
		}
		$index = $index + 1
	}
	Bool.True
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "text-layout bidi evidence index escaped"
}
