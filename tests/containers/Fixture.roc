import pdf.Conformance
import pdf.Document
import pdf.KernelFacadeSemantics
import pdf.KernelFacadeSources
import pdf.KernelSemantics
import pdf.KernelTextSemantics
import pdf.Pdf
import pdf.Scene
import pdf.Layout
import pdf.Image

## Semantic-foundation evidence through the public `Pdf` constructors.
##
## - `nested`: parts, sections, and divisions nested four containers deep
##   around headings, paragraphs, a bulleted list, a destination heading,
##   and an internal link, plus leaf blocks outside any container.
## - `sections xN`: N sections, each an `H1` and two paragraphs, the scale
##   pair for linear container planning and containment checking.
## - `atomic_negatives`: container depth, empty containers, and nested
##   unavailable or invalid blocks reject with stable diagnostics and no bytes.
##
## Bytes always come from `Pdf.to_bytes` (the default `Archive` profile). The
## work vector comes from one additional semantic planning pass over the same
## normalized authoring with the facade's container and semantic limits.
Fixture :: [].{
	EvidenceError : [EvidenceFailure, InvalidScale, MissingRejection(U64)]

	nested : {} -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	nested = |_| evidence(nested_document({}))

	sections : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	sections = |count| {
		if count == 0 or count > 1000 {
			return Err(InvalidScale)
		}
		evidence(section_document(count))
	}

	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |context| run_negatives(context)
}

nested_document : {} -> Document
nested_document = |_| Pdf.document({
	contents: [
		Pdf.title("Operations handbook"),
		Pdf.paragraph("This handbook groups its procedures into parts, sections, and divisions."),
		Pdf.part([
			Pdf.section([
				Pdf.destination_heading("receiving", 1, "1 Receiving"),
				Pdf.paragraph("Deliveries are received at the Moonah yard between 7 am and 3 pm."),
				Pdf.division([
					Pdf.section([
						Pdf.heading(2, "1.1 Inspection"),
						Pdf.paragraph("Every delivery is inspected before it is accepted."),
						Pdf.bullets(["Count the cartons", "Check each seal", "Record damage"]),
					]),
				]),
				Pdf.internal_link("Return to Receiving", "receiving"),
			]),
			Pdf.section([Pdf.heading(1, "2 Dispatch"), Pdf.paragraph("Orders leave in the order they were confirmed.")]),
		]),
		Pdf.division([Pdf.paragraph("Questions go to the operations team.")]),
	],
	language: "en-AU",
	title: "Operations handbook",
})

section_document : U64 -> Document
section_document = |count| {
	var $contents = List.with_capacity(count + 1)
	$contents = $contents.append(Pdf.title("Sectioned report"))
	var $index = 0
	while $index < count {
		label = (1 + $index).to_str()
		$contents = $contents.append(
			Pdf.section([
				Pdf.heading(1, "Section ${label}"),
				Pdf.paragraph("Section ${label} opens with a paragraph that belongs to its own grouping element."),
				Pdf.paragraph("A second paragraph closes section ${label}."),
			]),
		)
		$index = $index + 1
	}
	Pdf.document({ contents: $contents, language: "en-AU", title: "Sectioned report" })
}

evidence : Document -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
evidence = |document| {
	bytes = Pdf.to_bytes(document) ? |_| EvidenceFailure
	plan = KernelFacadeSemantics.Plan.build(Document.normalize(document), semantic_limits) ? |_| EvidenceFailure
	work = KernelFacadeSemantics.Plan.work(plan)
	semantic_work = KernelSemantics.Plan.work(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(plan)))
	Ok({
		bytes,
		work: [
			work.node_writes,
			work.container_nodes,
			work.content_writes,
			work.occurrence_writes,
			semantic_work.node_visits,
			semantic_work.containment_edges,
			semantic_work.max_semantic_depth,
			bytes.len(),
		],
	})
}

