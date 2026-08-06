import Semantics
import KernelFont

Font :: [].{
	ResourceId :: U64.{
		from_index : U64 -> ResourceId
		from_index = |index| ResourceId.(index)

		index : ResourceId -> U64
		index = |ResourceId.(index)| index
	}

	FaceId :: U64.{
		from_index : U64 -> FaceId
		from_index = |index| FaceId.(index)

		index : FaceId -> U64
		index = |FaceId.(index)| index
	}

	InstanceId :: U64.{
		from_index : U64 -> InstanceId
		from_index = |index| InstanceId.(index)

		index : InstanceId -> U64
		index = |InstanceId.(index)| index
	}

	PolicyId :: U64.{
		from_index : U64 -> PolicyId
		from_index = |index| PolicyId.(index)

		index : PolicyId -> U64
		index = |PolicyId.(index)| index
	}

	Script :: Str.{
		from_iso15924 : Str -> Script
		from_iso15924 = |value| Script.(value)

		as_str : Script -> Str
		as_str = |Script.(value)| value
	}

	ScalarSpan : { first : U32, last : U32 }

	Format : [OpenTypeTrueType]

	EmbeddingRights : [Editable, Installable, PreviewAndPrint, Restricted]

	## These alternatives are capability facts, not fallback levels. Packaged
	## coverage does not imply that the built-in shaper supports the script.
	ShapingProvision : [
		AdvancedRunsRequired,
		BuiltIn,
		PackagedCoverageOnly,
	]

	Resource : {
		bytes : List(U8),
		id : ResourceId,
	}

	## Coverage and script fields are exact ranges into their respective flat
	## store buffers. A validated face never consults a system font registry.
	Face : {
		coverage : Semantics.Range,
		embedding_rights : EmbeddingRights,
		format : Format,
		id : FaceId,
		provision : ShapingProvision,
		resource : ResourceId,
		scripts : Semantics.Range,
	}

	## Gate 0 accepts only static instances. A future variable-font capability
	## can extend InstanceKind without changing face or plan identity.
	InstanceKind : [Static]
	Instance : {
		face : FaceId,
		id : InstanceId,
		kind : InstanceKind,
	}
	InstanceKey : { face : FaceId, kind : InstanceKind }

	Policy : {

		## Ordered exact instances are the complete selection search space.
		id : PolicyId,
		instances : List(InstanceId),
	}

	SourceCluster : {
		source : Semantics.TextRange,
	}

	PlanRequest : {
		clusters : List(SourceCluster),
		language : Semantics.Language,
		policy : PolicyId,
		script : Script,
		source : Semantics.TextSourceId,
	}

	## Resource and face identities are exact-byte and exact-face cache keys.
	ParseKey : { resource : ResourceId }
	CoverageKey : { face : FaceId }
	PlanKey : {
		language : Semantics.Language,
		policy : PolicyId,
		script : Script,
		source : Semantics.TextSourceId,
		source_range : Semantics.TextRange,
	}

	## A face range covers whole grapheme clusters; it cannot split one to
	## select a different font for an independent scalar.
	FaceRange : {
		clusters : Semantics.Range,
		instance : InstanceId,
	}

	PlanWork : {
		coverage_span_visits : U64,
		face_visits : U64,
		grapheme_visits : U64,
	}

	Plan : {
		face_ranges : List(FaceRange),
		work : PlanWork,
	}

	PlanError : [
		EmbeddingProhibited(FaceId),
		MissingCoverage({ cluster : U64, source : Semantics.TextRange }),
		UnsupportedBuiltInShaping({ cluster : U64, script : Script }),
	]

	## Rejection is transactional and never carries a partial usable plan.
	PlanResult : [Complete(Plan), Rejected(List(PlanError))]

	ValidationDimension : [CmapMappings, FontBytes, Glyphs, Tables]
	ResourceError : [
		EmbeddingRightsProhibited({ fs_type : U16 }),
		InvalidFont,
		InvalidScript({ index : U64 }),
		LimitExceeded({ attempted : U64, dimension : ValidationDimension, limit : U64 }),
		UnknownFace(FaceId),
		UnsupportedFormat(U32),
	]
	ValidationLimits :: { max_bytes : U64, max_cmap_mappings : U64, max_glyphs : U64, max_tables : U64 }.{
		default : ValidationLimits
		default = ValidationLimits.{ max_bytes: 2000000, max_cmap_mappings: 1200000, max_glyphs: 65535, max_tables: 128 }

		make : { max_bytes : U64, max_cmap_mappings : U64, max_glyphs : U64, max_tables : U64 } -> ValidationLimits
		make = |limits| ValidationLimits.(limits)
	}

	Registration : { provision : ShapingProvision, scripts : List(Script) }
	RegistrationWork : {
		cmap_mapping_visits : U64,
		component_edge_visits : U64,
		copied_input_bytes : U64,
		glyph_visits : U64,
		input_bytes : U64,
		retained_input_bytes : U64,
		table_visits : U64,
	}

	Store : {
		coverage_spans : List(ScalarSpan),
		faces : List(Face),
		instances : List(Instance),
		policies : List(Policy),
		resources : List(Resource),
		scripts : List(Script),
	}

	Registry :: { inspections : List(KernelFont.Inspection), store : Store }.{
		empty : Registry
		empty = Registry.({ inspections: [], store: empty_store })

		register : Registry, List(U8), Registration, ValidationLimits -> Try({ face : FaceId, instance : InstanceId, policy : PolicyId, registry : Registry, work : RegistrationWork }, ResourceError)
		register = |registry, bytes, registration, limits| register_font(registry, bytes, registration, limits)

		store : Registry -> Store
		store = |Registry.(state)| state.store
	}
}

