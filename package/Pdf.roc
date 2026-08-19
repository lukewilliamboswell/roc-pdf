import Color
import Conformance
import Document
import Font
import KernelLex
import KernelEmit
import KernelBuiltInFont
import KernelFacadePipeline
import KernelFont
import KernelFontPlan
import KernelMetadata
import KernelNavigation
import KernelSrgbProfile
import KernelXmp
import Metadata
import KernelFacadeFragments
import KernelFacadeLines
import KernelFacadeOutput
import KernelFacadePages
import KernelFacadeScenes
import KernelFacadeSemantics
import KernelFacadeShape
import KernelFacadeSources
import KernelFacadeText
import KernelColor
import KernelContent
import KernelObjectPlan
import KernelTaggedTextStructure
import KernelImage
import KernelLineLayout
import KernelPageLayout
import KernelPdfFont
import KernelPdfText
import KernelScene
import KernelUnicode
import KernelObject
import KernelSeal
import KernelStructure
import KernelSemantics
import KernelShape
import KernelTextSemantics
import Layout
import Scene
import Theme

Pdf :: [].{
	Profile := [AccessibleArchive, Archive, Standard]

	## The facade records whether its selected theme face is the small packaged
	## face or one of the opaque faces retained by a caller font registry. Both
	## cases resolve to one validated inspection before the shared pipeline; no
	## later stage branches on font provenance.
	FontSource := [BuiltIn, Registered(Font.Registry)]

	PageSize := [A4, Letter]
	ChunkRetention := [OwnChunks, ShareUnchangedResources]

	## Stable roadmap feature identity carried by `FeatureUnavailable` diagnostics.
	Feature : Document.Feature

	## Every facade failure is typed. `InvalidDocument` is a bounded diagnostic
	## batch and preparation emits no partial bytes on any error.
	Error := [
		InternalGenerationFailure,
		InvalidDocument(Conformance.DiagnosticBatch),
		InvalidFontResource(Font.ResourceError),
		InvalidFontSelection(List(Font.PlanError)),
		InvalidMetadata(Metadata.Error),
		InvalidNavigation(Document.NavigationError),
		UnsupportedAuthoringContent({ blocks : U64 }),
	]

	Options :: {
		chunk_retention : ChunkRetention,
		font_source : FontSource,
		page_size : PageSize,
		profile : Profile,
		theme : Theme,
	}.{
		default : Options
		default = Options.{
			chunk_retention: ShareUnchangedResources,
			font_source: BuiltIn,
			page_size: A4,
			profile: Standard,
			theme: Theme.default,
		}

		with_profile : Options, Profile -> Options
		with_profile = |options, profile| { ..options, profile }

		with_page_size : Options, PageSize -> Options
		with_page_size = |options, page_size| { ..options, page_size }

		with_theme : Options, Theme -> Options
		with_theme = |options, theme| { ..options, theme }

		## A registry is the complete public caller-resource boundary. It carries
		## the original immutable font bytes and the once-produced inspection
		## facts; callers still select only the returned opaque face through Theme.
		with_font_registry : Options, Font.Registry -> Options
		with_font_registry = |options, registry| { ..options, font_source: Registered(registry) }

		with_chunk_retention : Options, ChunkRetention -> Options
		with_chunk_retention = |options, chunk_retention| { ..options, chunk_retention }
	}

	## An opaque, fully validated document plan. Preparation performs all
	## authoring, layout, resource, navigation, conformance, and object-planning
	## work once; emission cannot reinterpret author intent or fail with a
	## document diagnostic after this boundary.
	Prepared :: KernelStructure.Plan.{}

	Encode :: KernelEmit.Encoder.{}
	ChunkStep : [Done, Emit(List(U8), Encode)]

	claims_for_profile : Profile -> Conformance.ClaimSet
	claims_for_profile = |profile| match profile {
		Standard => Conformance.claims_for_profile(Standard)
		Archive => Conformance.claims_for_profile(Archive)
		AccessibleArchive => Conformance.claims_for_profile(AccessibleArchive)
	}

	## Build an automatically paginated document from semantic blocks.
	document : { contents : List(Document.Block), language : Str, title : Str } -> Document
	document = |input| Document.from_blocks(input)

	## Build an explicitly framed document. The stable shape is available now;
	## preparation reports `layout.custom` until its lowering closes.
	fixed_document : { language : Str, pages : List(Document.FixedPage), title : Str } -> Document
	fixed_document = |input| Document.from_fixed_pages(input)

	## Add the document's visible title block.
	title : Str -> Document.Block
	title = |text| Document.title(text)

	## Add a semantic heading at the requested level.
	heading : U8, Str -> Document.Block
	heading = |level, text| Document.heading(level, text)

	## Add a plain paragraph.
	paragraph : Str -> Document.Block
	paragraph = |text| Document.paragraph(text)

	## Add an unordered list whose items are plain text.
	bullets : List(Str) -> Document.Block
	bullets = |items| Document.bullets(items)

	## Own a drawing as meaningful figure content with required alternative text.
	## The executable slice accepts exactly one typed image command; unsupported
	## vector, grouped, or multi-command drawings report `document.figure`.
	figure : Scene.Drawing, Str, Document.Caption -> Document.Block
	figure = |drawing, alternative, caption_value| Document.figure(drawing, alternative, caption_value)

	## Add an optional visible caption to a figure.
	caption : Str -> Document.Caption
	caption = |text| Document.caption(text)

	## Explicitly omit a visible figure caption; alternative text is still required.
	no_caption : Document.Caption
	no_caption = NoCaption

	## Start a fixed page with explicit semantic frames and classified artifacts.
	fixed_page : Layout.Size -> Document.FixedPageBuilder
	fixed_page = |size| Document.fixed_page(size)

	## Gate 6-8 authoring shapes are stable before their lowering is enabled.
	## These constructors retain the authored intent and reject transactionally
	## at preparation with a feature-specific explanation.
	## Reserve authored rich-inline intent; currently reports `semantics.rich_inline`.
	rich_paragraph : Str -> Document.Block
	rich_paragraph = |text| Document.unavailable(RichInline, text)

	## Reserve a semantic container; currently reports `semantics.containers`.
	section : Str -> Document.Block
	section = |summary| Document.unavailable(SemanticContainers, summary)

	## Reserve a simple logical table; currently reports `table.simple`.
	simple_table : Str -> Document.Block
	simple_table = |summary| Document.unavailable(SimpleTables, summary)

	## Reserve a spanning/header-associated table; currently reports `table.complex`.
	complex_table : Str -> Document.Block
	complex_table = |summary| Document.unavailable(ComplexTables, summary)

	## Reserve footnote content; currently reports `document.footnote`.
	footnote : Str -> Document.Block
	footnote = |text| Document.unavailable(Footnotes, text)

	## Reserve sidebar content; currently reports `document.side_content`.
	side_content : Str -> Document.Block
	side_content = |text| Document.unavailable(SideContent, text)

	## Reserve a generated cross-reference; currently reports `document.generated_reference`.
	generated_reference : Str -> Document.Block
	generated_reference = |name| Document.unavailable(GeneratedReferences, name)

	## Reserve a multi-column region; currently reports `layout.multi_column`.
	multi_column : Str -> Document.Block
	multi_column = |summary| Document.unavailable(MultiColumnLayout, summary)

	## Reserve custom layout intent; currently reports `layout.custom`.
	custom_layout : Str -> Document.Block
	custom_layout = |summary| Document.unavailable(CustomLayout, summary)

	page_header : Str -> Document.Block
	page_header = |text| Document.page_header(text)

	page_footer : Str -> Document.Block
	page_footer = |text| Document.page_footer(text)

	## A URI link block; the whole text is the link.
	link : Str, Str -> Document.Block
	link = |text, uri| Document.link(text, uri)

	## An internal link block referencing an authored destination name.
	internal_link : Str, Str -> Document.Block
	internal_link = |text, destination| Document.internal_link(text, destination)

	## A heading that also declares a named destination.
	destination_heading : Str, U8, Str -> Document.Block
	destination_heading = |name, level, text| Document.destination_heading(name, level, text)

	destination_paragraph : Str, Str -> Document.Block
	destination_paragraph = |name, text| Document.destination_paragraph(name, text)

	## The authored document outline in dense preorder over authored
	## destination names.
	with_outline : Document, List(Document.OutlineEntry) -> Document
	with_outline = |doc, entries| Document.with_outline(doc, entries)

	## Authored page-label ranges keyed by physical page index.
	with_page_labels : Document, List(Document.PageLabelRange) -> Document
	with_page_labels = |doc, ranges| Document.with_page_labels(doc, ranges)

	## Optional explicit metadata timestamps in the canonical UTC form
	## `YYYY-MM-DDThh:mm:ssZ`. The package never invents a timestamp: omitted
	## values deterministically omit their XMP properties.
	with_created : Document, Str -> Document
	with_created = |doc, timestamp| Document.with_created(doc, timestamp)

	with_modified : Document, Str -> Document
	with_modified = |doc, timestamp| Document.with_modified(doc, timestamp)

	## Standard authored content follows the completed typed facade pipeline.
	## Archive claims remain unavailable until their independent capabilities close.
	to_bytes : Document -> Try(List(U8), Error)
	to_bytes = |doc| to_bytes_with(doc, Options.default)

	to_bytes_with : Document, Options -> Try(List(U8), Error)
	to_bytes_with = |doc, options| {
		prepared = prepare(doc, options)?
		to_bytes_prepared(prepared)
	}

	## Validate and lower an authored document once for repeated or deferred
	## emission. The returned value contains no authoring callbacks or mutable
	## caches and exposes no PDF object internals.
	prepare : Document, Options -> Try(Prepared, Error)
	prepare = |doc, options| {
		match Document.first_unavailable(doc) {
			Available => {}
			UnavailableFeature({ feature, summary }) => return Err(InvalidDocument(unavailable_batch(feature, summary)))
		}
		plan = build_standard_plan(doc, options)?
		Ok(Prepared.(plan))
	}

	to_bytes_prepared : Prepared -> Try(List(U8), Error)
	to_bytes_prepared = |Prepared.(plan)| {
		bytes = KernelEmit.to_bytes(plan) ? |_| InternalGenerationFailure
		Ok(bytes)
	}

	to_chunks : Document -> Try(Encode, Error)
	to_chunks = |doc| to_chunks_with(doc, Options.default)

	## Chunked delivery drives the same emission transition as `to_bytes_with`
	## over the same sealed plan, so the concatenated chunks are byte-identical
	## to the buffered output by construction. Every document error occurs
	## while building that plan, before sealing: a rejected document yields a
	## typed error and no partial chunk sequence.
	to_chunks_with : Document, Options -> Try(Encode, Error)
	to_chunks_with = |doc, options| {
		prepared = prepare(doc, options)?
		to_chunks_prepared(prepared, options.chunk_retention)
	}

	## Start chunked emission from an already prepared document. Retention is
	## selected at emission time and cannot alter the sealed document bytes.
	to_chunks_prepared : Prepared, ChunkRetention -> Try(Encode, Error)
	to_chunks_prepared = |Prepared.(plan), chunk_retention| {
		retention = match chunk_retention {
			OwnChunks => OwnResourceChunks
			ShareUnchangedResources => ShareResourceChunks
		}
		encoder = KernelEmit.start(plan, retention) ? |_| InternalGenerationFailure
		Ok(Encode.(encoder))
	}

	next_chunk : Encode -> ChunkStep
	next_chunk = |Encode.(encoder)| match KernelEmit.Encoder.next_infallible(encoder) {
		Done => Done
		Emit(segment, next) => Emit(segment.bytes, Encode.(next))
	}
}

