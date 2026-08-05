app [main!] {
	pf: platform "../tests/platform/main.roc",
	pdf: "../package/main.roc",
}

import pdf.Color
import pdf.Font
import pdf.Layout
import pdf.Scene
import pdf.Semantics
import pdf.Text

source_range : Semantics.TextRange
source_range = {
	scalars: Semantics.Range.from_start_and_length(0, 2),
	utf8_bytes: Semantics.Range.from_start_and_length(0, 3),
}

## Font planning assigns complete grapheme clusters to exact static instances.
expect {
	plan : Font.PlanResult
	plan = Complete({
		face_ranges: [
			{
				clusters: Semantics.Range.from_start_and_length(0, 1),
				instance: Font.InstanceId.from_index(2),
			},
		],
		work: { coverage_span_visits: 2, face_visits: 1, grapheme_visits: 1 },
	})

	plan == Complete({
		face_ranges: [
			{
				clusters: Semantics.Range.from_start_and_length(0, 1),
				instance: Font.InstanceId.from_index(2),
			},
		],
		work: { coverage_span_visits: 2, face_visits: 1, grapheme_visits: 1 },
	})
}

## Cluster evidence can explicitly represent many source scalars forming one glyph.
expect {
	cluster : Text.Cluster
	cluster = {
		glyphs: Semantics.Range.from_start_and_length(0, 1),
		kind: ManyToOne,
		source: source_range,
	}

	cluster.kind == ManyToOne and cluster.source.scalars.length() == 2
}

## A shaped run retains occurrence ownership and source-to-glyph evidence by ranges.
expect {
	run : Text.Run
	run = {
		actual_text: FromOccurrence,
		clusters: Semantics.Range.from_start_and_length(0, 1),
		direction: LeftToRight,
		glyphs: Semantics.Range.from_start_and_length(0, 1),
		id: Text.RunId.from_index(0),
		instance: Font.InstanceId.from_index(2),
		language: Language("en-AU"),
		occurrence: Semantics.OccurrenceId.from_index(4),
		script: Font.Script.from_iso15924("Latn"),
		source: source_range,
		substitutions: Semantics.Range.from_start_and_length(0, 0),
		transformations: Semantics.Range.from_start_and_length(0, 0),
		writing_mode: Horizontal,
	}

	run.occurrence.index() == 4 and run.instance.index() == 2
}

## Text paint admits only the initial visible rendering modes.
expect {
	black : Color.Value
	black = {
		channels: Rgb({ blue: 0, green: 0, red: 0 }),
		space: Color.SpaceId.from_index(0),
	}
	paint : Scene.TextPaint
	paint = {
		fill: black,
		mode: Fill,
		opacity: 65535,
		stroke: NoStroke,
	}

	channels_are_black = match paint.fill.channels {
		Rgb({ blue, green, red }) => blue == 0 and green == 0 and red == 0
		_ => False
	}

	channels_are_black and paint.fill.space.index() == 0 and Layout.Unit.units_per_point == 1000
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |_| { bytes: [], work: [] }