empty_store : Font.Store
empty_store = { coverage_spans: [], faces: [], instances: [], policies: [], resources: [], scripts: [] }

register_font : Font.Registry, List(U8), Font.Registration, Font.ValidationLimits -> Try({ face : Font.FaceId, instance : Font.InstanceId, policy : Font.PolicyId, registry : Font.Registry, work : Font.RegistrationWork }, Font.ResourceError)
register_font = |Font.Registry.(state), bytes, registration, Font.ValidationLimits.(limits)| {
	validate_scripts(registration.scripts)?
	inspection = KernelFont.inspect(bytes, KernelFont.Limits.make(limits)) ? map_font_error
	resource_index = state.store.resources.len()
	face_index = state.store.faces.len()
	instance_index = state.store.instances.len()
	policy_index = state.store.policies.len()
	if resource_index != face_index or face_index != instance_index or instance_index != policy_index or state.inspections.len() != face_index {
		return Err(InvalidFont)
	}
	resource = Font.ResourceId.from_index(resource_index)
	face = Font.FaceId.from_index(face_index)
	instance = Font.InstanceId.from_index(instance_index)
	policy = Font.PolicyId.from_index(policy_index)
	coverage_start = state.store.coverage_spans.len()
	var $coverage = state.store.coverage_spans
	var $coverage_index = 0
	while $coverage_index < inspection.coverage.len() {
		span = list_at(inspection.coverage, $coverage_index)
		$coverage = $coverage.append({ first: span.first, last: span.last })
		$coverage_index = $coverage_index + 1
	}
	script_start = state.store.scripts.len()
	var $scripts = state.store.scripts
	var $script_index = 0
	while $script_index < registration.scripts.len() {
		$scripts = $scripts.append(list_at(registration.scripts, $script_index))
		$script_index = $script_index + 1
	}
	font_rights = match inspection.embedding_rights {
		Editable => Editable
		Installable => Installable
		PreviewAndPrint => PreviewAndPrint
	}
	store = {
		coverage_spans: $coverage,
		faces: state.store.faces.append({
			coverage: Semantics.Range.from_start_and_length(coverage_start, inspection.coverage.len()),
			embedding_rights: font_rights,
			format: OpenTypeTrueType,
			id: face,
			provision: registration.provision,
			resource,
			scripts: Semantics.Range.from_start_and_length(script_start, registration.scripts.len()),
		}),
		instances: state.store.instances.append({ face, id: instance, kind: Static }),
		policies: state.store.policies.append({ id: policy, instances: [instance] }),
		resources: state.store.resources.append({ bytes, id: resource }),
		scripts: $scripts,
	}
	Ok({
		face,
		instance,
		policy,
		registry: Font.Registry.({ inspections: state.inspections.append(inspection), store }),
		work: {
			cmap_mapping_visits: inspection.work.cmap_mapping_visits,
			component_edge_visits: inspection.work.component_edge_visits,
			copied_input_bytes: 0,
			glyph_visits: inspection.work.glyph_visits,
			input_bytes: bytes.len(),
			retained_input_bytes: inspection.bytes.len(),
			table_visits: inspection.work.directory_entries,
		},
	})
}

validate_scripts : List(Font.Script) -> Try({}, Font.ResourceError)
validate_scripts = |scripts| {
	if scripts.is_empty() {
		return Err(InvalidScript({ index: 0 }))
	}
	var $index = 0
	while $index < scripts.len() {
		bytes = Str.to_utf8(list_at(scripts, $index).as_str())
		if bytes.len() != 4 or !ascii_upper(list_at(bytes, 0)) or !ascii_lower(list_at(bytes, 1)) or !ascii_lower(list_at(bytes, 2)) or !ascii_lower(list_at(bytes, 3)) {
			return Err(InvalidScript({ index: $index }))
		}
		var $previous = 0
		while $previous < $index {
			if list_at(scripts, $previous).as_str() == list_at(scripts, $index).as_str() {
				return Err(InvalidScript({ index: $index }))
			}
			$previous = $previous + 1
		}
		$index = $index + 1
	}
	Ok({})
}

map_font_error : KernelFont.Error -> Font.ResourceError
map_font_error = |error| match error {
	InvalidEmbeddingRights(fs_type) => {
		problem : Font.ResourceError
		problem = EmbeddingRightsProhibited({ fs_type: fs_type })
		problem
	}
	LimitExceeded({ attempted, dimension, limit }) => LimitExceeded({ attempted, dimension, limit })
	CmapLimitExceeded({ attempted, limit }) => LimitExceeded({ attempted, dimension: CmapMappings, limit })
	UnsupportedFontProgram(signature) => UnsupportedFormat(signature)
	_ => InvalidFont
}

ascii_upper : U8 -> Bool
ascii_upper = |byte| byte >= 0x41 and byte <= 0x5a

ascii_lower : U8 -> Bool
ascii_lower = |byte| byte >= 0x61 and byte <= 0x7a

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated font registry index escaped"
	}
	Ok(value) => value
}

## Font resource IDs preserve their dense index.
expect Font.ResourceId.from_index(2).index() == 2

## Font face IDs preserve their dense index.
expect Font.FaceId.from_index(3).index() == 3

## Static font instance IDs preserve their dense index.
expect Font.InstanceId.from_index(5).index() == 5

## Font policy IDs preserve their dense index.
expect Font.PolicyId.from_index(6).index() == 6

## Script tags retain their exact source spelling for later validation.
expect Font.Script.from_iso15924("Latn").as_str() == "Latn"
