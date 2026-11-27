import fuzz.Solve
import pdf.Font
import pdf.KernelBidiBoundary
import pdf.KernelInternationalLine
import pdf.KernelUnicode
import pdf.Layout
import pdf.Semantics
import pdf.Text

InternationalAdvanceProof := [].{}

## Both increments are representable nonnegative Layout.Unit values.
## Their U64 sum is exact, so an I64 overflow is detected precisely by
## comparing it with the largest representable positioned advance.
expect Solve.prove_within(
	{ used: Solve.u64, next: Solve.u64 }.Solve,
	|{ used, next }| {
		max = 9223372036854775807
		within = Solve.all([used.lte(max), next.lte(max)])
		sum = used.plus_wrap(next)
		exact = Solve.all([used.plus_overflows(next).not(), next.lte(max - used).iff(sum.lte(max))])
		Solve.any([within.not(), exact])
	},
	5000,
) == Ok(Proved)

expect match Solve.find_within(
	{ used: Solve.u64, next: Solve.u64 }.Solve,
	|{ used, next }| {
		max = 9223372036854775807
		Solve.all([used.lte(max), next.lte(max), used.plus_wrap(next).gt(max)])
	},
	1000,
) {
	Ok(Found({ used: used_model, next: next_model })) => {
		u = used_model.value().to_i64_wrap()
		n = next_model.value().to_i64_wrap()
		match (position(u, n), position(u, I64.highest - u)) {
			(Err(ArithmeticOverflow), Ok(accepted)) => accepted.pieces.len() == 1 and accepted.work.glyphs == 2
			_ => False
		}
	}
	_ => False
}

position : I64, I64 -> Try(KernelInternationalLine.Positioned, KernelInternationalLine.Error)
position = |first, next| {
	source = "AB"
	limits = KernelBidiBoundary.Limits.make({ max_scalars: 2, max_clusters: 2, max_visual_order: 2 })
	analysis = KernelUnicode.analyze(source, KernelUnicode.default_limits) ? |_| InvalidStore
	bidi = KernelBidiBoundary.analyze_paragraph(source, analysis, Auto, limits) ? Bidi
	source_range = { scalars: span(0, 2), utf8_bytes: span(0, 2) }
	clusters : List(Text.Cluster)
	clusters = [0, 1].map(
		|index| {
			glyphs: span(index, 1),
			kind: OneToOne,
			source: { scalars: span(index, 1), utf8_bytes: span(index, 1) },
		},
	)
	store : Text.Store
	store = {
		clusters,
		glyphs: [first, next].map(
			|x| {
				id: Text.GlyphId.from_raw(1),
				advance_x: Layout.Unit.from_raw(x),
				advance_y: 0,
				offset_x: 0,
				offset_y: 0,
			},
		),
		glyph_indices: [0, 1],
		runs: [
			{
				actual_text: FromOccurrence,
				clusters: span(0, 2),
				direction: LeftToRight,
				glyphs: span(0, 2),
				id: Text.RunId.from_index(0),
				instance: Font.InstanceId.from_index(0),
				language: Language("en"),
				script: Font.Script.from_iso15924("Latn"),
				size: 11,
				source: source_range,
				substitutions: span(0, 0),
				transformations: span(0, 0),
				unicode: OccurrenceText(Semantics.OccurrenceId.from_index(0)),
				writing_mode: Horizontal,
			},
		],
		substitutions: [],
		transformations: [],
	}
	owners = KernelInternationalLine.cluster_owners(store)?
	KernelInternationalLine.position(bidi, store, owners, { advance: Layout.Unit.from_raw(I64.highest), clusters: span(0, 2), source: source_range }, limits)
}

span : U64, U64 -> Semantics.IndexRange
span = |start, length| Semantics.IndexRange.from_start_and_length({ start, length })
