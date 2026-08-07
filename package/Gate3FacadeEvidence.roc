import Document
import Font
import KernelEmit
import KernelLineLayout
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