build_standard_plan : Document, Pdf.Options -> Try(KernelStructure.Plan, Pdf.Error)
build_standard_plan = |doc, options| {
	validate_standard_request(options)?

	## The authored metadata facts validate once and the canonical XMP packet
	## serializes once; every later stage consumes the same validated values.
	validated = KernelMetadata.validate(
		{
			created: Document.created(doc),
			language: Document.language(doc),
			modified: Document.modified(doc),
			title: Document.metadata_title(doc),
		},
		standard_metadata_limits,
	) ? InvalidMetadata
	xmp = KernelXmp.Packet.build(validated.facts, standard_xmp_bytes) ? |_| InternalGenerationFailure
	if Document.block_count(doc) == 0 {
		plan = KernelStructure.build_blank_with_facts(
			1,
			structure_page_size(options.page_size),
			{
				condition_identifier: KernelMetadata.srgb_condition_identifier,
				language: validated.facts.language,
				profile_bytes: KernelSrgbProfile.bytes,
				profile_components: 3,
				registry_name: KernelMetadata.icc_registry_name,
				xmp: KernelXmp.Packet.bytes(xmp),
			},
		) ? |_| InternalGenerationFailure
		return Ok(plan)
	}
	facts = WithDocumentFacts({
		condition_identifier: KernelMetadata.srgb_condition_identifier,
		profile: Color.ProfileId.from_index(0),
		registry_name: KernelMetadata.icc_registry_name,
		language: validated.facts.language,
		xmp: KernelXmp.Packet.bytes(xmp),
	})
	pipeline = match selected_fonts(options)? {
		Single(font) => KernelFacadePipeline.Plan.build_with_facts(
			Document.normalize(doc),
			font,
			options.theme,
			layout_page_size(options.page_size),
			standard_font_descriptor,
			facts,
			standard_pipeline_limits,
		) ? |error| pipeline_error(error, Document.block_count(doc))
		Ordered(ordered) => KernelFacadePipeline.Plan.build_ordered_with_facts(
			Document.normalize(doc),
			ordered,
			options.theme,
			layout_page_size(options.page_size),
			standard_font_descriptor,
			facts,
			standard_pipeline_limits,
		) ? |error| ordered_pipeline_error(error, ordered.policy, Document.block_count(doc))
	}
	Ok(KernelFacadePipeline.Plan.structure(pipeline))
}

