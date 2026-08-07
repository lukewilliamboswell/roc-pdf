import Font
import KernelEmit
import KernelFacadeFragments
import KernelSemantics
import KernelStructure
import KernelTextSemantics
import Layout
import Semantics
import Text

Gate3FacadeFragmentEvidence :: [].{
	arena : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	arena = |repetitions| evidence_arena(repetitions)

	negative : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	negative = |repetitions| evidence_negative(repetitions)

	prepare : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	prepare = |repetitions| evidence_prepare(repetitions)

	validate : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	validate = |repetitions| evidence_validate(repetitions)
}

Input := {
	preliminary : KernelTextSemantics.Plan,
	prepared : KernelFacadeFragments.Prepared,
	repetitions : U64,
}

evidence_prepare : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_prepare = |repetitions| {
	input = synthetic_input(repetitions)?
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	store = input.prepared.text
	Ok({
		bytes,
		work: [
			input.repetitions,
			input.prepared.pages.len(),
			input.prepared.placements.len(),
			store.runs.len(),
			store.clusters.len(),
			store.glyph_indices.len(),
			store.glyphs.len(),
			bytes.len(),
		],
	})
}

evidence_arena : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_arena = |repetitions| {
	input = synthetic_input(repetitions)?
	arena = KernelFacadeFragments.Arena.build_prepared(input.preliminary, input.prepared, fragment_limits(input.prepared)) ? |_| EvidenceFailure
	work = KernelFacadeFragments.Arena.work(arena)
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			input.repetitions,
			input.prepared.pages.len(),
			input.prepared.placements.len(),
			work.page_visits,
			work.placement_visits,
			work.fragment_writes,
			work.continuation_reads,
			work.continuation_writes,
			KernelFacadeFragments.Arena.fragments(arena).len(),
			bytes.len(),
		],
	})
}

evidence_validate : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_validate = |repetitions| {
	input = synthetic_input(repetitions)?
	arena = KernelFacadeFragments.Arena.build_prepared(input.preliminary, input.prepared, fragment_limits(input.prepared)) ? |_| EvidenceFailure
	fragments = KernelFacadeFragments.Arena.fragments(arena)
	pages = input.prepared.pages.len()
	validated = KernelTextSemantics.Plan.attach_fragments(input.preliminary, fragments, pages, pages, semantic_limits(input.repetitions, fragments.len())) ? |_| EvidenceFailure
	semantic_plan = KernelTextSemantics.Plan.semantics(validated)
	semantic_store = KernelSemantics.Plan.store(semantic_plan)
	semantic_work = KernelSemantics.Plan.work(semantic_plan)
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			input.repetitions,
			fragments.len(),
			semantic_store.occurrence_fragments.len(),
			semantic_work.fragment_count_visits,
			semantic_work.fragment_validation_visits,
			semantic_work.prefix_steps,
			semantic_work.reverse_writes,
			bytes.len(),
		],
	})
}

evidence_negative : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_negative = |repetitions| {
	input = synthetic_input(repetitions)?
	prepared = input.prepared
	first_placement = list_at(prepared.placements, 0)
	bad_placements = list_set(prepared.placements, 0, { ..first_placement, page: Semantics.PageId.from_index(prepared.pages.len()) })
	bad_page_rejected = match KernelFacadeFragments.Arena.build_prepared(input.preliminary, { ..prepared, placements: bad_placements }, fragment_limits(prepared)) {
		Err(InvalidPlacement(_)) => 1
		_ => return Err(EvidenceFailure)
	}
	first_run = list_at(prepared.text.runs, 0)
	bad_runs = list_set(prepared.text.runs, 0, { ..first_run, source: { scalars: Semantics.Range.from_start_and_length(0, 7), utf8_bytes: Semantics.Range.from_start_and_length(0, 7) } })
	bad_source_rejected = match KernelFacadeFragments.Arena.build_prepared(input.preliminary, { ..prepared, text: { ..prepared.text, runs: bad_runs } }, fragment_limits(prepared)) {
		Err(SourceRangeMismatch(_)) => 1
		_ => return Err(EvidenceFailure)
	}
	limit_rejected = match KernelFacadeFragments.Arena.build_prepared(input.preliminary, prepared, KernelFacadeFragments.Limits.make({ max_fragments: prepared.text.runs.len() - 1, max_occurrences: repetitions, max_pages: prepared.pages.len() })) {
		Err(LimitExceeded(_)) => 1
		_ => return Err(EvidenceFailure)
	}
	arena = KernelFacadeFragments.Arena.build_prepared(input.preliminary, prepared, fragment_limits(prepared)) ? |_| EvidenceFailure
	pages = prepared.pages.len()
	attached = KernelTextSemantics.Plan.attach_fragments(input.preliminary, KernelFacadeFragments.Arena.fragments(arena), pages, pages, semantic_limits(repetitions, prepared.text.runs.len())) ? |_| EvidenceFailure
	preexisting_rejected = match KernelFacadeFragments.Arena.build_prepared(attached, prepared, fragment_limits(prepared)) {
		Err(InvalidPreliminaryFragments(_)) => 1
		_ => return Err(EvidenceFailure)
	}
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	Ok({ bytes, work: [bad_page_rejected, bad_source_rejected, limit_rejected, preexisting_rejected, bytes.len()] })
}

