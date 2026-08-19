import pdf.Font
import pdf.KernelFont
import pdf.Pdf
import pdf.Semantics
import pdf.Theme
import "../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font : List(U8)
import "../tests/assets/CallerFont-Regular.ttf" as caller_font : List(U8)
import "../tests/assets/CallerFont-Restricted.ttf" as restricted_font : List(U8)
import "../tests/assets/IBMPlexSansHebrew-Rtl-Fixture.ttf" as hebrew_font : List(U8)
import "../tests/assets/IBMPlexSerif-FiLigature-Fixture.ttf" as ligature_font : List(U8)
import "../tests/assets/NotoSansSC-CJK-Fixture.ttf" as cjk_font : List(U8)

RegistryTargets :: [].{
	Registration : { font : U8, limits : U8, provision : U8, scripts : List(U8) }
	Cluster : { scalars : List(U8), script : U8 }
	Input : {
		clusters : List(Cluster),
		facade : U8,
		plan_policy : U8,
		policies : List(List(U8)),
		probe : U8,
		registrations : List(Registration),
	}

	## Drive the public `Font.Registry` boundary rather than the kernel behind
	## it: `empty`, then N `register` calls over caller font bytes, then M
	## `with_policy` calls, then `plan`, then the same registry through the
	## facade. Caller font bytes are the most exposed public input this package
	## takes, and the wrapper that validates and retains them is a different
	## body of code from the inspector the other font targets already cover.
	##
	## The properties are the ones a caller can actually rely on:
	##
	## - a registry is a persistent value, so every mutator appends and the
	##   value the caller already holds keeps working unchanged,
	## - resource, face, instance, and the implicitly created single-face policy
	##   share one dense index, and the flat coverage and script buffers are
	##   exactly tiled by the faces in registration order,
	## - `copied_input_bytes` is zero for every accepted font, which is the
	##   package's zero-copy claim about caller bytes,
	## - `policy_faces` round-trips the exact ordered face list it was given
	##   rather than re-deriving an order from insertion history,
	## - out-of-range identities are typed errors at the `index == len`
	##   boundary, not only at some far-away index,
	## - and planning is transactional: one complete plan whose face ranges tile
	##   the clusters, or an ascending list of every cluster's rejection.
	registry_boundary : Input -> Bool
	registry_boundary = |input| {
		registered = match register_all(input.registrations) {
			Err(Violation) => return False
			Ok(value) => value
		}
		configured = match add_policies(registered, input.policies) {
			Err(Violation) => return False
			Ok(value) => value
		}
		if !boundary_probes(configured, input.probe) {
			return False
		}
		if !registers_after_policy(configured) {
			return False
		}
		if !plan_invariants(configured, input) {
			return False
		}
		facade_wiring(configured, input.facade)
	}
}

## The registry the caller ends up holding, the face identities it handed back,
## and the policy count those calls should have produced.
Configured : {
	faces : List(Font.FaceId),
	policies : U64,
	registry : Font.Registry,
}

## Apply every generated registration in order against one growing registry.
##
## Registration happens before any explicit policy so that the face identities
## this returns are a dense prefix the later invariants can index directly.
## The two mutators are freely interleavable; `registers_after_policy`
## below pins that consequence separately.
register_all : List(RegistryTargets.Registration) -> Try(Configured, [Violation])
register_all = |specs| {
	var $registry = Font.Registry.empty
	var $faces = []
	var $index = 0
	while $index < specs.len() {
		spec = list_at(specs, $index)
		bytes = fixture(spec.font)
		scripts = scripts_for(spec.scripts)
		limits = limit_choice(spec.limits)
		registration = { provision: provision_for(spec.provision), scripts }
		before = $registry.store()

		## The first pre-call store is the empty registry's, observed through a
		## loop variable so it is a measurement rather than a folded constant.
		if $index == 0 and !empty_store(before) {
			return Err(Violation)
		}
		match $registry.register(bytes, registration, Font.ValidationLimits.make(limits)) {
			Err(error) => {

				## A rejection leaves the caller holding the registry it already
				## had, so the loop simply continues with it. What the property
				## checks is that the rejection is the exact one the public
				## contract describes for this input.
				if !expected_registration_failure(error, spec, scripts, limits) {
					return Err(Violation)
				}
			}
			Ok(result) => {
				after = result.registry.store()
				position = before.faces.len()
				if !append_only(before, after) or !tiled(after) {
					return Err(Violation)
				}
				if after.faces.len() != position + 1 or
					after.instances.len() != position + 1 or
						after.policies.len() != position + 1 or
							after.resources.len() != position + 1 {
					return Err(Violation)
				}
				if result.face.index() != position or
					result.instance.index() != position or
						result.policy.index() != position {
					return Err(Violation)
				}
				if !dense_identities(after, position, registration) {
					return Err(Violation)
				}
				if list_at(after.resources, position).bytes != bytes {
					return Err(Violation)
				}
				inspection = match result.registry.prepared_face(result.face) {
					Err(_) => return Err(Violation)
					Ok(value) => value
				}
				if !work_invariants(result.work, bytes, inspection) or
					!retained_coverage(after, position, inspection) {
					return Err(Violation)
				}

				## The implicit policy registration created resolves back to the
				## single face it was created for.
				match result.registry.policy_faces(result.policy) {
					Err(_) => return Err(Violation)
					Ok(returned) => if !same_faces(returned, [result.face]) return Err(Violation)
				}
				$registry = result.registry
				$faces = $faces.append(result.face)
			}
		}
		$index = $index + 1
	}
	Ok({ faces: $faces, policies: $faces.len(), registry: $registry })
}

empty_store : Font.Store -> Bool
empty_store = |store|
	store.coverage_spans.is_empty() and
		store.faces.is_empty() and
			store.instances.is_empty() and
				store.policies.is_empty() and
					store.resources.is_empty() and
						store.scripts.is_empty()

