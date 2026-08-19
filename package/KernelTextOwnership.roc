import KernelScene
import KernelTagged
import KernelTextSemantics
import Scene
import Semantics
import Text

KernelTextOwnership :: [].{
	Error : [
		ArithmeticOverflow,
		ArtifactTextUnsupported({ group : U64, run : U64 }),
		DuplicateRunOwnership({ run : U64 }),
		FragmentTextCoverageMismatch({ fragment : U64 }),
		NonDenseRunIdentity({ actual : U64, expected : U64 }),
		OccurrenceMismatch({ fragment : U64, run : U64 }),
		OrphanRun({ run : U64 }),
		RunIndexOutOfRange({ available : U64, run : U64 }),
		Tagged(KernelTagged.Error),
	]

	Work : {
		command_visits : U64,
		fragment_prefix_steps : U64,
		fragment_writes : U64,
		group_visits : U64,
		range_checks : U64,
		run_visits : U64,
		text_fragments : U64,
	}

	Plan :: { run_fragments : List(Semantics.FragmentId), tagged : KernelTagged.Plan, text : Text.Store, work : Work }.{
		build : KernelTextSemantics.Plan, KernelScene.Plan, Text.Store -> Try(Plan, Error)
		build = |semantics, scene, text| build_plan(semantics, scene, text, [])

		## production-visual scenes additionally assign runs painted inside Form XObjects.
		## Each such run arrives as an explicit resolved fact (the fragment
		## owning the form's unique placement chain); ownership rules are
		## unchanged: every run is owned exactly once, and only by a fragment.
		build_with_forms : KernelTextSemantics.Plan, KernelScene.Plan, Text.Store, List({ fragment : Semantics.FragmentId, run : U64 }) -> Try(Plan, Error)
		build_with_forms = |semantics, scene, text, form_runs| build_plan(semantics, scene, text, form_runs)

		run_fragments : Plan -> List(Semantics.FragmentId)
		run_fragments = |plan| plan.run_fragments

		tagged : Plan -> KernelTagged.Plan
		tagged = |plan| plan.tagged

		text : Plan -> Text.Store
		text = |plan| plan.text

		work : Plan -> Work
		work = |plan| plan.work
	}
}

RunOwner := [Owned(Semantics.FragmentId), Unowned]

Frame := { range : Semantics.Range }

Collected := { command_visits : U64, group_visits : U64, owners : List(RunOwner) }

build_plan : KernelTextSemantics.Plan, KernelScene.Plan, Text.Store, List({ fragment : Semantics.FragmentId, run : U64 }) -> Try(KernelTextOwnership.Plan, KernelTextOwnership.Error)
build_plan = |text_semantics, scene_plan, text, form_runs| {
	tagged = KernelTagged.Plan.build(KernelTextSemantics.Plan.semantics(text_semantics), scene_plan) ? Tagged
	semantics = KernelTagged.Plan.semantics(tagged)
	scenes = KernelTagged.Plan.scenes(tagged)
	collected = collect_owners(scenes, text)?
	with_forms = apply_form_runs(collected.owners, form_runs, text)?
	validated = validate_coverage(semantics, text, with_forms)?
	Ok(
		KernelTextOwnership.Plan.{
			run_fragments: validated.run_fragments,
			tagged,
			text,
			work: {
				command_visits: collected.command_visits,
				fragment_prefix_steps: validated.prefix_steps,
				fragment_writes: validated.writes,
				group_visits: collected.group_visits,
				range_checks: validated.range_checks,
				run_visits: text.runs.len(),
				text_fragments: validated.text_fragments,
			},
		},
	)
}

apply_form_runs : List(RunOwner), List({ fragment : Semantics.FragmentId, run : U64 }), Text.Store -> Try(List(RunOwner), KernelTextOwnership.Error)
apply_form_runs = |owners, form_runs, text| {
	var $owners = owners
	var $index = 0
	var $failure = NoFailure
	while $index < form_runs.len() and $failure == NoFailure {
		assignment = list_at(form_runs, $index)
		if assignment.run >= text.runs.len() {
			$failure = Failed(RunIndexOutOfRange({ available: text.runs.len(), run: assignment.run }))
		} else {
			record = list_at(text.runs, assignment.run)
			if record.id.index() != assignment.run {
				$failure = Failed(NonDenseRunIdentity({ actual: record.id.index(), expected: assignment.run }))
			} else {
				match list_at($owners, assignment.run) {
					Owned(_) => {
						$failure = Failed(DuplicateRunOwnership({ run: assignment.run }))
					}
					Unowned => {
						$owners = list_set($owners, assignment.run, Owned(assignment.fragment))
					}
				}
			}
		}
		$index = $index + 1
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok($owners)
	}
}