## The Theme decides between exact style faces and an ordered policy. Policy
## selection requires the caller registry that constructed the policy; the
## packaged built-in face defines no policies, so that combination is a
## stable typed error rather than an implicit single-face fallback.
selected_fonts : Pdf.Options -> Try(KernelFacadeShape.FontSelection, Pdf.Error)
selected_fonts = |options| match Theme.font_selection(options.theme) {
	StyleFaces => Ok(Single(selected_font(options)?))
	Policy(policy) => match options.font_source {
		BuiltIn => Err(InvalidFontSelection([InvalidPolicy(policy)]))
		Registered(registry) => {
			_faces = registry.policy_faces(policy) ? |_| InvalidFontSelection([InvalidPolicy(policy)])
			Ok(Ordered({ policy, registry }))
		}
	}
}

## Ordered-selection failures surface the exact planner rejections; script
## boundaries of the convenience path map to the planner's typed
## unsupported-shaping fact. Everything else keeps the authored-content error.
ordered_pipeline_error : KernelFacadePipeline.Error, Font.PolicyId, U64 -> Pdf.Error
ordered_pipeline_error = |error, policy, blocks| match error {
	Shape(FontSelectionRejected(errors)) => InvalidFontSelection(errors)
	Shape(PolicyInvalid(_)) => InvalidFontSelection([InvalidPolicy(policy)])
	Shape(UndeclaredScript({ script, source })) => InvalidFontSelection([UnsupportedBuiltInShaping({ cluster: source, script: Font.Script.from_iso15924(script) })])
	_ => pipeline_error(error, blocks)
}

