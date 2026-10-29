import Document
import Font
import KernelBalanced
import KernelColor
import KernelContent
import KernelDeflate
import KernelFacadeFragments
import KernelFacadeFurniture
import KernelFacadeLabels
import KernelFacadeLines
import KernelFacadeOutput
import KernelFacadePages
import KernelFacadePipeline
import KernelFacadeReferenceLines
import KernelFacadeReferenceShape
import KernelFacadeReferences
import KernelFacadeScenes
import KernelFacadeSemantics
import KernelFacadeShape
import KernelFacadeSources
import KernelFacadeTables
import KernelFacadeText
import KernelFont
import KernelFontObjects
import KernelFontPlan
import KernelFontSubset
import KernelGeometry
import KernelIdentity
import KernelImage
import KernelIndex
import KernelLex
import KernelLineLayout
import KernelNavigationObjects
import KernelObject
import KernelObjectPlan
import KernelOutline
import KernelOutputBound
import KernelPageLabels
import KernelPageLayout
import KernelPageObjects
import KernelPdfFont
import KernelPdfText
import KernelReferenceLayout
import KernelResourceObjects
import KernelResourceUse
import KernelScene
import KernelSeal
import KernelSemantics
import KernelSha256
import KernelShape
import KernelSourceText
import KernelTagged
import KernelTaggedObjects
import KernelTaggedTextStructure
import KernelTextOwnership
import KernelTextSemantics
import KernelUnicode
import Text

## Typed classification at the public facade boundary. Feature identities and
## categories are explicit; debug representations supply bounded detail only.
## Private module: no PDF object or compiler error types enter the public API.
KernelFacadeFailure :: [].{
	Failure : { category : [Budget, Invariant], feature : Str, path : Str, detail : Str }

	pipeline : KernelFacadePipeline.Error -> Failure
	pipeline = |error| kernel_facade_pipeline_error(error)

	image : KernelImage.Error -> Failure
	image = |error| kernel_image_error(error)
}

## Add the owning stage without changing the cause or its category.
context : Str, Str, KernelFacadeFailure.Failure -> KernelFacadeFailure.Failure
context = |feature, path, cause| { ..cause, feature: "${feature}.${cause.feature}", path: "${path}.${cause.path}" }

## Diagnostic detail is explanatory and bounded. It cannot select a feature
## or category, including when strings contain text resembling error tags.
leaf : [Budget, Invariant], Str, Str, Str -> KernelFacadeFailure.Failure
leaf = |category, feature, path, inspected| {
	bytes = inspected.to_utf8()
	detail = if bytes.len() <= 160 {
		inspected
	} else {
		"${Str.from_utf8(bytes.sublist({ start: 0, len: 160 })) ?? "(detail truncated)"}…"
	}
	{ category, feature, path, detail }
}

kernel_facade_pipeline_error : KernelFacadePipeline.Error -> KernelFacadeFailure.Failure
kernel_facade_pipeline_error = |error| match error {
	Fragments(cause) => context("fragments", "Fragments", kernel_facade_fragments_error(cause))
	Furniture(cause) => context("furniture", "Furniture", kernel_facade_furniture_error(cause))
	Labels(cause) => context("labels", "Labels", kernel_facade_labels_error(cause))
	Lines(cause) => context("lines", "Lines", kernel_facade_lines_error(cause))
	Output(cause) => context("output", "Output", kernel_facade_output_error(cause))
	Pages(cause) => context("pages", "Pages", kernel_facade_pages_error(cause))
	References(cause) => context("references", "References", kernel_facade_references_error(cause))
	ReferenceBudget(_) => leaf(Budget, "reference_budget", "ReferenceBudget", Str.inspect(error))
	ReferenceCycle(_) => leaf(Invariant, "reference_cycle", "ReferenceCycle", Str.inspect(error))
	Scenes(cause) => context("scenes", "Scenes", kernel_facade_scenes_error(cause))
	Semantics(cause) => context("semantics", "Semantics", kernel_facade_semantics_error(cause))
	Shape(cause) => context("shape", "Shape", kernel_facade_shape_error(cause))
	Text(cause) => context("text", "Text", kernel_facade_text_error(cause))
}

kernel_image_error : KernelImage.Error -> KernelFacadeFailure.Failure
kernel_image_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	ColorComponentMismatch(_) => leaf(Invariant, "color_component_mismatch", "ColorComponentMismatch", Str.inspect(error))
	ColorSpaceOutOfRange(_) => leaf(Invariant, "color_space_out_of_range", "ColorSpaceOutOfRange", Str.inspect(error))
	DecodedLengthMismatch(_) => leaf(Invariant, "decoded_length_mismatch", "DecodedLengthMismatch", Str.inspect(error))
	InvalidDimensions(_) => leaf(Invariant, "invalid_dimensions", "InvalidDimensions", Str.inspect(error))
	InvalidExif(_) => leaf(Invariant, "invalid_exif", "InvalidExif", Str.inspect(error))
	InvalidJpegMarker(_) => leaf(Invariant, "invalid_jpeg_marker", "InvalidJpegMarker", Str.inspect(error))
	InvalidJpegSegment(_) => leaf(Invariant, "invalid_jpeg_segment", "InvalidJpegSegment", Str.inspect(error))
	InvalidRowStride(_) => leaf(Invariant, "invalid_row_stride", "InvalidRowStride", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	MarkerLimitExceeded(_) => leaf(Budget, "marker_limit_exceeded", "MarkerLimitExceeded", Str.inspect(error))
	NonDenseIdentity(_) => leaf(Invariant, "non_dense_identity", "NonDenseIdentity", Str.inspect(error))
	OrientationRequiresTransform(_) => leaf(Invariant, "orientation_requires_transform", "OrientationRequiresTransform", Str.inspect(error))
	UnsupportedJpegComponents(_) => leaf(Invariant, "unsupported_jpeg_components", "UnsupportedJpegComponents", Str.inspect(error))
}

kernel_facade_fragments_error : KernelFacadeFragments.Error -> KernelFacadeFailure.Failure
kernel_facade_fragments_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	Navigation(cause) => context("navigation", "Navigation", document_navigation_error(cause))
	InvalidOccurrence(_) => leaf(Invariant, "invalid_occurrence", "InvalidOccurrence", Str.inspect(error))
	InvalidPage(_) => leaf(Invariant, "invalid_page", "InvalidPage", Str.inspect(error))
	InvalidPlacement(_) => leaf(Invariant, "invalid_placement", "InvalidPlacement", Str.inspect(error))
	InvalidPreliminaryFragments(_) => leaf(Invariant, "invalid_preliminary_fragments", "InvalidPreliminaryFragments", Str.inspect(error))
	InvalidRun(_) => leaf(Invariant, "invalid_run", "InvalidRun", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	SourceRangeMismatch(_) => leaf(Invariant, "source_range_mismatch", "SourceRangeMismatch", Str.inspect(error))
	TextSemantics(cause) => context("text_semantics", "TextSemantics", kernel_text_semantics_error(cause))
}

kernel_facade_furniture_error : KernelFacadeFurniture.Error -> KernelFacadeFailure.Failure
kernel_facade_furniture_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	PageLabels(cause) => context("page_labels", "PageLabels", document_navigation_error(cause))
	PageLabelText({ error: cause, .. }) => leaf(kernel_page_labels_error(cause).category, "page_label_text", "PageLabelText", Str.inspect(error))
	ScopeInvalid(_) => leaf(Invariant, "scope_invalid", "ScopeInvalid", Str.inspect(error))
	BodyEmpty => leaf(Invariant, "body_empty", "BodyEmpty", Str.inspect(error))
	BodySpace(_) => leaf(Invariant, "body_space", "BodySpace", Str.inspect(error))
	DrawingInvalid(_) => leaf(Invariant, "drawing_invalid", "DrawingInvalid", Str.inspect(error))
	FieldOverflow(_) => leaf(Invariant, "field_overflow", "FieldOverflow", Str.inspect(error))
	FurnitureInline(_) => leaf(Invariant, "furniture_inline", "FurnitureInline", Str.inspect(error))
	GapNegative(_) => leaf(Invariant, "gap_negative", "GapNegative", Str.inspect(error))
	InsetNegative(_) => leaf(Invariant, "inset_negative", "InsetNegative", Str.inspect(error))
	InlineEmpty(_) => leaf(Invariant, "inline_empty", "InlineEmpty", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	FurnitureText(_) => leaf(Invariant, "furniture_text", "FurnitureText", Str.inspect(error))
	FurnitureCluster(_) => leaf(Invariant, "furniture_cluster", "FurnitureCluster", Str.inspect(error))
	RegionEmpty(_) => leaf(Invariant, "region_empty", "RegionEmpty", Str.inspect(error))
	RegionOverflow(_) => leaf(Invariant, "region_overflow", "RegionOverflow", Str.inspect(error))
	Selection(cause) => context("selection", "Selection", kernel_facade_shape_error(cause))
	Shape(cause) => context("shape", "Shape", kernel_shape_error(cause))
	SlotOverlap(_) => leaf(Invariant, "slot_overlap", "SlotOverlap", Str.inspect(error))
	Sources(cause) => context("sources", "Sources", kernel_facade_sources_error(cause))
	UnsupportedThemeFace(_) => leaf(Invariant, "unsupported_theme_face", "UnsupportedThemeFace", Str.inspect(error))
}

kernel_facade_labels_error : KernelFacadeLabels.Error -> KernelFacadeFailure.Failure
kernel_facade_labels_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	InvalidPlacement(cause) => context("invalid_placement", "InvalidPlacement", kernel_facade_labels_owner(cause))
	LabelBounds(_) => leaf(Invariant, "label_bounds", "LabelBounds", Str.inspect(error))
	LabelText(_) => leaf(Invariant, "label_text", "LabelText", Str.inspect(error))
	LabelPolicy => leaf(Invariant, "label_policy", "LabelPolicy", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	Shape(cause) => context("shape", "Shape", kernel_shape_error(cause))
	Sources(cause) => context("sources", "Sources", kernel_facade_sources_error(cause))
}

kernel_facade_lines_error : KernelFacadeLines.Error -> KernelFacadeFailure.Failure
kernel_facade_lines_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	SourceContentWidth(_) => leaf(Invariant, "source_content_width", "SourceContentWidth", Str.inspect(error))
	SourceTokenTooWide(_) => leaf(Invariant, "source_token_too_wide", "SourceTokenTooWide", Str.inspect(error))
	CalloutWidth(_) => leaf(Invariant, "callout_width", "CalloutWidth", Str.inspect(error))
	CustomWidth(_) => leaf(Invariant, "custom_width", "CustomWidth", Str.inspect(error))
	InvalidGeometry => leaf(Invariant, "invalid_geometry", "InvalidGeometry", Str.inspect(error))
	InvalidRun(_) => leaf(Invariant, "invalid_run", "InvalidRun", Str.inspect(error))
	LabelTooWide(_) => leaf(Invariant, "label_too_wide", "LabelTooWide", Str.inspect(error))
	LineLayout(cause) => context("line_layout", "LineLayout", kernel_line_layout_error(cause))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	RunCoverage(_) => leaf(Invariant, "run_coverage", "RunCoverage", Str.inspect(error))
	Tables(cause) => context("tables", "Tables", kernel_facade_tables_error(cause))
}

