app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import fuzz.Solve
import pdf.KernelScene
import pdf.KernelSpan
import pdf.Layout
import pdf.Semantics

target = Fuzz.suite([])

## The production predicate accepts exactly the ranges with a representable
## sum inside the store, including empty ranges at the store's end. Solve
## checks all U64 starts, lengths, and store limits. The overflow guard
## protects the independent checked sum from evaluating on invalid inputs.
expect Solve.prove_within(
	{ start: Solve.u64, length: Solve.u64, available: Solve.u64 }.Solve,
	|{ start, length, available }| {
		ending = KernelSpan.Arithmetic.wrapped_end(start, length)
		fits = KernelSpan.Arithmetic.fits(start, ending, available, |left, right| left.lte(right), |left, right| Solve.all([left, right]))
		exact = Solve.all([start.plus_overflows(length).not(), (start + length).lte(available)])
		fits.iff(exact)
	},
	5000,
) == Ok(Proved)

## Compare the concrete dispatcher and returned endpoint against a wider
## addition, around zero, the top bit, and the U64 overflow boundary.
expect {
	edges = [0.U64, 1, 2, U64.highest // 2, U64.highest // 2 + 1, U64.highest - 1, U64.highest]
	edges.all(
		|start| edges.all(
			|length| edges.all(
				|available| {
					exact_end = start.to_u128() + length.to_u128()
					expected = if exact_end <= available.to_u128() {
						Ok(exact_end.to_u64_wrap())
					} else {
						Err(Outside)
					}
					KernelSpan.end_within(start, length, available) == expected
				},
			),
		),
	)
}

## Find a nonempty span that would pass an end-only check against an empty
## store. Pass the actual solver values to scene planning. If the validator
## accepted the wrapped end, its paint-order walk would do no work and
## the malformed scene would otherwise look like a valid blank page.
expect match Solve.find_within(
	{ start: Solve.u64, length: Solve.u64 }.Solve,
	|{ start, length }| Solve.all([start.neq(0), KernelSpan.Arithmetic.wrapped_end(start, length).eq(0)]),
	1000,
) {
	Ok(Found({ start: witness_start, length: witness_length })) => {
		start = witness_start.value()
		length = witness_length.value()
		match (plan_page_with_paint_range(start, length), plan_page_with_paint_range(0, 0)) {
			(Err(SpanOutOfRange({ available: 0, kind: GroupIndex, owner: 0, start: reported_start, length: reported_length })), Ok(_)) =>
				reported_start == start and reported_length == length
			_ => False
		}
	}
	_ => False
}

plan_page_with_paint_range : U64, U64 -> Try(KernelScene.Plan, KernelScene.Error)
plan_page_with_paint_range = |start, length| {
	box = Layout.rect({ x: 0, y: 0, width: 1, height: 1 })
	KernelScene.Plan.build(
		{
			commands: [],
			dash_lengths: [],
			groups: [],
			page_groups: [],
			pages: [
				{
					boxes: { art: box, bleed: box, crop: box, media: box, trim: box },
					id: Semantics.PageId.from_index(0),
					paint_order: Semantics.IndexRange.from_start_and_length({ start, length }),
					rotation: Rotate0,
				},
			],
			path_segments: [],
			paths: [],
		},
		KernelScene.Resources.make({ color_spaces: 0, images: 0 }),
		KernelScene.Limits.make({ max_commands: 0, max_dash_lengths: 0, max_graphics_depth: 0, max_groups: 0, max_pages: 1, max_path_segments: 0, max_paths: 0 }),
	)
}
