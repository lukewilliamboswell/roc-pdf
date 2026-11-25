import pdf.KernelContent
import pdf.KernelFixture
import pdf.KernelScene
import pdf.KernelSemantics
import pdf.KernelTagged
import pdf.Scene
import pdf.Semantics

TaggedStreamOwners := [].{}

# The valid pair reuses MCID zero without sharing a ParentTree row. The
# negative twins use the same in-range stream IDs and even the same counts
# per stream in the swapped case. Only the page-to-stream link differs.
expect agrees([0, 0, 1])
expect agrees([0, 0, 0])
expect agrees([1, 0, 0])

# Paint order deliberately differs from the fragment arena and logical order.
# The authored page paint lists supply the expected stream keys and each MCID
# is the index within its own page's list (ISO 32000-2 §14.7.5.2 and §14.7.5.4).
paint : List(List(U64))
paint = [[1, 0], [2]]

Slot : { fragment : U64, mcid : U64, page : U64, stream : U64 }

agrees : List(U64) -> Bool
agrees = |streams| {
	rows = paint.map_with_index(|fragments, page| fragments.map_with_index(|fragment, mcid| { fragment, mcid, page, stream: page }))
	expected = List.join(rows)
	first_mismatch = expected.find_first(|slot| at(streams, slot.fragment) != slot.stream)
	match (first_mismatch, plans(streams)) {
		(Ok(slot), Err(ContentFailure(FragmentStreamMismatch(details)))) => details == { fragment: slot.fragment, page: slot.page, stream: at(streams, slot.fragment) }
		(Err(NotFound), Ok({ tagged, content })) => observes(tagged, rows) and emitted_mcids(content) == rows.map(|slots| slots.map(|slot| "/P <</MCID ${slot.mcid.to_str()}>> BDC"))
		_ => False
	}
}

observes : KernelTagged.Plan, List(List(Slot)) -> Bool
observes = |plan, expected| {
	entries = KernelTagged.Plan.parent_entries(plan)
	rows = KernelTagged.Plan.parent_rows(plan).map_with_index(
		|row, page| {
			values = entries.sublist({ start: row.entries.start(), len: row.entries.length() })
			{ key: row.content_stream.index(), page, slots: values.map(project) }
		},
	)
	marked = KernelTagged.Plan.marked_fragments(plan).map(project)
	rows == expected.map_with_index(|slots, page| { key: page, page, slots }) and
		List.join(expected).all(|slot| at(marked, slot.fragment) == slot)
}

project : KernelTagged.MarkedContentReference -> Slot
project = |reference| { fragment: reference.fragment.index(), mcid: reference.mcid, page: reference.page.index(), stream: reference.content_stream.index() }

emitted_mcids : KernelContent.Plan -> List(List(Str))
emitted_mcids = |content| [0, 1].map(
	|page| {
		stream = KernelContent.Plan.stream(content, Semantics.ContentStreamId.from_index(page))
		Str.from_utf8_lossy(stream.bytes).split_on("\n").keep_if(|line| line.starts_with("/P <</MCID "))
	},
)

Failure : [ContentFailure(KernelContent.Error), SceneFailure(KernelScene.Error), SemanticFailure(KernelSemantics.Error), TaggedFailure(KernelTagged.Error)]

plans : List(U64) -> Try({ tagged : KernelTagged.Plan, content : KernelContent.Plan }, Failure)
plans = |streams| {
	fixture = KernelFixture.semantics
	fragment = at(fixture.fragments, 0)
	fragments = streams.map_with_index(
		|stream, index| {
			{
				..fragment,
				id: Semantics.FragmentId.from_index(index),
				continuation_index: index,
				page: Semantics.PageId.from_index(if (index == 2) 1 else 0),
				content_stream: Semantics.ContentStreamId.from_index(stream),
			}
		},
	)
	semantic_store = { ..fixture, fragments }
	semantic = KernelSemantics.Plan.build(semantic_store, 2, 2, KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 3, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 })) ? SemanticFailure
	base = KernelFixture.scene
	page = at(base.pages, 0)
	group = at(base.groups, 0)
	scene = {
		..base,
		commands: List.repeat(at(base.commands, 0), 3),
		groups: [0, 1, 2].map(|id| { ..group, id: Scene.GroupId.from_index(id), commands: range(id, 1), owner: Fragment(Semantics.FragmentId.from_index(id)) }),
		page_groups: List.join(paint).map(Scene.GroupId.from_index),
		pages: [{ ..page, paint_order: range(0, 2) }, { ..page, id: Semantics.PageId.from_index(1), paint_order: range(2, 1) }],
	}
	scenes = KernelScene.Plan.build(scene, KernelScene.Resources.make({ color_spaces: 1, images: 0 }), KernelScene.Limits.make({ max_commands: 3, max_dash_lengths: 0, max_graphics_depth: 1, max_groups: 3, max_pages: 2, max_path_segments: 1, max_paths: 1 })) ? SceneFailure
	tagged = KernelTagged.Plan.build(semantic, scenes) ? TaggedFailure
	content = KernelContent.Plan.build(tagged, KernelContent.Limits.make({ max_content_bytes: 1024, max_content_streams: 2 })) ? ContentFailure
	Ok({ tagged, content })
}

range : U64, U64 -> Semantics.IndexRange
range = |start, length| Semantics.IndexRange.from_start_and_length({ start, length })

at : List(a), U64 -> a
at = |values, index| values.get(index) ?? crash "tagged stream fixture index escaped"