kernel_facade_output_error : KernelFacadeOutput.Error -> KernelFacadeFailure.Failure
kernel_facade_output_error = |error| match error {
	Content(cause) => context("content", "Content", kernel_content_error(cause))
	FontObjects(cause) => context("font_objects", "FontObjects", kernel_font_objects_error(cause))
	FontPlan(cause) => context("font_plan", "FontPlan", kernel_font_plan_error(cause))
	Images(cause) => context("images", "Images", kernel_image_error(cause))
	Objects(cause) => context("objects", "Objects", kernel_object_plan_error(cause))
	Resources(cause) => context("resources", "Resources", kernel_resource_use_error(cause))
	Structure(cause) => context("structure", "Structure", kernel_tagged_text_structure_error(cause))
	Subset(cause) => context("subset", "Subset", kernel_font_subset_error(cause))
	Text(cause) => context("text", "Text", kernel_pdf_text_error(cause))
}

kernel_facade_pages_error : KernelFacadePages.Error -> KernelFacadeFailure.Failure
kernel_facade_pages_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	CustomMeasureShort(_) => leaf(Invariant, "custom_measure_short", "CustomMeasureShort", Str.inspect(error))
	CustomOversize(_) => leaf(Invariant, "custom_oversize", "CustomOversize", Str.inspect(error))
	DecorationOversize(_) => leaf(Invariant, "decoration_oversize", "DecorationOversize", Str.inspect(error))
	FigureOversize(_) => leaf(Invariant, "figure_oversize", "FigureOversize", Str.inspect(error))
	FigureScaleFloor(_) => leaf(Invariant, "figure_scale_floor", "FigureScaleFloor", Str.inspect(error))
	InvalidBlock(_) => leaf(Invariant, "invalid_block", "InvalidBlock", Str.inspect(error))
	InvalidLine(_) => leaf(Invariant, "invalid_line", "InvalidLine", Str.inspect(error))
	InvalidRun(_) => leaf(Invariant, "invalid_run", "InvalidRun", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	PageBreakPosition(_) => leaf(Invariant, "page_break_position", "PageBreakPosition", Str.inspect(error))
	PageLayout(cause) => context("page_layout", "PageLayout", kernel_page_layout_error(cause))
	TableLayout({ error: cause, .. }) => leaf(kernel_page_layout_error(cause).category, "table_layout", "TableLayout", Str.inspect(error))
	TableRuleWidth(_) => leaf(Invariant, "table_rule_width", "TableRuleWidth", Str.inspect(error))
}

kernel_facade_references_error : KernelFacadeReferences.Error -> KernelFacadeFailure.Failure
kernel_facade_references_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	Semantics(cause) => context("semantics", "Semantics", kernel_facade_semantics_error(cause))
	Shape(cause) => context("shape", "Shape", kernel_facade_reference_shape_error(cause))
	Lines(cause) => context("lines", "Lines", kernel_facade_reference_lines_error(cause))
	Pages(cause) => context("pages", "Pages", kernel_facade_pages_error(cause))
	Text(cause) => context("text", "Text", kernel_facade_text_error(cause))
	Navigation(cause) => context("navigation", "Navigation", document_navigation_error(cause))
	UnknownDestination(_) => leaf(Invariant, "unknown_destination", "UnknownDestination", Str.inspect(error))
	MissingAnchor(_) => leaf(Invariant, "missing_anchor", "MissingAnchor", Str.inspect(error))
	Format({ error: cause, .. }) => leaf(kernel_page_labels_error(cause).category, "format", "Format", Str.inspect(error))
	FieldOverflow(_) => leaf(Invariant, "field_overflow", "FieldOverflow", Str.inspect(error))
	InvalidMapping(_) => leaf(Invariant, "invalid_mapping", "InvalidMapping", Str.inspect(error))
}

kernel_facade_scenes_error : KernelFacadeScenes.Error -> KernelFacadeFailure.Failure
kernel_facade_scenes_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	Color(cause) => context("color", "Color", kernel_color_error(cause))
	InvalidPage(_) => leaf(Invariant, "invalid_page", "InvalidPage", Str.inspect(error))
	InvalidPageSize => leaf(Invariant, "invalid_page_size", "InvalidPageSize", Str.inspect(error))
	InvalidPlacement(_) => leaf(Invariant, "invalid_placement", "InvalidPlacement", Str.inspect(error))
	InvalidStyleCount(_) => leaf(Invariant, "invalid_style_count", "InvalidStyleCount", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	Ownership(cause) => context("ownership", "Ownership", kernel_text_ownership_error(cause))
	Scene(cause) => context("scene", "Scene", kernel_scene_error(cause))
	UnsupportedColor(_) => leaf(Invariant, "unsupported_color", "UnsupportedColor", Str.inspect(error))
}

