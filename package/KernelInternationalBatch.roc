import Font
import KernelBidiBoundary
import KernelInternationalSelection
import KernelInternationalShape
import KernelInternationalText
import KernelShape
import KernelUnicode
import Layout
import Semantics
import Text

KernelInternationalBatch :: [].{
	Request : { authored : KernelInternationalText.Occurrence, segment : U64, shape : KernelShape.SimpleRequest }
	Limits : { max_clusters : U64, max_glyphs : U64, max_requests : U64, max_scalars : U64, max_source_bytes : U64 }
	Dimension : [Clusters, FontPrograms, Glyphs, Requests, Scalars, SourceBytes]

	Error : [
		Coverage({ request : U64, cause : KernelInternationalSelection.Error }),
		InvalidRequest(U64),
		LimitExceeded({ request : U64, attempted : U64, dimension : Dimension, limit : U64 }),
		Paragraph({ request : U64, cause : KernelInternationalText.Error }),
		Shape({ request : U64, cause : KernelInternationalShape.Error }),
		Scale({ request : U64, cause : KernelShape.Error }),
	]

	Paragraph : [Analyzed(KernelBidiBoundary.Paragraph), Unseen]
	Work : { coverage_spans : U64, faces : U64, graphemes : U64, paragraphs : U64, programs : U64 }

	Plan : {
		batch : KernelShape.Batch,
		firsts : List(U64),
		paragraphs : List(Paragraph),
		parents : List(U64),
		work : Work,
	}

	## Expand authoring occurrences into explicitly selected and directed
	## physical runs. The shape store's clusters stay logical, while each run's
	## glyph span retains that provider run's paint order.
	build : List(KernelShape.SimpleSource), List(Request), KernelInternationalSelection.Policy, Limits -> Try(Plan, Error)
	build = |sources, requests, policy, limits| {
		if requests.is_empty() or requests.len() > limits.max_requests {
			return Err(InvalidRequest(0))
		}
		var $paragraphs = List.repeat(Unseen, sources.len())
		var $firsts = List.repeat(U64.highest, requests.len() + 1)
		var $programs = []
		var $parents = []
		var $advances = []
		var $clusters = []
		var $glyph_indices = []
		var $glyphs = []
		var $runs = []
		var $coverage = 0
		var $face_visits = 0
		var $source_scalars = 0
		var $source_bytes = 0
		var $script_runs = 0
		var $paragraph_count = 0
		var $next = 0
		while $next < requests.len() {
			first = $next
			head = list_at(requests, first)
			source_index = head.shape.source.index()
			if source_index >= sources.len() {
				return Err(InvalidRequest($next))
			}
			source = list_at(sources, source_index)
			analysis = source.analysis
			length = analysis.work.scalar_visits
			if analysis.line_boundaries.len() != length + 1 {
				return Err(InvalidRequest(first))
			}
			bytes = source.unicode.count_utf8_bytes()
			$source_scalars = checked_total($source_scalars, length, limits.max_scalars, first, Scalars)?
			$source_bytes = checked_total($source_bytes, bytes, limits.max_source_bytes, first, SourceBytes)?
			$script_runs = $script_runs + analysis.script_runs.len()

			var $owners = []
			while $next < requests.len() and list_at(requests, $next).segment == head.segment {
				member = list_at(requests, $next)
				if member.shape.occurrence != member.authored.id or member.shape.source.index() != source_index or member.shape.size <= 0 {
					return Err(InvalidRequest($next))
				}
				$owners = $owners.append(member.authored)
				$next = $next + 1
			}
			if $next == first {
				return Err(InvalidRequest(first))
			}
			bidi_limits = KernelBidiBoundary.Limits.make({ max_clusters: limits.max_clusters, max_scalars: limits.max_scalars, max_visual_order: limits.max_clusters })
			var $paragraph = list_at($paragraphs, source_index)
			match $paragraph {
				Unseen => {
					bidi = KernelBidiBoundary.analyze_paragraph(source.unicode, analysis, Auto, bidi_limits) ? |cause| Paragraph({ request: first, cause: Bidi(cause) })
					$paragraphs = set_at($paragraphs, source_index, Analyzed(bidi))
					$paragraph = Analyzed(bidi)
				}
				Analyzed(_) => {}
			}
			bidi = match $paragraph {
				Analyzed(resolved) => resolved
				Unseen => return Err(InvalidRequest(first))
			}
			paragraph = KernelInternationalText.from_paragraph(source.unicode, analysis, bidi, $owners, UnpointedHebrewLatin, { max_clusters: limits.max_clusters, max_items: limits.max_requests, max_scalars: limits.max_scalars }) ? |cause| Paragraph({ request: first, cause })
			faces = KernelInternationalSelection.select(policy, head.shape.source, head.authored.language, paragraph) ? |cause| Coverage({ request: first, cause })
			$coverage = $coverage + faces.work.coverage_spans
			$face_visits = $face_visits + faces.work.faces
			$paragraph_count = $paragraph_count + 1
			var $parent = first
			for selected in faces.selected {
				item = selected.item
				while $parent < $next and list_at(requests, $parent).authored.id != item.occurrence {
					$parent = $parent + 1
				}
				if $parent >= $next {
					return Err(InvalidRequest(first))
				}
				author = list_at(requests, $parent)
				if list_at($firsts, $parent) == U64.highest {
					$firsts = set_at($firsts, $parent, $runs.len())
				}
				face = list_at(policy.faces, selected.face)
				options = { direction: item.direction, language: item.language, script: item.script }
				var $program_index = 0
				while $program_index < $programs.len() {
					entry = list_at($programs, $program_index)
					if entry.face == selected.face and entry.options == options {
						break
					}
					$program_index = $program_index + 1
				}
				if $program_index == $programs.len() {
					_ = checked_total($program_index, 1, max_programs, $parent, FontPrograms)?
					provider = KernelInternationalShape.program(face.shaper, options)
					$programs = $programs.append({ face: selected.face, options, provider })
				}
				provider = list_at($programs, $program_index).provider

				# Isolate the spans that end at legal wrap boundaries before
				# fitting. This first repertoire accepts only unpointed
				# Hebrew and Latin, so the breaks carry no joining context.
				var $start = item.source.scalars.start()
				item_end = $start + item.source.scalars.length()
				while $start < item_end {
					var $stop = $start + 1
					while $stop < item_end and list_at(analysis.line_boundaries, $stop).decision == Prohibited {
						$stop = $stop + 1
					}
					byte_start = list_at(paragraph.scalars, $start).offset
					byte_end = if ($stop == length) bytes else list_at(paragraph.scalars, $stop).offset
					range = {
						scalars: span($start, $stop - $start),
						utf8_bytes: span(byte_start, byte_end - byte_start),
					}
					physical = { ..item, source: range }
					_ = checked_total($runs.len(), 1, limits.max_requests, $parent, Requests)?
					shaped = KernelInternationalShape.shape(provider, physical, paragraph.scalars, limits.max_glyphs - $glyphs.len()) ? |cause| Shape({ request: $parent, cause })
					_ = checked_total($clusters.len(), shaped.clusters.len(), limits.max_clusters, $parent, Clusters)?
					glyph_start = $glyphs.len()
					cluster_start = $clusters.len()
					size = author.shape.size
					units = face.inspection.metrics.units_per_em
					var $advance = 0
					for glyph in shaped.glyphs {
						advance = KernelShape.scale_font_units(glyph.advance.x, size, units) ? |cause| Scale({ request: $parent, cause })
						x = KernelShape.scale_font_units(glyph.offset.x, size, units) ? |cause| Scale({ request: $parent, cause })
						y = KernelShape.scale_font_units(glyph.offset.y, size, units) ? |cause| Scale({ request: $parent, cause })
						$advance = match I64.plus_try($advance, advance.raw()) {
							Ok(value) => value
							Err(Overflow) => return Err(Scale({ request: $parent, cause: ArithmeticOverflow }))
						}
						$glyphs = $glyphs.append({ id: Text.GlyphId.from_raw(glyph.id), advance_x: advance, advance_y: 0, offset_x: x, offset_y: y })
					}
					for cluster in shaped.clusters {
						reference_start = $glyph_indices.len()
						var $glyph = cluster.glyphs.start()
						while $glyph < cluster.glyphs.start() + cluster.glyphs.length() {
							$glyph_indices = $glyph_indices.append(glyph_start + $glyph)
							$glyph = $glyph + 1
						}
						kind = cluster_kind(cluster, shaped.glyphs)
						$clusters = $clusters.append({ source: cluster.source, glyphs: span(reference_start, cluster.glyphs.length()), kind })
					}
					$runs = $runs.append({
						actual_text: FromOccurrence,
						clusters: span(cluster_start, shaped.clusters.len()),
						direction: item.direction,
						glyphs: span(glyph_start, shaped.glyphs.len()),
						id: Text.RunId.from_index($runs.len()),
						instance: Font.InstanceId.from_index(selected.face),
						language: item.language,
						script: Font.Script.from_iso15924(item.script),
						size,
						source: range,
						substitutions: span(0, 0),
						transformations: span(0, 0),
						unicode: OccurrenceText(item.occurrence),
						writing_mode: Horizontal,
					})
					$advances = $advances.append(Layout.Unit.from_raw($advance))
					$parents = $parents.append($parent)
					$start = $stop
				}
			}
			if $parent + 1 != $next {
				return Err(InvalidRequest($parent))
			}
		}
		$firsts = set_at($firsts, requests.len(), $runs.len())
		Ok({
			batch: {
				advances: $advances,
				inter_runs: [],
				store: { clusters: $clusters, glyph_indices: $glyph_indices, glyphs: $glyphs, runs: $runs, substitutions: [], transformations: [] },
				work: { cluster_visits: $clusters.len(), glyph_visits: $glyphs.len(), metric_reads: $glyphs.len(), scalar_visits: $source_scalars, script_run_visits: $script_runs, utf8_bytes: $source_bytes },
			},
			firsts: $firsts,
			paragraphs: $paragraphs,
			parents: $parents,
			work: { coverage_spans: $coverage, faces: $face_visits, graphemes: $source_scalars, paragraphs: $paragraph_count, programs: $programs.len() },
		})
	}
}