## Every mutator on a persistent registry appends. The pre-call value of every
## flat buffer must survive as a bit-identical prefix of the post-call value,
## which is what makes the pre-call registry independently usable afterwards.
append_only : Font.Store, Font.Store -> Bool
append_only = |before, after|
	prefix_of_spans(before.coverage_spans, after.coverage_spans) and
		prefix_of_faces(before.faces, after.faces) and
			prefix_of_instances(before.instances, after.instances) and
				prefix_of_policies(before.policies, after.policies) and
					prefix_of_resources(before.resources, after.resources) and
						prefix_of_scripts(before.scripts, after.scripts)

## Constructing a policy is a strictly narrower append than registration: it
## touches the policy space and leaves every other buffer at the exact length
## and content it already had.
policy_append_only : Font.Store, Font.Store -> Bool
policy_append_only = |before, after|
	before.coverage_spans.len() == after.coverage_spans.len() and
		before.faces.len() == after.faces.len() and
			before.instances.len() == after.instances.len() and
				before.resources.len() == after.resources.len() and
					before.scripts.len() == after.scripts.len() and
						append_only(before, after)

## The registry's identity types are opaque, so the prefix comparisons below are
## written out field by field: `index()` and `as_str()` are the only ways to
## observe a face, instance, policy, resource, or script identity from outside
## the package, and a derived structural equality is not available.
prefix_of_spans : List(Font.ScalarSpan), List(Font.ScalarSpan) -> Bool
prefix_of_spans = |before, after| {
	if before.len() > after.len() {
		return False
	}
	var $index = 0
	while $index < before.len() {
		left = list_at(before, $index)
		right = list_at(after, $index)
		if left.first != right.first or left.last != right.last {
			return False
		}
		$index = $index + 1
	}
	True
}

prefix_of_faces : List(Font.Face), List(Font.Face) -> Bool
prefix_of_faces = |before, after| {
	if before.len() > after.len() {
		return False
	}
	var $index = 0
	while $index < before.len() {
		left = list_at(before, $index)
		right = list_at(after, $index)
		if left.id.index() != right.id.index() or
			left.resource.index() != right.resource.index() or
				left.coverage.start() != right.coverage.start() or
					left.coverage.length() != right.coverage.length() or
						left.scripts.start() != right.scripts.start() or
							left.scripts.length() != right.scripts.length() {
			return False
		}
		if left.embedding_rights != right.embedding_rights or
			left.format != right.format or
				left.provision != right.provision or
					left.postscript_name != right.postscript_name {
			return False
		}
		$index = $index + 1
	}
	True
}

prefix_of_instances : List(Font.Instance), List(Font.Instance) -> Bool
prefix_of_instances = |before, after| {
	if before.len() > after.len() {
		return False
	}
	var $index = 0
	while $index < before.len() {
		left = list_at(before, $index)
		right = list_at(after, $index)
		if left.id.index() != right.id.index() or
			left.face.index() != right.face.index() or
				left.kind != right.kind {
			return False
		}
		$index = $index + 1
	}
	True
}

prefix_of_policies : List(Font.Policy), List(Font.Policy) -> Bool
prefix_of_policies = |before, after| {
	if before.len() > after.len() {
		return False
	}
	var $index = 0
	while $index < before.len() {
		left = list_at(before, $index)
		right = list_at(after, $index)
		if left.id.index() != right.id.index() or !same_instances(left.instances, right.instances) {
			return False
		}
		$index = $index + 1
	}
	True
}

prefix_of_resources : List(Font.Resource), List(Font.Resource) -> Bool
prefix_of_resources = |before, after| {
	if before.len() > after.len() {
		return False
	}
	var $index = 0
	while $index < before.len() {
		left = list_at(before, $index)
		right = list_at(after, $index)
		if left.id.index() != right.id.index() or left.bytes != right.bytes {
			return False
		}
		$index = $index + 1
	}
	True
}

prefix_of_scripts : List(Font.Script), List(Font.Script) -> Bool
prefix_of_scripts = |before, after| {
	if before.len() > after.len() {
		return False
	}
	var $index = 0
	while $index < before.len() {
		if list_at(before, $index).as_str() != list_at(after, $index).as_str() {
			return False
		}
		$index = $index + 1
	}
	True
}

same_instances : List(Font.InstanceId), List(Font.InstanceId) -> Bool
same_instances = |left, right| {
	if left.len() != right.len() {
		return False
	}
	var $index = 0
	while $index < left.len() {
		if list_at(left, $index).index() != list_at(right, $index).index() {
			return False
		}
		$index = $index + 1
	}
	True
}

same_faces : List(Font.FaceId), List(Font.FaceId) -> Bool
same_faces = |left, right| {
	if left.len() != right.len() {
		return False
	}
	var $index = 0
	while $index < left.len() {
		if list_at(left, $index).index() != list_at(right, $index).index() {
			return False
		}
		$index = $index + 1
	}
	True
}

## The faces tile the two flat buffers exactly: face zero starts at zero, each
## following face starts where the previous one ended, and the last one ends at
## the buffer length. One pass establishes contiguity, absence of gaps, absence
## of overlap, and exact coverage of the buffer together.
tiled : Font.Store -> Bool
tiled = |store| {
	var $coverage_next = 0
	var $script_next = 0
	var $index = 0
	while $index < store.faces.len() {
		face = list_at(store.faces, $index)
		if face.coverage.start() != $coverage_next or face.scripts.start() != $script_next {
			return False
		}
		$coverage_next = face.coverage.start() + face.coverage.length()
		$script_next = face.scripts.start() + face.scripts.length()
		$index = $index + 1
	}
	$coverage_next == store.coverage_spans.len() and $script_next == store.scripts.len()
}

