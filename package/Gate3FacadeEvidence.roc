import Document
import Font
import KernelEmit
import KernelLineLayout
import KernelPageLayout
import KernelShape
import KernelStructure
import KernelUnicode
import Layout
import Semantics
import Text

Gate3FacadeEvidence :: [].{
	normalize_builder : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	normalize_builder = |repetitions| normalize(repetitions, Builder)

	normalize_simple : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	normalize_simple = |repetitions| normalize(repetitions, Simple)

	line_layout : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	line_layout = |repetitions| evidence_line_layout(repetitions)

	page_layout : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	page_layout = |repetitions| evidence_page_layout(repetitions)
}

Authoring := [Builder, Simple]

normalize : U64, Authoring -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
normalize = |repetitions, authoring| {
	if repetitions == 0 or repetitions > 100000 {
		return Err(InvalidRepetitions)
	}
	document = match authoring {
		Builder => build_with_builder(repetitions)
		Simple => build_with_list(repetitions)
	}
	store = Document.normalize(document)
	work = inspect(store) ? |_| EvidenceFailure
	plan = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(plan) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			repetitions + 3,
			store.blocks.len(),
			work.text_bytes,
			work.titles,
			work.headings,
			work.paragraphs,
			work.bullets,
			work.lists,
			bytes.len(),
		],
	})
}

evidence_line_layout : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_line_layout = |repetitions| {
	if repetitions == 0 or repetitions > 100000 {
		return Err(InvalidRepetitions)
	}
	scalars = repetitions * 6
	input = synthetic_line_input(scalars)
	plan = KernelLineLayout.Plan.build_simple(
		input.analysis,
		input.shaped,
		Layout.Unit.from_raw(3000),
		KernelLineLayout.Limits.make({
			max_boundaries: scalars + 1,
			max_candidates: scalars * 2 - 2,
			max_clusters: scalars,
			max_glyph_indices: scalars,
			max_glyphs: scalars,
			max_lines: scalars / 2,
		}),
	) ? |_| EvidenceFailure
	work = KernelLineLayout.Plan.work(plan)
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			repetitions,
			scalars,
			work.boundary_visits,
			work.cluster_visits,
			work.glyph_index_visits,
			work.glyph_visits,
			work.candidate_visits,
			work.line_writes,
			bytes.len(),
		],
	})
}