cluster_kind : KernelInternationalShape.Cluster, List(KernelInternationalShape.Glyph) -> Text.ClusterKind
cluster_kind = |cluster, glyphs| {
	scalars = cluster.source.scalars.length()
	count = cluster.glyphs.length()
	if count == 1 {
		origin = list_at(glyphs, cluster.glyphs.start()).origin
		match origin {
			Mapped if scalars == 1 => OneToOne
			Ligature(_) if scalars > 1 => Ligature
			_ if scalars > 1 => ManyToOne
			_ => Contextual
		}
	} else if scalars == 1 {
		OneToMany
	} else {
		ManyToMany
	}
}

max_programs : U64
max_programs = 48

span : U64, U64 -> Semantics.IndexRange
span = |start, length| Semantics.IndexRange.from_start_and_length({ start, length })

checked_total : U64, U64, U64, U64, KernelInternationalBatch.Dimension -> Try(U64, KernelInternationalBatch.Error)
checked_total = |used, addition, limit, request, dimension| {
	result = match U64.plus_try(used, addition) {
		Ok(value) => value
		Err(Overflow) => return Err(LimitExceeded({ request, attempted: U64.highest, dimension, limit }))
	}
	if result > limit {
		Err(LimitExceeded({ request, attempted: result, dimension, limit }))
	} else {
		Ok(result)
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(_) => crash "international batch index escaped its validated range"
}

set_at : List(a), U64, a -> List(a)
set_at = |items, index, value| match items.set(index, value) {
	Ok(updated) => updated
	Err(_) => crash "international batch update escaped its validated range"
}