synthetic_input : U64 -> Try(Input, [EvidenceFailure, InvalidRepetitions])
synthetic_input = |repetitions| {
	if repetitions == 0 or repetitions > 100000 {
		return Err(InvalidRepetitions)
	}
	preliminary = KernelTextSemantics.Plan.build(
		semantic_store(repetitions),
		0,
		0,
		semantic_limits(repetitions, 0),
		KernelTextSemantics.Limits.make({
			max_text_properties: 0,
			max_text_property_bytes: 0,
			max_text_source_bytes: 6,
			max_text_source_scalars: 6,
			max_text_sources: 1,
		}),
	) ? |_| EvidenceFailure
	Ok({ preliminary, prepared: prepared_text(repetitions), repetitions })
}

semantic_store : U64 -> Semantics.Store
semantic_store = |occurrence_count| {
	var $content = [ChildNode(Semantics.NodeId.from_index(1))]
	var $occurrences = List.with_capacity(occurrence_count)
	var $index = 0
	while $index < occurrence_count {
		$content = $content.append(ContentOccurrence(Semantics.OccurrenceId.from_index($index)))
		$occurrences = $occurrences.append({
			fragments: empty_range,
			id: Semantics.OccurrenceId.from_index($index),
			language: Language("en"),
			source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange(full_source_range)),
			text_properties: empty_range,
		})
		$index = $index + 1
	}
	{
		annotations: [],
		assertions: [],
		attribute_roles: [],
		attributes: [],
		content_spine: $content,
		contextual_artifacts: [],
		document_root: Semantics.NodeId.from_index(0),
		element_identifiers: [],
		fragments: [],
		mathml_subtrees: [],
		namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
		nodes: [
			{
				attributes: empty_range,
				content: Semantics.Range.from_start_and_length(0, 1),
				element_identifier: NoElementIdentifier,
				id: Semantics.NodeId.from_index(0),
				language: Language("en"),
				parent: DocumentRoot,
				role: { local_name: "Document", namespace: Semantics.NamespaceId.from_index(0) },
				structure_element: Semantics.StructureElementId.from_index(0),
				text_properties: empty_range,
			},
			{
				attributes: empty_range,
				content: Semantics.Range.from_start_and_length(1, occurrence_count),
				element_identifier: NoElementIdentifier,
				id: Semantics.NodeId.from_index(1),
				language: Language("en"),
				parent: ParentNode(Semantics.NodeId.from_index(0)),
				role: { local_name: "P", namespace: Semantics.NamespaceId.from_index(0) },
				structure_element: Semantics.StructureElementId.from_index(1),
				text_properties: empty_range,
			},
		],
		non_text_sources: [],
		occurrence_fragments: [],
		occurrences: $occurrences,
		relationships: [],
		role_mappings: [],
		text_properties: [],
		text_sources: [{ unicode: "abcdef" }],
	}
}

