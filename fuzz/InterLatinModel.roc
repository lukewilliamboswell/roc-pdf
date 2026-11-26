import fuzz.Model
import fuzz.Solve
import pdf.KernelBuiltInFontInspections
import pdf.KernelBuiltInFonts
import pdf.KernelLatinShape
import pdf.KernelFont
import pdf.KernelUnicode
import pdf.Text

InterLatinModel := [].{}

Piece : [AsciiArrow, KernedPair, LiteralArrow, UnsafeCut]

Expected : { advance : I32, bytes : U64, glyph : U32, kind : Text.ClusterKind, scalars : U64 }

choices : List(Piece)
choices = [AsciiArrow, KernedPair, LiteralArrow, UnsafeCut]

## Each history is a sequence of independently authored pieces separated by
## one space. The fixture model describes the cluster source length without
## reading any provider offsets or Unicode boundary output.
machine : Model.Machine(List(Piece), Piece)
machine = {
	init: [],
	actions: |pieces| if (pieces.len() < 3) choices else [],
	step: |pieces, piece| pieces.append(piece),
	rules: [
		Model.always("provider preserves the independent cluster partition and advance", adapter_agrees),
		Model.sometimes("a later ligature keeps its nonzero byte offset", |pieces| pieces == [LiteralArrow, AsciiArrow]),
		Model.sometimes("an unsafe legal cut shapes its independent pieces", |pieces| pieces == [UnsafeCut]),
	],
}

expect {
	report = Model.explore(machine, { depth: 4, key: |pieces| pieces, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 85 and report.steps == 84 and report.depth == 3 and report.reached.len() == 2
}

prepared_for_test : U64 -> Try({ font : KernelFont.Inspection, plan : KernelLatinShape.Plan }, [Font])
prepared_for_test = |slot| {
	font = KernelBuiltInFontInspections.inspection(KernelBuiltInFonts.Slot.from_index(slot)) ? |_| Font
	plan = KernelLatinShape.prepare(font) ? |_| Font
	Ok({ font, plan })
}

adapter_agrees : List(Piece) -> Bool
adapter_agrees = |pieces| {
	if pieces.is_empty() {
		return True
	}
	match prepared_for_test(if (pieces.len() <= 3) 0 else 1) {
		Ok({ font, plan }) => {
			text = Str.join_with(pieces.map(spell), " ")
			when_isolated = pieces.contains(UnsafeCut)
			match KernelUnicode.analyze(text, KernelUnicode.default_limits) {
				Err(_) => False
				Ok(analysis) => match KernelLatinShape.input(text, analysis) {
					Ok(Eligible(scalars)) => match KernelLatinShape.shape(plan, font, scalars, analysis) {
						Err(_) => False
						Ok(result) => result.glyphs == expected_glyphs(pieces) and
							(result.scalar_visits == 2 * scalars.len() or (!when_isolated and result.scalar_visits == scalars.len()))
					}
					_ => False
				}
			}
		}
		_ => False
	}
}

spell : Piece -> Str
spell = |piece| match piece {
	AsciiArrow => "->"
	KernedPair => "AV"
	LiteralArrow => "→"
	UnsafeCut => "a->b"
}

expected_piece : Piece -> List(Expected)
expected_piece = |piece| match piece {
	AsciiArrow => [{ advance: 1954, bytes: 2, glyph: 1805, kind: Ligature, scalars: 2 }]
	KernedPair => [
		{ advance: 1273, bytes: 1, glyph: 2, kind: OneToOne, scalars: 1 },
		{ advance: 1413, bytes: 1, glyph: 456, kind: OneToOne, scalars: 1 },
	]
	LiteralArrow => [{ advance: 1954, bytes: 3, glyph: 1805, kind: OneToOne, scalars: 1 }]
	UnsafeCut => [
		{ advance: 1150, bytes: 1, glyph: 507, kind: OneToOne, scalars: 1 },
		{ advance: 942, bytes: 1, glyph: 1459, kind: OneToOne, scalars: 1 },
		{ advance: 1355, bytes: 1, glyph: 1517, kind: OneToOne, scalars: 1 },
		{ advance: 1254, bytes: 1, glyph: 578, kind: OneToOne, scalars: 1 },
	]
}

expected_glyphs : List(Piece) -> List(KernelLatinShape.Glyph)
expected_glyphs = |pieces| {
	var $expected = []
	var $first = True
	for piece in pieces {
		if !$first {
			$expected = $expected.append({ advance: 576, bytes: 1, glyph: 1777, kind: OneToOne, scalars: 1 })
		}
		for glyph in expected_piece(piece) {
			$expected = $expected.append(glyph)
		}
		$first = False
	}
	var $byte = 0
	var $scalar = 0
	var $result = []
	for glyph in $expected {
		end_byte = $byte + glyph.bytes
		end_scalar = $scalar + glyph.scalars
		$result = $result.append({
			advance: glyph.advance,
			id: glyph.glyph,
			kind: glyph.kind,
			offset: 0,
			range: { byte_end: end_byte, byte_start: $byte, scalar_end: end_scalar, scalar_start: $scalar },
		})
		$byte = end_byte
		$scalar = end_scalar
	}
	$result
}

## The checked endpoints consumed by the glyph and cluster adapters define
## a compact length. Ordered endpoints give a non-underflowing difference
## that reconstructs the endpoint when added to the start.
expect {
	proof = Solve.prove_within(
		{ start: Solve.u64, end: Solve.u64 }.Solve,
		|{ start, end }| {
			length = KernelLatinShape.span_length(start, end)
			ordered = start.lte(end)
			Solve.all([
				ordered.iff(end.minus_overflows(start).not()),
				Solve.any([ordered.not(), start.plus_wrap(length).eq(end)]),
			])
		},
		5000,
	)
	if proof != Ok(Proved) {
		crash "Inter source span proof: ${Str.inspect(proof)}"
	}
	True
}