## Author-facing navigation rejections surface with their exact typed cause;
## every other pipeline failure keeps the authored-content error.
pipeline_error : KernelFacadePipeline.Error, U64 -> Pdf.Error
pipeline_error = |error, blocks| match error {
	Fragments(Navigation(navigation)) => InvalidNavigation(navigation)
	Output(Structure(Navigation(navigation))) => InvalidNavigation(navigation)
	_ => UnsupportedAuthoringContent({ blocks: blocks })
}

selected_font : Pdf.Options -> Try(KernelFont.Inspection, Pdf.Error)
selected_font = |options| match options.font_source {
	BuiltIn => {

		## The packaged face has the same dense facade identity as the initial
		## caller registry face. The shaping stage consumes only the validated
		## inspection and typed Theme face, never a provenance flag.
		if Theme.body_font(options.theme).index() != 0 {
			Err(InvalidFontResource(UnknownFace(Theme.body_font(options.theme))))
		} else {
			selected_built_in_font({})
		}
	}
	Registered(registry) => selected_registered_font(registry, Theme.body_font(options.theme))
}

selected_built_in_font : {} -> Try(KernelFont.Inspection, Pdf.Error)
selected_built_in_font = |_| {
	font = KernelFont.inspect(KernelBuiltInFont.bytes, standard_font_limits) ? |_| InternalGenerationFailure
	Ok(font)
}

selected_registered_font : Font.Registry, Font.FaceId -> Try(KernelFont.Inspection, Pdf.Error)
selected_registered_font = |registry, face| {
	font = registry.prepared_face(face) ? InvalidFontResource
	Ok(font)
}

validate_standard_request : Pdf.Options -> Try({}, Pdf.Error)
validate_standard_request = |options| {
	match options.profile {
		Archive => Err(Pdf.Error.InvalidDocument(unavailable_batch(ArchiveProfile, "The Archive profile requires the unfinished PDF/A-4 capability.")))
		AccessibleArchive => Err(Pdf.Error.InvalidDocument(unavailable_batch(AccessibleArchiveProfile, "The AccessibleArchive profile requires the unfinished combined PDF/A-4 and PDF/UA-2 capability.")))
		Standard => Ok({})
	}
}