kernel_facade_semantics_error : KernelFacadeSemantics.Error -> KernelFacadeFailure.Failure
kernel_facade_semantics_error = |error| match error {
	CalloutStyle(_) => leaf(Invariant, "callout_style", "CalloutStyle", Str.inspect(error))
	CalloutContent(_) => leaf(Invariant, "callout_content", "CalloutContent", Str.inspect(error))
	CalloutBlock(_) => leaf(Invariant, "callout_block", "CalloutBlock", Str.inspect(error))
	CalloutFlow(_) => leaf(Invariant, "callout_flow", "CalloutFlow", Str.inspect(error))
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	ReferenceStageRequired => leaf(Invariant, "reference_stage_required", "ReferenceStageRequired", Str.inspect(error))
	ContentsEntry(_) => leaf(Invariant, "contents_entry", "ContentsEntry", Str.inspect(error))
	PageReference(_) => leaf(Invariant, "page_reference", "PageReference", Str.inspect(error))
	ReferenceResolution(_) => leaf(Invariant, "reference_resolution", "ReferenceResolution", Str.inspect(error))
	SourceWhitespace({ error: cause, .. }) => leaf(kernel_source_text_error(cause).category, "source_whitespace", "SourceWhitespace", Str.inspect(error))
	SourceStyle(_) => leaf(Invariant, "source_style", "SourceStyle", Str.inspect(error))
	SourcePosition(_) => leaf(Invariant, "source_position", "SourcePosition", Str.inspect(error))
	ContainerDepthExceeded(_) => leaf(Budget, "container_depth_exceeded", "ContainerDepthExceeded", Str.inspect(error))
	CustomContent(_) => leaf(Invariant, "custom_content", "CustomContent", Str.inspect(error))
	CustomDrawing(_) => leaf(Invariant, "custom_drawing", "CustomDrawing", Str.inspect(error))
	CustomMeasure(_) => leaf(Invariant, "custom_measure", "CustomMeasure", Str.inspect(error))
	CustomName(_) => leaf(Invariant, "custom_name", "CustomName", Str.inspect(error))
	EmptyContainer(_) => leaf(Invariant, "empty_container", "EmptyContainer", Str.inspect(error))
	DecorationDrawing(_) => leaf(Invariant, "decoration_drawing", "DecorationDrawing", Str.inspect(error))
	DecorationPosition(_) => leaf(Invariant, "decoration_position", "DecorationPosition", Str.inspect(error))
	EmptyInline(_) => leaf(Invariant, "empty_inline", "EmptyInline", Str.inspect(error))
	EmptyKeep(_) => leaf(Invariant, "empty_keep", "EmptyKeep", Str.inspect(error))
	EmptyScope(_) => leaf(Invariant, "empty_scope", "EmptyScope", Str.inspect(error))
	EmptyLanguage => leaf(Invariant, "empty_language", "EmptyLanguage", Str.inspect(error))
	EmptyLinkText(_) => leaf(Invariant, "empty_link_text", "EmptyLinkText", Str.inspect(error))
	EmptyList(_) => leaf(Invariant, "empty_list", "EmptyList", Str.inspect(error))
	EmptyListItem(_) => leaf(Invariant, "empty_list_item", "EmptyListItem", Str.inspect(error))
	EmptyMetadataTitle => leaf(Invariant, "empty_metadata_title", "EmptyMetadataTitle", Str.inspect(error))
	EmptyRichParagraph(_) => leaf(Invariant, "empty_rich_paragraph", "EmptyRichParagraph", Str.inspect(error))
	FigureAlternativeEmpty(_) => leaf(Invariant, "figure_alternative_empty", "FigureAlternativeEmpty", Str.inspect(error))
	FigureCaptionEmpty(_) => leaf(Invariant, "figure_caption_empty", "FigureCaptionEmpty", Str.inspect(error))
	FigureDrawing(_) => leaf(Invariant, "figure_drawing", "FigureDrawing", Str.inspect(error))
	FigureFitInvalid(_) => leaf(Invariant, "figure_fit_invalid", "FigureFitInvalid", Str.inspect(error))
	FurnitureInline(_) => leaf(Invariant, "furniture_inline", "FurnitureInline", Str.inspect(error))
	InlineDepthExceeded(_) => leaf(Budget, "inline_depth_exceeded", "InlineDepthExceeded", Str.inspect(error))
	InvalidInlineLanguage(_) => leaf(Invariant, "invalid_inline_language", "InvalidInlineLanguage", Str.inspect(error))
	InvalidInlineUri({ error: cause, .. }) => leaf(document_navigation_error(cause).category, "invalid_inline_uri", "InvalidInlineUri", Str.inspect(error))
	InvalidList(_) => leaf(Invariant, "invalid_list", "InvalidList", Str.inspect(error))
	LineBreakPosition(_) => leaf(Invariant, "line_break_position", "LineBreakPosition", Str.inspect(error))
	ListDepthExceeded(_) => leaf(Budget, "list_depth_exceeded", "ListDepthExceeded", Str.inspect(error))
	ListItemBlock(_) => leaf(Invariant, "list_item_block", "ListItemBlock", Str.inspect(error))
	ListItemBreak(_) => leaf(Invariant, "list_item_break", "ListItemBreak", Str.inspect(error))
	ListItemDecoration(_) => leaf(Invariant, "list_item_decoration", "ListItemDecoration", Str.inspect(error))
	ListItemGroup(_) => leaf(Invariant, "list_item_group", "ListItemGroup", Str.inspect(error))
	ListItemSpacer(_) => leaf(Invariant, "list_item_spacer", "ListItemSpacer", Str.inspect(error))
	ListItemStart(_) => leaf(Invariant, "list_item_start", "ListItemStart", Str.inspect(error))
	ListNumbering(_) => leaf(Invariant, "list_numbering", "ListNumbering", Str.inspect(error))
	NegativeSpacer(_) => leaf(Invariant, "negative_spacer", "NegativeSpacer", Str.inspect(error))
	NestedLink(_) => leaf(Invariant, "nested_link", "NestedLink", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	BlockLimitExceeded(_) => leaf(Budget, "block_limit_exceeded", "BlockLimitExceeded", Str.inspect(error))
	Source(cause) => context("source", "Source", kernel_facade_sources_error(cause))
	TableCellEmpty(_) => leaf(Invariant, "table_cell_empty", "TableCellEmpty", Str.inspect(error))
	TableEmpty(_) => leaf(Invariant, "table_empty", "TableEmpty", Str.inspect(error))
	TableGridMismatch(_) => leaf(Invariant, "table_grid_mismatch", "TableGridMismatch", Str.inspect(error))
	TableHeaderMissing(_) => leaf(Invariant, "table_header_missing", "TableHeaderMissing", Str.inspect(error))
	TableRowSpan(_) => leaf(Invariant, "table_row_span", "TableRowSpan", Str.inspect(error))
	TextSemantics(cause) => context("text_semantics", "TextSemantics", kernel_text_semantics_error(cause))
	UnsupportedHeadingLevel(_) => leaf(Invariant, "unsupported_heading_level", "UnsupportedHeadingLevel", Str.inspect(error))
	HeadingSkip(_) => leaf(Invariant, "heading_skip", "HeadingSkip", Str.inspect(error))
}

kernel_facade_shape_error : KernelFacadeShape.Error -> KernelFacadeFailure.Failure
kernel_facade_shape_error = |error| match error {
	FontSelectionRejected(_) => leaf(Invariant, "font_selection_rejected", "FontSelectionRejected", Str.inspect(error))
	GeneratedLabelEvidenceInvalid(_) => leaf(Invariant, "generated_label_evidence_invalid", "GeneratedLabelEvidenceInvalid", Str.inspect(error))
	InlineClusterBoundary(_) => leaf(Invariant, "inline_cluster_boundary", "InlineClusterBoundary", Str.inspect(error))
	InvalidOccurrence(_) => leaf(Invariant, "invalid_occurrence", "InvalidOccurrence", Str.inspect(error))
	LanguageMismatch(_) => leaf(Invariant, "language_mismatch", "LanguageMismatch", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	OccurrenceCoverage(_) => leaf(Invariant, "occurrence_coverage", "OccurrenceCoverage", Str.inspect(error))
	PolicyInvalid(cause) => context("policy_invalid", "PolicyInvalid", font_policy_error(cause))
	ShapeFailure => leaf(Invariant, "shape_failure", "ShapeFailure", Str.inspect(error))
	StyleArithmeticOverflow(_) => leaf(Invariant, "style_arithmetic_overflow", "StyleArithmeticOverflow", Str.inspect(error))
	UndeclaredScript(_) => leaf(Invariant, "undeclared_script", "UndeclaredScript", Str.inspect(error))
	UnsupportedInlineScript(_) => leaf(Invariant, "unsupported_inline_script", "UnsupportedInlineScript", Str.inspect(error))
	UnsupportedThemeFace(_) => leaf(Invariant, "unsupported_theme_face", "UnsupportedThemeFace", Str.inspect(error))
	UnsupportedText(_) => leaf(Invariant, "unsupported_text", "UnsupportedText", Str.inspect(error))
}

kernel_facade_text_error : KernelFacadeText.Error -> KernelFacadeFailure.Failure
kernel_facade_text_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	InvalidCluster(_) => leaf(Invariant, "invalid_cluster", "InvalidCluster", Str.inspect(error))
	InvalidGlyph(_) => leaf(Invariant, "invalid_glyph", "InvalidGlyph", Str.inspect(error))
	InvalidLine(_) => leaf(Invariant, "invalid_line", "InvalidLine", Str.inspect(error))
	InvalidPage(_) => leaf(Invariant, "invalid_page", "InvalidPage", Str.inspect(error))
	InvalidPlacement(_) => leaf(Invariant, "invalid_placement", "InvalidPlacement", Str.inspect(error))
	InvalidRun(_) => leaf(Invariant, "invalid_run", "InvalidRun", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	UnsupportedRunEvidence(_) => leaf(Invariant, "unsupported_run_evidence", "UnsupportedRunEvidence", Str.inspect(error))
}

document_navigation_error : Document.NavigationError -> KernelFacadeFailure.Failure
document_navigation_error = |error| match error {
	NavigationPlanContextMismatch => leaf(Invariant, "navigation_plan_context_mismatch", "NavigationPlanContextMismatch", Str.inspect(error))
	AnnotationCountMismatch(_) => leaf(Invariant, "annotation_count_mismatch", "AnnotationCountMismatch", Str.inspect(error))
	AnnotationLimitExceeded(_) => leaf(Budget, "annotation_limit_exceeded", "AnnotationLimitExceeded", Str.inspect(error))
	AnnotationPageOutOfRange(_) => leaf(Invariant, "annotation_page_out_of_range", "AnnotationPageOutOfRange", Str.inspect(error))
	AppearanceFormOutOfRange(_) => leaf(Invariant, "appearance_form_out_of_range", "AppearanceFormOutOfRange", Str.inspect(error))
	AppearanceGeometryMismatch(_) => leaf(Invariant, "appearance_geometry_mismatch", "AppearanceGeometryMismatch", Str.inspect(error))
	AppearanceTextUnsupported(_) => leaf(Invariant, "appearance_text_unsupported", "AppearanceTextUnsupported", Str.inspect(error))
	DescriptionEmpty(_) => leaf(Invariant, "description_empty", "DescriptionEmpty", Str.inspect(error))
	DescriptionTooLong(_) => leaf(Invariant, "description_too_long", "DescriptionTooLong", Str.inspect(error))
	DestinationAnchorOutOfRange(_) => leaf(Invariant, "destination_anchor_out_of_range", "DestinationAnchorOutOfRange", Str.inspect(error))
	DestinationLimitExceeded(_) => leaf(Budget, "destination_limit_exceeded", "DestinationLimitExceeded", Str.inspect(error))
	DestinationNameEmpty(_) => leaf(Invariant, "destination_name_empty", "DestinationNameEmpty", Str.inspect(error))
	DestinationNameInvalidByte(_) => leaf(Invariant, "destination_name_invalid_byte", "DestinationNameInvalidByte", Str.inspect(error))
	DestinationNameTooLong(_) => leaf(Invariant, "destination_name_too_long", "DestinationNameTooLong", Str.inspect(error))
	DestinationTargetMismatch(_) => leaf(Invariant, "destination_target_mismatch", "DestinationTargetMismatch", Str.inspect(error))
	DestinationTargetOutOfRange(_) => leaf(Invariant, "destination_target_out_of_range", "DestinationTargetOutOfRange", Str.inspect(error))
	DuplicateDestinationName(_) => leaf(Invariant, "duplicate_destination_name", "DuplicateDestinationName", Str.inspect(error))
	DuplicateKeyboardOrder(_) => leaf(Invariant, "duplicate_keyboard_order", "DuplicateKeyboardOrder", Str.inspect(error))
	InvalidAnchorGeometry(_) => leaf(Invariant, "invalid_anchor_geometry", "InvalidAnchorGeometry", Str.inspect(error))
	InvalidAnnotationRect(_) => leaf(Invariant, "invalid_annotation_rect", "InvalidAnnotationRect", Str.inspect(error))
	InvalidQuad(_) => leaf(Invariant, "invalid_quad", "InvalidQuad", Str.inspect(error))
	KeyboardOrderOutOfRange(_) => leaf(Invariant, "keyboard_order_out_of_range", "KeyboardOrderOutOfRange", Str.inspect(error))
	LabelLimitExceeded(_) => leaf(Budget, "label_limit_exceeded", "LabelLimitExceeded", Str.inspect(error))
	LabelNumberWithoutStyle(_) => leaf(Invariant, "label_number_without_style", "LabelNumberWithoutStyle", Str.inspect(error))
	LabelPrefixTooLong(_) => leaf(Invariant, "label_prefix_too_long", "LabelPrefixTooLong", Str.inspect(error))
	LabelRangeNotAscending(_) => leaf(Invariant, "label_range_not_ascending", "LabelRangeNotAscending", Str.inspect(error))
	LabelStartNumberZero(_) => leaf(Invariant, "label_start_number_zero", "LabelStartNumberZero", Str.inspect(error))
	LabelStartPageNotZero(_) => leaf(Invariant, "label_start_page_not_zero", "LabelStartPageNotZero", Str.inspect(error))
	LabelStartPageOutOfRange(_) => leaf(Invariant, "label_start_page_out_of_range", "LabelStartPageOutOfRange", Str.inspect(error))
	OutlineDepthJump(_) => leaf(Invariant, "outline_depth_jump", "OutlineDepthJump", Str.inspect(error))
	OutlineDepthLimitExceeded(_) => leaf(Budget, "outline_depth_limit_exceeded", "OutlineDepthLimitExceeded", Str.inspect(error))
	OutlineDestinationUnknown(_) => leaf(Invariant, "outline_destination_unknown", "OutlineDestinationUnknown", Str.inspect(error))
	OutlineEntryLimitExceeded(_) => leaf(Budget, "outline_entry_limit_exceeded", "OutlineEntryLimitExceeded", Str.inspect(error))
	OutlineFirstDepthNonzero(_) => leaf(Invariant, "outline_first_depth_nonzero", "OutlineFirstDepthNonzero", Str.inspect(error))
	OutlineTitleEmpty(_) => leaf(Invariant, "outline_title_empty", "OutlineTitleEmpty", Str.inspect(error))
	OutlineTitleTooLong(_) => leaf(Invariant, "outline_title_too_long", "OutlineTitleTooLong", Str.inspect(error))
	QuadLimitExceeded(_) => leaf(Budget, "quad_limit_exceeded", "QuadLimitExceeded", Str.inspect(error))
	QuadOutsideRect(_) => leaf(Invariant, "quad_outside_rect", "QuadOutsideRect", Str.inspect(error))
	QuadsEmpty(_) => leaf(Invariant, "quads_empty", "QuadsEmpty", Str.inspect(error))
	UnknownDestinationName(_) => leaf(Invariant, "unknown_destination_name", "UnknownDestinationName", Str.inspect(error))
	UnresolvedDestinationAnchor(_) => leaf(Invariant, "unresolved_destination_anchor", "UnresolvedDestinationAnchor", Str.inspect(error))
	UriEmpty(_) => leaf(Invariant, "uri_empty", "UriEmpty", Str.inspect(error))
	UriInvalidByte(_) => leaf(Invariant, "uri_invalid_byte", "UriInvalidByte", Str.inspect(error))
	UriInvalidPercentEncoding(_) => leaf(Invariant, "uri_invalid_percent_encoding", "UriInvalidPercentEncoding", Str.inspect(error))
	UriMissingScheme(_) => leaf(Invariant, "uri_missing_scheme", "UriMissingScheme", Str.inspect(error))
	UriTooLong(_) => leaf(Invariant, "uri_too_long", "UriTooLong", Str.inspect(error))
}

kernel_text_semantics_error : KernelTextSemantics.Error -> KernelFacadeFailure.Failure
kernel_text_semantics_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	DuplicateTextPropertyOwnership(_) => leaf(Invariant, "duplicate_text_property_ownership", "DuplicateTextPropertyOwnership", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	OrphanTextProperty(_) => leaf(Invariant, "orphan_text_property", "OrphanTextProperty", Str.inspect(error))
	Semantic(cause) => context("semantic", "Semantic", kernel_semantics_error(cause))
	TextPropertySpanOutOfRange(_) => leaf(Invariant, "text_property_span_out_of_range", "TextPropertySpanOutOfRange", Str.inspect(error))
}

kernel_shape_error : KernelShape.Error -> KernelFacadeFailure.Failure
kernel_shape_error = |error| match error {
	AnalysisMismatch(_) => leaf(Invariant, "analysis_mismatch", "AnalysisMismatch", Str.inspect(error))
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	EmptySource => leaf(Invariant, "empty_source", "EmptySource", Str.inspect(error))
	InvalidSource(_) => leaf(Invariant, "invalid_source", "InvalidSource", Str.inspect(error))
	InvalidSize(_) => leaf(Invariant, "invalid_size", "InvalidSize", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	MetricFailure(_) => leaf(Invariant, "metric_failure", "MetricFailure", Str.inspect(error))
	MissingGlyph(_) => leaf(Invariant, "missing_glyph", "MissingGlyph", Str.inspect(error))
	NotdefGlyph(_) => leaf(Invariant, "notdef_glyph", "NotdefGlyph", Str.inspect(error))
	AdvancedClusterInvalid(_) => leaf(Invariant, "advanced_cluster_invalid", "AdvancedClusterInvalid", Str.inspect(error))
	SelectedRequestInvalid(_) => leaf(Invariant, "selected_request_invalid", "SelectedRequestInvalid", Str.inspect(error))
	BidiOrderInvalid(_) => leaf(Invariant, "bidi_order_invalid", "BidiOrderInvalid", Str.inspect(error))
	AdvancedGlyphInvalid(_) => leaf(Invariant, "advanced_glyph_invalid", "AdvancedGlyphInvalid", Str.inspect(error))
	AdvancedRunInvalid(_) => leaf(Invariant, "advanced_run_invalid", "AdvancedRunInvalid", Str.inspect(error))
	DuplicateGlyphReference(_) => leaf(Invariant, "duplicate_glyph_reference", "DuplicateGlyphReference", Str.inspect(error))
	GlyphOutsideRun(_) => leaf(Invariant, "glyph_outside_run", "GlyphOutsideRun", Str.inspect(error))
	InstanceMismatch(_) => leaf(Invariant, "instance_mismatch", "InstanceMismatch", Str.inspect(error))
	SelectedFaceMissing(_) => leaf(Invariant, "selected_face_missing", "SelectedFaceMissing", Str.inspect(error))
	SelectedFaceRangeMismatch(_) => leaf(Invariant, "selected_face_range_mismatch", "SelectedFaceRangeMismatch", Str.inspect(error))
	OccurrenceMismatch(_) => leaf(Invariant, "occurrence_mismatch", "OccurrenceMismatch", Str.inspect(error))
	ArtifactRunUnsupported(_) => leaf(Invariant, "artifact_run_unsupported", "ArtifactRunUnsupported", Str.inspect(error))
	UnreferencedGlyph(_) => leaf(Invariant, "unreferenced_glyph", "UnreferencedGlyph", Str.inspect(error))
	UnsupportedCluster(_) => leaf(Invariant, "unsupported_cluster", "UnsupportedCluster", Str.inspect(error))
	UnsupportedDirection(cause) => context("unsupported_direction", "UnsupportedDirection", text_direction(cause))
	UnsupportedScript(_) => leaf(Invariant, "unsupported_script", "UnsupportedScript", Str.inspect(error))
	UnsupportedWritingMode(cause) => context("unsupported_writing_mode", "UnsupportedWritingMode", text_writing_mode(cause))
}

kernel_facade_sources_error : KernelFacadeSources.Error -> KernelFacadeFailure.Failure
kernel_facade_sources_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	EmptySource(_) => leaf(Invariant, "empty_source", "EmptySource", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	TableExhausted => leaf(Invariant, "table_exhausted", "TableExhausted", Str.inspect(error))
	Unicode(cause) => context("unicode", "Unicode", kernel_unicode_unicode_error(cause))
}

kernel_facade_labels_owner : KernelFacadeLabels.Owner -> KernelFacadeFailure.Failure
kernel_facade_labels_owner = |error| match error {
	FigureOwner(_) => leaf(Invariant, "figure_owner", "FigureOwner", Str.inspect(error))
	PanelOwner(_) => leaf(Invariant, "panel_owner", "PanelOwner", Str.inspect(error))
}

kernel_line_layout_error : KernelLineLayout.Error -> KernelFacadeFailure.Failure
kernel_line_layout_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	InvalidAnalysis => leaf(Invariant, "invalid_analysis", "InvalidAnalysis", Str.inspect(error))
	InvalidCluster(_) => leaf(Invariant, "invalid_cluster", "InvalidCluster", Str.inspect(error))
	InvalidGlyphAdvance(_) => leaf(Invariant, "invalid_glyph_advance", "InvalidGlyphAdvance", Str.inspect(error))
	InvalidRun(_) => leaf(Invariant, "invalid_run", "InvalidRun", Str.inspect(error))
	InvalidWidth(_) => leaf(Invariant, "invalid_width", "InvalidWidth", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	TableExhausted => leaf(Invariant, "table_exhausted", "TableExhausted", Str.inspect(error))
	Unbreakable(_) => leaf(Invariant, "unbreakable", "Unbreakable", Str.inspect(error))
	SourceUnbreakable(_) => leaf(Invariant, "source_unbreakable", "SourceUnbreakable", Str.inspect(error))
}

kernel_facade_tables_error : KernelFacadeTables.Error -> KernelFacadeFailure.Failure
kernel_facade_tables_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	InvalidCell(_) => leaf(Invariant, "invalid_cell", "InvalidCell", Str.inspect(error))
	Measure(cause) => context("measure", "Measure", kernel_line_layout_error(cause))
	TableWidth(_) => leaf(Invariant, "table_width", "TableWidth", Str.inspect(error))
	UnbreakableToken(_) => leaf(Invariant, "unbreakable_token", "UnbreakableToken", Str.inspect(error))
	UnbreakableItems(_) => leaf(Invariant, "unbreakable_items", "UnbreakableItems", Str.inspect(error))
}

kernel_content_error : KernelContent.Error -> KernelFacadeFailure.Failure
kernel_content_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	ContentStreamCountMismatch(_) => leaf(Invariant, "content_stream_count_mismatch", "ContentStreamCountMismatch", Str.inspect(error))
	FormPlacementInvalid(_) => leaf(Invariant, "form_placement_invalid", "FormPlacementInvalid", Str.inspect(error))
	FragmentStreamMismatch(_) => leaf(Invariant, "fragment_stream_mismatch", "FragmentStreamMismatch", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	MissingMarkedFragment(_) => leaf(Invariant, "missing_marked_fragment", "MissingMarkedFragment", Str.inspect(error))
	TextRunInvalid(_) => leaf(Invariant, "text_run_invalid", "TextRunInvalid", Str.inspect(error))
	UnsupportedValidatedCommand(_) => leaf(Invariant, "unsupported_validated_command", "UnsupportedValidatedCommand", Str.inspect(error))
}

kernel_font_objects_error : KernelFontObjects.Error -> KernelFacadeFailure.Failure
kernel_font_objects_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	NoFonts => leaf(Invariant, "no_fonts", "NoFonts", Str.inspect(error))
}

kernel_font_plan_error : KernelFontPlan.Error -> KernelFacadeFailure.Failure
kernel_font_plan_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	FontFailure(cause) => context("font_failure", "FontFailure", kernel_font_error(cause))
	GlyphOutOfRange(_) => leaf(Invariant, "glyph_out_of_range", "GlyphOutOfRange", Str.inspect(error))
	GlyphZeroUsed(_) => leaf(Invariant, "glyph_zero_used", "GlyphZeroUsed", Str.inspect(error))
	RetainedGlyphLimitExceeded(_) => leaf(Budget, "retained_glyph_limit_exceeded", "RetainedGlyphLimitExceeded", Str.inspect(error))
}