## Resource, face, instance, and the implicitly created policy all take the same
## dense index. The implicit policy is the subtle part: `register` creates one
## single-face policy of its own, so the policy space is already N entries wide
## before the caller constructs any explicit policy.
dense_identities : Font.Store, U64, Font.Registration -> Bool
dense_identities = |store, index, registration| {
	face = list_at(store.faces, index)
	instance = list_at(store.instances, index)
	policy = list_at(store.policies, index)
	resource = list_at(store.resources, index)
	if face.id.index() != index or face.resource.index() != index or resource.id.index() != index {
		return False
	}
	if instance.id.index() != index or instance.face.index() != index or instance.kind != Static {
		return False
	}
	if policy.id.index() != index or policy.instances.len() != 1 or list_at(policy.instances, 0).index() != index {
		return False
	}

	## Only one font program format is accepted today, and the provision is a
	## caller declaration that registration records rather than infers.
	if face.format != OpenTypeTrueType or face.provision != registration.provision {
		return False
	}
	if face.scripts.length() != registration.scripts.len() {
		return False
	}
	var $script_index = 0
	while $script_index < registration.scripts.len() {
		stored = list_at(store.scripts, face.scripts.start() + $script_index)
		if stored.as_str() != list_at(registration.scripts, $script_index).as_str() {
			return False
		}
		$script_index = $script_index + 1
	}
	True
}

## The face's coverage slice is exactly the inspection's coverage, copied once
## into the flat buffer in the same order. This is what lets planning resolve
## coverage from the store without holding the inspection.
retained_coverage : Font.Store, U64, KernelFont.Inspection -> Bool
retained_coverage = |store, index, inspection| {
	face = list_at(store.faces, index)
	if face.coverage.length() != inspection.coverage.len() {
		return False
	}
	var $span_index = 0
	while $span_index < inspection.coverage.len() {
		stored = list_at(store.coverage_spans, face.coverage.start() + $span_index)
		source = list_at(inspection.coverage, $span_index)
		if stored.first != source.first or stored.last != source.last {
			return False
		}
		$span_index = $span_index + 1
	}
	True
}

## `copied_input_bytes` is the package's zero-copy claim about caller font
## bytes: registration retains them and never duplicates them, whatever the
## font. The rest of the record is a per-call measurement of this registration,
## so it must describe these bytes and this inspection rather than accumulate
## across the registry.
work_invariants : Font.RegistrationWork, List(U8), KernelFont.Inspection -> Bool
work_invariants = |work, bytes, inspection|
	work.copied_input_bytes == 0 and
		work.input_bytes == bytes.len() and
			work.retained_input_bytes == inspection.bytes.len() and
				work.cmap_mapping_visits == inspection.work.cmap_mapping_visits and
					work.component_edge_visits == inspection.work.component_edge_visits and
						work.glyph_visits == inspection.work.glyph_visits and
							work.table_visits == inspection.work.directory_entries

## Decide, independently of the package, which rejection a registration must
## produce. The script rules are reimplemented here from ISO 15924's shape
## rather than reused from `Font`, so the two implementations act as oracles for
## each other.
expected_registration_failure : Font.ResourceError, RegistryTargets.Registration, List(Font.Script), LimitChoice -> Bool
expected_registration_failure = |error, spec, scripts, limits| {

	## Script validation runs before the font is even looked at, so an invalid
	## tag outranks every other rejection and must name the exact index the
	## contract rejects: the first malformed tag, or the second occurrence of a
	## duplicated one.
	match expected_script_rejection(scripts) {
		ScriptRejected(index) => return match error {
			InvalidScript(detail) => detail.index == index
			_ => False
		}
		ScriptsValid => {}
	}
	generous = spec.limits % 5 == 0
	kind = fixture_kind(spec.font)

	## A packaged fixture with a valid script list and the default limits has no
	## reason to fail, so a rejection there is a regression rather than an
	## ordinary outcome. Each deliberately broken fixture has exactly one
	## rejection it must reach under those same limits.
	if generous and kind == Healthy {
		return False
	}
	if generous and kind == Restricted and !rights_rejection(error) {
		return False
	}
	if generous and kind == Foreign and !format_rejection(error) {
		return False
	}

	## Four bytes cannot hold a table directory under any limits at all.
	if kind == Truncated and !malformed_rejection(error) {
		return False
	}
	match error {
		InvalidScript(_) => False
		LimitExceeded(detail) => detail.attempted > detail.limit and detail.limit == declared_limit(limits, detail.dimension)
		EmbeddingRightsProhibited(_) => kind == Restricted
		UnsupportedFormat(signature) => signature != 0x00010000
		InvalidFont => True

		## `UnknownFace` belongs to `prepared_face`; registration never mints it.
		UnknownFace(_) => False
	}
}

rights_rejection : Font.ResourceError -> Bool
rights_rejection = |error| match error {
	EmbeddingRightsProhibited(_) => True
	_ => False
}

format_rejection : Font.ResourceError -> Bool
format_rejection = |error| match error {
	UnsupportedFormat(_) => True
	_ => False
}

malformed_rejection : Font.ResourceError -> Bool
malformed_rejection = |error| match error {
	InvalidFont => True
	_ => False
}

## The limit a `LimitExceeded` rejection reports must be the one the caller
## declared for that dimension, not an internal default.
declared_limit : LimitChoice, Font.ValidationDimension -> U64
declared_limit = |limits, dimension| match dimension {
	CmapMappings => limits.max_cmap_mappings
	FontBytes => limits.max_bytes
	Glyphs => limits.max_glyphs
	Tables => limits.max_tables
}

