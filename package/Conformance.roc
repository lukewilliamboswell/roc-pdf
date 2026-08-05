Conformance :: [].{

	## Public profiles are exact claim sets, not fallback levels.
	Profile : [AccessibleArchive, Archive, Standard]

	## Orthogonal claims remain independently selectable and auditable.
	Capability : [Pdf20, PdfA4f, PdfUa2, StaticPdfA4, WtpdfAccessibility, WtpdfReuse]

	ClaimSet : {
		pdf20 : Bool,
		pdf_a4f : Bool,
		pdf_ua2 : Bool,
		static_pdf_a4 : Bool,
		wtpdf_accessibility : Bool,
		wtpdf_reuse : Bool,
	}

	## Stable diagnostic families reserved by the Gate 0 contract. Runtime
	## validation for each code is introduced with the gate that implements it.
	DiagnosticCode : [
		BudgetExceeded,
		DuplicateIdentity,
		FontCoverageMissing,
		FragmentCoverageInvalid,
		IdentityOutOfRange,
		InvalidLanguage,
		InvalidNamespace,
		InvalidOwnership,
		InvalidRelationship,
		InvalidStructureAttribute,
		LayoutCycle,
	]

	DiagnosticLocation : [
		Annotation(U64),
		Document,
		Fragment(U64),
		Node(U64),
		Occurrence(U64),
		Page(U64),
		Resource(U64),
	]
	ValidationStage : [AuthoringValidation, LoweredPlanValidation, ProfileValidation]

	Diagnostic : {
		clause_references : List(Str),
		code : DiagnosticCode,
		details : List(Str),
		location : DiagnosticLocation,
		requirement_ids : List(Str),
		stage : ValidationStage,
	}

	DiagnosticTruncation : [Complete, Truncated]

	## Validators consume one bounded accumulator and stop at a deterministic
	## count or byte limit. They do not rescan the rejected document merely to
	## count findings that cannot be retained.
	DiagnosticBatch : {
		detail_bytes : U64,
		diagnostics : List(Diagnostic),
		truncation : DiagnosticTruncation,
	}

	## Dimension-specific limits are carried through every compiler stage.
	## A zero limit means that dimension accepts no input; it never means
	## "unlimited".
	ResourcePolicy : {
		max_annotations : U64,
		max_comparison_work : U64,
		max_compression_input_bytes : U64,
		max_content_occurrences : U64,
		max_diagnostic_detail_bytes : U64,
		max_diagnostics : U64,
		max_font_bytes : U64,
		max_font_composite_depth : U64,
		max_font_glyphs : U64,
		max_font_tables : U64,
		max_fragments : U64,
		max_hash_work_bytes : U64,
		max_icc_bytes : U64,
		max_icc_tags : U64,
		max_image_decoded_bytes : U64,
		max_image_encoded_bytes : U64,
		max_layout_passes : U64,
		max_mcid_entries : U64,
		max_metadata_bytes : U64,
		max_output_bytes : U64,
		max_pages : U64,
		max_parent_tree_entries : U64,
		max_reference_count : U64,
		max_resource_edges : U64,
		max_resources : U64,
		max_scene_commands : U64,
		max_semantic_depth : U64,
		max_semantic_nodes : U64,
		max_xmp_bytes : U64,
	}

	claims_for_profile : Profile -> ClaimSet
	claims_for_profile = |profile| {
		match profile {
			Standard => {
				pdf20: True,
				pdf_a4f: False,
				pdf_ua2: False,
				static_pdf_a4: False,
				wtpdf_accessibility: False,
				wtpdf_reuse: False,
			}
			Archive => {
				pdf20: True,
				pdf_a4f: False,
				pdf_ua2: False,
				static_pdf_a4: True,
				wtpdf_accessibility: False,
				wtpdf_reuse: False,
			}
			AccessibleArchive => {
				pdf20: True,
				pdf_a4f: False,
				pdf_ua2: True,
				static_pdf_a4: True,
				wtpdf_accessibility: False,
				wtpdf_reuse: False,
			}
		}
	}
}

## Standard always carries the PDF 2.0 claim.
expect Conformance.claims_for_profile(Standard).pdf20

## Standard does not silently add the archival claim.
expect !Conformance.claims_for_profile(Standard).static_pdf_a4

## Archive adds the static PDF/A-4 claim.
expect Conformance.claims_for_profile(Archive).static_pdf_a4

## AccessibleArchive adds the PDF/UA-2 claim.
expect Conformance.claims_for_profile(AccessibleArchive).pdf_ua2

## WTPDF accessibility remains an orthogonal declaration.
expect !Conformance.claims_for_profile(AccessibleArchive).wtpdf_accessibility