prepared_text : U64 -> KernelFacadeFragments.Prepared
prepared_text = |occurrence_count| {
	run_count = occurrence_count * 2
	glyph_count = run_count * 3
	var $clusters = List.with_capacity(glyph_count)
	var $glyph_indices = List.with_capacity(glyph_count)
	var $glyphs = List.with_capacity(glyph_count)
	var $placements = List.with_capacity(run_count)
	var $runs = List.with_capacity(run_count)
	var $occurrence_index = 0
	while $occurrence_index < occurrence_count {
		var $line = 0
		while $line < 2 {
			run_index = $runs.len()
			glyph_start = $glyphs.len()
			source_start = $line * 3
			var $local = 0
			while $local < 3 {
				glyph_index = $glyphs.len()
				$clusters = $clusters.append({
					glyphs: Semantics.Range.from_start_and_length($glyph_indices.len(), 1),
					kind: OneToOne,
					source: {
						scalars: Semantics.Range.from_start_and_length(source_start + $local, 1),
						utf8_bytes: Semantics.Range.from_start_and_length(source_start + $local, 1),
					},
				})
				$glyph_indices = $glyph_indices.append(glyph_index)
				$glyphs = $glyphs.append({
					advance_x: Layout.Unit.from_raw(1000),
					advance_y: Layout.Unit.from_raw(0),
					id: Text.GlyphId.from_raw(($local + 1).to_u32_wrap()),
					offset_x: Layout.Unit.from_raw(0),
					offset_y: Layout.Unit.from_raw(0),
				})
				$local = $local + 1
			}
			run_id = Text.RunId.from_index(run_index)
			$runs = $runs.append({
				actual_text: FromOccurrence,
				clusters: Semantics.Range.from_start_and_length(glyph_start, 3),
				direction: LeftToRight,
				glyphs: Semantics.Range.from_start_and_length(glyph_start, 3),
				id: run_id,
				instance: Font.InstanceId.from_index(0),
				language: Language("en"),
				occurrence: Semantics.OccurrenceId.from_index($occurrence_index),
				script: Font.Script.from_iso15924("Latn"),
				size: Layout.Unit.from_raw(1000),
				source: {
					scalars: Semantics.Range.from_start_and_length(source_start, 3),
					utf8_bytes: Semantics.Range.from_start_and_length(source_start, 3),
				},
				substitutions: empty_range,
				transformations: empty_range,
				writing_mode: Horizontal,
			})
			page_index = run_index / 64
			$placements = $placements.append({
				origin: { x: Layout.Unit.from_raw(72000), y: Layout.Unit.from_raw(700000) },
				page: Semantics.PageId.from_index(page_index),
				run: run_id,
			})
			$line = $line + 1
		}
		$occurrence_index = $occurrence_index + 1
	}
	var $pages = []
	var $run_start = 0
	while $run_start < run_count {
		page_index = $pages.len()
		length = U64.min(64, run_count - $run_start)
		$pages = $pages.append({
			id: Semantics.PageId.from_index(page_index),
			runs: Semantics.Range.from_start_and_length($run_start, length),
		})
		$run_start = $run_start + length
	}
	{
		pages: $pages,
		placements: $placements,
		text: {
			clusters: $clusters,
			glyph_indices: $glyph_indices,
			glyphs: $glyphs,
			runs: $runs,
			substitutions: [],
			transformations: [],
		},
	}
}

fragment_limits : KernelFacadeFragments.Prepared -> KernelFacadeFragments.Limits
fragment_limits = |prepared| KernelFacadeFragments.Limits.make({
	max_fragments: prepared.text.runs.len(),
	max_occurrences: prepared.text.runs.len(),
	max_pages: prepared.pages.len(),
})

semantic_limits : U64, U64 -> KernelSemantics.Limits
semantic_limits = |occurrences, fragments| KernelSemantics.Limits.make({
	max_attributes: 0,
	max_content_spine: occurrences + 1,
	max_fragments: fragments,
	max_namespaces: 1,
	max_nodes: 2,
	max_occurrences: occurrences,
	max_semantic_depth: 2,
})

full_source_range : Semantics.TextRange
full_source_range = {
	scalars: Semantics.Range.from_start_and_length(0, 6),
	utf8_bytes: Semantics.Range.from_start_and_length(0, 6),
}

empty_range : Semantics.Range
empty_range = Semantics.Range.from_start_and_length(0, 0)

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated facade-fragment evidence index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated facade-fragment evidence update escaped"
	}
}