kernel_object_plan_error : KernelObjectPlan.Error -> KernelFacadeFailure.Failure
kernel_object_plan_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	PageCountZero => leaf(Invariant, "page_count_zero", "PageCountZero", Str.inspect(error))
	ResourceCountMismatch(_) => leaf(Invariant, "resource_count_mismatch", "ResourceCountMismatch", Str.inspect(error))
	Shape(cause) => context("shape", "Shape", kernel_balanced_error(cause))
}

kernel_resource_use_error : KernelResourceUse.Error -> KernelFacadeFailure.Failure
kernel_resource_use_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	ColorComponentMismatch(_) => leaf(Invariant, "color_component_mismatch", "ColorComponentMismatch", Str.inspect(error))
	CountMismatch(_) => leaf(Invariant, "count_mismatch", "CountMismatch", Str.inspect(error))
	OrphanResource(_) => leaf(Invariant, "orphan_resource", "OrphanResource", Str.inspect(error))
	ShadingStopComponentMismatch(_) => leaf(Invariant, "shading_stop_component_mismatch", "ShadingStopComponentMismatch", Str.inspect(error))
}

kernel_tagged_text_structure_error : KernelTaggedTextStructure.Error -> KernelFacadeFailure.Failure
kernel_tagged_text_structure_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	Font(cause) => context("font", "Font", kernel_pdf_font_error(cause))
	FontCountMismatch(_) => leaf(Invariant, "font_count_mismatch", "FontCountMismatch", Str.inspect(error))
	Identity(cause) => context("identity", "Identity", kernel_identity_error(cause))
	IntentProfileUnplanned(_) => leaf(Invariant, "intent_profile_unplanned", "IntentProfileUnplanned", Str.inspect(error))
	Navigation(cause) => context("navigation", "Navigation", document_navigation_error(cause))
	NavigationObjects(cause) => context("navigation_objects", "NavigationObjects", kernel_navigation_objects_error(cause))
	Object(cause) => context("object", "Object", kernel_object_error(cause))
	ObjectCountMismatch(_) => leaf(Invariant, "object_count_mismatch", "ObjectCountMismatch", Str.inspect(error))
	ObjectOrder(_) => leaf(Invariant, "object_order", "ObjectOrder", Str.inspect(error))
	OutputBound(cause) => context("output_bound", "OutputBound", kernel_output_bound_error(cause))
	Pages(cause) => context("pages", "Pages", kernel_page_objects_error(cause))
	Resources(cause) => context("resources", "Resources", kernel_resource_objects_error(cause))
	Seal(cause) => context("seal", "Seal", kernel_seal_error(cause))
	TaggedObjects(cause) => context("tagged_objects", "TaggedObjects", kernel_tagged_objects_error(cause))
}