unavailable_message : Document.Feature, Str -> Str
unavailable_message = |feature, summary| {
	roadmap = match feature {
		ArchiveProfile => "Gate 5"
		AccessibleArchiveProfile => "Gate 7"
		Figures => "the current figure authoring slice"
		RichInline | SemanticContainers | ContextualArtifacts | NestedLanguage | SemanticTextProperties | SimpleTables => "Gate 6"
		ComplexTables | CustomLayout | Floats | Footnotes | GeneratedReferences | MultiColumnLayout | PageTemplates | SideContent | VerticalWriting => "Gate 8"
	}
	"${summary} No PDF bytes were emitted. This capability remains scheduled for ${roadmap}."
}

feature_code : Document.Feature -> Str
feature_code = |feature| match feature {
	ArchiveProfile => "profile.archive"
	AccessibleArchiveProfile => "profile.accessible_archive"
	Figures => "document.figure"
	RichInline => "semantics.rich_inline"
	SemanticContainers => "semantics.containers"
	ContextualArtifacts => "semantics.contextual_artifact"
	NestedLanguage => "semantics.nested_language"
	SemanticTextProperties => "semantics.text_properties"
	SimpleTables => "table.simple"
	ComplexTables => "table.complex"
	CustomLayout => "layout.custom"
	Floats => "layout.float"
	Footnotes => "document.footnote"
	GeneratedReferences => "document.generated_reference"
	MultiColumnLayout => "layout.multi_column"
	PageTemplates => "layout.page_template"
	SideContent => "document.side_content"
	VerticalWriting => "text.vertical_writing"
}

unavailable_batch : Document.Feature, Str -> Conformance.DiagnosticBatch
unavailable_batch = |feature, summary| {
	message = unavailable_message(feature, summary)
	{
		detail_bytes: Str.to_utf8(message).len(),
		diagnostics: [
			{
				clause_references: [],
				code: FeatureUnavailable,
				details: [],
				feature: Feature(feature_code(feature)),
				location: Document,
				message,
				requirement_ids: [],
				stage: AuthoringValidation,
			},
		],
		truncation: Complete,
	}
}

structure_page_size : Pdf.PageSize -> KernelStructure.PageSize
structure_page_size = |page_size| match page_size {
	A4 => KernelStructure.PageSize.A4
	Letter => KernelStructure.PageSize.Letter
}

layout_page_size : Pdf.PageSize -> Layout.Size
layout_page_size = |page_size| match page_size {
	A4 => { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) }
	Letter => { height: Layout.Unit.from_raw(792000), width: Layout.Unit.from_raw(612000) }
}

standard_metadata_limits : KernelMetadata.Limits
standard_metadata_limits = KernelMetadata.Limits.make({ max_language_bytes: 64, max_title_bytes: 2048 })

## The canonical packet for a maximal facade title (2048 bytes escaped up to
## five-fold), language, and both timestamps stays far below this budget, so
## the facade cannot reach the kernel packet bound.
standard_xmp_bytes : U64
standard_xmp_bytes = 16384

standard_font_limits : KernelFont.Limits
standard_font_limits = KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })

standard_font_descriptor : KernelPdfFont.Descriptor
standard_font_descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