collect_owners : Scene.Store, Text.Store -> Try(Collected, KernelTextOwnership.Error)
collect_owners = |scenes, text| {
	var $owners = List.repeat(Unowned, text.runs.len())
	var $group_index = 0
	var $command_visits = 0
	while $group_index < scenes.groups.len() {
		group = list_at(scenes.groups, $group_index)
		var $frames = [Frame.{ range: group.commands }]
		var $frame_index = 0
		while $frame_index < $frames.len() {
			frame = list_at($frames, $frame_index)
			var $command_index = frame.range.start()
			end = frame.range.start() + frame.range.length()
			while $command_index < end {
				command = list_at(scenes.commands, $command_index)
				match command {
					Clip({ children, path: _ }) | Opacity({ children, opacity: _ }) | SoftMask({ children, mask: _ }) | Transform({ children, matrix: _ }) => {
						$frames = $frames.append(Frame.{ range: children })
					}
					DrawText({ paint: _, run }) => {
						run_index = run.index()
						if run_index >= text.runs.len() {
							return Err(RunIndexOutOfRange({ available: text.runs.len(), run: run_index }))
						}
						record = list_at(text.runs, run_index)
						if record.id.index() != run_index {
							return Err(NonDenseRunIdentity({ actual: record.id.index(), expected: run_index }))
						}
						match list_at($owners, run_index) {
							Owned(_) => return Err(DuplicateRunOwnership({ run: run_index }))
							Unowned => match group.owner {
								PageArtifact(_) => return Err(ArtifactTextUnsupported({ group: $group_index, run: run_index }))
								Fragment(fragment) => {
									$owners = list_set($owners, run_index, Owned(fragment))
								}
							}
						}
					}
					DrawImage(_) | DrawPath(_) | PaintShading(_) | PlaceForm(_) => {}
				}
				$command_index = $command_index + 1
				$command_visits = $command_visits + 1
			}
			$frame_index = $frame_index + 1
		}
		$group_index = $group_index + 1
	}
	Ok({ command_visits: $command_visits, group_visits: scenes.groups.len(), owners: $owners })
}

validate_coverage : Semantics.Store, Text.Store, List(RunOwner) -> Try({ prefix_steps : U64, range_checks : U64, run_fragments : List(Semantics.FragmentId), text_fragments : U64, writes : U64 }, KernelTextOwnership.Error)
validate_coverage = |semantics, text, owners| {
	var $counts = List.repeat(0, semantics.fragments.len())
	var $run_index = 0
	while $run_index < owners.len() {
		match list_at(owners, $run_index) {
			Unowned => return Err(OrphanRun({ run: $run_index }))
			Owned(fragment) => {
				count = list_at($counts, fragment.index())
				$counts = list_set($counts, fragment.index(), checked_add(count, 1)?)
			}
		}
		$run_index = $run_index + 1
	}
	var $starts = List.repeat(0, semantics.fragments.len())
	var $total = 0
	var $fragment_index = 0
	while $fragment_index < semantics.fragments.len() {
		$starts = list_set($starts, $fragment_index, $total)
		$total = checked_add($total, list_at($counts, $fragment_index))?
		$fragment_index = $fragment_index + 1
	}
	var $cursors = $starts
	var $fragment_runs = List.repeat(Text.RunId.from_index(0), text.runs.len())
	var $run_fragments = List.repeat(Semantics.FragmentId.from_index(0), text.runs.len())
	$run_index = 0
	while $run_index < owners.len() {
		fragment = match list_at(owners, $run_index) {
			Owned(value) => value
			Unowned => return Err(OrphanRun({ run: $run_index }))
		}
		write_index = list_at($cursors, fragment.index())
		$fragment_runs = list_set($fragment_runs, write_index, Text.RunId.from_index($run_index))
		$run_fragments = list_set($run_fragments, $run_index, fragment)
		$cursors = list_set($cursors, fragment.index(), write_index + 1)
		$run_index = $run_index + 1
	}
	var $range_checks = 0
	var $text_fragments = 0
	$fragment_index = 0
	while $fragment_index < semantics.fragments.len() {
		fragment = list_at(semantics.fragments, $fragment_index)
		occurrence = list_at(semantics.occurrences, fragment.occurrence.index())
		match (fragment.source_range, occurrence.source) {
			(UnicodeRange(fragment_range), Text(_, UnicodeRange(occurrence_range))) => {
				$text_fragments = $text_fragments + 1
				var $scalar_cursor = fragment_range.scalars.start()
				var $byte_cursor = fragment_range.utf8_bytes.start()
				start = list_at($starts, $fragment_index)
				end = start + list_at($counts, $fragment_index)
				var $edge = start
				while $edge < end {
					run_index = list_at($fragment_runs, $edge).index()
					run = list_at(text.runs, run_index)
					if run.occurrence.index() != fragment.occurrence.index() {
						return Err(OccurrenceMismatch({ fragment: $fragment_index, run: run_index }))
					}
					scalar_start = checked_add(occurrence_range.scalars.start(), run.source.scalars.start())?
					byte_start = checked_add(occurrence_range.utf8_bytes.start(), run.source.utf8_bytes.start())?
					if scalar_start != $scalar_cursor or byte_start != $byte_cursor {
						return Err(FragmentTextCoverageMismatch({ fragment: $fragment_index }))
					}
					$scalar_cursor = checked_add($scalar_cursor, run.source.scalars.length())?
					$byte_cursor = checked_add($byte_cursor, run.source.utf8_bytes.length())?
					$range_checks = $range_checks + 1
					$edge = $edge + 1
				}
				if $scalar_cursor != fragment_range.scalars.start() + fragment_range.scalars.length() or $byte_cursor != fragment_range.utf8_bytes.start() + fragment_range.utf8_bytes.length() {
					return Err(FragmentTextCoverageMismatch({ fragment: $fragment_index }))
				}
			}
			_ => if list_at($counts, $fragment_index) != 0 {
				return Err(FragmentTextCoverageMismatch({ fragment: $fragment_index }))
			}
		}
		$fragment_index = $fragment_index + 1
	}
	Ok({ prefix_steps: semantics.fragments.len(), range_checks: $range_checks, run_fragments: $run_fragments, text_fragments: $text_fragments, writes: text.runs.len() })
}

checked_add : U64, U64 -> Try(U64, KernelTextOwnership.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Ok(value) => Ok(value)
	Err(_) => Err(ArithmeticOverflow)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated text-ownership index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated text-ownership update escaped"
	}
}