kernel_font_subset_error : KernelFontSubset.Error -> KernelFacadeFailure.Failure
kernel_font_subset_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	InvalidPlan => leaf(Invariant, "invalid_plan", "InvalidPlan", Str.inspect(error))
	MissingSourceTable(_) => leaf(Invariant, "missing_source_table", "MissingSourceTable", Str.inspect(error))
	UnmappedComposite(_) => leaf(Invariant, "unmapped_composite", "UnmappedComposite", Str.inspect(error))
}

kernel_pdf_text_error : KernelPdfText.Error -> KernelFacadeFailure.Failure
kernel_pdf_text_error = |error| match error {
	ActualTextRequired(_) => leaf(Invariant, "actual_text_required", "ActualTextRequired", Str.inspect(error))
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	ClusterInvalid(_) => leaf(Invariant, "cluster_invalid", "ClusterInvalid", Str.inspect(error))
	FontPlanInvalid(_) => leaf(Invariant, "font_plan_invalid", "FontPlanInvalid", Str.inspect(error))
	GlyphNotRetained(_) => leaf(Invariant, "glyph_not_retained", "GlyphNotRetained", Str.inspect(error))
	IncompleteUnicodeMapping(_) => leaf(Invariant, "incomplete_unicode_mapping", "IncompleteUnicodeMapping", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	OccurrenceInvalid(_) => leaf(Invariant, "occurrence_invalid", "OccurrenceInvalid", Str.inspect(error))
	PlacementInvalid(_) => leaf(Invariant, "placement_invalid", "PlacementInvalid", Str.inspect(error))
	RunInvalid(_) => leaf(Invariant, "run_invalid", "RunInvalid", Str.inspect(error))
	UnicodeMappingConflict(_) => leaf(Invariant, "unicode_mapping_conflict", "UnicodeMappingConflict", Str.inspect(error))
}

kernel_page_layout_error : KernelPageLayout.Error -> KernelFacadeFailure.Failure
kernel_page_layout_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	InvalidBlock(_) => leaf(Invariant, "invalid_block", "InvalidBlock", Str.inspect(error))
	InvalidConstraints => leaf(Invariant, "invalid_constraints", "InvalidConstraints", Str.inspect(error))
	InvalidGroup(_) => leaf(Invariant, "invalid_group", "InvalidGroup", Str.inspect(error))
	InvalidLine(_) => leaf(Invariant, "invalid_line", "InvalidLine", Str.inspect(error))
	KeepConflict(cause) => context("keep_conflict", "KeepConflict", kernel_page_layout_conflict(cause))
	LeadOverflow(_) => leaf(Invariant, "lead_overflow", "LeadOverflow", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	Oversize(_) => leaf(Invariant, "oversize", "Oversize", Str.inspect(error))
}

kernel_facade_reference_shape_error : KernelFacadeReferenceShape.Error -> KernelFacadeFailure.Failure
kernel_facade_reference_shape_error = |error| match error {
	InvalidLiteral(_) => leaf(Invariant, "invalid_literal", "InvalidLiteral", Str.inspect(error))
	InvalidSelection => leaf(Invariant, "invalid_selection", "InvalidSelection", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	Shape(cause) => context("shape", "Shape", kernel_shape_error(cause))
	Style(cause) => context("style", "Style", kernel_facade_shape_error(cause))
}

kernel_facade_reference_lines_error : KernelFacadeReferenceLines.Error -> KernelFacadeFailure.Failure
kernel_facade_reference_lines_error = |error| match error {
	InvalidContext(_) => leaf(Invariant, "invalid_context", "InvalidContext", Str.inspect(error))
	ContentsGeometry(_) => leaf(Invariant, "contents_geometry", "ContentsGeometry", Str.inspect(error))
	LimitExceeded => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	Geometry(cause) => context("geometry", "Geometry", kernel_facade_lines_error(cause))
	Items({ error: cause, .. }) => leaf(kernel_reference_layout_error(cause).category, "items", "Items", Str.inspect(error))
	Tables(cause) => context("tables", "Tables", kernel_facade_tables_error(cause))
	SourceOverflow(_) => leaf(Invariant, "source_overflow", "SourceOverflow", Str.inspect(error))
}

kernel_color_error : KernelColor.Error -> KernelFacadeFailure.Failure
kernel_color_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	ComponentMismatch(_) => leaf(Invariant, "component_mismatch", "ComponentMismatch", Str.inspect(error))
	DeclaredSizeMismatch(_) => leaf(Invariant, "declared_size_mismatch", "DeclaredSizeMismatch", Str.inspect(error))
	DuplicateTagOwnership(_) => leaf(Invariant, "duplicate_tag_ownership", "DuplicateTagOwnership", Str.inspect(error))
	IndexOutOfRange(_) => leaf(Invariant, "index_out_of_range", "IndexOutOfRange", Str.inspect(error))
	InvalidCalibratedGray(_) => leaf(Invariant, "invalid_calibrated_gray", "InvalidCalibratedGray", Str.inspect(error))
	InvalidIccSignature(_) => leaf(Invariant, "invalid_icc_signature", "InvalidIccSignature", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	NonDenseSpaceIdentity(_) => leaf(Invariant, "non_dense_space_identity", "NonDenseSpaceIdentity", Str.inspect(error))
	NonDenseProfileIdentity(_) => leaf(Invariant, "non_dense_profile_identity", "NonDenseProfileIdentity", Str.inspect(error))
	OrphanTag(_) => leaf(Invariant, "orphan_tag", "OrphanTag", Str.inspect(error))
	ProfileTooShort(_) => leaf(Invariant, "profile_too_short", "ProfileTooShort", Str.inspect(error))
	SpanOutOfRange(_) => leaf(Invariant, "span_out_of_range", "SpanOutOfRange", Str.inspect(error))
	TagRecordMismatch(_) => leaf(Invariant, "tag_record_mismatch", "TagRecordMismatch", Str.inspect(error))
	UnsupportedIccVersion(_) => leaf(Invariant, "unsupported_icc_version", "UnsupportedIccVersion", Str.inspect(error))
}

kernel_text_ownership_error : KernelTextOwnership.Error -> KernelFacadeFailure.Failure
kernel_text_ownership_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	ArtifactTextUnsupported(_) => leaf(Invariant, "artifact_text_unsupported", "ArtifactTextUnsupported", Str.inspect(error))
	ArtifactTextInFragment(_) => leaf(Invariant, "artifact_text_in_fragment", "ArtifactTextInFragment", Str.inspect(error))
	DuplicateRunOwnership(_) => leaf(Invariant, "duplicate_run_ownership", "DuplicateRunOwnership", Str.inspect(error))
	FragmentTextCoverageMismatch(_) => leaf(Invariant, "fragment_text_coverage_mismatch", "FragmentTextCoverageMismatch", Str.inspect(error))
	NonDenseRunIdentity(_) => leaf(Invariant, "non_dense_run_identity", "NonDenseRunIdentity", Str.inspect(error))
	OccurrenceMismatch(_) => leaf(Invariant, "occurrence_mismatch", "OccurrenceMismatch", Str.inspect(error))
	OrphanRun(_) => leaf(Invariant, "orphan_run", "OrphanRun", Str.inspect(error))
	RunIndexOutOfRange(_) => leaf(Invariant, "run_index_out_of_range", "RunIndexOutOfRange", Str.inspect(error))
	Tagged(cause) => context("tagged", "Tagged", kernel_tagged_error(cause))
}

kernel_scene_error : KernelScene.Error -> KernelFacadeFailure.Failure
kernel_scene_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	DashAllZero(_) => leaf(Invariant, "dash_all_zero", "DashAllZero", Str.inspect(error))
	DashLengthNegative(_) => leaf(Invariant, "dash_length_negative", "DashLengthNegative", Str.inspect(error))
	DashPhaseNegative(_) => leaf(Invariant, "dash_phase_negative", "DashPhaseNegative", Str.inspect(error))
	DuplicateOwnership(_) => leaf(Invariant, "duplicate_ownership", "DuplicateOwnership", Str.inspect(error))
	EmptyCommandRange(_) => leaf(Invariant, "empty_command_range", "EmptyCommandRange", Str.inspect(error))
	EmptyForm(_) => leaf(Invariant, "empty_form", "EmptyForm", Str.inspect(error))
	EmptyPath(_) => leaf(Invariant, "empty_path", "EmptyPath", Str.inspect(error))
	FormTransformSingular(_) => leaf(Invariant, "form_transform_singular", "FormTransformSingular", Str.inspect(error))
	Geometry(cause) => context("geometry", "Geometry", kernel_geometry_error(cause))
	IndexOutOfRange(_) => leaf(Invariant, "index_out_of_range", "IndexOutOfRange", Str.inspect(error))
	InvalidPathOrder(_) => leaf(Invariant, "invalid_path_order", "InvalidPathOrder", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	MiterLimitTooSmall(_) => leaf(Invariant, "miter_limit_too_small", "MiterLimitTooSmall", Str.inspect(error))
	NoPathPaint(_) => leaf(Invariant, "no_path_paint", "NoPathPaint", Str.inspect(error))
	NonDenseIdentity(_) => leaf(Invariant, "non_dense_identity", "NonDenseIdentity", Str.inspect(error))
	NonPositiveRect(_) => leaf(Invariant, "non_positive_rect", "NonPositiveRect", Str.inspect(error))
	Orphaned(_) => leaf(Invariant, "orphaned", "Orphaned", Str.inspect(error))
	SpanOutOfRange(_) => leaf(Invariant, "span_out_of_range", "SpanOutOfRange", Str.inspect(error))
	TextPaintInvalid(_) => leaf(Invariant, "text_paint_invalid", "TextPaintInvalid", Str.inspect(error))
	UnsupportedCommand(_) => leaf(Invariant, "unsupported_command", "UnsupportedCommand", Str.inspect(error))
	UnpaintedPath(_) => leaf(Invariant, "unpainted_path", "UnpaintedPath", Str.inspect(error))
	DegenerateShadingGeometry(_) => leaf(Invariant, "degenerate_shading_geometry", "DegenerateShadingGeometry", Str.inspect(error))
	EmptyPatternCell(_) => leaf(Invariant, "empty_pattern_cell", "EmptyPatternCell", Str.inspect(error))
	NegativeShadingRadius(_) => leaf(Invariant, "negative_shading_radius", "NegativeShadingRadius", Str.inspect(error))
	PatternInPatternCell(_) => leaf(Invariant, "pattern_in_pattern_cell", "PatternInPatternCell", Str.inspect(error))
	PatternMatrixSingular(_) => leaf(Invariant, "pattern_matrix_singular", "PatternMatrixSingular", Str.inspect(error))
	PatternStepInvalid(_) => leaf(Invariant, "pattern_step_invalid", "PatternStepInvalid", Str.inspect(error))
	ShadingStopEndpointInvalid(_) => leaf(Invariant, "shading_stop_endpoint_invalid", "ShadingStopEndpointInvalid", Str.inspect(error))
	ShadingStopsNotIncreasing(_) => leaf(Invariant, "shading_stops_not_increasing", "ShadingStopsNotIncreasing", Str.inspect(error))
	TextInPatternCell(_) => leaf(Invariant, "text_in_pattern_cell", "TextInPatternCell", Str.inspect(error))
	TooFewShadingStops(_) => leaf(Invariant, "too_few_shading_stops", "TooFewShadingStops", Str.inspect(error))
	TransparencyInPatternCell(_) => leaf(Invariant, "transparency_in_pattern_cell", "TransparencyInPatternCell", Str.inspect(error))
}

font_policy_error : Font.PolicyError -> KernelFacadeFailure.Failure
font_policy_error = |error| match error {
	AmbiguousFace(_) => leaf(Invariant, "ambiguous_face", "AmbiguousFace", Str.inspect(error))
	EmptyPolicy => leaf(Invariant, "empty_policy", "EmptyPolicy", Str.inspect(error))
	UnknownPolicy(_) => leaf(Invariant, "unknown_policy", "UnknownPolicy", Str.inspect(error))
	UnknownPolicyFace(_) => leaf(Invariant, "unknown_policy_face", "UnknownPolicyFace", Str.inspect(error))
}

kernel_semantics_error : KernelSemantics.Error -> KernelFacadeFailure.Failure
kernel_semantics_error = |error| match error {
	AnnotationLogicalOrderInvalid(_) => leaf(Invariant, "annotation_logical_order_invalid", "AnnotationLogicalOrderInvalid", Str.inspect(error))
	AnnotationOwnerMismatch(_) => leaf(Invariant, "annotation_owner_mismatch", "AnnotationOwnerMismatch", Str.inspect(error))
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	CaptionPosition(_) => leaf(Invariant, "caption_position", "CaptionPosition", Str.inspect(error))
	DuplicateChildRole(_) => leaf(Invariant, "duplicate_child_role", "DuplicateChildRole", Str.inspect(error))
	DuplicateElementIdentifier(_) => leaf(Invariant, "duplicate_element_identifier", "DuplicateElementIdentifier", Str.inspect(error))
	DuplicateOwnership(_) => leaf(Invariant, "duplicate_ownership", "DuplicateOwnership", Str.inspect(error))
	ElementIdentifierOrder(_) => leaf(Invariant, "element_identifier_order", "ElementIdentifierOrder", Str.inspect(error))
	EmptyElementIdentifier(_) => leaf(Invariant, "empty_element_identifier", "EmptyElementIdentifier", Str.inspect(error))
	FragmentRangeOutsideOccurrence(_) => leaf(Invariant, "fragment_range_outside_occurrence", "FragmentRangeOutsideOccurrence", Str.inspect(error))
	HeaderAssociationMismatch(_) => leaf(Invariant, "header_association_mismatch", "HeaderAssociationMismatch", Str.inspect(error))
	IllegalContainment(_) => leaf(Invariant, "illegal_containment", "IllegalContainment", Str.inspect(error))
	IllegalContentItem(_) => leaf(Invariant, "illegal_content_item", "IllegalContentItem", Str.inspect(error))
	IndexOutOfRange(_) => leaf(Invariant, "index_out_of_range", "IndexOutOfRange", Str.inspect(error))
	InvalidAttribute(_) => leaf(Invariant, "invalid_attribute", "InvalidAttribute", Str.inspect(error))
	InvalidContextualArtifactAttribute(_) => leaf(Invariant, "invalid_contextual_artifact_attribute", "InvalidContextualArtifactAttribute", Str.inspect(error))
	InvalidDocumentRoot(_) => leaf(Invariant, "invalid_document_root", "InvalidDocumentRoot", Str.inspect(error))
	InvalidLanguage(_) => leaf(Invariant, "invalid_language", "InvalidLanguage", Str.inspect(error))
	InvalidNodeTextProperty(_) => leaf(Invariant, "invalid_node_text_property", "InvalidNodeTextProperty", Str.inspect(error))
	InvalidParent(_) => leaf(Invariant, "invalid_parent", "InvalidParent", Str.inspect(error))
	InvalidPdf20Namespace => leaf(Invariant, "invalid_pdf20_namespace", "InvalidPdf20Namespace", Str.inspect(error))
	InvalidRelationship(_) => leaf(Invariant, "invalid_relationship", "InvalidRelationship", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	NonDenseIdentity(_) => leaf(Invariant, "non_dense_identity", "NonDenseIdentity", Str.inspect(error))
	Orphaned(_) => leaf(Invariant, "orphaned", "Orphaned", Str.inspect(error))
	SpanOutOfRange(_) => leaf(Invariant, "span_out_of_range", "SpanOutOfRange", Str.inspect(error))
	UnknownAttributeTarget(_) => leaf(Invariant, "unknown_attribute_target", "UnknownAttributeTarget", Str.inspect(error))
	UnsupportedAnnotation(_) => leaf(Invariant, "unsupported_annotation", "UnsupportedAnnotation", Str.inspect(error))
	UnsupportedRole(_) => leaf(Invariant, "unsupported_role", "UnsupportedRole", Str.inspect(error))
	UnsupportedStoreContent => leaf(Invariant, "unsupported_store_content", "UnsupportedStoreContent", Str.inspect(error))
	UnsupportedTextOccurrence(_) => leaf(Invariant, "unsupported_text_occurrence", "UnsupportedTextOccurrence", Str.inspect(error))
}

text_direction : Text.Direction -> KernelFacadeFailure.Failure
text_direction = |error| match error {
	LeftToRight => leaf(Invariant, "left_to_right", "LeftToRight", Str.inspect(error))
	RightToLeft => leaf(Invariant, "right_to_left", "RightToLeft", Str.inspect(error))
}

text_writing_mode : Text.WritingMode -> KernelFacadeFailure.Failure
text_writing_mode = |error| match error {
	Horizontal => leaf(Invariant, "horizontal", "Horizontal", Str.inspect(error))
	Vertical => leaf(Invariant, "vertical", "Vertical", Str.inspect(error))
}

kernel_unicode_unicode_error : KernelUnicode.UnicodeError -> KernelFacadeFailure.Failure
kernel_unicode_unicode_error = |error| match error {
	GraphemeLimitExceeded(_) => leaf(Budget, "grapheme_limit_exceeded", "GraphemeLimitExceeded", Str.inspect(error))
	InconsistentGraphemeRange(_) => leaf(Invariant, "inconsistent_grapheme_range", "InconsistentGraphemeRange", Str.inspect(error))
	LineBoundaryLimitExceeded(_) => leaf(Budget, "line_boundary_limit_exceeded", "LineBoundaryLimitExceeded", Str.inspect(error))
	ScalarLimitExceeded(_) => leaf(Budget, "scalar_limit_exceeded", "ScalarLimitExceeded", Str.inspect(error))
	ScriptRunLimitExceeded(_) => leaf(Budget, "script_run_limit_exceeded", "ScriptRunLimitExceeded", Str.inspect(error))
}

kernel_font_error : KernelFont.Error -> KernelFacadeFailure.Failure
kernel_font_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	ChecksumMismatch(_) => leaf(Invariant, "checksum_mismatch", "ChecksumMismatch", Str.inspect(error))
	CmapLimitExceeded(_) => leaf(Budget, "cmap_limit_exceeded", "CmapLimitExceeded", Str.inspect(error))
	CompositeCycle => leaf(Invariant, "composite_cycle", "CompositeCycle", Str.inspect(error))
	CompositeDepthMismatch(_) => leaf(Invariant, "composite_depth_mismatch", "CompositeDepthMismatch", Str.inspect(error))
	DuplicateOrUnorderedTable(_) => leaf(Invariant, "duplicate_or_unordered_table", "DuplicateOrUnorderedTable", Str.inspect(error))
	FontChecksumMismatch(_) => leaf(Invariant, "font_checksum_mismatch", "FontChecksumMismatch", Str.inspect(error))
	InvalidCmap => leaf(Invariant, "invalid_cmap", "InvalidCmap", Str.inspect(error))
	InvalidDirectory => leaf(Invariant, "invalid_directory", "InvalidDirectory", Str.inspect(error))
	InvalidEmbeddingRights(_) => leaf(Invariant, "invalid_embedding_rights", "InvalidEmbeddingRights", Str.inspect(error))
	InvalidHead => leaf(Invariant, "invalid_head", "InvalidHead", Str.inspect(error))
	InvalidHorizontalMetrics => leaf(Invariant, "invalid_horizontal_metrics", "InvalidHorizontalMetrics", Str.inspect(error))
	InvalidGlyph(_) => leaf(Invariant, "invalid_glyph", "InvalidGlyph", Str.inspect(error))
	InvalidLoca => leaf(Invariant, "invalid_loca", "InvalidLoca", Str.inspect(error))
	InvalidMaxp => leaf(Invariant, "invalid_maxp", "InvalidMaxp", Str.inspect(error))
	InvalidName => leaf(Invariant, "invalid_name", "InvalidName", Str.inspect(error))
	InvalidOs2 => leaf(Invariant, "invalid_os2", "InvalidOs2", Str.inspect(error))
	InvalidTableRange(_) => leaf(Invariant, "invalid_table_range", "InvalidTableRange", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	MissingTable(_) => leaf(Invariant, "missing_table", "MissingTable", Str.inspect(error))
	OverlappingTables(_) => leaf(Invariant, "overlapping_tables", "OverlappingTables", Str.inspect(error))
	UnsupportedFontProgram(_) => leaf(Invariant, "unsupported_font_program", "UnsupportedFontProgram", Str.inspect(error))
}

kernel_balanced_error : KernelBalanced.Error -> KernelFacadeFailure.Failure
kernel_balanced_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	ItemCountZero => leaf(Invariant, "item_count_zero", "ItemCountZero", Str.inspect(error))
	ItemLimitExceeded(_) => leaf(Budget, "item_limit_exceeded", "ItemLimitExceeded", Str.inspect(error))
}

kernel_pdf_font_error : KernelPdfFont.Error -> KernelFacadeFailure.Failure
kernel_pdf_font_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	IncompleteUnicodeMapping(_) => leaf(Invariant, "incomplete_unicode_mapping", "IncompleteUnicodeMapping", Str.inspect(error))
	InvalidDescriptor => leaf(Invariant, "invalid_descriptor", "InvalidDescriptor", Str.inspect(error))
	InvalidFontPlan => leaf(Invariant, "invalid_font_plan", "InvalidFontPlan", Str.inspect(error))
	InvalidPostScriptName => leaf(Invariant, "invalid_post_script_name", "InvalidPostScriptName", Str.inspect(error))
	InvalidSubset => leaf(Invariant, "invalid_subset", "InvalidSubset", Str.inspect(error))
	InvalidUnicodeScalar(_) => leaf(Invariant, "invalid_unicode_scalar", "InvalidUnicodeScalar", Str.inspect(error))
	Object(cause) => context("object", "Object", kernel_object_error(cause))
	UnexpectedUnicodeMapping(_) => leaf(Invariant, "unexpected_unicode_mapping", "UnexpectedUnicodeMapping", Str.inspect(error))
	UnicodeMappingLimitExceeded(_) => leaf(Budget, "unicode_mapping_limit_exceeded", "UnicodeMappingLimitExceeded", Str.inspect(error))
}

