app [main!] {
	pf: platform "../tests/platform/main.roc",
	pdf: "../package/main.roc",
}

import pdf.Layout
import pdf.Scene
import pdf.Semantics

contract_report : Str
contract_report = {
	root = Semantics.NodeId.from_index(0)
	link = Semantics.NodeId.from_index(1)
	first_text = Semantics.OccurrenceId.from_index(0)
	last_text = Semantics.OccurrenceId.from_index(1)
	artifact = Semantics.ContextualArtifactId.from_index(0)

	logical_order : List(Semantics.ContentSpineItem)
	logical_order = [
		ContentOccurrence(first_text),
		ChildNode(link),
		ContentOccurrence(last_text),
		ContextualArtifact(artifact),
	]

	first_range : Semantics.TextRange
	first_range = {
		scalars: Semantics.Range.from_start_and_length(0, 4),
		utf8_bytes: Semantics.Range.from_start_and_length(0, 4),
	}

	second_range : Semantics.TextRange
	second_range = {
		scalars: Semantics.Range.from_start_and_length(4, 4),
		utf8_bytes: Semantics.Range.from_start_and_length(4, 4),
	}

	first_fragment : Semantics.LayoutFragment
	first_fragment = {
		content_stream: Semantics.ContentStreamId.from_index(0),
		continuation_index: 0,
		id: Semantics.FragmentId.from_index(0),
		occurrence: first_text,
		page: Semantics.PageId.from_index(0),
		source_range: UnicodeRange(first_range),
	}

	second_fragment : Semantics.LayoutFragment
	second_fragment = {
		content_stream: Semantics.ContentStreamId.from_index(1),
		continuation_index: 1,
		id: Semantics.FragmentId.from_index(1),
		occurrence: first_text,
		page: Semantics.PageId.from_index(1),
		source_range: UnicodeRange(second_range),
	}

	## Paint order deliberately differs from the logical content spine.
	paint_order : List(Scene.GroupOwner)
	paint_order = [
		PageArtifact(Header),
		Fragment(second_fragment.id),
		Fragment(first_fragment.id),
	]

	continuation : Layout.Continuation(U64)
	continuation = {
		component: Layout.ComponentId.from_index(0),
		source: Layout.SourceId.from_index(0),
		source_cursor: 8,
		state: 1,
	}

	stable : Layout.Stabilization(U64)
	stable = Stable({ passes: 2, state: 7, work: 12 })

	cycle : Layout.Stabilization(U64)
	cycle = Cycle({ first_seen_pass: 1, repeated: 7, repeated_at_pass: 3 })

	exhausted : Layout.Stabilization(U64)
	exhausted = BudgetExhausted({ attempted: 8, passes: 4, work: 100 })

	\\root index: ${root.index().to_str()}
	\\link index: ${link.index().to_str()}
	\\logical items: ${logical_order.len().to_str()}
	\\paint groups: ${paint_order.len().to_str()}
	\\continuation cursor: ${continuation.source_cursor.to_str()}
	\\stable represented: ${Str.inspect(stable == Stable({ passes: 2, state: 7, work: 12 }))}
	\\cycle represented: ${Str.inspect(cycle == Cycle({ first_seen_pass: 1, repeated: 7, repeated_at_pass: 3 }))}
	\\exhaustion represented: ${Str.inspect(exhausted == BudgetExhausted({ attempted: 8, passes: 4, work: 100 }))}
}

## Gate 0 types preserve mixed order, fragmented ownership, and stabilization outcomes.
expect {
	expected =
		\\root index: 0
		\\link index: 1
		\\logical items: 4
		\\paint groups: 3
		\\continuation cursor: 8
		\\stable represented: True
		\\cycle represented: True
		\\exhaustion represented: True

	contract_report == expected
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |_| { bytes: [], work: [] }
