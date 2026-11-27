import fuzz.Model
import pdf.KernelAssociatedFiles

AssociatedFilesModel := [].{}

World : { authored : List(U8), closed : Bool }

Action : [Add(U8), Finalize]

## Exhaustive through four additions, including duplicate histories and
## exact-limit and overflow sequences. The key/payload table is an authored
## oracle independent of the registry's encoded ordering and accounting.
machine : Model.Machine(World, Action)
machine = {
	init: { authored: [], closed: False },
	actions: |world| if world.closed {
		[]
	} else if world.authored.len() == 4 {
		[Finalize]
	} else {
		[Add(0), Add(1), Add(2), Add(3), Finalize]
	},
	step: |world, action| match action {
		Add(index) => { ..world, authored: world.authored.append(index) }
		Finalize => { ..world, closed: True }
	},
	rules: [
		Model.always("encoded order, retained data, and spent budget agree at finalize", |world| !world.closed or agrees(world.authored)),
		Model.sometimes("shared payload and prefix filenames", |world| world.closed and world.authored == [0, 1]),
		Model.sometimes("reversed ordering and non-ASCII", |world| world.closed and world.authored == [2, 1, 0]),
		Model.sometimes("duplicate name", |world| world.closed and world.authored == [0, 0]),
		Model.sometimes("per-file limit", |world| world.closed and world.authored == [3]),
		Model.sometimes("aggregate limit", |world| world.closed and world.authored == [2, 2, 0]),
		Model.sometimes("count limit", |world| world.closed and world.authored.len() == 4),
	],
}

file : U8 -> KernelAssociatedFiles.File
file = |index| KernelAssociatedFiles.File.{
	bytes: payload(index),
	description: "Usage ${index.to_str()}",
	filename: filename(index),
	media_type: "application/octet-stream",
	modified: "2024-02-29T12:34:56Z",
	necessity: Supplemental,
	relationship: if (index == 1) Supplement else Data,
}

filename : U8 -> Str
filename = |index| match index {
	0 => "a"
	1 => "ab"
	2 => "ä"
	_ => "oversize"
}

payload : U8 -> List(U8)
payload = |index| match index {
	0 | 1 => [17]
	2 => [17, 17]
	_ => [17, 17, 17]
}

expected_budget : List(U8) -> [OverCount, OverFile(U64), OverTotal(U64), Valid(U64)]
expected_budget = |authored| {
	if authored.len() > 3 {
		return OverCount
	}
	var $total = 0
	var $index = 0
	for selection in authored {
		size = payload(selection).len()
		if size == 3 {
			return OverFile($index)
		}
		$total = $total + size
		if $total > 4 {
			return OverTotal($index)
		}
		$index = $index + 1
	}
	Valid($total)
}

agrees : List(U8) -> Bool
agrees = |authored| {
	actual = KernelAssociatedFiles.Plan.build(authored.map(file), True, { count: 3, description_bytes: 1024, file_bytes: 2, media_type_bytes: 127, total_bytes: 4 })
	match expected_budget(authored) {
		OverCount => match actual {
			Err(CountLimit({ actual: 4, maximum: 3 })) => True
			_ => False
		}
		OverFile(index) => match actual {
			Err(FileLimit(problem)) => problem.index == index and problem.actual == 3 and problem.maximum == 2
			_ => False
		}
		OverTotal(index) => match actual {
			Err(TotalLimit(problem)) => problem.index == index and problem.maximum == 4
			_ => False
		}
		Valid(bytes) => match actual {
			Err(Duplicate(index)) => duplicate_index(authored, index)
			Ok(plan) => {
				sorted = [0, 1, 2].keep_if(|index| authored.contains(index))
				actual_entries = KernelAssociatedFiles.Plan.entries(plan)
				if sorted.len() != authored.len() or actual_entries.len() != sorted.len() or KernelAssociatedFiles.Plan.payload_bytes(plan) != bytes {
					return False
				}
				# Description and date always have 7 and 17 bytes. The
				# non-ASCII name has two UTF-8 bytes and six legacy bytes.
				expected_text_bytes = sorted.fold(0, |sum, index| sum + 24 + (if (index == 0) 2 else if (index == 1) 4 else 8))
				if KernelAssociatedFiles.Plan.text_bytes(plan) != expected_text_bytes or KernelAssociatedFiles.Plan.media_type_bytes(plan) != 24 * sorted.len() {
					return False
				}
				var $rank = 0
				for index in sorted {
					entry = actual_entries.get($rank) ?? crash "model lost a file entry"
					exact = file(index)
					if entry.filename != exact.filename or entry.key != [239, 187, 191].concat(Str.to_utf8(exact.filename))
						or entry.description != exact.description or entry.relationship != exact.relationship or entry.necessity != exact.necessity
						or entry.media_type != Str.to_utf8(exact.media_type) or entry.modified != "D:20240229123456Z"
						or entry.bytes != exact.bytes or authored.get(entry.position) != Ok(index) {
						return False
					}
					$rank = $rank + 1
				}
				True
			}
			_ => False
		}
	}
}

duplicate_index : List(U8), U64 -> Bool
duplicate_index = |authored, index| match authored.get(index) {
	Ok(selection) => authored.sublist({ start: 0, len: index }).contains(selection)
	Err(OutOfBounds) => False
}

expect {
	report = Model.explore(machine, { depth: 6, key: |world| world, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash Model.explain(report)
	}
	report.states == 682 and report.steps == 681 and report.depth == 5 and report.reached.len() == 6
}
