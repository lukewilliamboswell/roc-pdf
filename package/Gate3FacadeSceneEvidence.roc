import Color
import KernelColor
import KernelEmit
import KernelFacadeScenes
import KernelScene
import KernelStructure
import Layout
import Semantics
import Text

Gate3FacadeSceneEvidence :: [].{
	arena : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	arena = |repetitions| evidence_arena(repetitions)

	negative : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	negative = |repetitions| evidence_negative(repetitions)

	prepare : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	prepare = |repetitions| evidence_prepare(repetitions)
}

evidence_prepare : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_prepare = |repetitions| {
	prepared = synthetic_input(repetitions)?
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	Ok({ bytes, work: [repetitions, prepared.pages.len(), prepared.placements.len(), prepared.styles.len(), prepared.text_runs, bytes.len()] })
}

evidence_arena : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_arena = |repetitions| {
	prepared = synthetic_input(repetitions)?
	arena = KernelFacadeScenes.Arena.build_prepared(prepared, limits(prepared)) ? |_| EvidenceFailure
	scenes = KernelFacadeScenes.Arena.scenes(arena)
	colors = KernelFacadeScenes.Arena.colors(arena)
	work = KernelFacadeScenes.Arena.work(arena)
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			repetitions,
			work.page_writes,
			work.placement_visits,
			work.color_checks,
			work.command_writes,
			work.group_writes,
			work.page_group_writes,
			scenes.pages.len(),
			scenes.commands.len(),
			scenes.groups.len(),
			scenes.page_groups.len(),
			colors.spaces.len(),
			bytes.len(),
		],
	})
}

evidence_negative : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_negative = |repetitions| {
	prepared = synthetic_input(repetitions)?
	first_style = list_at(prepared.styles, 0)
	colored = { ..first_style, color: Srgb(Rgb({ blue: 0, green: 0, red: 1 })) }
	bad_styles = list_set(prepared.styles, 0, colored)
	color_rejected = match KernelFacadeScenes.Arena.build_prepared({ ..prepared, styles: bad_styles }, limits(prepared)) {
		Err(UnsupportedColor(_)) => 1
		_ => return Err(EvidenceFailure)
	}
	page_size_rejected = match KernelFacadeScenes.Arena.build_prepared({ ..prepared, page_size: { ..prepared.page_size, width: Layout.Unit.from_raw(0) } }, limits(prepared)) {
		Err(InvalidPageSize) => 1
		_ => return Err(EvidenceFailure)
	}
	run_limit_rejected = match KernelFacadeScenes.Arena.build_prepared(prepared, group_limit(prepared)) {
		Err(LimitExceeded(_)) => 1
		_ => return Err(EvidenceFailure)
	}
	first_placement = list_at(prepared.placements, 0)
	bad_placements = list_set(prepared.placements, 0, { ..first_placement, page: Semantics.PageId.from_index(prepared.pages.len()) })
	placement_rejected = match KernelFacadeScenes.Arena.build_prepared({ ..prepared, placements: bad_placements }, limits(prepared)) {
		Err(InvalidPlacement(_)) => 1
		_ => return Err(EvidenceFailure)
	}
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	Ok({ bytes, work: [color_rejected, page_size_rejected, run_limit_rejected, placement_rejected, bytes.len()] })
}

synthetic_input : U64 -> Try(KernelFacadeScenes.ArenaPrepared, [EvidenceFailure, InvalidRepetitions])
synthetic_input = |repetitions| {
	if repetitions == 0 or repetitions > 100000 {
		return Err(InvalidRepetitions)
	}
	run_count = repetitions * 2
	black = Srgb(Rgb({ blue: 0, green: 0, red: 0 }))
	var $placements = List.with_capacity(run_count)
	var $styles = List.with_capacity(run_count)
	var $run_index = 0
	while $run_index < run_count {
		page_index = $run_index / 64
		$placements = $placements.append({
			origin: { x: Layout.Unit.from_raw(72000), y: Layout.Unit.from_raw(700000) },
			page: Semantics.PageId.from_index(page_index),
			run: Text.RunId.from_index($run_index),
		})
		$styles = $styles.append({ color: black, leading: Layout.Unit.from_raw(12000) })
		$run_index = $run_index + 1
	}
	var $pages = []
	var $run_start = 0
	while $run_start < run_count {
		page_index = $pages.len()
		length = U64.min(64, run_count - $run_start)
		$pages = $pages.append({
			id: Semantics.PageId.from_index(page_index),
			runs: Semantics.Range.from_start_and_length($run_start, length),
		})
		$run_start = $run_start + length
	}
	Ok({
		page_size: { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) },
		pages: $pages,
		placements: $placements,
		styles: $styles,
		text_runs: run_count,
	})
}

limits : KernelFacadeScenes.ArenaPrepared -> KernelFacadeScenes.Limits
limits = |prepared| KernelFacadeScenes.Limits.make({
	color: KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 }),
	max_commands: prepared.text_runs * 2,
	max_groups: prepared.text_runs,
	max_page_group_edges: prepared.text_runs,
	max_pages: prepared.pages.len(),
	scene: KernelScene.Limits.make({
		max_commands: prepared.text_runs * 2,
		max_dash_lengths: 0,
		max_graphics_depth: 2,
		max_groups: prepared.text_runs,
		max_pages: prepared.pages.len(),
		max_path_segments: 0,
		max_paths: 0,
	}),
})

group_limit : KernelFacadeScenes.ArenaPrepared -> KernelFacadeScenes.Limits
group_limit = |prepared| KernelFacadeScenes.Limits.make({
	color: KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 }),
	max_commands: prepared.text_runs * 2,
	max_groups: prepared.text_runs - 1,
	max_page_group_edges: prepared.text_runs,
	max_pages: prepared.pages.len(),
	scene: KernelScene.Limits.make({
		max_commands: prepared.text_runs * 2,
		max_dash_lengths: 0,
		max_graphics_depth: 2,
		max_groups: prepared.text_runs,
		max_pages: prepared.pages.len(),
		max_path_segments: 0,
		max_paths: 0,
	}),
})

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated facade-scene evidence index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated facade-scene evidence update escaped"
	}
}