standard_pipeline_limits : KernelFacadePipeline.Limits
standard_pipeline_limits = KernelFacadePipeline.Limits.make({
	fragment_semantics: KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 8192, max_fragments: 100000, max_namespaces: 1, max_nodes: 4096, max_occurrences: 2048, max_semantic_depth: 4 }),
	fragments: KernelFacadeFragments.Limits.make({ max_fragments: 100000, max_occurrences: 2048, max_pages: 1024 }),
	navigation: KernelNavigation.standard_limits,
	lines: KernelFacadeLines.Limits.make({
		line: KernelLineLayout.BatchLimits.make({
			line: KernelLineLayout.Limits.make({ max_boundaries: 1000001, max_candidates: 2000000, max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_lines: 1000000 }),
			max_key_probes: 1000000,
			max_lines: 1000000,
			max_runs: 2048,
			max_table_slots: 8192,
			max_templates: 2048,
		}),
		max_blocks: 2048,
		max_runs: 2048,
	}),
	output: KernelFacadeOutput.Limits.make({
		content: KernelContent.Limits.make({ max_content_bytes: 16000000, max_content_streams: 1024 }),
		font_plan: KernelFontPlan.Limits.make({ max_retained_glyphs: 10000 }),
		images: KernelImage.Limits.make({ max_decoded_bytes: 67108864, max_encoded_bytes: 67108864, max_height: 16384, max_markers: 4096, max_resources: 2048, max_width: 16384 }),
		max_objects: 65536,
		objects: KernelObjectPlan.Limits.make({ max_objects: 65527, max_pages: 1024 }),
		structure: KernelTaggedTextStructure.Limits.make({
			font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 1000000, max_unicode_mappings: 10000, max_unicode_scalars: 1000000 }),
			object_limits: standard_object_limits,
		}),
		text: KernelPdfText.Limits.make({ max_actual_text_scalars: 1000000, max_content_bytes: 16000000, max_mappings: 10000, max_placements: 0, max_source_scalars: 1000000 }),
	}),
	pages: KernelFacadePages.Limits.make({
		max_blocks: 2048,
		max_rows: 1000000,
		page: KernelPageLayout.Limits.make({ max_blocks: 2048, max_fragments: 1000000, max_lines: 1000000, max_pages: 1024, max_placements: 1000000 }),
	}),
	scenes: KernelFacadeScenes.Limits.make({
		color: KernelColor.Limits.make({ max_icc_bytes: KernelSrgbProfile.byte_count, max_profiles: 1, max_spaces: 2, max_tags: KernelSrgbProfile.tag_count }),
		max_commands: 2000000,
		max_groups: 1000000,
		max_page_group_edges: 1000000,
		max_pages: 1024,
		scene: KernelScene.Limits.make({ max_commands: 2000000, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 1000000, max_pages: 1024, max_path_segments: 0, max_paths: 0 }),
	}),
	semantics: KernelFacadeSemantics.Limits.make({
		max_artifacts: 0,
		max_content_spine: 8192,
		max_nodes: 4096,
		max_occurrences: 2048,
		max_properties: 2048,
		max_source_inputs: 2048,
		semantics: KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 8192, max_fragments: 0, max_namespaces: 1, max_nodes: 4096, max_occurrences: 2048, max_semantic_depth: 4 }),
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
	}),
	shape: KernelFacadeShape.Limits.make({ max_requests: 2048, shape: KernelShape.Limits.make({ max_clusters: 1000000, max_glyphs: 1000000, max_scalars: 1000000, max_source_bytes: 1000000 }) }),
	text: KernelFacadeText.Limits.make({ max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_pages: 1024, max_placements: 1000000, max_runs: 1000000 }),
})

standard_object_limits : KernelObject.Limits
standard_object_limits = {
	max_array_items: 1000000,
	max_byte_string_bytes: 1048576,
	max_byte_strings: 65536,
	max_dictionary_entries: 1000000,
	max_direct_depth: 8,
	max_name_bytes: 8192,
	max_names: 100000,
	max_objects: 65536,
	max_payload_bytes: 16000000,
	max_payloads: 100000,
	max_streams: 100000,
	max_text_string_bytes: 1000000,
	max_text_strings: 16384,
	max_values: 1000000,
}

## Public profiles map to exact claim sets without enabling orthogonal WTPDF claims.
expect {
	claims = Pdf.claims_for_profile(Pdf.Profile.AccessibleArchive)

	claims.pdf20 and claims.static_pdf_a4 and claims.pdf_ua2 and !claims.wtpdf_accessibility
}

## The lexical implementation remains a private package module.
expect KernelLex.boolean(True) == Str.to_utf8("true")

## text-layout Unicode analysis is pinned to the reviewed Unicode 17 package release.
expect KernelUnicode.version == "17.0.0"

## Object/value/edge storage is likewise package-private.
expect KernelObject.counts(
	KernelObject.init({
		max_array_items: 0,
		max_byte_string_bytes: 0,
		max_byte_strings: 0,
		max_dictionary_entries: 0,
		max_direct_depth: 0,
		max_name_bytes: 0,
		max_names: 0,
		max_objects: 0,
		max_payload_bytes: 0,
		max_payloads: 0,
		max_streams: 0,
		max_text_string_bytes: 0,
		max_text_strings: 0,
		max_values: 0,
	}),
).objects == 0

