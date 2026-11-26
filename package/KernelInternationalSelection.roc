import Font
import KernelFont
import KernelInternationalShape
import KernelInternationalText
import KernelLatinShape
import Semantics

## Font planning runs over complete earlier grapheme items. Its public
## registry policy chooses among exact authored faces, while the international
## repertoire defines which of those faces have shape evidence.
KernelInternationalSelection :: [].{
	Error : [
		FacePolicy(Font.PolicyError),
		InvalidSelection(U64),
		NoCoverage({ scalar : U32, scalar_index : U64 }),
		RegistryFace(Font.FaceId),
		UnsupportedFace(Font.FaceId),
		UnsupportedPolicyCount(U64),
		ShaperFace({ face : Font.FaceId, cause : KernelInternationalShape.Error }),
	]

	Face : { id : Font.FaceId, inspection : KernelFont.Inspection, shaper : KernelInternationalShape.Face }
	Policy : { id : Font.PolicyId, faces : List(Face), registry : Font.Registry }

	Selected : { face : U64, item : KernelInternationalText.Item }

	Work : { coverage_spans : U64, faces : U64, graphemes : U64 }

	## The first repertoire names static Inter Regular and IBM Plex Sans
	## Hebrew Regular. The complete font identity is the validated bytes'
	## SHA-256 value, not a family or PostScript name.
	policy : Font.Registry, Font.PolicyId -> Try(Policy, Error)
	policy = |registry, id| {
		ordered = registry.policy_faces(id) ? FacePolicy
		if ordered.is_empty() or ordered.len() > 2 {
			return Err(UnsupportedPolicyCount(ordered.len()))
		}
		store = registry.store()
		var $faces = List.with_capacity(ordered.len())
		for face in ordered {
			provision = list_at(store.faces, face.index()).provision
			inspection = registry.prepared_face(face) ? |_| RegistryFace(face)
			if provision != BuiltIn or !(KernelLatinShape.eligible_face(inspection) or inspection.digest == plex_hebrew_sha256) {
				return Err(UnsupportedFace(face))
			}
			shaper = KernelInternationalShape.prepare(inspection) ? |cause| ShaperFace({ face, cause })
			$faces = $faces.append({ id: face, inspection, shaper })
		}
		Ok({ registry, id, faces: $faces })
	}

	select : Policy, Semantics.TextSourceId, Semantics.Language, KernelInternationalText.Plan -> Try({ selected : List(Selected), work : Work }, Error)
	select = |prepared, source, language, plan| {
		clusters = source_clusters(plan)?
		fonts = match prepared.registry.plan({ source, policy: prepared.id, language, clusters }) {
			Complete(value) => value
			Rejected(errors) => {
				match errors.get(0) {
					Ok(MissingCoverage({ cluster, source: _ })) if cluster < plan.scalars.len() => return Err(NoCoverage({ scalar: list_at(plan.scalars, cluster).scalar, scalar_index: cluster }))
					_ => return Err(InvalidSelection(0))
				}
			}
		}

		var $selection = List.with_capacity(plan.items.len())
		var $range_index = 0
		var $cursor = 0
		for item in plan.items {
			start = item.source.scalars.start()
			ending = start + item.source.scalars.length()
			if start != $cursor or ending > plan.scalars.len() or ending <= start {
				return Err(InvalidSelection(start))
			}
			while $cursor < ending {
				if $range_index >= fonts.face_ranges.len() {
					return Err(InvalidSelection($cursor))
				}
				range = list_at(fonts.face_ranges, $range_index)
				range_end = range.clusters.start() + range.clusters.length()
				if range.clusters.start() > $cursor or range_end <= $cursor {
					return Err(InvalidSelection($cursor))
				}
				face = face_index(prepared.faces, range.instance, $cursor)?
				stop = U64.min(ending, range_end)
				$selection = $selection.append({ face, item: { ..item, source: source_range(plan, $cursor, stop) } })
				if stop == range_end {
					$range_index = $range_index + 1
				}
				$cursor = stop
			}
		}
		if $cursor != plan.scalars.len() or $range_index != fonts.face_ranges.len() {
			return Err(InvalidSelection($cursor))
		}
		Ok({ selected: $selection, work: { coverage_spans: fonts.work.coverage_span_visits, faces: fonts.work.face_visits, graphemes: fonts.work.grapheme_visits } })
	}
}

source_clusters : KernelInternationalText.Plan -> Try(List(Font.SourceCluster), KernelInternationalSelection.Error)
source_clusters = |plan| {
	var $clusters = List.with_capacity(plan.scalars.len())
	for item in plan.items {
		script = Font.Script.from_iso15924(item.script)
		start = item.source.scalars.start()
		length = item.source.scalars.length()
		if start != $clusters.len() or start > plan.scalars.len() or length > plan.scalars.len() - start {
			return Err(InvalidSelection(start))
		}
		var $scalar = start
		while $scalar < start + length {
			value = list_at(plan.scalars, $scalar)
			$clusters = $clusters.append({ scalars: [value.scalar], script, source: source_range(plan, $scalar, $scalar + 1) })
			$scalar = $scalar + 1
		}
	}
	if $clusters.len() != plan.scalars.len() {
		Err(InvalidSelection($clusters.len()))
	} else {
		Ok($clusters)
	}
}

source_range : KernelInternationalText.Plan, U64, U64 -> Semantics.TextRange
source_range = |plan, start, ending| {
	byte_start = list_at(plan.scalars, start).offset
	byte_end = if (ending == plan.scalars.len()) plan.bidi.logical_source.utf8_bytes.length() else list_at(plan.scalars, ending).offset
	{
		scalars: Semantics.IndexRange.from_start_and_length({ start, length: ending - start }),
		utf8_bytes: Semantics.IndexRange.from_start_and_length({ start: byte_start, length: byte_end - byte_start }),
	}
}

face_index : List(KernelInternationalSelection.Face), Font.InstanceId, U64 -> Try(U64, KernelInternationalSelection.Error)
face_index = |faces, instance, scalar| {
	var $index = 0
	for face in faces {
		if face.id.index() == instance.index() {
			return Ok($index)
		}
		$index = $index + 1
	}
	Err(InvalidSelection(scalar))
}

plex_hebrew_sha256 : List(U8)
plex_hebrew_sha256 = [0x98, 0xcd, 0x8c, 0xa1, 0x3f, 0xef, 0x47, 0xfb, 0x57, 0xc2, 0x0f, 0xae, 0xd1, 0x7a, 0x34, 0x66, 0x39, 0xbb, 0x41, 0x8b, 0x7a, 0xbe, 0xb0, 0x96, 0xfd, 0x96, 0x93, 0xea, 0x3e, 0xec, 0xc4, 0x45]

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(_) => crash "international font selection escaped its validated range"
}