## ISO 15924 script codes are exactly four ASCII bytes shaped
## `[A-Z][a-z][a-z][a-z]`, and one registration may not name the same script
## twice. A duplicate is rejected at the second occurrence, not at the first.
expected_script_rejection : List(Font.Script) -> [ScriptRejected(U64), ScriptsValid]
expected_script_rejection = |scripts| {
	if scripts.is_empty() {
		return ScriptRejected(0)
	}
	var $index = 0
	while $index < scripts.len() {
		tag = Str.to_utf8(list_at(scripts, $index).as_str())
		if tag.len() != 4 {
			return ScriptRejected($index)
		}
		if !upper_ascii(list_at(tag, 0)) or
			!lower_ascii(list_at(tag, 1)) or
				!lower_ascii(list_at(tag, 2)) or
					!lower_ascii(list_at(tag, 3)) {
			return ScriptRejected($index)
		}
		var $previous = 0
		while $previous < $index {
			if list_at(scripts, $previous).as_str() == list_at(scripts, $index).as_str() {
				return ScriptRejected($index)
			}
			$previous = $previous + 1
		}
		$index = $index + 1
	}
	ScriptsValid
}

upper_ascii : U8 -> Bool
upper_ascii = |byte| byte >= 0x41 and byte <= 0x5a

lower_ascii : U8 -> Bool
lower_ascii = |byte| byte >= 0x61 and byte <= 0x7a

## Construct every generated explicit policy against the registry the
## registrations produced.
add_policies : Configured, List(List(U8)) -> Try(Configured, [Violation])
add_policies = |configured, requests| {
	var $registry = configured.registry
	var $policies = configured.policies
	var $index = 0
	while $index < requests.len() {
		requested = policy_faces_for(list_at(requests, $index), configured.faces.len())
		before = $registry.store()
		previous = $registry
		match $registry.with_policy(requested) {
			Err(error) => if !expected_policy_failure(error, requested, configured.faces.len()) {
				return Err(Violation)
			}
			Ok(result) => {
				after = result.registry.store()
				if expected_policy_rejection(requested, configured.faces.len()) != PolicyValid {
					return Err(Violation)
				}
				if !policy_append_only(before, after) {
					return Err(Violation)
				}
				if after.policies.len() != before.policies.len() + 1 or
					result.policy.index() != before.policies.len() {
					return Err(Violation)
				}
				record = list_at(after.policies, result.policy.index())
				if record.id.index() != result.policy.index() or record.instances.len() != requested.len() {
					return Err(Violation)
				}

				## Instance identity is dense, so the policy's instance list is
				## the requested face list read through that identity.
				var $slot = 0
				while $slot < requested.len() {
					if list_at(record.instances, $slot).index() != list_at(requested, $slot).index() {
						return Err(Violation)
					}
					$slot = $slot + 1
				}

				## The round trip returns the caller's exact ordered list, not a
				## list re-derived from registration order.
				match result.registry.policy_faces(result.policy) {
					Err(_) => return Err(Violation)
					Ok(returned) => if !same_faces(returned, requested) return Err(Violation)
				}

				## The pre-call registry keeps working and does not learn about a
				## policy that was constructed from it afterwards.
				if !unknown_policy(previous, result.policy.index()) {
					return Err(Violation)
				}
				$registry = result.registry
				$policies = $policies + 1
			}
		}
		$index = $index + 1
	}
	Ok({ faces: configured.faces, policies: $policies, registry: $registry })
}

## Face choices deliberately reach two indexes past the registered faces, so the
## generator produces `UnknownPolicyFace` as often as it produces a valid
## policy, and repeats produce `AmbiguousFace`.
policy_faces_for : List(U8), U64 -> List(Font.FaceId)
policy_faces_for = |choices, face_count| {
	var $faces = []
	var $index = 0
	while $index < choices.len() {
		$faces = $faces.append(Font.FaceId.from_index(list_at(choices, $index).to_u64() % (face_count + 2)))
		$index = $index + 1
	}
	$faces
}

expected_policy_failure : Font.PolicyError, List(Font.FaceId), U64 -> Bool
expected_policy_failure = |error, requested, face_count| match (expected_policy_rejection(requested, face_count), error) {
	(RejectEmpty, EmptyPolicy) => True
	(RejectUnknown(index), UnknownPolicyFace(face)) => face.index() == index
	(RejectAmbiguous(index), AmbiguousFace(face)) => face.index() == index
	_ => False
}

## An empty policy is rejected outright; otherwise the first face that is out of
## range, or that repeats an earlier one, decides the rejection, scanning in the
## caller's order.
expected_policy_rejection : List(Font.FaceId), U64 -> [PolicyValid, RejectAmbiguous(U64), RejectEmpty, RejectUnknown(U64)]
expected_policy_rejection = |requested, face_count| {
	if requested.is_empty() {
		return RejectEmpty
	}
	var $index = 0
	while $index < requested.len() {
		face = list_at(requested, $index)
		if face.index() >= face_count {
			return RejectUnknown(face.index())
		}
		var $previous = 0
		while $previous < $index {
			if list_at(requested, $previous).index() == face.index() {
				return RejectAmbiguous(face.index())
			}
			$previous = $previous + 1
		}
		$index = $index + 1
	}
	PolicyValid
}

