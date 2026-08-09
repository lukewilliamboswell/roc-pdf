import Document
import KernelEmit
import KernelFacadeSemantics
import KernelFacadeShape
import KernelFacadeSources
import KernelSemantics
import KernelStructure
import KernelTextSemantics
import Semantics
import Theme

Gate3GeneratedLabelEvidence :: [].{

	## The malformed store differs only by deleting the label occurrence's typed
	## generated-presentation property. Preparation must reject it before font
	## shaping or any PDF object plan can begin.
	negative : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	negative = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		document = Document.from_blocks({
			contents: [Document.bullets(["First"])],
			language: "en-AU",
			title: "Gate 3 generated-label negative",
		})
		plan = KernelFacadeSemantics.Plan.build(Document.normalize(document), semantic_limits) ? |_| EvidenceFailure
		preliminary = KernelFacadeSemantics.Plan.preliminary(plan)
		store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(preliminary))
		label = match list_at(KernelFacadeSemantics.Plan.block_ownership(plan), 0) {
			TextBlock({ body: _, label: Label(occurrence) }) => occurrence.index()
			_ => return Err(EvidenceFailure)
		}
		occurrence = list_at(store.occurrences, label)
		malformed = {
			..store,
			occurrences: list_set(store.occurrences, label, { ..occurrence, text_properties: Semantics.Range.from_start_and_length(0, 0) }),
		}
		rejected = match KernelFacadeShape.Preparation.build(
			KernelFacadeSemantics.Plan.authoring(plan),
			KernelFacadeSemantics.Plan.block_ownership(plan),
			malformed,
			KernelFacadeSources.Plan.sources(KernelFacadeSemantics.Plan.sources(plan)).len(),
			KernelFacadeSemantics.Plan.artifacts(plan).len(),
			2,
			Theme.default,
		) {
			Err(GeneratedLabelEvidenceInvalid({ block: 0, occurrence: 0 })) => 1
			_ => return Err(EvidenceFailure)
		}
		blank = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(blank) ? |_| EvidenceFailure
		Ok({ bytes, work: [rejected, bytes.len()] })
	}
}

semantic_limits : KernelFacadeSemantics.Limits
semantic_limits = KernelFacadeSemantics.Limits.make({
	max_artifacts: 0,
	max_content_spine: 16,
	max_nodes: 8,
	max_occurrences: 4,
	max_properties: 2,
	max_source_inputs: 4,
	semantics: KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 16, max_fragments: 0, max_namespaces: 1, max_nodes: 8, max_occurrences: 4, max_semantic_depth: 4 }),
	sources: KernelFacadeSources.Limits.make({
		max_hash_probes: 16,
		max_inputs: 4,
		max_source_bytes: 32,
		max_source_scalars: 16,
		max_table_slots: 8,
		max_unique_sources: 4,
		unicode: { max_graphemes: 8, max_line_boundaries: 9, max_scalars: 8, max_script_runs: 4 },
	}),
	text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 2, max_text_property_bytes: 8, max_text_source_bytes: 32, max_text_source_scalars: 16, max_text_sources: 4 }),
})

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "validated generated-label evidence index escaped"
	Ok(value) => value
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => crash "validated generated-label evidence update escaped"
	Ok(updated) => updated
}