kernel_identity_error : KernelIdentity.Error -> KernelFacadeFailure.Failure
kernel_identity_error = |error| match error {
	Hash(cause) => context("hash", "Hash", kernel_sha256_error(cause))
	WorkOverflow => leaf(Invariant, "work_overflow", "WorkOverflow", Str.inspect(error))
}

kernel_navigation_objects_error : KernelNavigationObjects.Error -> KernelFacadeFailure.Failure
kernel_navigation_objects_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	Index(cause) => context("index", "Index", kernel_index_error(cause))
	Object(cause) => context("object", "Object", kernel_object_error(cause))
	ObjectOrder(_) => leaf(Invariant, "object_order", "ObjectOrder", Str.inspect(error))
	Outline(cause) => context("outline", "Outline", kernel_outline_error(cause))
	Shape(cause) => context("shape", "Shape", kernel_balanced_error(cause))
}

kernel_object_error : KernelObject.Error -> KernelFacadeFailure.Failure
kernel_object_error = |error| match error {
	DuplicateDictionaryKey(_) => leaf(Invariant, "duplicate_dictionary_key", "DuplicateDictionaryKey", Str.inspect(error))
	IndexOutOfRange(_) => leaf(Invariant, "index_out_of_range", "IndexOutOfRange", Str.inspect(error))
	Lexical(cause) => context("lexical", "Lexical", kernel_lex_error(cause))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	NonMonotonicDictionaryKeys(_) => leaf(Invariant, "non_monotonic_dictionary_keys", "NonMonotonicDictionaryKeys", Str.inspect(error))
	ObjectNumberZero => leaf(Invariant, "object_number_zero", "ObjectNumberZero", Str.inspect(error))
	Overflow(cause) => context("overflow", "Overflow", kernel_object_dimension(cause))
}