## Both dense spaces are probed at the `index == len` boundary as well as past
## it. The boundary is the interesting one: an off-by-one in a range check
## survives a probe at a far-out index and fails here.
boundary_probes : Configured, U8 -> Bool
boundary_probes = |configured, probe| {
	store = configured.registry.store()
	faces = configured.faces.len()

	## `register` mints one implicit single-face policy per face, so the policy
	## space is N wide before any explicit policy and N + M wide after M of them.
	if store.faces.len() != faces or store.policies.len() != configured.policies {
		return False
	}
	var $index = 0
	while $index < faces {
		match configured.registry.prepared_face(Font.FaceId.from_index($index)) {
			Err(_) => return False
			Ok(_) => {}
		}
		$index = $index + 1
	}
	if !unknown_face(configured.registry, faces) or
		!unknown_face(configured.registry, faces + 1 + probe.to_u64()) {
		return False
	}
	var $policy = 0
	while $policy < configured.policies {
		match configured.registry.policy_faces(Font.PolicyId.from_index($policy)) {
			Err(_) => return False
			Ok(returned) => if returned.is_empty() return False
		}
		$policy = $policy + 1
	}
	unknown_policy(configured.registry, configured.policies) and
		unknown_policy(configured.registry, configured.policies + 1 + probe.to_u64())
}

unknown_face : Font.Registry, U64 -> Bool
unknown_face = |registry, index| match registry.prepared_face(Font.FaceId.from_index(index)) {
	Ok(_) => False
	Err(UnknownFace(face)) => face.index() == index
	Err(_) => False
}

unknown_policy : Font.Registry, U64 -> Bool
unknown_policy = |registry, index| match registry.policy_faces(Font.PolicyId.from_index(index)) {
	Ok(_) => False
	Err(UnknownPolicy(policy)) => policy.index() == index
	Err(_) => False
}

## `with_policy` appends a policy without a resource, face, or instance, so the
## policy store is deliberately outside the parallel-array invariant `register`
## re-checks. Registration therefore stays available after any number of
## explicit policies, and the identities it hands back continue from the store
## lengths rather than from the policy count.
##
## This property found the opposite: the guard required the policy count to
## match too, so one explicit policy sealed the registry and every later
## `register` reported `InvalidFont` - a fault in the caller's bytes for a
## registry-state cause that had nothing to do with them.
registers_after_policy : Configured -> Bool
registers_after_policy = |configured| {
	if configured.policies <= configured.faces.len() {
		return True
	}
	match configured.registry.register(
		cjk_font,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Hani")] },
		Font.ValidationLimits.default,
	) {
		Err(_) => False
		Ok(added) => {
			if added.face.index() != configured.faces.len() or added.policy.index() != configured.policies {
				return False
			}
			store = added.registry.store()
			if store.faces.len() != configured.faces.len() + 1 or
				store.instances.len() != configured.faces.len() + 1 or
					store.resources.len() != configured.faces.len() + 1 or
						store.policies.len() != configured.policies + 1 {
				return False
			}

			## The implicit policy a registration creates still names exactly the
			## face that registration produced, whatever explicit policies sit
			## between them in the store.
			match added.registry.policy_faces(added.policy) {
				Err(_) => False
				Ok(faces) => same_faces(faces, [added.face])
			}
		}
	}
}

## Selection is the part of the boundary a caller cannot inspect any other way,
## so the property reimplements it: for each cluster, walk the policy's
## instances in order and take the first face that declares the cluster's script
## and covers every one of its scalars. That independent answer must match the
## planner's, cluster by cluster.
plan_invariants : Configured, RegistryTargets.Input -> Bool
plan_invariants = |configured, input| {
	store = configured.registry.store()
	clusters = clusters_for(input.clusters)
	policy = Font.PolicyId.from_index(input.plan_policy.to_u64() % (configured.policies + 2))
	request = {
		clusters,
		language: Language("en-AU"),
		policy,
		source: Semantics.TextSourceId.from_index(0),
	}
	result = configured.registry.plan(request)
	if !same_results(result, configured.registry.plan(request)) {
		return False
	}
	if policy.index() >= configured.policies {

		## An unknown policy is a single-element early return, never a list that
		## also accumulates per-cluster rejections.
		return match result {
			Complete(_) => False
			Rejected([InvalidPolicy(reported)]) => reported.index() == policy.index()
			Rejected(_) => False
		}
	}
	instances = list_at(store.policies, policy.index()).instances
	match result {
		Rejected(errors) => rejection_invariants(store, instances, clusters, errors)
		Complete(plan) => complete_invariants(store, instances, clusters, plan)
	}
}

## Rejection collects every failing cluster in ascending order and carries no
## partial plan. The repository's hand-written assertions only ever match a
## singleton list, so multi-error accumulation is checked here for the first
## time: the reported list must be exactly the failing clusters, in order, with
## the cause that cluster actually has.
rejection_invariants : Font.Store, List(Font.InstanceId), List(Font.SourceCluster), List(Font.PlanError) -> Bool
rejection_invariants = |store, instances, clusters, errors| {
	if errors.is_empty() {
		return False
	}
	var $expected = 0
	var $index = 0
	while $index < clusters.len() {
		if !cluster_succeeds(store, instances, list_at(clusters, $index)) {
			$expected = $expected + 1
		}
		$index = $index + 1
	}
	if errors.len() != $expected {
		return False
	}
	var $previous = 0
	var $error_index = 0
	while $error_index < errors.len() {
		reported = match list_at(errors, $error_index) {
			EmptyCluster(detail) => { cluster: detail.cluster, empty: True }
			MissingCoverage(detail) => { cluster: detail.cluster, empty: False }

			## `InvalidPolicy` is handled by the early return above, and
			## `EmbeddingProhibited` and `UnsupportedBuiltInShaping` are declared
			## by `Font.PlanError` but produced nowhere in the planner:
			## `EmbeddingProhibited` is a dead variant with no producer anywhere
			## in the package, and the shaping rejection is minted by the
			## facade's shaping stage instead. Seeing either here would mean a
			## new code path, not a new input.
			_ => return False
		}
		if reported.cluster >= clusters.len() or ($error_index > 0 and reported.cluster <= $previous) {
			return False
		}
		cluster = list_at(clusters, reported.cluster)
		if cluster.scalars.is_empty() != reported.empty {
			return False
		}
		if cluster_succeeds(store, instances, cluster) {
			return False
		}
		$previous = reported.cluster
		$error_index = $error_index + 1
	}
	True
}