## The facade's semantic-planning limits (package/Pdf.roc).
semantic_limits : KernelFacadeSemantics.Limits
semantic_limits = KernelFacadeSemantics.Limits.make({
	max_artifacts: 0,
	max_container_depth: 16,
	max_content_spine: 8192,
	max_nodes: 4096,
	max_occurrences: 2048,
	max_properties: 2048,
	max_source_inputs: 2048,
	semantics: KernelSemantics.Limits.make({ max_attributes: 8192, max_content_spine: 8192, max_fragments: 0, max_namespaces: 1, max_nodes: 4096, max_occurrences: 2048, max_semantic_depth: 32 }),
	sources: KernelFacadeSources.Limits.make({
		max_hash_probes: 1000000,
		max_inputs: 2048,
		max_source_bytes: 1000000,
		max_source_scalars: 1000000,
		max_table_slots: 8192,
		max_unique_sources: 2048,
		unicode: { max_graphemes: 1000000, max_line_boundaries: 1000001, max_scalars: 1000000, max_script_runs: 2048 },
	}),
	text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 2048, max_text_property_bytes: 1000000, max_text_source_bytes: 1000000, max_text_source_scalars: 1000000, max_text_sources: 2048 }),
})

nest : Document.Block, U64 -> Document.Block
nest = |block, depth| {
	var $block = block
	var $level = 0
	while $level < depth {
		$block = Pdf.section([$block])
		$level = $level + 1
	}
	$block
}

rejects : Document, Conformance.DiagnosticCode, Str, Str -> U64
rejects = |document, expected_code, expected_feature, expected_path| match Pdf.to_bytes(document) {
	Err(InvalidDocument({ diagnostics: [{ code, details, feature: Feature(feature), location: Document, stage: AuthoringValidation, .. }], truncation: Complete, .. })) => if code == expected_code and feature == expected_feature and details == (if expected_path.is_empty() [] else [expected_path]) 1 else 0
	_ => 0
}

## Each document differs from a valid authoring in one container fact.
run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_negatives = |context| {
	title = if context == 0 "Container negatives" else "guarded"
	document = |contents| Pdf.document({ contents, language: "en-AU", title })
	blank_figure = Scene.drawing({}).image(Image.Source.gray8({ alpha: NoAlpha, dimensions: { height: 1, width: 1 }, pixels: [128], row_stride: 1 }), Layout.rect(0, 0, 10, 10))

	## Every rejection depends on the runtime depth offset so none is
	## evaluated at compile time.
	offset = U64.mod_by(context, 1)
	checks = [
		rejects(document([Pdf.title("Deep"), nest(Pdf.paragraph("Leaf"), 17 + offset)]), BudgetExceeded, "semantics.container_depth", "contents[1]${Str.repeat(".contents[0]", 16)}"),
		rejects(document([Pdf.paragraph("Lead"), nest(Pdf.section([Pdf.paragraph("Kept"), Pdf.division([])]), offset)]), InvalidRelationship, "semantics.empty_container", "contents[1].contents[1]"),
		rejects(document([nest(Pdf.section([]), offset), Pdf.paragraph("Body")]), InvalidRelationship, "semantics.empty_container", "contents[0]"),
		rejects(document([nest(Pdf.section([Pdf.heading(1, "Tables"), Pdf.simple_table("A nested table placeholder.")]), offset)]), FeatureUnavailable, "table.simple", ""),
		rejects(document([nest(Pdf.part([Pdf.division([Pdf.figure(blank_figure, "", Pdf.no_caption)])]), offset)]), FeatureUnavailable, "document.figure", ""),
	]
	passed = checks.sum()
	if passed != checks.len() {
		return Err(MissingRejection(passed))
	}

	## The deepest accepted nesting is the facade bound itself.
	boundary = Pdf.to_bytes(document([Pdf.title("Boundary"), nest(Pdf.paragraph("Leaf"), 16 + offset)])) ? |_| EvidenceFailure
	carrier = Pdf.to_bytes(document([Pdf.title("Container carrier"), Pdf.section([Pdf.heading(1, "Carrier"), Pdf.paragraph("A valid grouped document.")])])) ? |_| EvidenceFailure
	Ok({ bytes: carrier, work: [passed, boundary.len(), carrier.len()] })
}