kernel_output_bound_error : KernelOutputBound.Error -> KernelFacadeFailure.Failure
kernel_output_bound_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	Deflate(cause) => context("deflate", "Deflate", kernel_deflate_error(cause))
	NestedStreamValue(_) => leaf(Invariant, "nested_stream_value", "NestedStreamValue", Str.inspect(error))
	XrefObjectMismatch(_) => leaf(Invariant, "xref_object_mismatch", "XrefObjectMismatch", Str.inspect(error))
}

kernel_page_objects_error : KernelPageObjects.Error -> KernelFacadeFailure.Failure
kernel_page_objects_error = |error| match error {
	Object(cause) => context("object", "Object", kernel_object_error(cause))
	ObjectOrder(_) => leaf(Invariant, "object_order", "ObjectOrder", Str.inspect(error))
}

kernel_resource_objects_error : KernelResourceObjects.Error -> KernelFacadeFailure.Failure
kernel_resource_objects_error = |error| match error {
	Object(cause) => context("object", "Object", kernel_object_error(cause))
	ObjectOrder(_) => leaf(Invariant, "object_order", "ObjectOrder", Str.inspect(error))
}

kernel_seal_error : KernelSeal.Error -> KernelFacadeFailure.Failure
kernel_seal_error = |error| match error {
	IndexOutOfRange(_) => leaf(Invariant, "index_out_of_range", "IndexOutOfRange", Str.inspect(error))
	ObjectOrder(_) => leaf(Invariant, "object_order", "ObjectOrder", Str.inspect(error))
	PayloadLastUseInvalid(_) => leaf(Invariant, "payload_last_use_invalid", "PayloadLastUseInvalid", Str.inspect(error))
	PayloadUseMissing(_) => leaf(Invariant, "payload_use_missing", "PayloadUseMissing", Str.inspect(error))
	ReferenceOutOfRange(_) => leaf(Invariant, "reference_out_of_range", "ReferenceOutOfRange", Str.inspect(error))
	SpanOutOfRange(_) => leaf(Invariant, "span_out_of_range", "SpanOutOfRange", Str.inspect(error))
	SpanOverflow(cause) => context("span_overflow", "SpanOverflow", kernel_seal_store_kind(cause))
	StreamLengthNotAdjacent(_) => leaf(Invariant, "stream_length_not_adjacent", "StreamLengthNotAdjacent", Str.inspect(error))
	StreamLengthObjectMismatch(_) => leaf(Invariant, "stream_length_object_mismatch", "StreamLengthObjectMismatch", Str.inspect(error))
	StreamObjectMismatch(_) => leaf(Invariant, "stream_object_mismatch", "StreamObjectMismatch", Str.inspect(error))
	WorkOverflow => leaf(Invariant, "work_overflow", "WorkOverflow", Str.inspect(error))
}

kernel_tagged_objects_error : KernelTaggedObjects.Error -> KernelFacadeFailure.Failure
kernel_tagged_objects_error = |error| match error {
	AnnotationObjectUnplanned(_) => leaf(Invariant, "annotation_object_unplanned", "AnnotationObjectUnplanned", Str.inspect(error))
	IdTree(cause) => context("id_tree", "IdTree", kernel_navigation_objects_error(cause))
	IdTreeIndex(cause) => context("id_tree_index", "IdTreeIndex", kernel_index_error(cause))
	IdTreeUnplanned(_) => leaf(Invariant, "id_tree_unplanned", "IdTreeUnplanned", Str.inspect(error))
	InvalidFigureAlternative(_) => leaf(Invariant, "invalid_figure_alternative", "InvalidFigureAlternative", Str.inspect(error))
	Object(cause) => context("object", "Object", kernel_object_error(cause))
	ObjectOrder(_) => leaf(Invariant, "object_order", "ObjectOrder", Str.inspect(error))
}

kernel_page_layout_conflict : KernelPageLayout.Conflict -> KernelFacadeFailure.Failure
kernel_page_layout_conflict = |error| match error {
	BreakAfterRequiredKeep(_) => leaf(Invariant, "break_after_required_keep", "BreakAfterRequiredKeep", Str.inspect(error))
	BreakInsideGroup(_) => leaf(Invariant, "break_inside_group", "BreakInsideGroup", Str.inspect(error))
	ChainTooTall(_) => leaf(Invariant, "chain_too_tall", "ChainTooTall", Str.inspect(error))
	GroupTooTall(_) => leaf(Invariant, "group_too_tall", "GroupTooTall", Str.inspect(error))
	RequiredKeepAtEnd(_) => leaf(Invariant, "required_keep_at_end", "RequiredKeepAtEnd", Str.inspect(error))
}

kernel_tagged_error : KernelTagged.Error -> KernelFacadeFailure.Failure
kernel_tagged_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	DuplicateFragmentOwnership(_) => leaf(Invariant, "duplicate_fragment_ownership", "DuplicateFragmentOwnership", Str.inspect(error))
	FragmentPageMismatch(_) => leaf(Invariant, "fragment_page_mismatch", "FragmentPageMismatch", Str.inspect(error))
	IndexOutOfRange(_) => leaf(Invariant, "index_out_of_range", "IndexOutOfRange", Str.inspect(error))
	OccurrenceHasNoFragments(_) => leaf(Invariant, "occurrence_has_no_fragments", "OccurrenceHasNoFragments", Str.inspect(error))
	OrphanFragment(_) => leaf(Invariant, "orphan_fragment", "OrphanFragment", Str.inspect(error))
	PageCountMismatch(_) => leaf(Invariant, "page_count_mismatch", "PageCountMismatch", Str.inspect(error))
}

kernel_geometry_error : KernelGeometry.Error -> KernelFacadeFailure.Failure
kernel_geometry_error = |error| match error {
	BoxOutside(_) => leaf(Invariant, "box_outside", "BoxOutside", Str.inspect(error))
	CoordinateOverflow => leaf(Invariant, "coordinate_overflow", "CoordinateOverflow", Str.inspect(error))
	NonPositiveBox(cause) => context("non_positive_box", "NonPositiveBox", kernel_geometry_box_kind(cause))
}

kernel_sha256_error : KernelSha256.Error -> KernelFacadeFailure.Failure
kernel_sha256_error = |error| match error {
	InputTooLarge => leaf(Invariant, "input_too_large", "InputTooLarge", Str.inspect(error))
}

kernel_index_error : KernelIndex.Error -> KernelFacadeFailure.Failure
kernel_index_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	DuplicateByteKey(_) => leaf(Invariant, "duplicate_byte_key", "DuplicateByteKey", Str.inspect(error))
	DuplicateNumberKey(_) => leaf(Invariant, "duplicate_number_key", "DuplicateNumberKey", Str.inspect(error))
	EntryCountZero => leaf(Invariant, "entry_count_zero", "EntryCountZero", Str.inspect(error))
	EntryLimitExceeded(_) => leaf(Budget, "entry_limit_exceeded", "EntryLimitExceeded", Str.inspect(error))
	KeyBytesLimitExceeded(_) => leaf(Budget, "key_bytes_limit_exceeded", "KeyBytesLimitExceeded", Str.inspect(error))
	NegativeParentKey(_) => leaf(Invariant, "negative_parent_key", "NegativeParentKey", Str.inspect(error))
	NonMonotonicByteKey(_) => leaf(Invariant, "non_monotonic_byte_key", "NonMonotonicByteKey", Str.inspect(error))
	NonMonotonicNumberKey(_) => leaf(Invariant, "non_monotonic_number_key", "NonMonotonicNumberKey", Str.inspect(error))
	Shape(cause) => context("shape", "Shape", kernel_balanced_error(cause))
	ValueIndexOutOfRange(_) => leaf(Invariant, "value_index_out_of_range", "ValueIndexOutOfRange", Str.inspect(error))
}