## A complete plan's face ranges tile the clusters exactly once, in order, and
## no two adjacent ranges share an instance: the builder coalesces
## equal-instance adjacency, so the range count is the number of instance
## switches plus one.
complete_invariants : Font.Store, List(Font.InstanceId), List(Font.SourceCluster), Font.Plan -> Bool
complete_invariants = |store, instances, clusters, plan| {
	if plan.work.grapheme_visits != clusters.len() {
		return False
	}
	var $next = 0
	var $previous_instance = 0
	var $index = 0
	while $index < plan.face_ranges.len() {
		range = list_at(plan.face_ranges, $index)
		if range.clusters.start() != $next or range.clusters.length() == 0 {
			return False
		}
		if range.instance.index() >= store.instances.len() {
			return False
		}
		if $index > 0 and range.instance.index() == $previous_instance {
			return False
		}
		var $offset = 0
		while $offset < range.clusters.length() {
			cluster = list_at(clusters, range.clusters.start() + $offset)
			if selected_instance(store, instances, cluster) != Selected(range.instance.index()) {
				return False
			}
			$offset = $offset + 1
		}
		$previous_instance = range.instance.index()
		$next = range.clusters.start() + range.clusters.length()
		$index = $index + 1
	}
	$next == clusters.len()
}

cluster_succeeds : Font.Store, List(Font.InstanceId), Font.SourceCluster -> Bool
cluster_succeeds = |store, instances, cluster| match selected_instance(store, instances, cluster) {
	NoInstance => False
	Selected(_) => True
}

## The first instance in the policy's order whose face declares the cluster's
## script and covers every scalar in it. Ordered search over a finite policy is
## the whole selection contract: there is no name lookup, no host font, and no
## implicit fallback to registration order.
selected_instance : Font.Store, List(Font.InstanceId), Font.SourceCluster -> [NoInstance, Selected(U64)]
selected_instance = |store, instances, cluster| {
	if cluster.scalars.is_empty() {
		return NoInstance
	}
	var $index = 0
	while $index < instances.len() {
		instance = list_at(instances, $index)
		if instance.index() >= store.instances.len() {
			return NoInstance
		}
		face = list_at(store.faces, list_at(store.instances, instance.index()).face.index())
		if declares_script(store, face, cluster.script) and covers_all(store, face, cluster.scalars) {
			return Selected(instance.index())
		}
		$index = $index + 1
	}
	NoInstance
}

declares_script : Font.Store, Font.Face, Font.Script -> Bool
declares_script = |store, face, script| {
	var $index = 0
	while $index < face.scripts.length() {
		if list_at(store.scripts, face.scripts.start() + $index).as_str() == script.as_str() {
			return True
		}
		$index = $index + 1
	}
	False
}

covers_all : Font.Store, Font.Face, List(U32) -> Bool
covers_all = |store, face, scalars| {
	var $index = 0
	while $index < scalars.len() {
		scalar = list_at(scalars, $index)
		var $covered = False
		var $span_index = 0
		while $span_index < face.coverage.length() {
			span = list_at(store.coverage_spans, face.coverage.start() + $span_index)
			if scalar >= span.first and scalar <= span.last {
				$covered = True
			}
			$span_index = $span_index + 1
		}
		if $covered == False {
			return False
		}
		$index = $index + 1
	}
	True
}

## Planning is a pure function of the registry and the request, so repeating it
## must reproduce the same result down to the reported source ranges.
same_results : Font.PlanResult, Font.PlanResult -> Bool
same_results = |left, right| match (left, right) {
	(Complete(first), Complete(second)) => {
		if first.work != second.work or first.face_ranges.len() != second.face_ranges.len() {
			return False
		}
		var $index = 0
		while $index < first.face_ranges.len() {
			one = list_at(first.face_ranges, $index)
			other = list_at(second.face_ranges, $index)
			if one.instance.index() != other.instance.index() or
				one.clusters.start() != other.clusters.start() or
					one.clusters.length() != other.clusters.length() {
				return False
			}
			$index = $index + 1
		}
		True
	}
	(Rejected(first), Rejected(second)) => {
		if first.len() != second.len() {
			return False
		}
		var $index = 0
		while $index < first.len() {
			if !same_plan_error(list_at(first, $index), list_at(second, $index)) {
				return False
			}
			$index = $index + 1
		}
		True
	}
	_ => False
}

same_plan_error : Font.PlanError, Font.PlanError -> Bool
same_plan_error = |left, right| match (left, right) {
	(EmptyCluster(first), EmptyCluster(second)) => first.cluster == second.cluster and same_text_range(first.source, second.source)
	(MissingCoverage(first), MissingCoverage(second)) => first.cluster == second.cluster and same_text_range(first.source, second.source)
	(InvalidPolicy(first), InvalidPolicy(second)) => first.index() == second.index()
	(EmbeddingProhibited(first), EmbeddingProhibited(second)) => first.index() == second.index()
	(UnsupportedBuiltInShaping(first), UnsupportedBuiltInShaping(second)) => first.cluster == second.cluster and first.script.as_str() == second.script.as_str()
	_ => False
}

same_text_range : Semantics.TextRange, Semantics.TextRange -> Bool
same_text_range = |left, right|
	left.scalars.start() == right.scalars.start() and
		left.scalars.length() == right.scalars.length() and
			left.utf8_bytes.start() == right.utf8_bytes.start() and
				left.utf8_bytes.length() == right.utf8_bytes.length()

