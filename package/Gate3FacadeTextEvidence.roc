import Color
import Font
import KernelEmit
import KernelFacadePages
import KernelFacadeShape
import KernelFacadeText
import KernelLineLayout
import KernelPageLayout
import KernelStructure
import Layout
import Semantics
import Text

Gate3FacadeTextEvidence :: [].{
	materialize : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	materialize = |repetitions| evidence_materialize(repetitions)

	prepare : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	prepare = |repetitions| evidence_prepare(repetitions)
}

PreparedInput := { prepared : KernelFacadeText.Prepared, source_runs : U64 }

evidence_materialize : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_materialize = |repetitions| {
	if repetitions == 0 or repetitions > 100000 {
		return Err(InvalidRepetitions)
	}
	input = synthetic_input(repetitions)
	prepared = input.prepared
	materialized = KernelFacadeText.Plan.build_prepared(
		prepared,
		KernelFacadeText.Limits.make({
			max_clusters: prepared.shape.clusters.len(),
			max_glyph_indices: prepared.shape.glyph_indices.len(),
			max_glyphs: prepared.shape.glyphs.len(),
			max_pages: prepared.pages.len(),
			max_placements: prepared.rows.len(),
			max_runs: prepared.rows.len(),
		}),
	) ? |_| EvidenceFailure
	text = KernelFacadeText.Plan.text(materialized)
	work = KernelFacadeText.Plan.work(materialized)
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			repetitions,
			input.source_runs,
			prepared.lines.len(),
			prepared.rows.len(),
			work.page_visits,
			work.placement_visits,
			work.run_writes,
			work.cluster_visits,
			work.glyph_index_visits,
			work.glyph_writes,
			text.runs.len(),
			text.clusters.len(),
			text.glyph_indices.len(),
			text.glyphs.len(),
			bytes.len(),
		],
	})
}

evidence_prepare : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_prepare = |repetitions| {
	if repetitions == 0 or repetitions > 100000 {
		return Err(InvalidRepetitions)
	}
	input = synthetic_input(repetitions)
	prepared = input.prepared
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			repetitions,
			input.source_runs,
			prepared.lines.len(),
			prepared.rows.len(),
			prepared.pages.len(),
			prepared.page_placements.len(),
			prepared.shape.runs.len(),
			prepared.shape.clusters.len(),
			prepared.shape.glyph_indices.len(),
			prepared.shape.glyphs.len(),
			bytes.len(),
		],
	})
}

synthetic_input : U64 -> PreparedInput
synthetic_input = |source_runs| {
	clusters_per_run = 6
	lines_per_run = 2
	clusters_per_line = 3
	line_count = source_runs * lines_per_run
	glyph_count = source_runs * clusters_per_run
	var $clusters = List.with_capacity(glyph_count)
	var $glyph_indices = List.with_capacity(glyph_count)
	var $glyphs = List.with_capacity(glyph_count)
	var $lines = List.with_capacity(line_count)
	var $placements = List.with_capacity(line_count)
	var $rows = List.with_capacity(line_count)
	var $runs = List.with_capacity(source_runs)
	var $styles = List.with_capacity(source_runs)
	var $run_index = 0
	while $run_index < source_runs {
		cluster_start = $clusters.len()
		glyph_start = $glyphs.len()
		var $local = 0
		while $local < clusters_per_run {
			global = glyph_start + $local
			$clusters = $clusters.append({
				glyphs: Semantics.Range.from_start_and_length(global, 1),
				kind: OneToOne,
				source: {
					scalars: Semantics.Range.from_start_and_length($local, 1),
					utf8_bytes: Semantics.Range.from_start_and_length($local, 1),
				},
			})
			$glyph_indices = $glyph_indices.append(global)
			$glyphs = $glyphs.append({
				advance_x: Layout.Unit.from_raw(1000),
				advance_y: Layout.Unit.from_raw(0),
				id: Text.GlyphId.from_raw(($local + 1).to_u32_wrap()),
				offset_x: Layout.Unit.from_raw(0),
				offset_y: Layout.Unit.from_raw(0),
			})
			$local = $local + 1
		}
		run_id = Text.RunId.from_index($run_index)
		$runs = $runs.append({
			actual_text: FromOccurrence,
			clusters: Semantics.Range.from_start_and_length(cluster_start, clusters_per_run),
			direction: LeftToRight,
			glyphs: Semantics.Range.from_start_and_length(glyph_start, clusters_per_run),
			id: run_id,
			instance: Font.InstanceId.from_index(0),
			language: Language("en"),
			occurrence: Semantics.OccurrenceId.from_index($run_index),
			script: Font.Script.from_iso15924("Latn"),
			size: Layout.Unit.from_raw(1000),
			source: {
				scalars: Semantics.Range.from_start_and_length(0, clusters_per_run),
				utf8_bytes: Semantics.Range.from_start_and_length(0, clusters_per_run),
			},
			substitutions: Semantics.Range.from_start_and_length(0, 0),
			transformations: Semantics.Range.from_start_and_length(0, 0),
			writing_mode: Horizontal,
		})
		$styles = $styles.append({ color: Srgb(Rgb({ blue: 0, green: 0, red: 0 })), leading: Layout.Unit.from_raw(1200) })
		var $line_local = 0
		while $line_local < lines_per_run {
			line_index = $lines.len()
			local_start = $line_local * clusters_per_line
			$lines = $lines.append({
				advance: Layout.Unit.from_raw(3000),
				clusters: Semantics.Range.from_start_and_length(cluster_start + local_start, clusters_per_line),
				source: {
					scalars: Semantics.Range.from_start_and_length(local_start, clusters_per_line),
					utf8_bytes: Semantics.Range.from_start_and_length(local_start, clusters_per_line),
				},
			})
			$placements = $placements.append({
				baseline: { x: Layout.Unit.from_raw(72000), y: Layout.Unit.from_raw(700000) },
				fragment: Semantics.FragmentId.from_index(line_index / 64),
				line: line_index,
			})
			$rows = $rows.append({
				body_line: line_index,
				body_offset: Layout.Unit.from_raw(0),
				body_runs: { physical: Semantics.Range.from_start_and_length($run_index, 1) },
				label: NoLabel,
			})
			$line_local = $line_local + 1
		}
		$run_index = $run_index + 1
	}
	var $pages = []
	var $placement_start = 0
	while $placement_start < line_count {
		page_index = $pages.len()
		length = U64.min(64, line_count - $placement_start)
		$pages = $pages.append({
			fragments: Semantics.Range.from_start_and_length(page_index, 1),
			id: Semantics.PageId.from_index(page_index),
			placements: Semantics.Range.from_start_and_length($placement_start, length),
		})
		$placement_start = $placement_start + length
	}
	{
		prepared: {
			fragment_count: $pages.len(),
			label_rows: 0,
			lines: $lines,
			page_placements: $placements,
			pages: $pages,
			rows: $rows,
			shape: {
				clusters: $clusters,
				glyph_indices: $glyph_indices,
				glyphs: $glyphs,
				runs: $runs,
				substitutions: [],
				transformations: [],
			},
			styles: $styles,
		},
		source_runs,
	}
}
