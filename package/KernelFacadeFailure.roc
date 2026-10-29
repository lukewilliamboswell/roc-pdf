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
context : { feature : Str, path : Str, cause : KernelFacadeFailure.Failure } -> KernelFacadeFailure.Failure
context = |{ feature, path, cause }| { ..cause, feature: "${feature}.${cause.feature}", path: "${path}.${cause.path}" }

## Diagnostic detail is explanatory and bounded. It cannot select a feature
## or category, including when strings contain text resembling error tags.
leaf : { category : [Budget, Invariant], feature : Str, path : Str, inspected : Str } -> KernelFacadeFailure.Failure
leaf = |{ category, feature, path, inspected }| {
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
	Fragments(cause) => context({ feature: "fragments", path: "Fragments", cause: kernel_facade_fragments_error(cause) })
	Furniture(cause) => context({ feature: "furniture", path: "Furniture", cause: kernel_facade_furniture_error(cause) })
	Labels(cause) => context({ feature: "labels", path: "Labels", cause: kernel_facade_labels_error(cause) })
	Lines(cause) => context({ feature: "lines", path: "Lines", cause: kernel_facade_lines_error(cause) })
	Output(cause) => context({ feature: "output", path: "Output", cause: kernel_facade_output_error(cause) })
	Pages(cause) => context({ feature: "pages", path: "Pages", cause: kernel_facade_pages_error(cause) })
	References(cause) => context({ feature: "references", path: "References", cause: kernel_facade_references_error(cause) })
	ReferenceBudget(_) => leaf({ category: Budget, feature: "reference_budget", path: "ReferenceBudget", inspected: Str.inspect(error) })
	ReferenceCycle(_) => leaf({ category: Invariant, feature: "reference_cycle", path: "ReferenceCycle", inspected: Str.inspect(error) })
	Scenes(cause) => context({ feature: "scenes", path: "Scenes", cause: kernel_facade_scenes_error(cause) })
	Semantics(cause) => context({ feature: "semantics", path: "Semantics", cause: kernel_facade_semantics_error(cause) })
	Shape(cause) => context({ feature: "shape", path: "Shape", cause: kernel_facade_shape_error(cause) })
	Text(cause) => context({ feature: "text", path: "Text", cause: kernel_facade_text_error(cause) })
}