synthetic_line_input : U64 -> { analysis : KernelUnicode.UnicodeAnalysis, shaped : KernelShape.Shape }
synthetic_line_input = |scalars| {
	var $boundaries = List.with_capacity(scalars + 1)
	var $clusters = List.with_capacity(scalars)
	var $graphemes = List.with_capacity(scalars)
	var $glyph_indices = List.with_capacity(scalars)
	var $glyphs = List.with_capacity(scalars)
	var $index = 0
	while $index < scalars {
		decision = if $index > 0 and $index % 2 == 0 Allowed else Prohibited
		$boundaries = $boundaries.append({ authority: Tailorable, byte_offset: $index, decision, scalar_offset: $index })
		$clusters = $clusters.append({
			glyphs: Semantics.Range.from_start_and_length($index, 1),
			kind: OneToOne,
			source: {
				scalars: Semantics.Range.from_start_and_length($index, 1),
				utf8_bytes: Semantics.Range.from_start_and_length($index, 1),
			},
		})
		$graphemes = $graphemes.append({ byte_start: $index, byte_end: $index + 1, scalar_start: $index, scalar_end: $index + 1 })
		$glyph_indices = $glyph_indices.append($index)
		$glyphs = $glyphs.append({
			advance_x: Layout.Unit.from_raw(1000),
			advance_y: Layout.Unit.from_raw(0),
			id: Text.GlyphId.from_raw(1),
			offset_x: Layout.Unit.from_raw(0),
			offset_y: Layout.Unit.from_raw(0),
		})
		$index = $index + 1
	}
	$boundaries = $boundaries.append({ authority: NonTailorable, byte_offset: scalars, decision: Mandatory, scalar_offset: scalars })
	{
		analysis: {
			graphemes: $graphemes,
			line_boundaries: $boundaries,
			script_runs: [{ range: { byte_start: 0, byte_end: scalars, scalar_start: 0, scalar_end: scalars }, script: "Latn" }],
			work: { grapheme_visits: scalars, line_boundary_visits: scalars + 1, scalar_visits: scalars, script_run_visits: 1 },
		},
		shaped: {
			advance: Layout.Unit.from_raw((scalars * 1000).to_i64_wrap()),
			store: {
				clusters: $clusters,
				glyph_indices: $glyph_indices,
				glyphs: $glyphs,
				runs: [
					{
						actual_text: FromOccurrence,
						clusters: Semantics.Range.from_start_and_length(0, scalars),
						direction: LeftToRight,
						glyphs: Semantics.Range.from_start_and_length(0, scalars),
						id: Text.RunId.from_index(0),
						instance: Font.InstanceId.from_index(0),
						language: Language("en"),
						occurrence: Semantics.OccurrenceId.from_index(0),
						script: Font.Script.from_iso15924("Latn"),
						size: Layout.Unit.from_raw(1000),
						source: {
							scalars: Semantics.Range.from_start_and_length(0, scalars),
							utf8_bytes: Semantics.Range.from_start_and_length(0, scalars),
						},
						substitutions: Semantics.Range.from_start_and_length(0, 0),
						transformations: Semantics.Range.from_start_and_length(0, 0),
						writing_mode: Horizontal,
					},
				],
				substitutions: [],
				transformations: [],
			},
			work: {
				cluster_visits: scalars,
				glyph_visits: scalars,
				metric_reads: scalars,
				scalar_visits: scalars,
				script_run_visits: 0,
				utf8_bytes: scalars,
			},
		},
	}
}

evidence_page_layout : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_page_layout = |repetitions| {
	if repetitions == 0 or repetitions > 100000 {
		return Err(InvalidRepetitions)
	}
	input = synthetic_page_input(repetitions)
	line_count = repetitions * 6
	plan = KernelPageLayout.Plan.build(
		input.blocks,
		input.lines,
		{
			margins: {
				bottom: Layout.Unit.from_raw(1000),
				left: Layout.Unit.from_raw(1000),
				right: Layout.Unit.from_raw(1000),
				top: Layout.Unit.from_raw(1000),
			},
			page: { height: Layout.Unit.from_raw(12000), width: Layout.Unit.from_raw(10000) },
		},
		KernelPageLayout.Limits.make({
			max_blocks: repetitions,
			max_fragments: line_count,
			max_lines: line_count,
			max_pages: line_count,
			max_placements: line_count,
		}),
	) ? |_| EvidenceFailure
	work = KernelPageLayout.Plan.work(plan)
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			repetitions,
			line_count,
			work.block_visits,
			work.line_visits,
			work.keep_policy_visits,
			work.fragment_writes,
			work.page_writes,
			work.placement_writes,
			bytes.len(),
		],
	})
}

