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
		postscript_name : List(U8),
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

		## These are the already-segmented scalar facts for exactly one grapheme
		## cluster. Font planning deliberately does not decode UTF-8 or rediscover
		## grapheme boundaries from a later source store.
		scalars : List(U32),

		## Script itemization is an earlier Unicode fact. A cluster does not borrow
		## a neighbouring run's provision merely because it shares one source.
		script : Script,
		source : Semantics.TextRange,
	}

	PlanRequest : {
		clusters : List(SourceCluster),
		language : Semantics.Language,
		policy : PolicyId,
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
		EmptyCluster({ cluster : U64, source : Semantics.TextRange }),
		EmbeddingProhibited(FaceId),
		InvalidPolicy(PolicyId),
		MissingCoverage({ cluster : U64, source : Semantics.TextRange }),
		UnsupportedBuiltInShaping({ cluster : U64, script : Script }),
	]
	PolicyError : [
		AmbiguousFace(FaceId),
		EmptyPolicy,
		UnknownPolicyFace(FaceId),
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

		## The advanced fixed-layout boundary consumes the validation facts
		## retained by registration. This never reparses or copies font bytes.
		prepared_face : Registry, FaceId -> Try(KernelFont.Inspection, ResourceError)
		prepared_face = |registry, face| registry_inspection(registry, face)

		## A policy is the finite, ordered search space for one text style. It is
		## constructed before planning, so selection never consults names, host
		## fonts, or registry insertion order as an implicit fallback.
		with_policy : Registry, List(FaceId) -> Try({ policy : PolicyId, registry : Registry }, PolicyError)
		with_policy = |registry, faces| add_policy(registry, faces)

		## Selection consumes caller-provided cluster facts and returns dense
		## instance ranges. It is intentionally separate from shaping and PDF
		## lowering: downstream stages receive the exact selected instance rather
		## than needing to infer it again from glyphs or coverage tables.
		plan : Registry, PlanRequest -> PlanResult
		plan = |registry, request| plan_clusters(registry, request)
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
			postscript_name: KernelFont.postscript_name(inspection),
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

registry_inspection : Font.Registry, Font.FaceId -> Try(KernelFont.Inspection, Font.ResourceError)
registry_inspection = |Font.Registry.(state), face| {
	index = face.index()
	if index >= state.inspections.len() or index >= state.store.faces.len() or list_at(state.store.faces, index).id.index() != index {
		Err(UnknownFace(face))
	} else {
		Ok(list_at(state.inspections, index))
	}
}

add_policy : Font.Registry, List(Font.FaceId) -> Try({ policy : Font.PolicyId, registry : Font.Registry }, Font.PolicyError)
add_policy = |Font.Registry.(state), faces| {
	if faces.is_empty() {
		return Err(EmptyPolicy)
	}
	var $face_index = 0
	while $face_index < faces.len() {
		face = list_at(faces, $face_index)
		if face.index() >= state.store.faces.len() or list_at(state.store.faces, face.index()).id.index() != face.index() {
			return Err(UnknownPolicyFace(face))
		}
		var $previous = 0
		while $previous < $face_index {
			if list_at(faces, $previous).index() == face.index() {
				return Err(AmbiguousFace(face))
			}
			$previous = $previous + 1
		}
		$face_index = $face_index + 1
	}
	policy = Font.PolicyId.from_index(state.store.policies.len())
	var $instances = []
	$face_index = 0
	while $face_index < faces.len() {
		face = list_at(faces, $face_index)

		## Static-instance identity is validated at registration and remains dense.
		$instances = $instances.append(Font.InstanceId.from_index(face.index()))
		$face_index = $face_index + 1
	}
	store = { ..state.store, policies: state.store.policies.append({ id: policy, instances: $instances }) }
	Ok({ policy, registry: Font.Registry.({ inspections: state.inspections, store }) })
}

plan_clusters : Font.Registry, Font.PlanRequest -> Font.PlanResult
plan_clusters = |Font.Registry.(state), request| {
	policy_index = request.policy.index()
	if policy_index >= state.store.policies.len() {
		return Rejected([InvalidPolicy(request.policy)])
	}
	policy = list_at(state.store.policies, policy_index)
	if policy.id.index() != request.policy.index() or policy.instances.is_empty() {
		return Rejected([InvalidPolicy(request.policy)])
	}
	var $ranges = []
	var $errors = []
	var $coverage_visits = 0
	var $face_visits = 0
	var $cluster_index = 0
	while $cluster_index < request.clusters.len() {
		cluster = list_at(request.clusters, $cluster_index)
		if cluster.scalars.is_empty() {
			$errors = $errors.append(EmptyCluster({ cluster: $cluster_index, source: cluster.source }))
		} else {
			match select_instance(state.store, policy, cluster, cluster.script, $coverage_visits, $face_visits) {
				Err(work) => {
					$coverage_visits = work.coverage_span_visits
					$face_visits = work.face_visits
					$errors = $errors.append(MissingCoverage({ cluster: $cluster_index, source: cluster.source }))
				}
				Ok(selected) => {
					$coverage_visits = selected.coverage_span_visits
					$face_visits = selected.face_visits
					$ranges = append_face_range($ranges, selected.instance, $cluster_index)
				}
			}
		}
		$cluster_index = $cluster_index + 1
	}
	if $errors.is_empty() == False {
		Rejected($errors)
	} else {
		Complete({ face_ranges: $ranges, work: { coverage_span_visits: $coverage_visits, face_visits: $face_visits, grapheme_visits: request.clusters.len() } })
	}
}

select_instance : Font.Store, Font.Policy, Font.SourceCluster, Font.Script, U64, U64 -> Try({ coverage_span_visits : U64, face_visits : U64, instance : Font.InstanceId }, { coverage_span_visits : U64, face_visits : U64 })
select_instance = |store, policy, cluster, script, prior_coverage, prior_faces| {
	var $instance_index = 0
	var $coverage_visits = prior_coverage
	var $face_visits = prior_faces
	while $instance_index < policy.instances.len() {
		instance = list_at(policy.instances, $instance_index)
		if instance.index() >= store.instances.len() {
			return Err({ coverage_span_visits: $coverage_visits, face_visits: $face_visits })
		}
		instance_record = list_at(store.instances, instance.index())
		face_index = instance_record.face.index()
		if instance_record.id.index() != instance.index() or face_index >= store.faces.len() {
			return Err({ coverage_span_visits: $coverage_visits, face_visits: $face_visits })
		}
		face = list_at(store.faces, face_index)
		$face_visits = $face_visits + 1

		if face.id.index() == instance_record.face.index() and face_supports_script(store, face, script) {
			coverage = cluster_coverage(store, face, cluster.scalars, $coverage_visits)
			$coverage_visits = coverage.visits
			if coverage.covered {
				return Ok({ coverage_span_visits: $coverage_visits, face_visits: $face_visits, instance })
			}
		}
		$instance_index = $instance_index + 1
	}
	Err({ coverage_span_visits: $coverage_visits, face_visits: $face_visits })
}

face_supports_script : Font.Store, Font.Face, Font.Script -> Bool
face_supports_script = |store, face, script| {
	var $index = 0
	while $index < face.scripts.length() {
		script_index = face.scripts.start() + $index
		if script_index >= store.scripts.len() {
			return False
		}
		if list_at(store.scripts, script_index).as_str() == script.as_str() {
			return True
		}
		$index = $index + 1
	}
	False
}

cluster_coverage : Font.Store, Font.Face, List(U32), U64 -> { covered : Bool, visits : U64 }
cluster_coverage = |store, face, scalars, prior_visits| {
	var $scalar_index = 0
	var $visits = prior_visits
	while $scalar_index < scalars.len() {
		scalar = list_at(scalars, $scalar_index)
		var $span_index = 0
		var $covered = False
		while $span_index < face.coverage.length() {
			coverage_index = face.coverage.start() + $span_index
			if coverage_index >= store.coverage_spans.len() {
				return { covered: False, visits: $visits }
			}
			span = list_at(store.coverage_spans, coverage_index)
			$visits = $visits + 1
			if scalar >= span.first and scalar <= span.last {
				$covered = True
			}
			$span_index = $span_index + 1
		}
		if $covered == False {
			return { covered: False, visits: $visits }
		}
		$scalar_index = $scalar_index + 1
	}
	{ covered: True, visits: $visits }
}

append_face_range : List(Font.FaceRange), Font.InstanceId, U64 -> List(Font.FaceRange)
append_face_range = |ranges, instance, cluster| {
	if ranges.is_empty() {
		return [{ clusters: Semantics.Range.from_start_and_length(cluster, 1), instance }]
	}
	last_index = ranges.len() - 1
	last = list_at(ranges, last_index)
	if last.instance.index() == instance.index() and last.clusters.start() + last.clusters.length() == cluster {
		match ranges.set(last_index, { clusters: Semantics.Range.from_start_and_length(last.clusters.start(), last.clusters.length() + 1), instance }) {
			Ok(updated) => updated
			Err(OutOfBounds) => crash "validated font plan range update escaped"
		}
	} else {
		ranges.append({ clusters: Semantics.Range.from_start_and_length(cluster, 1), instance })
	}
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