clusters_for : List(RegistryTargets.Cluster) -> List(Font.SourceCluster)
clusters_for = |specs| {
	var $clusters = []
	var $index = 0
	while $index < specs.len() {
		spec = list_at(specs, $index)
		var $scalars = []
		var $scalar_index = 0
		while $scalar_index < spec.scalars.len() {
			$scalars = $scalars.append(scalar_for(list_at(spec.scalars, $scalar_index)))
			$scalar_index = $scalar_index + 1
		}
		$clusters = $clusters.append({
			scalars: $scalars,
			script: script_for(spec.script),
			source: {
				scalars: Semantics.Range.from_start_and_length($index, spec.scalars.len()),
				utf8_bytes: Semantics.Range.from_start_and_length($index * 4, spec.scalars.len() * 4),
			},
		})
		$index = $index + 1
	}
	$clusters
}

## Two independent facade traps, checked through their observable consequence
## rather than by inspecting the theme.
##
## `Theme.with_font` rewrites `font_selection` to `StyleFaces`, so calling it
## after `Theme.with_font_policy` silently discards the policy; the last of the
## two calls wins in both directions. And `with_font_registry` and `with_theme`
## are independent options, so a theme naming a face minted by one registry can
## be paired with another registry, or with the packaged built-in face, and
## nothing catches the mismatch until preparation.
facade_wiring : Configured, U8 -> Bool
facade_wiring = |configured, choice| {
	faces = configured.faces.len()
	missing_face = Font.FaceId.from_index(faces)
	missing_policy = Font.PolicyId.from_index(configured.policies)
	reset = Theme.with_font(Theme.with_font_policy(Theme.default, Font.PolicyId.from_index(0)), missing_face)

	## The reset is a pure theme fact and holds for every generated registry.
	match Theme.font_selection(reset) {
		Policy(_) => return False
		StyleFaces => {}
	}
	document = Pdf.document({
		contents: [Pdf.paragraph("Ab")],
		language: "en-AU",
		title: "Registry boundary",
	})
	registered = |theme| Pdf.Options.with_font_registry(Pdf.Options.with_theme(Pdf.Options.default, theme), configured.registry)
	built_in = |theme| Pdf.Options.with_theme(Pdf.Options.default, theme)

	## One trap per execution keeps the property cheap; the generator reaches all
	## four within a handful of inputs.
	match choice % 4 {

		## The policy set first is discarded, so preparation consults the body
		## face instead and reports that face missing.
		0 => match Pdf.to_bytes_with(document, registered(reset)) {
			Err(InvalidFontResource(UnknownFace(face))) => face.index() == faces
			_ => False
		}

		## The policy set last wins, so preparation never looks at the body face
		## and reports the policy instead.
		1 => match Pdf.to_bytes_with(document, registered(Theme.with_font_policy(Theme.with_font(Theme.default, Font.FaceId.from_index(0)), missing_policy))) {
			Err(InvalidFontSelection([InvalidPolicy(policy)])) => policy.index() == configured.policies
			_ => False
		}

		## A face identity from a caller registry paired with the packaged
		## built-in source: the built-in source owns exactly face zero, and the
		## mismatch surfaces only here.
		2 => match Pdf.to_bytes_with(document, built_in(Theme.with_font(Theme.default, Font.FaceId.from_index(faces + 1)))) {
			Err(InvalidFontResource(UnknownFace(face))) => face.index() == faces + 1
			_ => False
		}

		## The built-in source defines no policies at all, so even policy zero,
		## which every non-empty registry owns, is a typed rejection there.
		_ => match Pdf.to_bytes_with(document, built_in(Theme.with_font_policy(Theme.default, Font.PolicyId.from_index(0)))) {
			Err(InvalidFontSelection([InvalidPolicy(policy)])) => policy.index() == 0
			_ => False
		}
	}
}

FixtureKind : [Foreign, Healthy, Restricted, Truncated]

fixture_kind : U8 -> FixtureKind
fixture_kind = |choice| match choice % 8 {
	5 => Restricted
	6 => Truncated
	7 => Foreign
	_ => Healthy
}

## The five text-layout fixtures the other font targets use, plus the three
## inputs that reach the registration failures nothing else in the repository
## reaches: rights-restricted, too short for a directory, and a font program
## format the package does not accept.
fixture : U8 -> List(U8)
fixture = |choice| match choice % 8 {
	0 => built_in_font
	1 => caller_font
	2 => cjk_font
	3 => hebrew_font
	4 => ligature_font
	5 => restricted_font
	6 => truncated_font
	_ => foreign_font
}

## Shorter than the twelve-byte offset table, so the directory guard rejects it
## under every limit rather than the byte-count guard in front of that.
truncated_font : List(U8)
truncated_font = [0x00, 0x01, 0x00, 0x00]