synthetic_page_input : U64 -> { blocks : List(KernelPageLayout.Block), lines : List(KernelLineLayout.Line) }
synthetic_page_input = |block_count| {
	line_count = block_count * 6
	var $blocks = List.with_capacity(block_count)
	var $lines = List.with_capacity(line_count)
	var $block_index = 0
	while $block_index < block_count {
		line_start = $lines.len()
		var $local = 0
		while $local < 6 {
			$lines = $lines.append({
				advance: Layout.Unit.from_raw(3000),
				clusters: Semantics.Range.from_start_and_length(line_start + $local, 1),
				source: {
					scalars: Semantics.Range.from_start_and_length($local, 1),
					utf8_bytes: Semantics.Range.from_start_and_length($local, 1),
				},
			})
			$local = $local + 1
		}
		kept = $block_index % 5 == 0
		$blocks = $blocks.append({
			baseline_offset: Layout.Unit.from_raw(800),
			leading: Layout.Unit.from_raw(1000),
			lines: Semantics.Range.from_start_and_length(line_start, 6),
			occurrence: Semantics.OccurrenceId.from_index($block_index),
			policy: {
				break_before: $block_index > 0 and $block_index % 10 == 0,
				keep_together: kept,
				keep_with_next: $block_index % 10 == 5 and $block_index + 1 < block_count,
				minimum_first_lines: 2,
				minimum_last_lines: 2,
			},
			space_after: Layout.Unit.from_raw(0),
		})
		$block_index = $block_index + 1
	}
	{ blocks: $blocks, lines: $lines }
}

build_with_list : U64 -> Document
build_with_list = |repetitions| {
	var $blocks = [Document.title("Report"), Document.heading(1, "Summary")]
	var $index = 0
	while $index < repetitions {
		$blocks = $blocks.append(Document.paragraph("Body"))
		$index = $index + 1
	}
	$blocks = $blocks.append(Document.bullets(["One", "Two"]))
	Document.from_blocks({ contents: $blocks, language: "en-AU", title: "Report" })
}

build_with_builder : U64 -> Document
build_with_builder = |repetitions| {
	var $builder = Document.builder({ language: "en-AU", title: "Report" })
		.add_title("Report")
		.add_heading(1, "Summary")
	$builder = $builder.add_paragraphs(List.repeat("Body", repetitions))
	$builder.add_bullets(["One", "Two"]).finish()
}

NormalizationWork := {
	bullets : U64,
	headings : U64,
	lists : U64,
	paragraphs : U64,
	text_bytes : U64,
	titles : U64,
}

inspect : Document.NormalizedAuthoring -> Try(NormalizationWork, [InvalidStore])
inspect = |store| {
	var $bullets = 0
	var $headings = 0
	var $lists = 0
	var $paragraphs = 0
	var $text_bytes = 0
	var $titles = 0
	var $next_list = 0
	var $expected_item = 0
	var $index = 0
	while $index < store.blocks.len() {
		block = list_at(store.blocks, $index)
		$text_bytes = $text_bytes + block.text.count_utf8_bytes()
		match block.kind {
			Bullet({ item, list }) => {
				if item == 0 {
					if list != $next_list {
						return Err(InvalidStore)
					}
					$lists = $lists + 1
					$next_list = $next_list + 1
					$expected_item = 0
				} else if list + 1 != $next_list {
					return Err(InvalidStore)
				}
				if item != $expected_item {
					return Err(InvalidStore)
				}
				$expected_item = $expected_item + 1
				$bullets = $bullets + 1
			}
			Heading(_) => {
				$headings = $headings + 1
			}
			PageArtifact(_) => return Err(InvalidStore)
			Paragraph => {
				$paragraphs = $paragraphs + 1
			}
			Title => {
				$titles = $titles + 1
			}
		}
		$index = $index + 1
	}
	Ok({ bullets: $bullets, headings: $headings, lists: $lists, paragraphs: $paragraphs, text_bytes: $text_bytes, titles: $titles })
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "Gate 3 facade evidence index escaped"
	}
	Ok(value) => value
}

expect {
	simple = Gate3FacadeEvidence.normalize_simple(2)?
	builder = Gate3FacadeEvidence.normalize_builder(2)?
	simple.work == [5, 6, 27, 1, 1, 2, 2, 1, 667] and builder.work == simple.work and builder.bytes == simple.bytes
}

expect {
	result = Gate3FacadeEvidence.line_layout(1)?
	result.work == [1, 6, 7, 6, 6, 6, 10, 3, 667]
}

expect {
	result = Gate3FacadeEvidence.page_layout(10)?
	result.work.len() == 9
}