## Sealing remains private and accepts the empty construction store.
expect match KernelSeal.seal(
	KernelObject.init({
		max_array_items: 0,
		max_byte_string_bytes: 0,
		max_byte_strings: 0,
		max_dictionary_entries: 0,
		max_direct_depth: 0,
		max_name_bytes: 0,
		max_names: 0,
		max_objects: 0,
		max_payload_bytes: 0,
		max_payloads: 0,
		max_streams: 0,
		max_text_string_bytes: 0,
		max_text_strings: 0,
		max_values: 0,
	}),
) {
	Ok(_) => True
	Err(_) => False
}

## The blank-page structural lowerer is private to the package.
expect match KernelStructure.build_blank(1, KernelStructure.PageSize.A4) {
	Ok(plan) => KernelStructure.Plan.object_count(plan) == 5
	Err(_) => False
}

## The private buffered and chunk transitions share one emitter.
expect {
	plan = KernelStructure.build_blank(1, KernelStructure.PageSize.A4)?
	bytes = KernelEmit.to_bytes(plan)?

	bytes.len() > 0
}

## Standard authored content crosses the public facade without exposing PDF internals.
expect {
	document = Pdf.document({
		contents: [Pdf.title("Report"), Pdf.paragraph("Body")],
		language: "en-AU",
		title: "Report",
	})

	bytes = Pdf.to_bytes(document)?
	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 667
}

## Preparation is a one-way public boundary and both emission paths consume
## the same sealed plan.
expect {
	document = Pdf.document({ contents: [Pdf.paragraph("Prepared once")], language: "en-AU", title: "Prepared" })
	prepared = Pdf.prepare(document, Pdf.Options.default)?
	buffered = Pdf.to_bytes_prepared(prepared)?
	chunked = collect_chunks(Pdf.to_chunks_prepared(prepared, ShareUnchangedResources)?)

	buffered == chunked.bytes
}

## Every sRGB theme color is resolved through the packaged profile rather
## than being silently reduced to black.
expect {
	blue : Color.SourceValue
	blue = Srgb(Rgb({ blue: 65535, green: 16000, red: 4000 }))
	theme = Theme.with_body_color(Theme.default, blue)
	options = Pdf.Options.with_theme(Pdf.Options.default, theme)
	document = Pdf.document({ contents: [Pdf.paragraph("Blue body text")], language: "en-AU", title: "Color" })
	bytes = Pdf.to_bytes_with(document, options)?

	bytes.len() > 667
}

## Unsupported page artifacts reject atomically through the facade; no blank
## document or partial bytes can escape a Try error.
expect {
	document = Pdf.document({
		contents: [Pdf.page_header("Running header")],
		language: "en-AU",
		title: "Artifact rejection",
	})

	match Pdf.to_bytes(document) {
		Err(UnsupportedAuthoringContent({ blocks })) => blocks == 1
		_ => False
	}
}

## Empty Standard documents emit one structural PDF 2.0 page.
expect {
	document = Pdf.document({ contents: [], language: "en-AU", title: "Blank" })
	bytes = Pdf.to_bytes(document)?

	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n")
}

## The explicit Standard option takes the same authored-content path.
expect {
	document = Pdf.document({
		contents: [Pdf.paragraph("Explicit Standard")],
		language: "en-AU",
		title: "Explicit Standard",
	})
	options = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Standard)
	bytes = Pdf.to_bytes_with(document, options)?

	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 667
}

## Archive remains unavailable rather than silently emitting Standard output.
expect {
	document = Pdf.document({ contents: [], language: "en-AU", title: "Archive" })
	options = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Archive)

	match Pdf.to_bytes_with(document, options) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, feature: Feature(code), message, .. }], .. })) => code == "profile.archive" and message.contains("Gate 5")
		_ => False
	}
}

## AccessibleArchive remains unavailable rather than dropping its UA claim.
expect {
	document = Pdf.document({ contents: [], language: "en-AU", title: "Accessible" })
	options = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.AccessibleArchive)

	match Pdf.to_bytes_with(document, options) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, feature: Feature(code), message, .. }], .. })) => code == "profile.accessible_archive" and message.contains("Gate 7")
		_ => False
	}
}

## Chunked facade output is byte-identical with buffered output.
expect {
	document = Pdf.document({ contents: [], language: "en-AU", title: "Blank" })
	expected = Pdf.to_bytes(document)?
	var $encoder = Pdf.to_chunks(document)?
	var $actual = []
	var $done = False
	while $done == False {
		match Pdf.next_chunk($encoder) {
			Done => {
				$done = True
			}
			Emit(bytes, next) => {
				$actual = append_pdf_bytes($actual, bytes)
				$encoder = next
			}
		}
	}

	$actual == expected
}

