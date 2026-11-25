import fuzz.Model
import pdf.KernelObject
import pdf.KernelOutline
import pdf.Document
import pdf.Pdf
import StructureOracle

OutlineModel := [].{}

Entry : { depth : U64, open : Bool }

Parent : [Root, Item(U64)]

machine : Model.Machine(List(Entry), Entry)
machine = {
	init: [],
	actions: |entries| {
		if entries.len() == 5 {
			return []
		}
		max_depth = match entries.last() {
			Err(_) => 0
			Ok(last) => U64.min(last.depth + 1, 3)
		}
		var $depth = 0
		var $actions = []
		while $depth <= max_depth {
			$actions = $actions.append({ depth: $depth, open: False }).append({ depth: $depth, open: True })
			$depth = $depth + 1
		}
		$actions
	},
	step: |entries, entry| entries.append(entry),
	rules: [
		Model.always("outline links and signed visible counts equal the authored forest", agrees),
		Model.sometimes(
			"open root with a closed nested branch, open grandson, then a sibling",
			|entries| entries == [
				{ depth: 0, open: True },
				{ depth: 1, open: False },
				{ depth: 2, open: True },
				{ depth: 3, open: False },
				{ depth: 1, open: False },
			],
		),
		Model.sometimes(
			"closed root hides an open nested branch and returns to the root level",
			|entries| entries == [
				{ depth: 0, open: False },
				{ depth: 1, open: True },
				{ depth: 2, open: False },
				{ depth: 0, open: True },
			],
		),
	],
}

expect {
	report = Model.explore(machine, { depth: 6, key: |entries| entries, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 1587 and report.steps == 1586 and report.depth == 5 and report.reached.len() == 2
}

agrees : List(Entry) -> Bool
agrees = |entries| {
	indices = indices_for(entries.len())
	candidates = indices.map(
		|index| {
			entry = at(entries, index)
			KernelOutline.Entry.make({ depth: entry.depth, open: entry.open, title: title(index), target: TargetValue(target(index)) })
		},
	)
	limits = KernelOutline.Limits.make({ max_depth: 3, max_entries: 5, text_string_count: 5, value_count: 5 })
	match KernelOutline.Plan.build(candidates, limits) {
		Err(EntryCountZero) => entries.is_empty()
		Err(_) => False
		Ok(plan) => {
			parents = indices.map(|index| authored_parent(entries, index))
			roots = indices.keep_if(|index| at(parents, index) == Root)
			if roots.is_empty() or KernelOutline.Plan.entry_count(plan) != entries.len() {
				return False
			}
			first = at(roots, 0)
			last = at(roots, roots.len() - 1)
			visible = indices.keep_if(|index| visible_from(entries, parents, index, Root)).len()
			open_item = indices.any(|index| at(entries, index).open and parents.contains(Item(index)))
			KernelOutline.Plan.has_open_items(plan) == open_item and KernelOutline.Plan.root_count(plan) == visible and
				KernelOutline.Plan.root_first(plan).index() == first and
					KernelOutline.Plan.root_last(plan).index() == last and
						indices.all(|index| agrees_on_item(plan, entries, indices, parents, index))
		}
	}
}

# Find a node's parent by scanning its prior authored entries for the nearest
# shallower node. From that relation, filter the whole forest for children and
# siblings instead of incrementally wiring earlier items.
authored_parent : List(Entry), U64 -> Parent
authored_parent = |entries, index| {
	depth = at(entries, index).depth
	var $prior = index
	while $prior > 0 {
		$prior = $prior - 1
		if at(entries, $prior).depth < depth {
			return Item($prior)
		}
	}
	Root
}

# A node is visible relative to an ancestor when every intervening ancestor is
# open. The selected ancestor is treated as open for its own Count, even if
# that Count will be emitted with a negative sign.
visible_from : List(Entry), List(Parent), U64, Parent -> Bool
visible_from = |entries, parents, index, ancestor| {
	var $parent = at(parents, index)
	while $parent != ancestor {
		match $parent {
			Root => return False
			Item(parent) => {
				if !at(entries, parent).open {
					return False
				}
				$parent = at(parents, parent)
			}
		}
	}
	True
}

agrees_on_item : KernelOutline.Plan, List(Entry), List(U64), List(Parent), U64 -> Bool
agrees_on_item = |plan, entries, indices, parents, index| {
	item = KernelOutline.Plan.item_at(plan, index)
	parent = at(parents, index)
	children = indices.keep_if(|child| at(parents, child) == Item(index))
	previous = indices.keep_if(|sibling| sibling < index and at(parents, sibling) == parent)
	following = indices.keep_if(|sibling| sibling > index and at(parents, sibling) == parent)
	count = indices.keep_if(|candidate| visible_from(entries, parents, candidate, Item(index))).len()
	actual_parent = match item.parent() {
		OutlineRoot => Root
		OutlineParent(id) => Item(id.index())
	}
	matches_count = match item.count() {
		Leaf => children.is_empty()
		OpenCount(magnitude) => !children.is_empty() and at(entries, index).open and magnitude == count
		ClosedCount(magnitude) => !children.is_empty() and !at(entries, index).open and magnitude == count
	}
	matches_target = match item.target() {
		NoTarget => False
		TargetValue(id) => id == target(index)
	}
	item.id().index() == index and item.title() == title(index) and matches_target and
		actual_parent == parent and matches_count and
			link_index(item.first()) == children.first() and link_index(item.last()) == children.last() and
				link_index(item.previous()) == previous.last() and link_index(item.next()) == following.first()
}

link_index : KernelOutline.Link -> Try(U64, [ListWasEmpty])
link_index = |link| match link {
	OutlineItem(id) => Ok(id.index())
	NoItem => Err(ListWasEmpty)
}

indices_for : U64 -> List(U64)
indices_for = |length| {
	var $indices = []
	var $index = 0
	while $index < length {
		$indices = $indices.append($index)
		$index = $index + 1
	}
	$indices
}

title = KernelObject.TextStringId.from_index

target = KernelObject.ValueId.from_index

at = |items, index| items.get(index) ?? crash "outline model index escaped"

# The initial state of a leaf is irrelevant because its dictionary never
# serializes a nonzero Count. A hidden open branch still supplies an open item,
# so the outline root records the one currently visible top-level entry.
expect observed_root([{ depth: 0, open: True }]) == Ok(NoCount)
expect observed_root([{ depth: 0, open: False }, { depth: 1, open: False }, { depth: 2, open: True }]) == Ok(NoCount)
expect observed_root([{ depth: 0, open: False }, { depth: 1, open: True }, { depth: 2, open: True }]) == Ok(Count(1))

observed_root : List(Entry) -> Try([NoCount, Count(U64)], [OutputFailed, StructureFailed(StructureOracle.Failure)])
observed_root = |entries| {
	outline : List(Document.OutlineEntry)
	outline = entries.map(|entry| { depth: entry.depth, open: entry.open, destination: "chapter", title: "Chapter" })
	document = Pdf.document({ contents: [Pdf.destination_heading({ level: 1, name: "chapter", text: "Chapter" })], language: "en", title: "Outline" }).with_outline(outline)
	bytes = Pdf.to_bytes(document) ? |_| OutputFailed
	count = StructureOracle.outline_root_count(bytes) ? StructureFailed
	Ok(count)
}