kernel_image_error : KernelImage.Error -> KernelFacadeFailure.Failure
kernel_image_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	ColorComponentMismatch(_) => leaf({ category: Invariant, feature: "color_component_mismatch", path: "ColorComponentMismatch", inspected: Str.inspect(error) })
	ColorSpaceOutOfRange(_) => leaf({ category: Invariant, feature: "color_space_out_of_range", path: "ColorSpaceOutOfRange", inspected: Str.inspect(error) })
	DecodedLengthMismatch(_) => leaf({ category: Invariant, feature: "decoded_length_mismatch", path: "DecodedLengthMismatch", inspected: Str.inspect(error) })
	InvalidDimensions(_) => leaf({ category: Invariant, feature: "invalid_dimensions", path: "InvalidDimensions", inspected: Str.inspect(error) })
	InvalidExif(_) => leaf({ category: Invariant, feature: "invalid_exif", path: "InvalidExif", inspected: Str.inspect(error) })
	InvalidJpegMarker(_) => leaf({ category: Invariant, feature: "invalid_jpeg_marker", path: "InvalidJpegMarker", inspected: Str.inspect(error) })
	InvalidJpegSegment(_) => leaf({ category: Invariant, feature: "invalid_jpeg_segment", path: "InvalidJpegSegment", inspected: Str.inspect(error) })
	InvalidRowStride(_) => leaf({ category: Invariant, feature: "invalid_row_stride", path: "InvalidRowStride", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	MarkerLimitExceeded(_) => leaf({ category: Budget, feature: "marker_limit_exceeded", path: "MarkerLimitExceeded", inspected: Str.inspect(error) })
	NonDenseIdentity(_) => leaf({ category: Invariant, feature: "non_dense_identity", path: "NonDenseIdentity", inspected: Str.inspect(error) })
	OrientationRequiresTransform(_) => leaf({ category: Invariant, feature: "orientation_requires_transform", path: "OrientationRequiresTransform", inspected: Str.inspect(error) })
	UnsupportedJpegComponents(_) => leaf({ category: Invariant, feature: "unsupported_jpeg_components", path: "UnsupportedJpegComponents", inspected: Str.inspect(error) })
}

kernel_facade_fragments_error : KernelFacadeFragments.Error -> KernelFacadeFailure.Failure
kernel_facade_fragments_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	Navigation(cause) => context({ feature: "navigation", path: "Navigation", cause: document_navigation_error(cause) })
	InvalidOccurrence(_) => leaf({ category: Invariant, feature: "invalid_occurrence", path: "InvalidOccurrence", inspected: Str.inspect(error) })
	InvalidPage(_) => leaf({ category: Invariant, feature: "invalid_page", path: "InvalidPage", inspected: Str.inspect(error) })
	InvalidPlacement(_) => leaf({ category: Invariant, feature: "invalid_placement", path: "InvalidPlacement", inspected: Str.inspect(error) })
	InvalidPreliminaryFragments(_) => leaf({ category: Invariant, feature: "invalid_preliminary_fragments", path: "InvalidPreliminaryFragments", inspected: Str.inspect(error) })
	InvalidRun(_) => leaf({ category: Invariant, feature: "invalid_run", path: "InvalidRun", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	SourceRangeMismatch(_) => leaf({ category: Invariant, feature: "source_range_mismatch", path: "SourceRangeMismatch", inspected: Str.inspect(error) })
	TextSemantics(cause) => context({ feature: "text_semantics", path: "TextSemantics", cause: kernel_text_semantics_error(cause) })
}

kernel_facade_furniture_error : KernelFacadeFurniture.Error -> KernelFacadeFailure.Failure
kernel_facade_furniture_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	PageLabels(cause) => context({ feature: "page_labels", path: "PageLabels", cause: document_navigation_error(cause) })
	PageLabelText({ error: cause, .. }) => leaf({ category: kernel_page_labels_error(cause).category, feature: "page_label_text", path: "PageLabelText", inspected: Str.inspect(error) })
	ScopeInvalid(_) => leaf({ category: Invariant, feature: "scope_invalid", path: "ScopeInvalid", inspected: Str.inspect(error) })
	BodyEmpty => leaf({ category: Invariant, feature: "body_empty", path: "BodyEmpty", inspected: Str.inspect(error) })
	BodySpace(_) => leaf({ category: Invariant, feature: "body_space", path: "BodySpace", inspected: Str.inspect(error) })
	DrawingInvalid(_) => leaf({ category: Invariant, feature: "drawing_invalid", path: "DrawingInvalid", inspected: Str.inspect(error) })
	FieldOverflow(_) => leaf({ category: Invariant, feature: "field_overflow", path: "FieldOverflow", inspected: Str.inspect(error) })
	FurnitureInline(_) => leaf({ category: Invariant, feature: "furniture_inline", path: "FurnitureInline", inspected: Str.inspect(error) })
	GapNegative(_) => leaf({ category: Invariant, feature: "gap_negative", path: "GapNegative", inspected: Str.inspect(error) })
	InsetNegative(_) => leaf({ category: Invariant, feature: "inset_negative", path: "InsetNegative", inspected: Str.inspect(error) })
	InlineEmpty(_) => leaf({ category: Invariant, feature: "inline_empty", path: "InlineEmpty", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	FurnitureText(_) => leaf({ category: Invariant, feature: "furniture_text", path: "FurnitureText", inspected: Str.inspect(error) })
	FurnitureCluster(_) => leaf({ category: Invariant, feature: "furniture_cluster", path: "FurnitureCluster", inspected: Str.inspect(error) })
	RegionEmpty(_) => leaf({ category: Invariant, feature: "region_empty", path: "RegionEmpty", inspected: Str.inspect(error) })
	RegionOverflow(_) => leaf({ category: Invariant, feature: "region_overflow", path: "RegionOverflow", inspected: Str.inspect(error) })
	Selection(cause) => context({ feature: "selection", path: "Selection", cause: kernel_facade_shape_error(cause) })
	Shape(cause) => context({ feature: "shape", path: "Shape", cause: kernel_shape_error(cause) })
	SlotOverlap(_) => leaf({ category: Invariant, feature: "slot_overlap", path: "SlotOverlap", inspected: Str.inspect(error) })
	Sources(cause) => context({ feature: "sources", path: "Sources", cause: kernel_facade_sources_error(cause) })
	UnsupportedThemeFace(_) => leaf({ category: Invariant, feature: "unsupported_theme_face", path: "UnsupportedThemeFace", inspected: Str.inspect(error) })
}

kernel_facade_labels_error : KernelFacadeLabels.Error -> KernelFacadeFailure.Failure
kernel_facade_labels_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	InvalidPlacement(cause) => context({ feature: "invalid_placement", path: "InvalidPlacement", cause: kernel_facade_labels_owner(cause) })
	LabelBounds(_) => leaf({ category: Invariant, feature: "label_bounds", path: "LabelBounds", inspected: Str.inspect(error) })
	LabelText(_) => leaf({ category: Invariant, feature: "label_text", path: "LabelText", inspected: Str.inspect(error) })
	LabelPolicy => leaf({ category: Invariant, feature: "label_policy", path: "LabelPolicy", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	Shape(cause) => context({ feature: "shape", path: "Shape", cause: kernel_shape_error(cause) })
	Sources(cause) => context({ feature: "sources", path: "Sources", cause: kernel_facade_sources_error(cause) })
}

kernel_facade_lines_error : KernelFacadeLines.Error -> KernelFacadeFailure.Failure
kernel_facade_lines_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	SourceContentWidth(_) => leaf({ category: Invariant, feature: "source_content_width", path: "SourceContentWidth", inspected: Str.inspect(error) })
	SourceTokenTooWide(_) => leaf({ category: Invariant, feature: "source_token_too_wide", path: "SourceTokenTooWide", inspected: Str.inspect(error) })
	CalloutWidth(_) => leaf({ category: Invariant, feature: "callout_width", path: "CalloutWidth", inspected: Str.inspect(error) })
	CustomWidth(_) => leaf({ category: Invariant, feature: "custom_width", path: "CustomWidth", inspected: Str.inspect(error) })
	InvalidGeometry => leaf({ category: Invariant, feature: "invalid_geometry", path: "InvalidGeometry", inspected: Str.inspect(error) })
	InvalidRun(_) => leaf({ category: Invariant, feature: "invalid_run", path: "InvalidRun", inspected: Str.inspect(error) })
	LabelTooWide(_) => leaf({ category: Invariant, feature: "label_too_wide", path: "LabelTooWide", inspected: Str.inspect(error) })
	LineLayout(cause) => context({ feature: "line_layout", path: "LineLayout", cause: kernel_line_layout_error(cause) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	RunCoverage(_) => leaf({ category: Invariant, feature: "run_coverage", path: "RunCoverage", inspected: Str.inspect(error) })
	Tables(cause) => context({ feature: "tables", path: "Tables", cause: kernel_facade_tables_error(cause) })
}

kernel_facade_output_error : KernelFacadeOutput.Error -> KernelFacadeFailure.Failure
kernel_facade_output_error = |error| match error {
	Content(cause) => context({ feature: "content", path: "Content", cause: kernel_content_error(cause) })
	FontObjects(cause) => context({ feature: "font_objects", path: "FontObjects", cause: kernel_font_objects_error(cause) })
	FontPlan(cause) => context({ feature: "font_plan", path: "FontPlan", cause: kernel_font_plan_error(cause) })
	Images(cause) => context({ feature: "images", path: "Images", cause: kernel_image_error(cause) })
	Objects(cause) => context({ feature: "objects", path: "Objects", cause: kernel_object_plan_error(cause) })
	Resources(cause) => context({ feature: "resources", path: "Resources", cause: kernel_resource_use_error(cause) })
	Structure(cause) => context({ feature: "structure", path: "Structure", cause: kernel_tagged_text_structure_error(cause) })
	Subset(cause) => context({ feature: "subset", path: "Subset", cause: kernel_font_subset_error(cause) })
	Text(cause) => context({ feature: "text", path: "Text", cause: kernel_pdf_text_error(cause) })
}

kernel_facade_pages_error : KernelFacadePages.Error -> KernelFacadeFailure.Failure
kernel_facade_pages_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	CustomMeasureShort(_) => leaf({ category: Invariant, feature: "custom_measure_short", path: "CustomMeasureShort", inspected: Str.inspect(error) })
	CustomOversize(_) => leaf({ category: Invariant, feature: "custom_oversize", path: "CustomOversize", inspected: Str.inspect(error) })
	DecorationOversize(_) => leaf({ category: Invariant, feature: "decoration_oversize", path: "DecorationOversize", inspected: Str.inspect(error) })
	FigureOversize(_) => leaf({ category: Invariant, feature: "figure_oversize", path: "FigureOversize", inspected: Str.inspect(error) })
	FigureScaleFloor(_) => leaf({ category: Invariant, feature: "figure_scale_floor", path: "FigureScaleFloor", inspected: Str.inspect(error) })
	InvalidBlock(_) => leaf({ category: Invariant, feature: "invalid_block", path: "InvalidBlock", inspected: Str.inspect(error) })
	InvalidLine(_) => leaf({ category: Invariant, feature: "invalid_line", path: "InvalidLine", inspected: Str.inspect(error) })
	InvalidRun(_) => leaf({ category: Invariant, feature: "invalid_run", path: "InvalidRun", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	PageBreakPosition(_) => leaf({ category: Invariant, feature: "page_break_position", path: "PageBreakPosition", inspected: Str.inspect(error) })
	PageLayout(cause) => context({ feature: "page_layout", path: "PageLayout", cause: kernel_page_layout_error(cause) })
	TableLayout({ error: cause, .. }) => leaf({ category: kernel_page_layout_error(cause).category, feature: "table_layout", path: "TableLayout", inspected: Str.inspect(error) })
	TableRuleWidth(_) => leaf({ category: Invariant, feature: "table_rule_width", path: "TableRuleWidth", inspected: Str.inspect(error) })
}

kernel_facade_references_error : KernelFacadeReferences.Error -> KernelFacadeFailure.Failure
kernel_facade_references_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	Semantics(cause) => context({ feature: "semantics", path: "Semantics", cause: kernel_facade_semantics_error(cause) })
	Shape(cause) => context({ feature: "shape", path: "Shape", cause: kernel_facade_reference_shape_error(cause) })
	Lines(cause) => context({ feature: "lines", path: "Lines", cause: kernel_facade_reference_lines_error(cause) })
	Pages(cause) => context({ feature: "pages", path: "Pages", cause: kernel_facade_pages_error(cause) })
	Text(cause) => context({ feature: "text", path: "Text", cause: kernel_facade_text_error(cause) })
	Navigation(cause) => context({ feature: "navigation", path: "Navigation", cause: document_navigation_error(cause) })
	UnknownDestination(_) => leaf({ category: Invariant, feature: "unknown_destination", path: "UnknownDestination", inspected: Str.inspect(error) })
	MissingAnchor(_) => leaf({ category: Invariant, feature: "missing_anchor", path: "MissingAnchor", inspected: Str.inspect(error) })
	Format({ error: cause, .. }) => leaf({ category: kernel_page_labels_error(cause).category, feature: "format", path: "Format", inspected: Str.inspect(error) })
	FieldOverflow(_) => leaf({ category: Invariant, feature: "field_overflow", path: "FieldOverflow", inspected: Str.inspect(error) })
	InvalidMapping(_) => leaf({ category: Invariant, feature: "invalid_mapping", path: "InvalidMapping", inspected: Str.inspect(error) })
}

kernel_facade_scenes_error : KernelFacadeScenes.Error -> KernelFacadeFailure.Failure
kernel_facade_scenes_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	Color(cause) => context({ feature: "color", path: "Color", cause: kernel_color_error(cause) })
	InvalidPage(_) => leaf({ category: Invariant, feature: "invalid_page", path: "InvalidPage", inspected: Str.inspect(error) })
	InvalidPageSize => leaf({ category: Invariant, feature: "invalid_page_size", path: "InvalidPageSize", inspected: Str.inspect(error) })
	InvalidPlacement(_) => leaf({ category: Invariant, feature: "invalid_placement", path: "InvalidPlacement", inspected: Str.inspect(error) })
	InvalidStyleCount(_) => leaf({ category: Invariant, feature: "invalid_style_count", path: "InvalidStyleCount", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	Ownership(cause) => context({ feature: "ownership", path: "Ownership", cause: kernel_text_ownership_error(cause) })
	Scene(cause) => context({ feature: "scene", path: "Scene", cause: kernel_scene_error(cause) })
	UnsupportedColor(_) => leaf({ category: Invariant, feature: "unsupported_color", path: "UnsupportedColor", inspected: Str.inspect(error) })
}

kernel_facade_semantics_error : KernelFacadeSemantics.Error -> KernelFacadeFailure.Failure
kernel_facade_semantics_error = |error| match error {
	CalloutStyle(_) => leaf({ category: Invariant, feature: "callout_style", path: "CalloutStyle", inspected: Str.inspect(error) })
	CalloutContent(_) => leaf({ category: Invariant, feature: "callout_content", path: "CalloutContent", inspected: Str.inspect(error) })
	CalloutBlock(_) => leaf({ category: Invariant, feature: "callout_block", path: "CalloutBlock", inspected: Str.inspect(error) })
	CalloutFlow(_) => leaf({ category: Invariant, feature: "callout_flow", path: "CalloutFlow", inspected: Str.inspect(error) })
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	ReferenceStageRequired => leaf({ category: Invariant, feature: "reference_stage_required", path: "ReferenceStageRequired", inspected: Str.inspect(error) })
	ContentsEntry(_) => leaf({ category: Invariant, feature: "contents_entry", path: "ContentsEntry", inspected: Str.inspect(error) })
	PageReference(_) => leaf({ category: Invariant, feature: "page_reference", path: "PageReference", inspected: Str.inspect(error) })
	ReferenceResolution(_) => leaf({ category: Invariant, feature: "reference_resolution", path: "ReferenceResolution", inspected: Str.inspect(error) })
	SourceWhitespace({ error: cause, .. }) => leaf({ category: kernel_source_text_error(cause).category, feature: "source_whitespace", path: "SourceWhitespace", inspected: Str.inspect(error) })
	SourceStyle(_) => leaf({ category: Invariant, feature: "source_style", path: "SourceStyle", inspected: Str.inspect(error) })
	SourcePosition(_) => leaf({ category: Invariant, feature: "source_position", path: "SourcePosition", inspected: Str.inspect(error) })
	ContainerDepthExceeded(_) => leaf({ category: Budget, feature: "container_depth_exceeded", path: "ContainerDepthExceeded", inspected: Str.inspect(error) })
	CustomContent(_) => leaf({ category: Invariant, feature: "custom_content", path: "CustomContent", inspected: Str.inspect(error) })
	CustomDrawing(_) => leaf({ category: Invariant, feature: "custom_drawing", path: "CustomDrawing", inspected: Str.inspect(error) })
	CustomMeasure(_) => leaf({ category: Invariant, feature: "custom_measure", path: "CustomMeasure", inspected: Str.inspect(error) })
	CustomName(_) => leaf({ category: Invariant, feature: "custom_name", path: "CustomName", inspected: Str.inspect(error) })
	EmptyContainer(_) => leaf({ category: Invariant, feature: "empty_container", path: "EmptyContainer", inspected: Str.inspect(error) })
	DecorationDrawing(_) => leaf({ category: Invariant, feature: "decoration_drawing", path: "DecorationDrawing", inspected: Str.inspect(error) })
	DecorationPosition(_) => leaf({ category: Invariant, feature: "decoration_position", path: "DecorationPosition", inspected: Str.inspect(error) })
	EmptyInline(_) => leaf({ category: Invariant, feature: "empty_inline", path: "EmptyInline", inspected: Str.inspect(error) })
	EmptyKeep(_) => leaf({ category: Invariant, feature: "empty_keep", path: "EmptyKeep", inspected: Str.inspect(error) })
	EmptyScope(_) => leaf({ category: Invariant, feature: "empty_scope", path: "EmptyScope", inspected: Str.inspect(error) })
	EmptyLanguage => leaf({ category: Invariant, feature: "empty_language", path: "EmptyLanguage", inspected: Str.inspect(error) })
	EmptyLinkText(_) => leaf({ category: Invariant, feature: "empty_link_text", path: "EmptyLinkText", inspected: Str.inspect(error) })
	EmptyList(_) => leaf({ category: Invariant, feature: "empty_list", path: "EmptyList", inspected: Str.inspect(error) })
	EmptyListItem(_) => leaf({ category: Invariant, feature: "empty_list_item", path: "EmptyListItem", inspected: Str.inspect(error) })
	EmptyMetadataTitle => leaf({ category: Invariant, feature: "empty_metadata_title", path: "EmptyMetadataTitle", inspected: Str.inspect(error) })
	EmptyRichParagraph(_) => leaf({ category: Invariant, feature: "empty_rich_paragraph", path: "EmptyRichParagraph", inspected: Str.inspect(error) })
	FigureAlternativeEmpty(_) => leaf({ category: Invariant, feature: "figure_alternative_empty", path: "FigureAlternativeEmpty", inspected: Str.inspect(error) })
	FigureCaptionEmpty(_) => leaf({ category: Invariant, feature: "figure_caption_empty", path: "FigureCaptionEmpty", inspected: Str.inspect(error) })
	FigureDrawing(_) => leaf({ category: Invariant, feature: "figure_drawing", path: "FigureDrawing", inspected: Str.inspect(error) })
	FigureFitInvalid(_) => leaf({ category: Invariant, feature: "figure_fit_invalid", path: "FigureFitInvalid", inspected: Str.inspect(error) })
	FurnitureInline(_) => leaf({ category: Invariant, feature: "furniture_inline", path: "FurnitureInline", inspected: Str.inspect(error) })
	InlineDepthExceeded(_) => leaf({ category: Budget, feature: "inline_depth_exceeded", path: "InlineDepthExceeded", inspected: Str.inspect(error) })
	InvalidInlineLanguage(_) => leaf({ category: Invariant, feature: "invalid_inline_language", path: "InvalidInlineLanguage", inspected: Str.inspect(error) })
	InvalidInlineUri({ error: cause, .. }) => leaf({ category: document_navigation_error(cause).category, feature: "invalid_inline_uri", path: "InvalidInlineUri", inspected: Str.inspect(error) })
	InvalidList(_) => leaf({ category: Invariant, feature: "invalid_list", path: "InvalidList", inspected: Str.inspect(error) })
	LineBreakPosition(_) => leaf({ category: Invariant, feature: "line_break_position", path: "LineBreakPosition", inspected: Str.inspect(error) })
	ListDepthExceeded(_) => leaf({ category: Budget, feature: "list_depth_exceeded", path: "ListDepthExceeded", inspected: Str.inspect(error) })
	ListItemBlock(_) => leaf({ category: Invariant, feature: "list_item_block", path: "ListItemBlock", inspected: Str.inspect(error) })
	ListItemBreak(_) => leaf({ category: Invariant, feature: "list_item_break", path: "ListItemBreak", inspected: Str.inspect(error) })
	ListItemDecoration(_) => leaf({ category: Invariant, feature: "list_item_decoration", path: "ListItemDecoration", inspected: Str.inspect(error) })
	ListItemGroup(_) => leaf({ category: Invariant, feature: "list_item_group", path: "ListItemGroup", inspected: Str.inspect(error) })
	ListItemSpacer(_) => leaf({ category: Invariant, feature: "list_item_spacer", path: "ListItemSpacer", inspected: Str.inspect(error) })
	ListItemStart(_) => leaf({ category: Invariant, feature: "list_item_start", path: "ListItemStart", inspected: Str.inspect(error) })
	ListNumbering(_) => leaf({ category: Invariant, feature: "list_numbering", path: "ListNumbering", inspected: Str.inspect(error) })
	NegativeSpacer(_) => leaf({ category: Invariant, feature: "negative_spacer", path: "NegativeSpacer", inspected: Str.inspect(error) })
	NestedLink(_) => leaf({ category: Invariant, feature: "nested_link", path: "NestedLink", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	BlockLimitExceeded(_) => leaf({ category: Budget, feature: "block_limit_exceeded", path: "BlockLimitExceeded", inspected: Str.inspect(error) })
	Source(cause) => context({ feature: "source", path: "Source", cause: kernel_facade_sources_error(cause) })
	TableCellEmpty(_) => leaf({ category: Invariant, feature: "table_cell_empty", path: "TableCellEmpty", inspected: Str.inspect(error) })
	TableEmpty(_) => leaf({ category: Invariant, feature: "table_empty", path: "TableEmpty", inspected: Str.inspect(error) })
	TableGridMismatch(_) => leaf({ category: Invariant, feature: "table_grid_mismatch", path: "TableGridMismatch", inspected: Str.inspect(error) })
	TableHeaderMissing(_) => leaf({ category: Invariant, feature: "table_header_missing", path: "TableHeaderMissing", inspected: Str.inspect(error) })
	TableRowSpan(_) => leaf({ category: Invariant, feature: "table_row_span", path: "TableRowSpan", inspected: Str.inspect(error) })
	TextSemantics(cause) => context({ feature: "text_semantics", path: "TextSemantics", cause: kernel_text_semantics_error(cause) })
	UnsupportedHeadingLevel(_) => leaf({ category: Invariant, feature: "unsupported_heading_level", path: "UnsupportedHeadingLevel", inspected: Str.inspect(error) })
	HeadingSkip(_) => leaf({ category: Invariant, feature: "heading_skip", path: "HeadingSkip", inspected: Str.inspect(error) })
}

kernel_facade_shape_error : KernelFacadeShape.Error -> KernelFacadeFailure.Failure
kernel_facade_shape_error = |error| match error {
	FontSelectionRejected(_) => leaf({ category: Invariant, feature: "font_selection_rejected", path: "FontSelectionRejected", inspected: Str.inspect(error) })
	GeneratedLabelEvidenceInvalid(_) => leaf({ category: Invariant, feature: "generated_label_evidence_invalid", path: "GeneratedLabelEvidenceInvalid", inspected: Str.inspect(error) })
	InlineClusterBoundary(_) => leaf({ category: Invariant, feature: "inline_cluster_boundary", path: "InlineClusterBoundary", inspected: Str.inspect(error) })
	InvalidOccurrence(_) => leaf({ category: Invariant, feature: "invalid_occurrence", path: "InvalidOccurrence", inspected: Str.inspect(error) })
	LanguageMismatch(_) => leaf({ category: Invariant, feature: "language_mismatch", path: "LanguageMismatch", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	OccurrenceCoverage(_) => leaf({ category: Invariant, feature: "occurrence_coverage", path: "OccurrenceCoverage", inspected: Str.inspect(error) })
	PolicyInvalid(cause) => context({ feature: "policy_invalid", path: "PolicyInvalid", cause: font_policy_error(cause) })
	ShapeFailure => leaf({ category: Invariant, feature: "shape_failure", path: "ShapeFailure", inspected: Str.inspect(error) })
	StyleArithmeticOverflow(_) => leaf({ category: Invariant, feature: "style_arithmetic_overflow", path: "StyleArithmeticOverflow", inspected: Str.inspect(error) })
	UndeclaredScript(_) => leaf({ category: Invariant, feature: "undeclared_script", path: "UndeclaredScript", inspected: Str.inspect(error) })
	UnsupportedInlineScript(_) => leaf({ category: Invariant, feature: "unsupported_inline_script", path: "UnsupportedInlineScript", inspected: Str.inspect(error) })
	UnsupportedThemeFace(_) => leaf({ category: Invariant, feature: "unsupported_theme_face", path: "UnsupportedThemeFace", inspected: Str.inspect(error) })
	UnsupportedText(_) => leaf({ category: Invariant, feature: "unsupported_text", path: "UnsupportedText", inspected: Str.inspect(error) })
}

kernel_facade_text_error : KernelFacadeText.Error -> KernelFacadeFailure.Failure
kernel_facade_text_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	InvalidCluster(_) => leaf({ category: Invariant, feature: "invalid_cluster", path: "InvalidCluster", inspected: Str.inspect(error) })
	InvalidGlyph(_) => leaf({ category: Invariant, feature: "invalid_glyph", path: "InvalidGlyph", inspected: Str.inspect(error) })
	InvalidLine(_) => leaf({ category: Invariant, feature: "invalid_line", path: "InvalidLine", inspected: Str.inspect(error) })
	InvalidPage(_) => leaf({ category: Invariant, feature: "invalid_page", path: "InvalidPage", inspected: Str.inspect(error) })
	InvalidPlacement(_) => leaf({ category: Invariant, feature: "invalid_placement", path: "InvalidPlacement", inspected: Str.inspect(error) })
	InvalidRun(_) => leaf({ category: Invariant, feature: "invalid_run", path: "InvalidRun", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	UnsupportedRunEvidence(_) => leaf({ category: Invariant, feature: "unsupported_run_evidence", path: "UnsupportedRunEvidence", inspected: Str.inspect(error) })
}

document_navigation_error : Document.NavigationError -> KernelFacadeFailure.Failure
document_navigation_error = |error| match error {
	NavigationPlanContextMismatch => leaf({ category: Invariant, feature: "navigation_plan_context_mismatch", path: "NavigationPlanContextMismatch", inspected: Str.inspect(error) })
	AnnotationCountMismatch(_) => leaf({ category: Invariant, feature: "annotation_count_mismatch", path: "AnnotationCountMismatch", inspected: Str.inspect(error) })
	AnnotationLimitExceeded(_) => leaf({ category: Budget, feature: "annotation_limit_exceeded", path: "AnnotationLimitExceeded", inspected: Str.inspect(error) })
	AnnotationPageOutOfRange(_) => leaf({ category: Invariant, feature: "annotation_page_out_of_range", path: "AnnotationPageOutOfRange", inspected: Str.inspect(error) })
	AppearanceFormOutOfRange(_) => leaf({ category: Invariant, feature: "appearance_form_out_of_range", path: "AppearanceFormOutOfRange", inspected: Str.inspect(error) })
	AppearanceGeometryMismatch(_) => leaf({ category: Invariant, feature: "appearance_geometry_mismatch", path: "AppearanceGeometryMismatch", inspected: Str.inspect(error) })
	AppearanceTextUnsupported(_) => leaf({ category: Invariant, feature: "appearance_text_unsupported", path: "AppearanceTextUnsupported", inspected: Str.inspect(error) })
	DescriptionEmpty(_) => leaf({ category: Invariant, feature: "description_empty", path: "DescriptionEmpty", inspected: Str.inspect(error) })
	DescriptionTooLong(_) => leaf({ category: Invariant, feature: "description_too_long", path: "DescriptionTooLong", inspected: Str.inspect(error) })
	DestinationAnchorOutOfRange(_) => leaf({ category: Invariant, feature: "destination_anchor_out_of_range", path: "DestinationAnchorOutOfRange", inspected: Str.inspect(error) })
	DestinationLimitExceeded(_) => leaf({ category: Budget, feature: "destination_limit_exceeded", path: "DestinationLimitExceeded", inspected: Str.inspect(error) })
	DestinationNameEmpty(_) => leaf({ category: Invariant, feature: "destination_name_empty", path: "DestinationNameEmpty", inspected: Str.inspect(error) })
	DestinationNameInvalidByte(_) => leaf({ category: Invariant, feature: "destination_name_invalid_byte", path: "DestinationNameInvalidByte", inspected: Str.inspect(error) })
	DestinationNameTooLong(_) => leaf({ category: Invariant, feature: "destination_name_too_long", path: "DestinationNameTooLong", inspected: Str.inspect(error) })
	DestinationTargetMismatch(_) => leaf({ category: Invariant, feature: "destination_target_mismatch", path: "DestinationTargetMismatch", inspected: Str.inspect(error) })
	DestinationTargetOutOfRange(_) => leaf({ category: Invariant, feature: "destination_target_out_of_range", path: "DestinationTargetOutOfRange", inspected: Str.inspect(error) })
	DuplicateDestinationName(_) => leaf({ category: Invariant, feature: "duplicate_destination_name", path: "DuplicateDestinationName", inspected: Str.inspect(error) })
	DuplicateKeyboardOrder(_) => leaf({ category: Invariant, feature: "duplicate_keyboard_order", path: "DuplicateKeyboardOrder", inspected: Str.inspect(error) })
	InvalidAnchorGeometry(_) => leaf({ category: Invariant, feature: "invalid_anchor_geometry", path: "InvalidAnchorGeometry", inspected: Str.inspect(error) })
	InvalidAnnotationRect(_) => leaf({ category: Invariant, feature: "invalid_annotation_rect", path: "InvalidAnnotationRect", inspected: Str.inspect(error) })
	InvalidQuad(_) => leaf({ category: Invariant, feature: "invalid_quad", path: "InvalidQuad", inspected: Str.inspect(error) })
	KeyboardOrderOutOfRange(_) => leaf({ category: Invariant, feature: "keyboard_order_out_of_range", path: "KeyboardOrderOutOfRange", inspected: Str.inspect(error) })
	LabelLimitExceeded(_) => leaf({ category: Budget, feature: "label_limit_exceeded", path: "LabelLimitExceeded", inspected: Str.inspect(error) })
	LabelNumberWithoutStyle(_) => leaf({ category: Invariant, feature: "label_number_without_style", path: "LabelNumberWithoutStyle", inspected: Str.inspect(error) })
	LabelPrefixTooLong(_) => leaf({ category: Invariant, feature: "label_prefix_too_long", path: "LabelPrefixTooLong", inspected: Str.inspect(error) })
	LabelRangeNotAscending(_) => leaf({ category: Invariant, feature: "label_range_not_ascending", path: "LabelRangeNotAscending", inspected: Str.inspect(error) })
	LabelStartNumberZero(_) => leaf({ category: Invariant, feature: "label_start_number_zero", path: "LabelStartNumberZero", inspected: Str.inspect(error) })
	LabelStartPageNotZero(_) => leaf({ category: Invariant, feature: "label_start_page_not_zero", path: "LabelStartPageNotZero", inspected: Str.inspect(error) })
	LabelStartPageOutOfRange(_) => leaf({ category: Invariant, feature: "label_start_page_out_of_range", path: "LabelStartPageOutOfRange", inspected: Str.inspect(error) })
	OutlineDepthJump(_) => leaf({ category: Invariant, feature: "outline_depth_jump", path: "OutlineDepthJump", inspected: Str.inspect(error) })
	OutlineDepthLimitExceeded(_) => leaf({ category: Budget, feature: "outline_depth_limit_exceeded", path: "OutlineDepthLimitExceeded", inspected: Str.inspect(error) })
	OutlineDestinationUnknown(_) => leaf({ category: Invariant, feature: "outline_destination_unknown", path: "OutlineDestinationUnknown", inspected: Str.inspect(error) })
	OutlineEntryLimitExceeded(_) => leaf({ category: Budget, feature: "outline_entry_limit_exceeded", path: "OutlineEntryLimitExceeded", inspected: Str.inspect(error) })
	OutlineFirstDepthNonzero(_) => leaf({ category: Invariant, feature: "outline_first_depth_nonzero", path: "OutlineFirstDepthNonzero", inspected: Str.inspect(error) })
	OutlineTitleEmpty(_) => leaf({ category: Invariant, feature: "outline_title_empty", path: "OutlineTitleEmpty", inspected: Str.inspect(error) })
	OutlineTitleTooLong(_) => leaf({ category: Invariant, feature: "outline_title_too_long", path: "OutlineTitleTooLong", inspected: Str.inspect(error) })
	QuadLimitExceeded(_) => leaf({ category: Budget, feature: "quad_limit_exceeded", path: "QuadLimitExceeded", inspected: Str.inspect(error) })
	QuadOutsideRect(_) => leaf({ category: Invariant, feature: "quad_outside_rect", path: "QuadOutsideRect", inspected: Str.inspect(error) })
	QuadsEmpty(_) => leaf({ category: Invariant, feature: "quads_empty", path: "QuadsEmpty", inspected: Str.inspect(error) })
	UnknownDestinationName(_) => leaf({ category: Invariant, feature: "unknown_destination_name", path: "UnknownDestinationName", inspected: Str.inspect(error) })
	UnresolvedDestinationAnchor(_) => leaf({ category: Invariant, feature: "unresolved_destination_anchor", path: "UnresolvedDestinationAnchor", inspected: Str.inspect(error) })
	UriEmpty(_) => leaf({ category: Invariant, feature: "uri_empty", path: "UriEmpty", inspected: Str.inspect(error) })
	UriInvalidByte(_) => leaf({ category: Invariant, feature: "uri_invalid_byte", path: "UriInvalidByte", inspected: Str.inspect(error) })
	UriInvalidPercentEncoding(_) => leaf({ category: Invariant, feature: "uri_invalid_percent_encoding", path: "UriInvalidPercentEncoding", inspected: Str.inspect(error) })
	UriMissingScheme(_) => leaf({ category: Invariant, feature: "uri_missing_scheme", path: "UriMissingScheme", inspected: Str.inspect(error) })
	UriTooLong(_) => leaf({ category: Invariant, feature: "uri_too_long", path: "UriTooLong", inspected: Str.inspect(error) })
}

kernel_text_semantics_error : KernelTextSemantics.Error -> KernelFacadeFailure.Failure
kernel_text_semantics_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	DuplicateTextPropertyOwnership(_) => leaf({ category: Invariant, feature: "duplicate_text_property_ownership", path: "DuplicateTextPropertyOwnership", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	OrphanTextProperty(_) => leaf({ category: Invariant, feature: "orphan_text_property", path: "OrphanTextProperty", inspected: Str.inspect(error) })
	Semantic(cause) => context({ feature: "semantic", path: "Semantic", cause: kernel_semantics_error(cause) })
	TextPropertySpanOutOfRange(_) => leaf({ category: Invariant, feature: "text_property_span_out_of_range", path: "TextPropertySpanOutOfRange", inspected: Str.inspect(error) })
}

kernel_shape_error : KernelShape.Error -> KernelFacadeFailure.Failure
kernel_shape_error = |error| match error {
	AnalysisMismatch(_) => leaf({ category: Invariant, feature: "analysis_mismatch", path: "AnalysisMismatch", inspected: Str.inspect(error) })
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	EmptySource => leaf({ category: Invariant, feature: "empty_source", path: "EmptySource", inspected: Str.inspect(error) })
	InvalidSource(_) => leaf({ category: Invariant, feature: "invalid_source", path: "InvalidSource", inspected: Str.inspect(error) })
	InvalidSize(_) => leaf({ category: Invariant, feature: "invalid_size", path: "InvalidSize", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	MetricFailure(_) => leaf({ category: Invariant, feature: "metric_failure", path: "MetricFailure", inspected: Str.inspect(error) })
	MissingGlyph(_) => leaf({ category: Invariant, feature: "missing_glyph", path: "MissingGlyph", inspected: Str.inspect(error) })
	NotdefGlyph(_) => leaf({ category: Invariant, feature: "notdef_glyph", path: "NotdefGlyph", inspected: Str.inspect(error) })
	AdvancedClusterInvalid(_) => leaf({ category: Invariant, feature: "advanced_cluster_invalid", path: "AdvancedClusterInvalid", inspected: Str.inspect(error) })
	SelectedRequestInvalid(_) => leaf({ category: Invariant, feature: "selected_request_invalid", path: "SelectedRequestInvalid", inspected: Str.inspect(error) })
	BidiOrderInvalid(_) => leaf({ category: Invariant, feature: "bidi_order_invalid", path: "BidiOrderInvalid", inspected: Str.inspect(error) })
	AdvancedGlyphInvalid(_) => leaf({ category: Invariant, feature: "advanced_glyph_invalid", path: "AdvancedGlyphInvalid", inspected: Str.inspect(error) })
	AdvancedRunInvalid(_) => leaf({ category: Invariant, feature: "advanced_run_invalid", path: "AdvancedRunInvalid", inspected: Str.inspect(error) })
	DuplicateGlyphReference(_) => leaf({ category: Invariant, feature: "duplicate_glyph_reference", path: "DuplicateGlyphReference", inspected: Str.inspect(error) })
	GlyphOutsideRun(_) => leaf({ category: Invariant, feature: "glyph_outside_run", path: "GlyphOutsideRun", inspected: Str.inspect(error) })
	InstanceMismatch(_) => leaf({ category: Invariant, feature: "instance_mismatch", path: "InstanceMismatch", inspected: Str.inspect(error) })
	SelectedFaceMissing(_) => leaf({ category: Invariant, feature: "selected_face_missing", path: "SelectedFaceMissing", inspected: Str.inspect(error) })
	SelectedFaceRangeMismatch(_) => leaf({ category: Invariant, feature: "selected_face_range_mismatch", path: "SelectedFaceRangeMismatch", inspected: Str.inspect(error) })
	OccurrenceMismatch(_) => leaf({ category: Invariant, feature: "occurrence_mismatch", path: "OccurrenceMismatch", inspected: Str.inspect(error) })
	ArtifactRunUnsupported(_) => leaf({ category: Invariant, feature: "artifact_run_unsupported", path: "ArtifactRunUnsupported", inspected: Str.inspect(error) })
	UnreferencedGlyph(_) => leaf({ category: Invariant, feature: "unreferenced_glyph", path: "UnreferencedGlyph", inspected: Str.inspect(error) })
	UnsupportedCluster(_) => leaf({ category: Invariant, feature: "unsupported_cluster", path: "UnsupportedCluster", inspected: Str.inspect(error) })
	UnsupportedDirection(cause) => context({ feature: "unsupported_direction", path: "UnsupportedDirection", cause: text_direction(cause) })
	UnsupportedScript(_) => leaf({ category: Invariant, feature: "unsupported_script", path: "UnsupportedScript", inspected: Str.inspect(error) })
	UnsupportedWritingMode(cause) => context({ feature: "unsupported_writing_mode", path: "UnsupportedWritingMode", cause: text_writing_mode(cause) })
}

kernel_facade_sources_error : KernelFacadeSources.Error -> KernelFacadeFailure.Failure
kernel_facade_sources_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	EmptySource(_) => leaf({ category: Invariant, feature: "empty_source", path: "EmptySource", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	TableExhausted => leaf({ category: Invariant, feature: "table_exhausted", path: "TableExhausted", inspected: Str.inspect(error) })
	Unicode(cause) => context({ feature: "unicode", path: "Unicode", cause: kernel_unicode_unicode_error(cause) })
}

kernel_facade_labels_owner : KernelFacadeLabels.Owner -> KernelFacadeFailure.Failure
kernel_facade_labels_owner = |error| match error {
	FigureOwner(_) => leaf({ category: Invariant, feature: "figure_owner", path: "FigureOwner", inspected: Str.inspect(error) })
	PanelOwner(_) => leaf({ category: Invariant, feature: "panel_owner", path: "PanelOwner", inspected: Str.inspect(error) })
}

kernel_line_layout_error : KernelLineLayout.Error -> KernelFacadeFailure.Failure
kernel_line_layout_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	InvalidAnalysis => leaf({ category: Invariant, feature: "invalid_analysis", path: "InvalidAnalysis", inspected: Str.inspect(error) })
	InvalidCluster(_) => leaf({ category: Invariant, feature: "invalid_cluster", path: "InvalidCluster", inspected: Str.inspect(error) })
	InvalidGlyphAdvance(_) => leaf({ category: Invariant, feature: "invalid_glyph_advance", path: "InvalidGlyphAdvance", inspected: Str.inspect(error) })
	InvalidRun(_) => leaf({ category: Invariant, feature: "invalid_run", path: "InvalidRun", inspected: Str.inspect(error) })
	InvalidWidth(_) => leaf({ category: Invariant, feature: "invalid_width", path: "InvalidWidth", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	TableExhausted => leaf({ category: Invariant, feature: "table_exhausted", path: "TableExhausted", inspected: Str.inspect(error) })
	Unbreakable(_) => leaf({ category: Invariant, feature: "unbreakable", path: "Unbreakable", inspected: Str.inspect(error) })
	SourceUnbreakable(_) => leaf({ category: Invariant, feature: "source_unbreakable", path: "SourceUnbreakable", inspected: Str.inspect(error) })
}

kernel_facade_tables_error : KernelFacadeTables.Error -> KernelFacadeFailure.Failure
kernel_facade_tables_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	InvalidCell(_) => leaf({ category: Invariant, feature: "invalid_cell", path: "InvalidCell", inspected: Str.inspect(error) })
	Measure(cause) => context({ feature: "measure", path: "Measure", cause: kernel_line_layout_error(cause) })
	TableWidth(_) => leaf({ category: Invariant, feature: "table_width", path: "TableWidth", inspected: Str.inspect(error) })
	UnbreakableToken(_) => leaf({ category: Invariant, feature: "unbreakable_token", path: "UnbreakableToken", inspected: Str.inspect(error) })
	UnbreakableItems(_) => leaf({ category: Invariant, feature: "unbreakable_items", path: "UnbreakableItems", inspected: Str.inspect(error) })
}

kernel_content_error : KernelContent.Error -> KernelFacadeFailure.Failure
kernel_content_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	ContentStreamCountMismatch(_) => leaf({ category: Invariant, feature: "content_stream_count_mismatch", path: "ContentStreamCountMismatch", inspected: Str.inspect(error) })
	FormPlacementInvalid(_) => leaf({ category: Invariant, feature: "form_placement_invalid", path: "FormPlacementInvalid", inspected: Str.inspect(error) })
	FragmentStreamMismatch(_) => leaf({ category: Invariant, feature: "fragment_stream_mismatch", path: "FragmentStreamMismatch", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	MissingMarkedFragment(_) => leaf({ category: Invariant, feature: "missing_marked_fragment", path: "MissingMarkedFragment", inspected: Str.inspect(error) })
	TextRunInvalid(_) => leaf({ category: Invariant, feature: "text_run_invalid", path: "TextRunInvalid", inspected: Str.inspect(error) })
	UnsupportedValidatedCommand(_) => leaf({ category: Invariant, feature: "unsupported_validated_command", path: "UnsupportedValidatedCommand", inspected: Str.inspect(error) })
}

kernel_font_objects_error : KernelFontObjects.Error -> KernelFacadeFailure.Failure
kernel_font_objects_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	NoFonts => leaf({ category: Invariant, feature: "no_fonts", path: "NoFonts", inspected: Str.inspect(error) })
}

kernel_font_plan_error : KernelFontPlan.Error -> KernelFacadeFailure.Failure
kernel_font_plan_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	FontFailure(cause) => context({ feature: "font_failure", path: "FontFailure", cause: kernel_font_error(cause) })
	GlyphOutOfRange(_) => leaf({ category: Invariant, feature: "glyph_out_of_range", path: "GlyphOutOfRange", inspected: Str.inspect(error) })
	GlyphZeroUsed(_) => leaf({ category: Invariant, feature: "glyph_zero_used", path: "GlyphZeroUsed", inspected: Str.inspect(error) })
	RetainedGlyphLimitExceeded(_) => leaf({ category: Budget, feature: "retained_glyph_limit_exceeded", path: "RetainedGlyphLimitExceeded", inspected: Str.inspect(error) })
}

kernel_object_plan_error : KernelObjectPlan.Error -> KernelFacadeFailure.Failure
kernel_object_plan_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	PageCountZero => leaf({ category: Invariant, feature: "page_count_zero", path: "PageCountZero", inspected: Str.inspect(error) })
	ResourceCountMismatch(_) => leaf({ category: Invariant, feature: "resource_count_mismatch", path: "ResourceCountMismatch", inspected: Str.inspect(error) })
	Shape(cause) => context({ feature: "shape", path: "Shape", cause: kernel_balanced_error(cause) })
}

kernel_resource_use_error : KernelResourceUse.Error -> KernelFacadeFailure.Failure
kernel_resource_use_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	ColorComponentMismatch(_) => leaf({ category: Invariant, feature: "color_component_mismatch", path: "ColorComponentMismatch", inspected: Str.inspect(error) })
	CountMismatch(_) => leaf({ category: Invariant, feature: "count_mismatch", path: "CountMismatch", inspected: Str.inspect(error) })
	OrphanResource(_) => leaf({ category: Invariant, feature: "orphan_resource", path: "OrphanResource", inspected: Str.inspect(error) })
	ShadingStopComponentMismatch(_) => leaf({ category: Invariant, feature: "shading_stop_component_mismatch", path: "ShadingStopComponentMismatch", inspected: Str.inspect(error) })
}

kernel_tagged_text_structure_error : KernelTaggedTextStructure.Error -> KernelFacadeFailure.Failure
kernel_tagged_text_structure_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	Font(cause) => context({ feature: "font", path: "Font", cause: kernel_pdf_font_error(cause) })
	FontCountMismatch(_) => leaf({ category: Invariant, feature: "font_count_mismatch", path: "FontCountMismatch", inspected: Str.inspect(error) })
	Identity(cause) => context({ feature: "identity", path: "Identity", cause: kernel_identity_error(cause) })
	IntentProfileUnplanned(_) => leaf({ category: Invariant, feature: "intent_profile_unplanned", path: "IntentProfileUnplanned", inspected: Str.inspect(error) })
	Navigation(cause) => context({ feature: "navigation", path: "Navigation", cause: document_navigation_error(cause) })
	NavigationObjects(cause) => context({ feature: "navigation_objects", path: "NavigationObjects", cause: kernel_navigation_objects_error(cause) })
	Object(cause) => context({ feature: "object", path: "Object", cause: kernel_object_error(cause) })
	ObjectCountMismatch(_) => leaf({ category: Invariant, feature: "object_count_mismatch", path: "ObjectCountMismatch", inspected: Str.inspect(error) })
	ObjectOrder(_) => leaf({ category: Invariant, feature: "object_order", path: "ObjectOrder", inspected: Str.inspect(error) })
	OutputBound(cause) => context({ feature: "output_bound", path: "OutputBound", cause: kernel_output_bound_error(cause) })
	Pages(cause) => context({ feature: "pages", path: "Pages", cause: kernel_page_objects_error(cause) })
	Resources(cause) => context({ feature: "resources", path: "Resources", cause: kernel_resource_objects_error(cause) })
	Seal(cause) => context({ feature: "seal", path: "Seal", cause: kernel_seal_error(cause) })
	TaggedObjects(cause) => context({ feature: "tagged_objects", path: "TaggedObjects", cause: kernel_tagged_objects_error(cause) })
}

kernel_font_subset_error : KernelFontSubset.Error -> KernelFacadeFailure.Failure
kernel_font_subset_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	InvalidPlan => leaf({ category: Invariant, feature: "invalid_plan", path: "InvalidPlan", inspected: Str.inspect(error) })
	MissingSourceTable(_) => leaf({ category: Invariant, feature: "missing_source_table", path: "MissingSourceTable", inspected: Str.inspect(error) })
	UnmappedComposite(_) => leaf({ category: Invariant, feature: "unmapped_composite", path: "UnmappedComposite", inspected: Str.inspect(error) })
}

kernel_pdf_text_error : KernelPdfText.Error -> KernelFacadeFailure.Failure
kernel_pdf_text_error = |error| match error {
	ActualTextRequired(_) => leaf({ category: Invariant, feature: "actual_text_required", path: "ActualTextRequired", inspected: Str.inspect(error) })
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	ClusterInvalid(_) => leaf({ category: Invariant, feature: "cluster_invalid", path: "ClusterInvalid", inspected: Str.inspect(error) })
	FontPlanInvalid(_) => leaf({ category: Invariant, feature: "font_plan_invalid", path: "FontPlanInvalid", inspected: Str.inspect(error) })
	GlyphNotRetained(_) => leaf({ category: Invariant, feature: "glyph_not_retained", path: "GlyphNotRetained", inspected: Str.inspect(error) })
	IncompleteUnicodeMapping(_) => leaf({ category: Invariant, feature: "incomplete_unicode_mapping", path: "IncompleteUnicodeMapping", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	OccurrenceInvalid(_) => leaf({ category: Invariant, feature: "occurrence_invalid", path: "OccurrenceInvalid", inspected: Str.inspect(error) })
	PlacementInvalid(_) => leaf({ category: Invariant, feature: "placement_invalid", path: "PlacementInvalid", inspected: Str.inspect(error) })
	RunInvalid(_) => leaf({ category: Invariant, feature: "run_invalid", path: "RunInvalid", inspected: Str.inspect(error) })
	UnicodeMappingConflict(_) => leaf({ category: Invariant, feature: "unicode_mapping_conflict", path: "UnicodeMappingConflict", inspected: Str.inspect(error) })
}

kernel_page_layout_error : KernelPageLayout.Error -> KernelFacadeFailure.Failure
kernel_page_layout_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	InvalidBlock(_) => leaf({ category: Invariant, feature: "invalid_block", path: "InvalidBlock", inspected: Str.inspect(error) })
	InvalidConstraints => leaf({ category: Invariant, feature: "invalid_constraints", path: "InvalidConstraints", inspected: Str.inspect(error) })
	InvalidGroup(_) => leaf({ category: Invariant, feature: "invalid_group", path: "InvalidGroup", inspected: Str.inspect(error) })
	InvalidLine(_) => leaf({ category: Invariant, feature: "invalid_line", path: "InvalidLine", inspected: Str.inspect(error) })
	KeepConflict(cause) => context({ feature: "keep_conflict", path: "KeepConflict", cause: kernel_page_layout_conflict(cause) })
	LeadOverflow(_) => leaf({ category: Invariant, feature: "lead_overflow", path: "LeadOverflow", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	Oversize(_) => leaf({ category: Invariant, feature: "oversize", path: "Oversize", inspected: Str.inspect(error) })
}

kernel_facade_reference_shape_error : KernelFacadeReferenceShape.Error -> KernelFacadeFailure.Failure
kernel_facade_reference_shape_error = |error| match error {
	InvalidLiteral(_) => leaf({ category: Invariant, feature: "invalid_literal", path: "InvalidLiteral", inspected: Str.inspect(error) })
	InvalidSelection => leaf({ category: Invariant, feature: "invalid_selection", path: "InvalidSelection", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	Shape(cause) => context({ feature: "shape", path: "Shape", cause: kernel_shape_error(cause) })
	Style(cause) => context({ feature: "style", path: "Style", cause: kernel_facade_shape_error(cause) })
}

kernel_facade_reference_lines_error : KernelFacadeReferenceLines.Error -> KernelFacadeFailure.Failure
kernel_facade_reference_lines_error = |error| match error {
	InvalidContext(_) => leaf({ category: Invariant, feature: "invalid_context", path: "InvalidContext", inspected: Str.inspect(error) })
	ContentsGeometry(_) => leaf({ category: Invariant, feature: "contents_geometry", path: "ContentsGeometry", inspected: Str.inspect(error) })
	LimitExceeded => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	Geometry(cause) => context({ feature: "geometry", path: "Geometry", cause: kernel_facade_lines_error(cause) })
	Items({ error: cause, .. }) => leaf({ category: kernel_reference_layout_error(cause).category, feature: "items", path: "Items", inspected: Str.inspect(error) })
	Tables(cause) => context({ feature: "tables", path: "Tables", cause: kernel_facade_tables_error(cause) })
	SourceOverflow(_) => leaf({ category: Invariant, feature: "source_overflow", path: "SourceOverflow", inspected: Str.inspect(error) })
}

kernel_color_error : KernelColor.Error -> KernelFacadeFailure.Failure
kernel_color_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	ComponentMismatch(_) => leaf({ category: Invariant, feature: "component_mismatch", path: "ComponentMismatch", inspected: Str.inspect(error) })
	DeclaredSizeMismatch(_) => leaf({ category: Invariant, feature: "declared_size_mismatch", path: "DeclaredSizeMismatch", inspected: Str.inspect(error) })
	DuplicateTagOwnership(_) => leaf({ category: Invariant, feature: "duplicate_tag_ownership", path: "DuplicateTagOwnership", inspected: Str.inspect(error) })
	IndexOutOfRange(_) => leaf({ category: Invariant, feature: "index_out_of_range", path: "IndexOutOfRange", inspected: Str.inspect(error) })
	InvalidCalibratedGray(_) => leaf({ category: Invariant, feature: "invalid_calibrated_gray", path: "InvalidCalibratedGray", inspected: Str.inspect(error) })
	InvalidIccSignature(_) => leaf({ category: Invariant, feature: "invalid_icc_signature", path: "InvalidIccSignature", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	NonDenseSpaceIdentity(_) => leaf({ category: Invariant, feature: "non_dense_space_identity", path: "NonDenseSpaceIdentity", inspected: Str.inspect(error) })
	NonDenseProfileIdentity(_) => leaf({ category: Invariant, feature: "non_dense_profile_identity", path: "NonDenseProfileIdentity", inspected: Str.inspect(error) })
	OrphanTag(_) => leaf({ category: Invariant, feature: "orphan_tag", path: "OrphanTag", inspected: Str.inspect(error) })
	ProfileTooShort(_) => leaf({ category: Invariant, feature: "profile_too_short", path: "ProfileTooShort", inspected: Str.inspect(error) })
	SpanOutOfRange(_) => leaf({ category: Invariant, feature: "span_out_of_range", path: "SpanOutOfRange", inspected: Str.inspect(error) })
	TagRecordMismatch(_) => leaf({ category: Invariant, feature: "tag_record_mismatch", path: "TagRecordMismatch", inspected: Str.inspect(error) })
	UnsupportedIccVersion(_) => leaf({ category: Invariant, feature: "unsupported_icc_version", path: "UnsupportedIccVersion", inspected: Str.inspect(error) })
}

kernel_text_ownership_error : KernelTextOwnership.Error -> KernelFacadeFailure.Failure
kernel_text_ownership_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	ArtifactTextUnsupported(_) => leaf({ category: Invariant, feature: "artifact_text_unsupported", path: "ArtifactTextUnsupported", inspected: Str.inspect(error) })
	ArtifactTextInFragment(_) => leaf({ category: Invariant, feature: "artifact_text_in_fragment", path: "ArtifactTextInFragment", inspected: Str.inspect(error) })
	DuplicateRunOwnership(_) => leaf({ category: Invariant, feature: "duplicate_run_ownership", path: "DuplicateRunOwnership", inspected: Str.inspect(error) })
	FragmentTextCoverageMismatch(_) => leaf({ category: Invariant, feature: "fragment_text_coverage_mismatch", path: "FragmentTextCoverageMismatch", inspected: Str.inspect(error) })
	NonDenseRunIdentity(_) => leaf({ category: Invariant, feature: "non_dense_run_identity", path: "NonDenseRunIdentity", inspected: Str.inspect(error) })
	OccurrenceMismatch(_) => leaf({ category: Invariant, feature: "occurrence_mismatch", path: "OccurrenceMismatch", inspected: Str.inspect(error) })
	OrphanRun(_) => leaf({ category: Invariant, feature: "orphan_run", path: "OrphanRun", inspected: Str.inspect(error) })
	RunIndexOutOfRange(_) => leaf({ category: Invariant, feature: "run_index_out_of_range", path: "RunIndexOutOfRange", inspected: Str.inspect(error) })
	Tagged(cause) => context({ feature: "tagged", path: "Tagged", cause: kernel_tagged_error(cause) })
}

kernel_scene_error : KernelScene.Error -> KernelFacadeFailure.Failure
kernel_scene_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	DashAllZero(_) => leaf({ category: Invariant, feature: "dash_all_zero", path: "DashAllZero", inspected: Str.inspect(error) })
	DashLengthNegative(_) => leaf({ category: Invariant, feature: "dash_length_negative", path: "DashLengthNegative", inspected: Str.inspect(error) })
	DashPhaseNegative(_) => leaf({ category: Invariant, feature: "dash_phase_negative", path: "DashPhaseNegative", inspected: Str.inspect(error) })
	DuplicateOwnership(_) => leaf({ category: Invariant, feature: "duplicate_ownership", path: "DuplicateOwnership", inspected: Str.inspect(error) })
	EmptyCommandRange(_) => leaf({ category: Invariant, feature: "empty_command_range", path: "EmptyCommandRange", inspected: Str.inspect(error) })
	EmptyForm(_) => leaf({ category: Invariant, feature: "empty_form", path: "EmptyForm", inspected: Str.inspect(error) })
	EmptyPath(_) => leaf({ category: Invariant, feature: "empty_path", path: "EmptyPath", inspected: Str.inspect(error) })
	FormTransformSingular(_) => leaf({ category: Invariant, feature: "form_transform_singular", path: "FormTransformSingular", inspected: Str.inspect(error) })
	Geometry(cause) => context({ feature: "geometry", path: "Geometry", cause: kernel_geometry_error(cause) })
	IndexOutOfRange(_) => leaf({ category: Invariant, feature: "index_out_of_range", path: "IndexOutOfRange", inspected: Str.inspect(error) })
	InvalidPathOrder(_) => leaf({ category: Invariant, feature: "invalid_path_order", path: "InvalidPathOrder", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	MiterLimitTooSmall(_) => leaf({ category: Invariant, feature: "miter_limit_too_small", path: "MiterLimitTooSmall", inspected: Str.inspect(error) })
	NoPathPaint(_) => leaf({ category: Invariant, feature: "no_path_paint", path: "NoPathPaint", inspected: Str.inspect(error) })
	NonDenseIdentity(_) => leaf({ category: Invariant, feature: "non_dense_identity", path: "NonDenseIdentity", inspected: Str.inspect(error) })
	NonPositiveRect(_) => leaf({ category: Invariant, feature: "non_positive_rect", path: "NonPositiveRect", inspected: Str.inspect(error) })
	Orphaned(_) => leaf({ category: Invariant, feature: "orphaned", path: "Orphaned", inspected: Str.inspect(error) })
	SpanOutOfRange(_) => leaf({ category: Invariant, feature: "span_out_of_range", path: "SpanOutOfRange", inspected: Str.inspect(error) })
	TextPaintInvalid(_) => leaf({ category: Invariant, feature: "text_paint_invalid", path: "TextPaintInvalid", inspected: Str.inspect(error) })
	UnsupportedCommand(_) => leaf({ category: Invariant, feature: "unsupported_command", path: "UnsupportedCommand", inspected: Str.inspect(error) })
	UnpaintedPath(_) => leaf({ category: Invariant, feature: "unpainted_path", path: "UnpaintedPath", inspected: Str.inspect(error) })
	DegenerateShadingGeometry(_) => leaf({ category: Invariant, feature: "degenerate_shading_geometry", path: "DegenerateShadingGeometry", inspected: Str.inspect(error) })
	EmptyPatternCell(_) => leaf({ category: Invariant, feature: "empty_pattern_cell", path: "EmptyPatternCell", inspected: Str.inspect(error) })
	NegativeShadingRadius(_) => leaf({ category: Invariant, feature: "negative_shading_radius", path: "NegativeShadingRadius", inspected: Str.inspect(error) })
	PatternInPatternCell(_) => leaf({ category: Invariant, feature: "pattern_in_pattern_cell", path: "PatternInPatternCell", inspected: Str.inspect(error) })
	PatternMatrixSingular(_) => leaf({ category: Invariant, feature: "pattern_matrix_singular", path: "PatternMatrixSingular", inspected: Str.inspect(error) })
	PatternStepInvalid(_) => leaf({ category: Invariant, feature: "pattern_step_invalid", path: "PatternStepInvalid", inspected: Str.inspect(error) })
	ShadingStopEndpointInvalid(_) => leaf({ category: Invariant, feature: "shading_stop_endpoint_invalid", path: "ShadingStopEndpointInvalid", inspected: Str.inspect(error) })
	ShadingStopsNotIncreasing(_) => leaf({ category: Invariant, feature: "shading_stops_not_increasing", path: "ShadingStopsNotIncreasing", inspected: Str.inspect(error) })
	TextInPatternCell(_) => leaf({ category: Invariant, feature: "text_in_pattern_cell", path: "TextInPatternCell", inspected: Str.inspect(error) })
	TooFewShadingStops(_) => leaf({ category: Invariant, feature: "too_few_shading_stops", path: "TooFewShadingStops", inspected: Str.inspect(error) })
	TransparencyInPatternCell(_) => leaf({ category: Invariant, feature: "transparency_in_pattern_cell", path: "TransparencyInPatternCell", inspected: Str.inspect(error) })
}

font_policy_error : Font.PolicyError -> KernelFacadeFailure.Failure
font_policy_error = |error| match error {
	AmbiguousFace(_) => leaf({ category: Invariant, feature: "ambiguous_face", path: "AmbiguousFace", inspected: Str.inspect(error) })
	EmptyPolicy => leaf({ category: Invariant, feature: "empty_policy", path: "EmptyPolicy", inspected: Str.inspect(error) })
	UnknownPolicy(_) => leaf({ category: Invariant, feature: "unknown_policy", path: "UnknownPolicy", inspected: Str.inspect(error) })
	UnknownPolicyFace(_) => leaf({ category: Invariant, feature: "unknown_policy_face", path: "UnknownPolicyFace", inspected: Str.inspect(error) })
}

kernel_semantics_error : KernelSemantics.Error -> KernelFacadeFailure.Failure
kernel_semantics_error = |error| match error {
	AnnotationLogicalOrderInvalid(_) => leaf({ category: Invariant, feature: "annotation_logical_order_invalid", path: "AnnotationLogicalOrderInvalid", inspected: Str.inspect(error) })
	AnnotationOwnerMismatch(_) => leaf({ category: Invariant, feature: "annotation_owner_mismatch", path: "AnnotationOwnerMismatch", inspected: Str.inspect(error) })
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	CaptionPosition(_) => leaf({ category: Invariant, feature: "caption_position", path: "CaptionPosition", inspected: Str.inspect(error) })
	DuplicateChildRole(_) => leaf({ category: Invariant, feature: "duplicate_child_role", path: "DuplicateChildRole", inspected: Str.inspect(error) })
	DuplicateElementIdentifier(_) => leaf({ category: Invariant, feature: "duplicate_element_identifier", path: "DuplicateElementIdentifier", inspected: Str.inspect(error) })
	DuplicateOwnership(_) => leaf({ category: Invariant, feature: "duplicate_ownership", path: "DuplicateOwnership", inspected: Str.inspect(error) })
	ElementIdentifierOrder(_) => leaf({ category: Invariant, feature: "element_identifier_order", path: "ElementIdentifierOrder", inspected: Str.inspect(error) })
	EmptyElementIdentifier(_) => leaf({ category: Invariant, feature: "empty_element_identifier", path: "EmptyElementIdentifier", inspected: Str.inspect(error) })
	FragmentRangeOutsideOccurrence(_) => leaf({ category: Invariant, feature: "fragment_range_outside_occurrence", path: "FragmentRangeOutsideOccurrence", inspected: Str.inspect(error) })
	HeaderAssociationMismatch(_) => leaf({ category: Invariant, feature: "header_association_mismatch", path: "HeaderAssociationMismatch", inspected: Str.inspect(error) })
	IllegalContainment(_) => leaf({ category: Invariant, feature: "illegal_containment", path: "IllegalContainment", inspected: Str.inspect(error) })
	IllegalContentItem(_) => leaf({ category: Invariant, feature: "illegal_content_item", path: "IllegalContentItem", inspected: Str.inspect(error) })
	IndexOutOfRange(_) => leaf({ category: Invariant, feature: "index_out_of_range", path: "IndexOutOfRange", inspected: Str.inspect(error) })
	InvalidAttribute(_) => leaf({ category: Invariant, feature: "invalid_attribute", path: "InvalidAttribute", inspected: Str.inspect(error) })
	InvalidContextualArtifactAttribute(_) => leaf({ category: Invariant, feature: "invalid_contextual_artifact_attribute", path: "InvalidContextualArtifactAttribute", inspected: Str.inspect(error) })
	InvalidDocumentRoot(_) => leaf({ category: Invariant, feature: "invalid_document_root", path: "InvalidDocumentRoot", inspected: Str.inspect(error) })
	InvalidLanguage(_) => leaf({ category: Invariant, feature: "invalid_language", path: "InvalidLanguage", inspected: Str.inspect(error) })
	InvalidNodeTextProperty(_) => leaf({ category: Invariant, feature: "invalid_node_text_property", path: "InvalidNodeTextProperty", inspected: Str.inspect(error) })
	InvalidParent(_) => leaf({ category: Invariant, feature: "invalid_parent", path: "InvalidParent", inspected: Str.inspect(error) })
	InvalidPdf20Namespace => leaf({ category: Invariant, feature: "invalid_pdf20_namespace", path: "InvalidPdf20Namespace", inspected: Str.inspect(error) })
	InvalidRelationship(_) => leaf({ category: Invariant, feature: "invalid_relationship", path: "InvalidRelationship", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	NonDenseIdentity(_) => leaf({ category: Invariant, feature: "non_dense_identity", path: "NonDenseIdentity", inspected: Str.inspect(error) })
	Orphaned(_) => leaf({ category: Invariant, feature: "orphaned", path: "Orphaned", inspected: Str.inspect(error) })
	SpanOutOfRange(_) => leaf({ category: Invariant, feature: "span_out_of_range", path: "SpanOutOfRange", inspected: Str.inspect(error) })
	UnknownAttributeTarget(_) => leaf({ category: Invariant, feature: "unknown_attribute_target", path: "UnknownAttributeTarget", inspected: Str.inspect(error) })
	UnsupportedAnnotation(_) => leaf({ category: Invariant, feature: "unsupported_annotation", path: "UnsupportedAnnotation", inspected: Str.inspect(error) })
	UnsupportedRole(_) => leaf({ category: Invariant, feature: "unsupported_role", path: "UnsupportedRole", inspected: Str.inspect(error) })
	UnsupportedStoreContent => leaf({ category: Invariant, feature: "unsupported_store_content", path: "UnsupportedStoreContent", inspected: Str.inspect(error) })
	UnsupportedTextOccurrence(_) => leaf({ category: Invariant, feature: "unsupported_text_occurrence", path: "UnsupportedTextOccurrence", inspected: Str.inspect(error) })
}

text_direction : Text.Direction -> KernelFacadeFailure.Failure
text_direction = |error| match error {
	LeftToRight => leaf({ category: Invariant, feature: "left_to_right", path: "LeftToRight", inspected: Str.inspect(error) })
	RightToLeft => leaf({ category: Invariant, feature: "right_to_left", path: "RightToLeft", inspected: Str.inspect(error) })
}

text_writing_mode : Text.WritingMode -> KernelFacadeFailure.Failure
text_writing_mode = |error| match error {
	Horizontal => leaf({ category: Invariant, feature: "horizontal", path: "Horizontal", inspected: Str.inspect(error) })
	Vertical => leaf({ category: Invariant, feature: "vertical", path: "Vertical", inspected: Str.inspect(error) })
}

kernel_unicode_unicode_error : KernelUnicode.UnicodeError -> KernelFacadeFailure.Failure
kernel_unicode_unicode_error = |error| match error {
	GraphemeLimitExceeded(_) => leaf({ category: Budget, feature: "grapheme_limit_exceeded", path: "GraphemeLimitExceeded", inspected: Str.inspect(error) })
	InconsistentGraphemeRange(_) => leaf({ category: Invariant, feature: "inconsistent_grapheme_range", path: "InconsistentGraphemeRange", inspected: Str.inspect(error) })
	LineBoundaryLimitExceeded(_) => leaf({ category: Budget, feature: "line_boundary_limit_exceeded", path: "LineBoundaryLimitExceeded", inspected: Str.inspect(error) })
	ScalarLimitExceeded(_) => leaf({ category: Budget, feature: "scalar_limit_exceeded", path: "ScalarLimitExceeded", inspected: Str.inspect(error) })
	ScriptRunLimitExceeded(_) => leaf({ category: Budget, feature: "script_run_limit_exceeded", path: "ScriptRunLimitExceeded", inspected: Str.inspect(error) })
}

kernel_font_error : KernelFont.Error -> KernelFacadeFailure.Failure
kernel_font_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	ChecksumMismatch(_) => leaf({ category: Invariant, feature: "checksum_mismatch", path: "ChecksumMismatch", inspected: Str.inspect(error) })
	CmapLimitExceeded(_) => leaf({ category: Budget, feature: "cmap_limit_exceeded", path: "CmapLimitExceeded", inspected: Str.inspect(error) })
	CompositeCycle => leaf({ category: Invariant, feature: "composite_cycle", path: "CompositeCycle", inspected: Str.inspect(error) })
	CompositeDepthMismatch(_) => leaf({ category: Invariant, feature: "composite_depth_mismatch", path: "CompositeDepthMismatch", inspected: Str.inspect(error) })
	DuplicateOrUnorderedTable(_) => leaf({ category: Invariant, feature: "duplicate_or_unordered_table", path: "DuplicateOrUnorderedTable", inspected: Str.inspect(error) })
	FontChecksumMismatch(_) => leaf({ category: Invariant, feature: "font_checksum_mismatch", path: "FontChecksumMismatch", inspected: Str.inspect(error) })
	InvalidCmap => leaf({ category: Invariant, feature: "invalid_cmap", path: "InvalidCmap", inspected: Str.inspect(error) })
	InvalidDirectory => leaf({ category: Invariant, feature: "invalid_directory", path: "InvalidDirectory", inspected: Str.inspect(error) })
	InvalidEmbeddingRights(_) => leaf({ category: Invariant, feature: "invalid_embedding_rights", path: "InvalidEmbeddingRights", inspected: Str.inspect(error) })
	InvalidHead => leaf({ category: Invariant, feature: "invalid_head", path: "InvalidHead", inspected: Str.inspect(error) })
	InvalidHorizontalMetrics => leaf({ category: Invariant, feature: "invalid_horizontal_metrics", path: "InvalidHorizontalMetrics", inspected: Str.inspect(error) })
	InvalidGlyph(_) => leaf({ category: Invariant, feature: "invalid_glyph", path: "InvalidGlyph", inspected: Str.inspect(error) })
	InvalidLoca => leaf({ category: Invariant, feature: "invalid_loca", path: "InvalidLoca", inspected: Str.inspect(error) })
	InvalidMaxp => leaf({ category: Invariant, feature: "invalid_maxp", path: "InvalidMaxp", inspected: Str.inspect(error) })
	InvalidName => leaf({ category: Invariant, feature: "invalid_name", path: "InvalidName", inspected: Str.inspect(error) })
	InvalidOs2 => leaf({ category: Invariant, feature: "invalid_os2", path: "InvalidOs2", inspected: Str.inspect(error) })
	InvalidPost => leaf({ category: Invariant, feature: "invalid_post", path: "InvalidPost", inspected: Str.inspect(error) })
	InvalidStyle => leaf({ category: Invariant, feature: "invalid_style", path: "InvalidStyle", inspected: Str.inspect(error) })
	InvalidTableRange(_) => leaf({ category: Invariant, feature: "invalid_table_range", path: "InvalidTableRange", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	MissingTable(_) => leaf({ category: Invariant, feature: "missing_table", path: "MissingTable", inspected: Str.inspect(error) })
	OverlappingTables(_) => leaf({ category: Invariant, feature: "overlapping_tables", path: "OverlappingTables", inspected: Str.inspect(error) })
	UnsupportedFontProgram(_) => leaf({ category: Invariant, feature: "unsupported_font_program", path: "UnsupportedFontProgram", inspected: Str.inspect(error) })
}

kernel_balanced_error : KernelBalanced.Error -> KernelFacadeFailure.Failure
kernel_balanced_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	ItemCountZero => leaf({ category: Invariant, feature: "item_count_zero", path: "ItemCountZero", inspected: Str.inspect(error) })
	ItemLimitExceeded(_) => leaf({ category: Budget, feature: "item_limit_exceeded", path: "ItemLimitExceeded", inspected: Str.inspect(error) })
}

kernel_pdf_font_error : KernelPdfFont.Error -> KernelFacadeFailure.Failure
kernel_pdf_font_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	IncompleteUnicodeMapping(_) => leaf({ category: Invariant, feature: "incomplete_unicode_mapping", path: "IncompleteUnicodeMapping", inspected: Str.inspect(error) })
	InvalidDescriptor => leaf({ category: Invariant, feature: "invalid_descriptor", path: "InvalidDescriptor", inspected: Str.inspect(error) })
	InvalidFontPlan => leaf({ category: Invariant, feature: "invalid_font_plan", path: "InvalidFontPlan", inspected: Str.inspect(error) })
	InvalidPostScriptName => leaf({ category: Invariant, feature: "invalid_post_script_name", path: "InvalidPostScriptName", inspected: Str.inspect(error) })
	InvalidSubset => leaf({ category: Invariant, feature: "invalid_subset", path: "InvalidSubset", inspected: Str.inspect(error) })
	InvalidUnicodeScalar(_) => leaf({ category: Invariant, feature: "invalid_unicode_scalar", path: "InvalidUnicodeScalar", inspected: Str.inspect(error) })
	Object(cause) => context({ feature: "object", path: "Object", cause: kernel_object_error(cause) })
	UnexpectedUnicodeMapping(_) => leaf({ category: Invariant, feature: "unexpected_unicode_mapping", path: "UnexpectedUnicodeMapping", inspected: Str.inspect(error) })
	UnicodeMappingLimitExceeded(_) => leaf({ category: Budget, feature: "unicode_mapping_limit_exceeded", path: "UnicodeMappingLimitExceeded", inspected: Str.inspect(error) })
}

kernel_identity_error : KernelIdentity.Error -> KernelFacadeFailure.Failure
kernel_identity_error = |error| match error {
	Hash(cause) => context({ feature: "hash", path: "Hash", cause: kernel_sha256_error(cause) })
	WorkOverflow => leaf({ category: Invariant, feature: "work_overflow", path: "WorkOverflow", inspected: Str.inspect(error) })
}

kernel_navigation_objects_error : KernelNavigationObjects.Error -> KernelFacadeFailure.Failure
kernel_navigation_objects_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	Index(cause) => context({ feature: "index", path: "Index", cause: kernel_index_error(cause) })
	Object(cause) => context({ feature: "object", path: "Object", cause: kernel_object_error(cause) })
	ObjectOrder(_) => leaf({ category: Invariant, feature: "object_order", path: "ObjectOrder", inspected: Str.inspect(error) })
	Outline(cause) => context({ feature: "outline", path: "Outline", cause: kernel_outline_error(cause) })
	Shape(cause) => context({ feature: "shape", path: "Shape", cause: kernel_balanced_error(cause) })
}

kernel_object_error : KernelObject.Error -> KernelFacadeFailure.Failure
kernel_object_error = |error| match error {
	DuplicateDictionaryKey(_) => leaf({ category: Invariant, feature: "duplicate_dictionary_key", path: "DuplicateDictionaryKey", inspected: Str.inspect(error) })
	IndexOutOfRange(_) => leaf({ category: Invariant, feature: "index_out_of_range", path: "IndexOutOfRange", inspected: Str.inspect(error) })
	Lexical(cause) => context({ feature: "lexical", path: "Lexical", cause: kernel_lex_error(cause) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	NonMonotonicDictionaryKeys(_) => leaf({ category: Invariant, feature: "non_monotonic_dictionary_keys", path: "NonMonotonicDictionaryKeys", inspected: Str.inspect(error) })
	ObjectNumberZero => leaf({ category: Invariant, feature: "object_number_zero", path: "ObjectNumberZero", inspected: Str.inspect(error) })
	Overflow(cause) => context({ feature: "overflow", path: "Overflow", cause: kernel_object_dimension(cause) })
}

kernel_output_bound_error : KernelOutputBound.Error -> KernelFacadeFailure.Failure
kernel_output_bound_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	Deflate(cause) => context({ feature: "deflate", path: "Deflate", cause: kernel_deflate_error(cause) })
	NestedStreamValue(_) => leaf({ category: Invariant, feature: "nested_stream_value", path: "NestedStreamValue", inspected: Str.inspect(error) })
	XrefObjectMismatch(_) => leaf({ category: Invariant, feature: "xref_object_mismatch", path: "XrefObjectMismatch", inspected: Str.inspect(error) })
}

kernel_page_objects_error : KernelPageObjects.Error -> KernelFacadeFailure.Failure
kernel_page_objects_error = |error| match error {
	Object(cause) => context({ feature: "object", path: "Object", cause: kernel_object_error(cause) })
	ObjectOrder(_) => leaf({ category: Invariant, feature: "object_order", path: "ObjectOrder", inspected: Str.inspect(error) })
}

kernel_resource_objects_error : KernelResourceObjects.Error -> KernelFacadeFailure.Failure
kernel_resource_objects_error = |error| match error {
	Object(cause) => context({ feature: "object", path: "Object", cause: kernel_object_error(cause) })
	ObjectOrder(_) => leaf({ category: Invariant, feature: "object_order", path: "ObjectOrder", inspected: Str.inspect(error) })
}

kernel_seal_error : KernelSeal.Error -> KernelFacadeFailure.Failure
kernel_seal_error = |error| match error {
	IndexOutOfRange(_) => leaf({ category: Invariant, feature: "index_out_of_range", path: "IndexOutOfRange", inspected: Str.inspect(error) })
	ObjectOrder(_) => leaf({ category: Invariant, feature: "object_order", path: "ObjectOrder", inspected: Str.inspect(error) })
	PayloadLastUseInvalid(_) => leaf({ category: Invariant, feature: "payload_last_use_invalid", path: "PayloadLastUseInvalid", inspected: Str.inspect(error) })
	PayloadUseMissing(_) => leaf({ category: Invariant, feature: "payload_use_missing", path: "PayloadUseMissing", inspected: Str.inspect(error) })
	ReferenceOutOfRange(_) => leaf({ category: Invariant, feature: "reference_out_of_range", path: "ReferenceOutOfRange", inspected: Str.inspect(error) })
	SpanOutOfRange(_) => leaf({ category: Invariant, feature: "span_out_of_range", path: "SpanOutOfRange", inspected: Str.inspect(error) })
	SpanOverflow(cause) => context({ feature: "span_overflow", path: "SpanOverflow", cause: kernel_seal_store_kind(cause) })
	StreamLengthNotAdjacent(_) => leaf({ category: Invariant, feature: "stream_length_not_adjacent", path: "StreamLengthNotAdjacent", inspected: Str.inspect(error) })
	StreamLengthObjectMismatch(_) => leaf({ category: Invariant, feature: "stream_length_object_mismatch", path: "StreamLengthObjectMismatch", inspected: Str.inspect(error) })
	StreamObjectMismatch(_) => leaf({ category: Invariant, feature: "stream_object_mismatch", path: "StreamObjectMismatch", inspected: Str.inspect(error) })
	WorkOverflow => leaf({ category: Invariant, feature: "work_overflow", path: "WorkOverflow", inspected: Str.inspect(error) })
}

kernel_tagged_objects_error : KernelTaggedObjects.Error -> KernelFacadeFailure.Failure
kernel_tagged_objects_error = |error| match error {
	AnnotationObjectUnplanned(_) => leaf({ category: Invariant, feature: "annotation_object_unplanned", path: "AnnotationObjectUnplanned", inspected: Str.inspect(error) })
	IdTree(cause) => context({ feature: "id_tree", path: "IdTree", cause: kernel_navigation_objects_error(cause) })
	IdTreeIndex(cause) => context({ feature: "id_tree_index", path: "IdTreeIndex", cause: kernel_index_error(cause) })
	IdTreeUnplanned(_) => leaf({ category: Invariant, feature: "id_tree_unplanned", path: "IdTreeUnplanned", inspected: Str.inspect(error) })
	InvalidFigureAlternative(_) => leaf({ category: Invariant, feature: "invalid_figure_alternative", path: "InvalidFigureAlternative", inspected: Str.inspect(error) })
	Object(cause) => context({ feature: "object", path: "Object", cause: kernel_object_error(cause) })
	ObjectOrder(_) => leaf({ category: Invariant, feature: "object_order", path: "ObjectOrder", inspected: Str.inspect(error) })
}

kernel_page_layout_conflict : KernelPageLayout.Conflict -> KernelFacadeFailure.Failure
kernel_page_layout_conflict = |error| match error {
	BreakAfterRequiredKeep(_) => leaf({ category: Invariant, feature: "break_after_required_keep", path: "BreakAfterRequiredKeep", inspected: Str.inspect(error) })
	BreakInsideGroup(_) => leaf({ category: Invariant, feature: "break_inside_group", path: "BreakInsideGroup", inspected: Str.inspect(error) })
	ChainTooTall(_) => leaf({ category: Invariant, feature: "chain_too_tall", path: "ChainTooTall", inspected: Str.inspect(error) })
	GroupTooTall(_) => leaf({ category: Invariant, feature: "group_too_tall", path: "GroupTooTall", inspected: Str.inspect(error) })
	RequiredKeepAtEnd(_) => leaf({ category: Invariant, feature: "required_keep_at_end", path: "RequiredKeepAtEnd", inspected: Str.inspect(error) })
}

kernel_tagged_error : KernelTagged.Error -> KernelFacadeFailure.Failure
kernel_tagged_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	DuplicateFragmentOwnership(_) => leaf({ category: Invariant, feature: "duplicate_fragment_ownership", path: "DuplicateFragmentOwnership", inspected: Str.inspect(error) })
	FragmentPageMismatch(_) => leaf({ category: Invariant, feature: "fragment_page_mismatch", path: "FragmentPageMismatch", inspected: Str.inspect(error) })
	IndexOutOfRange(_) => leaf({ category: Invariant, feature: "index_out_of_range", path: "IndexOutOfRange", inspected: Str.inspect(error) })
	OccurrenceHasNoFragments(_) => leaf({ category: Invariant, feature: "occurrence_has_no_fragments", path: "OccurrenceHasNoFragments", inspected: Str.inspect(error) })
	OrphanFragment(_) => leaf({ category: Invariant, feature: "orphan_fragment", path: "OrphanFragment", inspected: Str.inspect(error) })
	PageCountMismatch(_) => leaf({ category: Invariant, feature: "page_count_mismatch", path: "PageCountMismatch", inspected: Str.inspect(error) })
}

kernel_geometry_error : KernelGeometry.Error -> KernelFacadeFailure.Failure
kernel_geometry_error = |error| match error {
	BoxOutside(_) => leaf({ category: Invariant, feature: "box_outside", path: "BoxOutside", inspected: Str.inspect(error) })
	CoordinateOverflow => leaf({ category: Invariant, feature: "coordinate_overflow", path: "CoordinateOverflow", inspected: Str.inspect(error) })
	NonPositiveBox(cause) => context({ feature: "non_positive_box", path: "NonPositiveBox", cause: kernel_geometry_box_kind(cause) })
}

kernel_sha256_error : KernelSha256.Error -> KernelFacadeFailure.Failure
kernel_sha256_error = |error| match error {
	InputTooLarge => leaf({ category: Invariant, feature: "input_too_large", path: "InputTooLarge", inspected: Str.inspect(error) })
}

kernel_index_error : KernelIndex.Error -> KernelFacadeFailure.Failure
kernel_index_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	DuplicateByteKey(_) => leaf({ category: Invariant, feature: "duplicate_byte_key", path: "DuplicateByteKey", inspected: Str.inspect(error) })
	DuplicateNumberKey(_) => leaf({ category: Invariant, feature: "duplicate_number_key", path: "DuplicateNumberKey", inspected: Str.inspect(error) })
	EntryCountZero => leaf({ category: Invariant, feature: "entry_count_zero", path: "EntryCountZero", inspected: Str.inspect(error) })
	EntryLimitExceeded(_) => leaf({ category: Budget, feature: "entry_limit_exceeded", path: "EntryLimitExceeded", inspected: Str.inspect(error) })
	KeyBytesLimitExceeded(_) => leaf({ category: Budget, feature: "key_bytes_limit_exceeded", path: "KeyBytesLimitExceeded", inspected: Str.inspect(error) })
	NegativeParentKey(_) => leaf({ category: Invariant, feature: "negative_parent_key", path: "NegativeParentKey", inspected: Str.inspect(error) })
	NonMonotonicByteKey(_) => leaf({ category: Invariant, feature: "non_monotonic_byte_key", path: "NonMonotonicByteKey", inspected: Str.inspect(error) })
	NonMonotonicNumberKey(_) => leaf({ category: Invariant, feature: "non_monotonic_number_key", path: "NonMonotonicNumberKey", inspected: Str.inspect(error) })
	Shape(cause) => context({ feature: "shape", path: "Shape", cause: kernel_balanced_error(cause) })
	ValueIndexOutOfRange(_) => leaf({ category: Invariant, feature: "value_index_out_of_range", path: "ValueIndexOutOfRange", inspected: Str.inspect(error) })
}

kernel_outline_error : KernelOutline.Error -> KernelFacadeFailure.Failure
kernel_outline_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	DepthJump(_) => leaf({ category: Invariant, feature: "depth_jump", path: "DepthJump", inspected: Str.inspect(error) })
	DepthLimitExceeded(_) => leaf({ category: Budget, feature: "depth_limit_exceeded", path: "DepthLimitExceeded", inspected: Str.inspect(error) })
	EntryCountZero => leaf({ category: Invariant, feature: "entry_count_zero", path: "EntryCountZero", inspected: Str.inspect(error) })
	EntryLimitExceeded(_) => leaf({ category: Budget, feature: "entry_limit_exceeded", path: "EntryLimitExceeded", inspected: Str.inspect(error) })
	FirstDepthNonzero(_) => leaf({ category: Invariant, feature: "first_depth_nonzero", path: "FirstDepthNonzero", inspected: Str.inspect(error) })
	TargetIndexOutOfRange(_) => leaf({ category: Invariant, feature: "target_index_out_of_range", path: "TargetIndexOutOfRange", inspected: Str.inspect(error) })
	TitleIndexOutOfRange(_) => leaf({ category: Invariant, feature: "title_index_out_of_range", path: "TitleIndexOutOfRange", inspected: Str.inspect(error) })
}

kernel_lex_error : KernelLex.Error -> KernelFacadeFailure.Failure
kernel_lex_error = |error| match error {
	DecimalScaleOutOfRange(_) => leaf({ category: Invariant, feature: "decimal_scale_out_of_range", path: "DecimalScaleOutOfRange", inspected: Str.inspect(error) })
	NullNameByte(_) => leaf({ category: Invariant, feature: "null_name_byte", path: "NullNameByte", inspected: Str.inspect(error) })
}

kernel_object_dimension : KernelObject.Dimension -> KernelFacadeFailure.Failure
kernel_object_dimension = |error| match error {
	ArrayItems => leaf({ category: Invariant, feature: "array_items", path: "ArrayItems", inspected: Str.inspect(error) })
	ByteStringBytes => leaf({ category: Invariant, feature: "byte_string_bytes", path: "ByteStringBytes", inspected: Str.inspect(error) })
	ByteStrings => leaf({ category: Invariant, feature: "byte_strings", path: "ByteStrings", inspected: Str.inspect(error) })
	DictionaryEntries => leaf({ category: Invariant, feature: "dictionary_entries", path: "DictionaryEntries", inspected: Str.inspect(error) })
	DirectDepth => leaf({ category: Invariant, feature: "direct_depth", path: "DirectDepth", inspected: Str.inspect(error) })
	NameBytes => leaf({ category: Invariant, feature: "name_bytes", path: "NameBytes", inspected: Str.inspect(error) })
	Names => leaf({ category: Invariant, feature: "names", path: "Names", inspected: Str.inspect(error) })
	Objects => leaf({ category: Invariant, feature: "objects", path: "Objects", inspected: Str.inspect(error) })
	PayloadBytes => leaf({ category: Invariant, feature: "payload_bytes", path: "PayloadBytes", inspected: Str.inspect(error) })
	Payloads => leaf({ category: Invariant, feature: "payloads", path: "Payloads", inspected: Str.inspect(error) })
	Streams => leaf({ category: Invariant, feature: "streams", path: "Streams", inspected: Str.inspect(error) })
	TextStringBytes => leaf({ category: Invariant, feature: "text_string_bytes", path: "TextStringBytes", inspected: Str.inspect(error) })
	TextStrings => leaf({ category: Invariant, feature: "text_strings", path: "TextStrings", inspected: Str.inspect(error) })
	Values => leaf({ category: Invariant, feature: "values", path: "Values", inspected: Str.inspect(error) })
	WorkUnits => leaf({ category: Invariant, feature: "work_units", path: "WorkUnits", inspected: Str.inspect(error) })
}

kernel_deflate_error : KernelDeflate.Error -> KernelFacadeFailure.Failure
kernel_deflate_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	CompressorFailed => leaf({ category: Invariant, feature: "compressor_failed", path: "CompressorFailed", inspected: Str.inspect(error) })
	InputLimitExceeded(_) => leaf({ category: Budget, feature: "input_limit_exceeded", path: "InputLimitExceeded", inspected: Str.inspect(error) })
	OutputBoundExceeded(_) => leaf({ category: Invariant, feature: "output_bound_exceeded", path: "OutputBoundExceeded", inspected: Str.inspect(error) })
	OutputLimitExceeded(_) => leaf({ category: Budget, feature: "output_limit_exceeded", path: "OutputLimitExceeded", inspected: Str.inspect(error) })
}

kernel_seal_store_kind : KernelSeal.StoreKind -> KernelFacadeFailure.Failure
kernel_seal_store_kind = |error| match error {
	ArrayEdge => leaf({ category: Invariant, feature: "array_edge", path: "ArrayEdge", inspected: Str.inspect(error) })
	ByteStringValue => leaf({ category: Invariant, feature: "byte_string_value", path: "ByteStringValue", inspected: Str.inspect(error) })
	DictionaryEdge => leaf({ category: Invariant, feature: "dictionary_edge", path: "DictionaryEdge", inspected: Str.inspect(error) })
	NameValue => leaf({ category: Invariant, feature: "name_value", path: "NameValue", inspected: Str.inspect(error) })
	ObjectContent => leaf({ category: Invariant, feature: "object_content", path: "ObjectContent", inspected: Str.inspect(error) })
	PayloadValue => leaf({ category: Invariant, feature: "payload_value", path: "PayloadValue", inspected: Str.inspect(error) })
	StreamValue => leaf({ category: Invariant, feature: "stream_value", path: "StreamValue", inspected: Str.inspect(error) })
	TextStringValue => leaf({ category: Invariant, feature: "text_string_value", path: "TextStringValue", inspected: Str.inspect(error) })
}

kernel_geometry_box_kind : KernelGeometry.BoxKind -> KernelFacadeFailure.Failure
kernel_geometry_box_kind = |error| match error {
	ArtBox => leaf({ category: Invariant, feature: "art_box", path: "ArtBox", inspected: Str.inspect(error) })
	BleedBox => leaf({ category: Invariant, feature: "bleed_box", path: "BleedBox", inspected: Str.inspect(error) })
	CropBox => leaf({ category: Invariant, feature: "crop_box", path: "CropBox", inspected: Str.inspect(error) })
	MediaBox => leaf({ category: Invariant, feature: "media_box", path: "MediaBox", inspected: Str.inspect(error) })
	TrimBox => leaf({ category: Invariant, feature: "trim_box", path: "TrimBox", inspected: Str.inspect(error) })
}

kernel_page_labels_error : KernelPageLabels.Error -> KernelFacadeFailure.Failure
kernel_page_labels_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	EmptyLabel => leaf({ category: Invariant, feature: "empty_label", path: "EmptyLabel", inspected: Str.inspect(error) })
	InvalidPage => leaf({ category: Invariant, feature: "invalid_page", path: "InvalidPage", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
}

kernel_source_text_error : KernelSourceText.Error -> KernelFacadeFailure.Failure
kernel_source_text_error = |error| match error {
	BareCarriageReturn(_) => leaf({ category: Invariant, feature: "bare_carriage_return", path: "BareCarriageReturn", inspected: Str.inspect(error) })
	ForegroundColor(_) => leaf({ category: Invariant, feature: "foreground_color", path: "ForegroundColor", inspected: Str.inspect(error) })
	ForegroundRange(_) => leaf({ category: Invariant, feature: "foreground_range", path: "ForegroundRange", inspected: Str.inspect(error) })
	InvalidTabWidth => leaf({ category: Invariant, feature: "invalid_tab_width", path: "InvalidTabWidth", inspected: Str.inspect(error) })
	LimitExceeded(_) => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	TabRejected(_) => leaf({ category: Invariant, feature: "tab_rejected", path: "TabRejected", inspected: Str.inspect(error) })
}

kernel_reference_layout_error : KernelReferenceLayout.Error -> KernelFacadeFailure.Failure
kernel_reference_layout_error = |error| match error {
	ArithmeticOverflow => leaf({ category: Invariant, feature: "arithmetic_overflow", path: "ArithmeticOverflow", inspected: Str.inspect(error) })
	EmptyItems => leaf({ category: Invariant, feature: "empty_items", path: "EmptyItems", inspected: Str.inspect(error) })
	InvalidAdvance(_) => leaf({ category: Invariant, feature: "invalid_advance", path: "InvalidAdvance", inspected: Str.inspect(error) })
	InvalidFinalBoundary => leaf({ category: Invariant, feature: "invalid_final_boundary", path: "InvalidFinalBoundary", inspected: Str.inspect(error) })
	InvalidLiteral(_) => leaf({ category: Invariant, feature: "invalid_literal", path: "InvalidLiteral", inspected: Str.inspect(error) })
	InvalidWidth => leaf({ category: Invariant, feature: "invalid_width", path: "InvalidWidth", inspected: Str.inspect(error) })
	LimitExceeded => leaf({ category: Budget, feature: "limit_exceeded", path: "LimitExceeded", inspected: Str.inspect(error) })
	Unbreakable(_) => leaf({ category: Invariant, feature: "unbreakable", path: "Unbreakable", inspected: Str.inspect(error) })
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