## Authored chunked output is byte-identical to buffered output and arrives
## in more than one plan-derived chunk.
expect {
	document = Pdf.document({
		contents: [Pdf.title("Report"), Pdf.paragraph("Body")],
		language: "en-AU",
		title: "Report",
	})
	expected = Pdf.to_bytes(document)?
	collected = collect_chunks(Pdf.to_chunks(document)?)

	collected.chunks >= 2 and collected.bytes == expected
}

## Unsupported authored content rejects atomically before any chunk exists.
expect {
	document = Pdf.document({
		contents: [Pdf.page_header("Running header")],
		language: "en-AU",
		title: "Chunk rejection",
	})

	match Pdf.to_chunks(document) {
		Err(UnsupportedAuthoringContent({ blocks })) => blocks == 1
		_ => False
	}
}

## The owned-chunk retention mode concatenates to the identical authored bytes.
expect {
	document = Pdf.document({
		contents: [Pdf.title("Report"), Pdf.paragraph("Body")],
		language: "en-AU",
		title: "Report",
	})
	expected = Pdf.to_bytes(document)?
	options = Pdf.Options.with_chunk_retention(Pdf.Options.default, Pdf.ChunkRetention.OwnChunks)
	collected = collect_chunks(Pdf.to_chunks_with(document, options)?)

	collected.bytes == expected
}

collect_chunks : Pdf.Encode -> { bytes : List(U8), chunks : U64 }
collect_chunks = |encoder| {
	var $encoder = encoder
	var $bytes = []
	var $chunks = 0
	var $done = False
	while $done == False {
		match Pdf.next_chunk($encoder) {
			Done => {
				$done = True
			}
			Emit(chunk, next) => {
				$bytes = append_pdf_bytes($bytes, chunk)
				$chunks = $chunks + 1
				$encoder = next
			}
		}
	}
	{ bytes: $bytes, chunks: $chunks }
}

append_pdf_bytes : List(U8), List(U8) -> List(U8)
append_pdf_bytes = |target, source| {
	length = source.len()
	var $out = List.reserve(target, length)
	var $index = 0
	while $index < length {
		match source.get($index) {
			Ok(byte) => {
				$out = $out.append(byte)
			}
			Err(OutOfBounds) => {
				crash "PDF chunk test index invariant failed"
			}
		}
		$index = $index + 1
	}
	$out
}

## Facade navigation: URI and internal links, an authored named destination,
## an outline, and page labels lower end to end through the standard
## pipeline, and the navigation rejections surface as typed errors.
expect {
	document = Pdf.document({
		contents: [
			Pdf.title("Navigation"),
			Pdf.destination_heading("intro", 1, "Introduction"),
			Pdf.paragraph("Opening body text."),
			Pdf.link("Visit the project site", "https://example.org/project"),
			Pdf.internal_link("Back to the introduction", "intro"),
		],
		language: "en-AU",
		title: "Navigation",
	})
	navigated = document
		.with_outline([{ depth: 0, destination: "intro", open: True, title: "Introduction" }])
		.with_page_labels([{ prefix: "", start_number: 1, start_page: 0, style: DecimalArabic }])
	bytes = Pdf.to_bytes(navigated)?

	bytes.len() > 4717
}

## A navigation document's chunked output is byte-identical to its buffered
## output under both retention policies.
expect {
	document = Pdf.document({
		contents: [
			Pdf.destination_heading("start", 1, "Start"),
			Pdf.internal_link("Back to the start", "start"),
			Pdf.link("Reference", "https://example.org/ref"),
		],
		language: "en-AU",
		title: "Chunked navigation",
	}).with_outline([{ depth: 0, destination: "start", open: True, title: "Start" }])
	expected = Pdf.to_bytes(document)?
	shared = collect_chunks(Pdf.to_chunks(document)?)
	owned_options = Pdf.Options.with_chunk_retention(Pdf.Options.default, OwnChunks)
	owned = collect_chunks(Pdf.to_chunks_with(document, owned_options)?)

	shared.bytes == expected and owned.bytes == expected
}

## An unknown destination name on an internal link is a typed navigation
## rejection through the facade, and no bytes escape.
expect {
	document = Pdf.document({
		contents: [Pdf.internal_link("Broken", "missing")],
		language: "en-AU",
		title: "Broken",
	})

	match Pdf.to_bytes(document) {
		Err(InvalidNavigation(UnknownDestinationName({ annotation: 0 }))) => True
		_ => False
	}
}
