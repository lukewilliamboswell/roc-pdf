app [main!] {
	pf: platform "../tests/platform/main.roc",
	pdf: "../package/main.roc",
}

import pdf.Conformance
import pdf.Document
import pdf.Image
import pdf.Layout
import pdf.Scene
import pdf.Semantics

## The prepared boundary exposes stable stores and exact work facts without
## exposing an eventual PDF object plan.
prepared_counts : Document.Prepared -> { pages : U64, resources : U64, semantic_nodes : U64 }
prepared_counts = |prepared| {
	pages: prepared.scenes.pages.len(),
	resources: prepared.resource_uses.len(),
	semantic_nodes: prepared.semantics.nodes.len(),
}

## Layout cache identity includes exact constraints, style, source, and resources.
expect {
	key : Layout.MeasurementKey
	key = {
		constraints: {
			available: {
				height: Layout.Unit.from_raw(792000),
				width: Layout.Unit.from_raw(612000),
			},
			column: 0,
			page: Semantics.PageId.from_index(0),
		},
		resources: Layout.ResourceStateId.from_index(3),
		source: Layout.SourceId.from_index(4),
		style: Layout.StyleId.from_index(5),
	}

	key.resources.index() == 3 and key.style.index() == 5
}

## Prepared resource edges keep placement ownership separate from payload identity.
expect {
	resource_use : Document.ResourceUse
	resource_use = {
		group: Scene.GroupId.from_index(7),
		resource: Image(Image.Id.from_index(9)),
	}

	match resource_use.resource {
		Image(image) => image.index() == 9
		_ => False
	}
}

## Rejected preparation is atomic and diagnostics carry stage and clause facts.
expect {
	diagnostic : Conformance.Diagnostic
	diagnostic = {
		clause_references: ["ISO 32000-2:2020, 14.8"],
		code: InvalidOwnership,
		details: ["scene group 7 has no fragment owner"],
		location: Resource(9),
		requirement_ids: ["ROC-PDF-PREPARED-STAGE-CONTRACT"],
		stage: AuthoringValidation,
	}

	result : Document.PreparationResult
	result = Err({ detail_bytes: 35, diagnostics: [diagnostic], truncation: Complete })

	match result {
		Err(batch) => batch.diagnostics.len() == 1 and batch.truncation == Complete
		Ok(_) => False
	}
}

## Phase-local layout handlers and caches expire at the prepared boundary.
expect {
	policy = Document.lifetimes

	policy.custom_handlers == ReleaseAfter(LayoutStabilization) and
		policy.layout_caches == ReleaseAfter(PreparedBoundary) and
			policy.validated_resource_bytes == RetainThroughEmission
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |_| { bytes: [], work: [] }