kernel_outline_error : KernelOutline.Error -> KernelFacadeFailure.Failure
kernel_outline_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	DepthJump(_) => leaf(Invariant, "depth_jump", "DepthJump", Str.inspect(error))
	DepthLimitExceeded(_) => leaf(Budget, "depth_limit_exceeded", "DepthLimitExceeded", Str.inspect(error))
	EntryCountZero => leaf(Invariant, "entry_count_zero", "EntryCountZero", Str.inspect(error))
	EntryLimitExceeded(_) => leaf(Budget, "entry_limit_exceeded", "EntryLimitExceeded", Str.inspect(error))
	FirstDepthNonzero(_) => leaf(Invariant, "first_depth_nonzero", "FirstDepthNonzero", Str.inspect(error))
	TargetIndexOutOfRange(_) => leaf(Invariant, "target_index_out_of_range", "TargetIndexOutOfRange", Str.inspect(error))
	TitleIndexOutOfRange(_) => leaf(Invariant, "title_index_out_of_range", "TitleIndexOutOfRange", Str.inspect(error))
}

kernel_lex_error : KernelLex.Error -> KernelFacadeFailure.Failure
kernel_lex_error = |error| match error {
	DecimalScaleOutOfRange(_) => leaf(Invariant, "decimal_scale_out_of_range", "DecimalScaleOutOfRange", Str.inspect(error))
	NullNameByte(_) => leaf(Invariant, "null_name_byte", "NullNameByte", Str.inspect(error))
}

kernel_object_dimension : KernelObject.Dimension -> KernelFacadeFailure.Failure
kernel_object_dimension = |error| match error {
	ArrayItems => leaf(Invariant, "array_items", "ArrayItems", Str.inspect(error))
	ByteStringBytes => leaf(Invariant, "byte_string_bytes", "ByteStringBytes", Str.inspect(error))
	ByteStrings => leaf(Invariant, "byte_strings", "ByteStrings", Str.inspect(error))
	DictionaryEntries => leaf(Invariant, "dictionary_entries", "DictionaryEntries", Str.inspect(error))
	DirectDepth => leaf(Invariant, "direct_depth", "DirectDepth", Str.inspect(error))
	NameBytes => leaf(Invariant, "name_bytes", "NameBytes", Str.inspect(error))
	Names => leaf(Invariant, "names", "Names", Str.inspect(error))
	Objects => leaf(Invariant, "objects", "Objects", Str.inspect(error))
	PayloadBytes => leaf(Invariant, "payload_bytes", "PayloadBytes", Str.inspect(error))
	Payloads => leaf(Invariant, "payloads", "Payloads", Str.inspect(error))
	Streams => leaf(Invariant, "streams", "Streams", Str.inspect(error))
	TextStringBytes => leaf(Invariant, "text_string_bytes", "TextStringBytes", Str.inspect(error))
	TextStrings => leaf(Invariant, "text_strings", "TextStrings", Str.inspect(error))
	Values => leaf(Invariant, "values", "Values", Str.inspect(error))
	WorkUnits => leaf(Invariant, "work_units", "WorkUnits", Str.inspect(error))
}

kernel_deflate_error : KernelDeflate.Error -> KernelFacadeFailure.Failure
kernel_deflate_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	CompressorFailed => leaf(Invariant, "compressor_failed", "CompressorFailed", Str.inspect(error))
	InputLimitExceeded(_) => leaf(Budget, "input_limit_exceeded", "InputLimitExceeded", Str.inspect(error))
	OutputBoundExceeded(_) => leaf(Invariant, "output_bound_exceeded", "OutputBoundExceeded", Str.inspect(error))
	OutputLimitExceeded(_) => leaf(Budget, "output_limit_exceeded", "OutputLimitExceeded", Str.inspect(error))
}

kernel_seal_store_kind : KernelSeal.StoreKind -> KernelFacadeFailure.Failure
kernel_seal_store_kind = |error| match error {
	ArrayEdge => leaf(Invariant, "array_edge", "ArrayEdge", Str.inspect(error))
	ByteStringValue => leaf(Invariant, "byte_string_value", "ByteStringValue", Str.inspect(error))
	DictionaryEdge => leaf(Invariant, "dictionary_edge", "DictionaryEdge", Str.inspect(error))
	NameValue => leaf(Invariant, "name_value", "NameValue", Str.inspect(error))
	ObjectContent => leaf(Invariant, "object_content", "ObjectContent", Str.inspect(error))
	PayloadValue => leaf(Invariant, "payload_value", "PayloadValue", Str.inspect(error))
	StreamValue => leaf(Invariant, "stream_value", "StreamValue", Str.inspect(error))
	TextStringValue => leaf(Invariant, "text_string_value", "TextStringValue", Str.inspect(error))
}

kernel_geometry_box_kind : KernelGeometry.BoxKind -> KernelFacadeFailure.Failure
kernel_geometry_box_kind = |error| match error {
	ArtBox => leaf(Invariant, "art_box", "ArtBox", Str.inspect(error))
	BleedBox => leaf(Invariant, "bleed_box", "BleedBox", Str.inspect(error))
	CropBox => leaf(Invariant, "crop_box", "CropBox", Str.inspect(error))
	MediaBox => leaf(Invariant, "media_box", "MediaBox", Str.inspect(error))
	TrimBox => leaf(Invariant, "trim_box", "TrimBox", Str.inspect(error))
}

kernel_page_labels_error : KernelPageLabels.Error -> KernelFacadeFailure.Failure
kernel_page_labels_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	EmptyLabel => leaf(Invariant, "empty_label", "EmptyLabel", Str.inspect(error))
	InvalidPage => leaf(Invariant, "invalid_page", "InvalidPage", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
}

kernel_source_text_error : KernelSourceText.Error -> KernelFacadeFailure.Failure
kernel_source_text_error = |error| match error {
	BareCarriageReturn(_) => leaf(Invariant, "bare_carriage_return", "BareCarriageReturn", Str.inspect(error))
	ForegroundColor(_) => leaf(Invariant, "foreground_color", "ForegroundColor", Str.inspect(error))
	ForegroundRange(_) => leaf(Invariant, "foreground_range", "ForegroundRange", Str.inspect(error))
	InvalidTabWidth => leaf(Invariant, "invalid_tab_width", "InvalidTabWidth", Str.inspect(error))
	LimitExceeded(_) => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	TabRejected(_) => leaf(Invariant, "tab_rejected", "TabRejected", Str.inspect(error))
}

kernel_reference_layout_error : KernelReferenceLayout.Error -> KernelFacadeFailure.Failure
kernel_reference_layout_error = |error| match error {
	ArithmeticOverflow => leaf(Invariant, "arithmetic_overflow", "ArithmeticOverflow", Str.inspect(error))
	EmptyItems => leaf(Invariant, "empty_items", "EmptyItems", Str.inspect(error))
	InvalidAdvance(_) => leaf(Invariant, "invalid_advance", "InvalidAdvance", Str.inspect(error))
	InvalidFinalBoundary => leaf(Invariant, "invalid_final_boundary", "InvalidFinalBoundary", Str.inspect(error))
	InvalidLiteral(_) => leaf(Invariant, "invalid_literal", "InvalidLiteral", Str.inspect(error))
	InvalidWidth => leaf(Invariant, "invalid_width", "InvalidWidth", Str.inspect(error))
	LimitExceeded => leaf(Budget, "limit_exceeded", "LimitExceeded", Str.inspect(error))
	Unbreakable(_) => leaf(Invariant, "unbreakable", "Unbreakable", Str.inspect(error))
}

# Nested limits preserve the exact public feature and stage context.
expect {
	failure = KernelFacadeFailure.pipeline(Output(Structure(TaggedObjects(Object(LimitExceeded({ attempted: 8196, dimension: NameBytes, limit: 8192 }))))))
	failure.category == Budget and failure.feature == "output.structure.tagged_objects.object.limit_exceeded" and failure.path == "Output.Structure.TaggedObjects.Object.LimitExceeded" and failure.detail.contains("8196")
}

# Debug-like string payloads do not select category or feature.
expect {
	first = KernelFacadeFailure.pipeline(Labels(Shape(UnsupportedScript({ actual: "LimitExceeded({ attempted: 99, limit: 1 })", expected: "Latn", run: 0 }))))
	second = KernelFacadeFailure.pipeline(Labels(Shape(UnsupportedScript({ actual: "a different debug representation", expected: "Latn", run: 0 }))))
	first.category == Invariant and second.category == Invariant and first.feature == "labels.shape.unsupported_script" and first.feature == second.feature and first.path == second.path
}

# Both payload-bearing and payload-free invariant failures retain identity.
expect {
	run = KernelFacadeFailure.pipeline(Text(InvalidRun({ run: 4 })))
	subset = KernelFacadeFailure.pipeline(Output(Subset(ArithmeticOverflow)))
	run.category == Invariant and run.feature == "text.invalid_run" and run.path == "Text.InvalidRun" and subset.category == Invariant and subset.feature == "output.subset.arithmetic_overflow"
}

# A record-held cause supplies its category while its stable feature remains.
expect {
	failure = KernelFacadeFailure.pipeline(Pages(TableLayout({ error: LimitExceeded({ attempted: 2, dimension: Pages, limit: 1 }), groups: [], units: [] })))
	failure.category == Budget and failure.feature == "pages.table_layout" and failure.path == "Pages.TableLayout"
}

expect {
	failure = KernelFacadeFailure.pipeline(Output(Images(MarkerLimitExceeded({ attempted: 9, limit: 8, resource: 0 }))))
	failure.category == Budget and failure.feature == "output.images.marker_limit_exceeded" and failure.path == "Output.Images.MarkerLimitExceeded"
}

# A long inspected payload stays explanatory and bounded.
expect {
	failure = KernelFacadeFailure.pipeline(Labels(Shape(UnsupportedScript({ actual: "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz", expected: "Latn", run: 0 }))))
	failure.category == Invariant and failure.feature == "labels.shape.unsupported_script" and failure.detail.to_utf8().len() <= 163
}
