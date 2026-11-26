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
	Policy : { id : Font.PolicyId, faces : List(Face), registry : Font.Registry, repertoire : KernelInternationalText.Repertoire }

	Selected : { face : U64, item : KernelInternationalText.Item }

	Work : { coverage_spans : U64, faces : U64, graphemes : U64 }

	## The first repertoire names static Inter Regular and IBM Plex Sans
	## Hebrew Regular. The complete font identity is the validated bytes'
	## SHA-256 value, not a family or PostScript name.
	for_repertoire : Font.Registry, Font.PolicyId, KernelInternationalText.Repertoire -> Try(Policy, Error)
	for_repertoire = |registry, id, repertoire| {
		script_digest = match repertoire {
			ModernHindiLatin => plex_hindi_sha256
			UnpointedArabicLatin => plex_arabic_sha256
			UnpointedHebrewLatin => plex_hebrew_sha256
		}
		ordered = registry.policy_faces(id) ? FacePolicy
		if ordered.is_empty() or ordered.len() > 2 {
			return Err(UnsupportedPolicyCount(ordered.len()))
		}
		store = registry.store()
		var $faces = List.with_capacity(ordered.len())
		for face in ordered {
			provision = list_at(store.faces, face.index()).provision
			inspection = registry.prepared_face(face) ? |_| RegistryFace(face)
			if provision != BuiltIn or !(KernelLatinShape.eligible_face(inspection) or inspection.digest == script_digest) {
				return Err(UnsupportedFace(face))
			}
			shaper = KernelInternationalShape.prepare(inspection) ? |cause| ShaperFace({ face, cause })
			$faces = $faces.append({ id: face, inspection, shaper })
		}
		Ok({ registry, id, faces: $faces, repertoire })
	}

	select : Policy, Semantics.TextSourceId, Semantics.Language, KernelInternationalText.Plan -> Try({ selected : List(Selected), work : Work }, Error)
	select = |prepared, source, language, plan| {
		clusters = source_clusters(plan)?
		fonts = match prepared.registry.plan({ source, policy: prepared.id, language, clusters }) {
			Complete(value) => value
			Rejected(errors) => {
				match errors.get(0) {
					Ok(MissingCoverage({ cluster, source: _ })) if cluster < plan.graphemes.len() => {
						scalar_index = list_at(plan.graphemes, cluster).scalar_start
						return Err(NoCoverage({ scalar: list_at(plan.scalars, scalar_index).scalar, scalar_index }))
					}
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
				cluster_end = range.clusters.start() + range.clusters.length()
				if range.clusters.length() == 0 or cluster_end > plan.graphemes.len() {
					return Err(InvalidSelection($cursor))
				}
				range_start = list_at(plan.graphemes, range.clusters.start()).scalar_start
				range_end = list_at(plan.graphemes, cluster_end - 1).scalar_end
				if range_start > $cursor or range_end <= $cursor {
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
	var $clusters = List.with_capacity(plan.graphemes.len())
	var $next_scalar = 0
	for item in plan.items {
		script = Font.Script.from_iso15924(item.script)
		start = item.source.scalars.start()
		length = item.source.scalars.length()
		if start != $next_scalar or start > plan.scalars.len() or length > plan.scalars.len() - start {
			return Err(InvalidSelection(start))
		}
		ending = start + length
		while $next_scalar < ending {
			if $clusters.len() >= plan.graphemes.len() {
				return Err(InvalidSelection($next_scalar))
			}
			grapheme = list_at(plan.graphemes, $clusters.len())
			stop = grapheme.scalar_end
			if grapheme.scalar_start != $next_scalar or stop > ending or stop <= $next_scalar {
				return Err(InvalidSelection($next_scalar))
			}
			size = stop - $next_scalar
			first_scalar = list_at(plan.scalars, $next_scalar).scalar
			values = if (size == 1) [first_scalar] else plan.scalars.sublist({ start: $next_scalar, len: size }).map(|entry| entry.scalar)
			$clusters = $clusters.append({
				scalars: values,
				script,
				source: source_range(plan, $next_scalar, stop),
			})
			$next_scalar = stop
		}
	}
	if $next_scalar != plan.scalars.len() or $clusters.len() != plan.graphemes.len() {
		Err(InvalidSelection($next_scalar))
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

plex_hindi_sha256 : List(U8)
plex_hindi_sha256 = [0xf3, 0xd8, 0x2e, 0x82, 0x79, 0x7c, 0x8c, 0xd2, 0x9e, 0x91, 0x71, 0xf3, 0x21, 0x74, 0xed, 0x5e, 0xe1, 0xa8, 0x8e, 0x13, 0x2d, 0x1b, 0xaa, 0xfb, 0xe2, 0x12, 0x37, 0xc4, 0x23, 0x20, 0x30, 0x4b]

plex_arabic_sha256 : List(U8)
plex_arabic_sha256 = [0x8e, 0x0f, 0x10, 0x46, 0xc7, 0x36, 0xbf, 0x93, 0x9d, 0x49, 0x39, 0xee, 0x3a, 0xe0, 0x11, 0x6a, 0xcf, 0x61, 0xcb, 0xcd, 0x65, 0x92, 0xde, 0xae, 0x76, 0x56, 0x76, 0x16, 0x27, 0x08, 0x09, 0x81]

plex_hebrew_sha256 : List(U8)
plex_hebrew_sha256 = [0x98, 0xcd, 0x8c, 0xa1, 0x3f, 0xef, 0x47, 0xfb, 0x57, 0xc2, 0x0f, 0xae, 0xd1, 0x7a, 0x34, 0x66, 0x39, 0xbb, 0x41, 0x8b, 0x7a, 0xbe, 0xb0, 0x96, 0xfd, 0x96, 0x93, 0xea, 0x3e, 0xec, 0xc4, 0x45]

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(_) => crash "international font selection escaped its validated range"
}