## Sixteen bytes carrying the `OTTO` signature of an OpenType CFF font. The
## inspector accepts only `0x00010000`, so this is the shortest input that gets
## past the length guard and reaches `UnsupportedFormat`.
foreign_font : List(U8)
foreign_font = [0x4f, 0x54, 0x54, 0x4f, 0x00, 0x01, 0x00, 0x10, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

LimitChoice : { max_bytes : U64, max_cmap_mappings : U64, max_glyphs : U64, max_tables : U64 }

## Rung zero is the published default; the other four are each tight in exactly
## one dimension, so a `LimitExceeded` rejection names an unambiguous dimension
## and the property can check the reported limit against the declared one.
limit_choice : U8 -> LimitChoice
limit_choice = |choice| match choice % 5 {
	0 => { max_bytes: 2000000, max_cmap_mappings: 1200000, max_glyphs: 65535, max_tables: 128 }
	1 => { max_bytes: 64, max_cmap_mappings: 1200000, max_glyphs: 65535, max_tables: 128 }
	2 => { max_bytes: 2000000, max_cmap_mappings: 1200000, max_glyphs: 65535, max_tables: 2 }
	3 => { max_bytes: 2000000, max_cmap_mappings: 1200000, max_glyphs: 4, max_tables: 128 }
	_ => { max_bytes: 2000000, max_cmap_mappings: 1, max_glyphs: 65535, max_tables: 128 }
}

provision_for : U8 -> Font.ShapingProvision
provision_for = |choice| match choice % 3 {
	0 => AdvancedRunsRequired
	1 => BuiltIn
	_ => PackagedCoverageOnly
}

scripts_for : List(U8) -> List(Font.Script)
scripts_for = |choices| {
	var $scripts = []
	var $index = 0
	while $index < choices.len() {
		$scripts = $scripts.append(script_for(list_at(choices, $index)))
		$index = $index + 1
	}
	$scripts
}

## Seven well-formed ISO 15924 codes and six that break the shape a different
## way each: empty, too short, all upper, all lower, a digit in a lowercase
## position, and a four-character tag whose UTF-8 encoding is five bytes.
script_for : U8 -> Font.Script
script_for = |choice| Font.Script.from_iso15924(
	match choice % 13 {
		0 => "Latn"
		1 => "Hani"
		2 => "Hebr"
		3 => "Arab"
		4 => "Zyyy"
		5 => "Grek"
		6 => "Cyrl"
		7 => ""
		8 => "Lat"
		9 => "LATN"
		10 => "latn"
		11 => "Lat1"
		_ => "Lätn"
	},
)

## Scalars taken from the fixtures' measured coverage, so that most generated
## clusters are selectable by some face and only some are selectable by every
## face. The four small fixtures are deliberately narrow subsets — the Latin one
## covers only `{space, C, D, F, P, a, f, é}`, the Han one covers exactly one
## ideograph, and the ligature one covers only `f` and `i` — so a ladder of
## plausible-looking letters would have made almost every cluster miss and left
## the selection and coalescing invariants unexercised.
##
## `f` is covered by three of the fixtures and `i` by two, which is what makes
## an ordered policy interesting: the first face in the policy that covers the
## cluster has to win, and adjacent clusters have to switch instance and switch
## back. The last rung is covered by nothing and reaches `MissingCoverage`.
scalar_for : U8 -> U32
scalar_for = |choice| match choice % 10 {
	0 => 0x20
	1 => 0x43
	2 => 0x61
	3 => 0x66
	4 => 0x69
	5 => 0x65
	6 => 0x4e2d
	7 => 0x05d0
	8 => 0x00e9
	_ => 0x10ffff
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "fuzz property escaped a validated dense index"
	Ok(value) => value
}

## Three registrations and two explicit policies: the policy space ends up five
## wide, which is the implicit-policy behaviour no existing test reaches.
expect RegistryTargets.registry_boundary({
	clusters: [{ scalars: [0], script: 0 }, { scalars: [6], script: 1 }, { scalars: [], script: 0 }],
	facade: 0,
	plan_policy: 3,
	policies: [[1, 2], [2, 1, 0]],
	probe: 0,
	registrations: [
		{ font: 1, limits: 0, provision: 1, scripts: [0] },
		{ font: 2, limits: 0, provision: 1, scripts: [1] },
		{ font: 3, limits: 0, provision: 0, scripts: [2] },
	],
})

## Every registration rejection the boundary can produce, in one input: a
## duplicated script tag, a malformed tag, a rights-restricted font, a truncated
## font, an unsupported font program, and a byte budget too small for the font.
## The two policy requests add `EmptyPolicy` and `UnknownPolicyFace`.
expect RegistryTargets.registry_boundary({
	clusters: [],
	facade: 1,
	plan_policy: 0,
	policies: [[], [9, 9]],
	probe: 3,
	registrations: [
		{ font: 1, limits: 0, provision: 1, scripts: [0, 0] },
		{ font: 1, limits: 0, provision: 1, scripts: [9] },
		{ font: 5, limits: 0, provision: 1, scripts: [0] },
		{ font: 6, limits: 0, provision: 1, scripts: [0] },
		{ font: 7, limits: 0, provision: 1, scripts: [0] },
		{ font: 4, limits: 1, provision: 1, scripts: [0] },
	],
})

## A Latin face and a Han face ordered into one explicit policy, over clusters
## that select the first, select the second, select the first again, miss every
## face, and carry no scalars at all. This is the multi-error accumulation case:
## the rejection carries both failing clusters in ascending order, which no
## hand-written assertion in the repository reaches.
expect RegistryTargets.registry_boundary({
	clusters: [
		{ scalars: [0], script: 0 },
		{ scalars: [6], script: 1 },
		{ scalars: [0], script: 0 },
		{ scalars: [9], script: 0 },
		{ scalars: [], script: 1 },
	],
	facade: 2,
	plan_policy: 2,
	policies: [[0, 1]],
	probe: 1,
	registrations: [
		{ font: 1, limits: 0, provision: 1, scripts: [0] },
		{ font: 2, limits: 0, provision: 1, scripts: [1] },
	],
})

## Two faces that both declare Latin but cover overlapping subsets, ordered into
## one policy. The clusters select the first face, then the second because only
## it covers `i`, then the first again because it comes earlier and covers `f`,
## then a cluster the first face also covers so that the builder coalesces it
## into the range already open. The complete plan therefore has three ranges for
## four clusters, with no two adjacent ranges sharing an instance.
expect RegistryTargets.registry_boundary({
	clusters: [
		{ scalars: [0], script: 0 },
		{ scalars: [4], script: 0 },
		{ scalars: [3], script: 0 },
		{ scalars: [3, 0], script: 0 },
	],
	facade: 3,
	plan_policy: 2,
	policies: [[0, 1]],
	probe: 7,
	registrations: [
		{ font: 1, limits: 0, provision: 1, scripts: [0] },
		{ font: 4, limits: 0, provision: 2, scripts: [0, 4] },
	],
})
