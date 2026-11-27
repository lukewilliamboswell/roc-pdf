app [main!] {
	pdf: "../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.11.0/7CdYzjBAJmprmnK45oTpmH6BXt76ZASN2Ck5uZQEoWsK.tar.zst",
}

import Bench
import pdf.Document
import pdf.Layout
import pdf.Pdf
import weaver.Cli

main! = |args| {
	builder = Cli.map(Bench.common_args(4096), |common| { common, workload: {} })
	Bench.run_configured!(
		args,
		{
			name: "pdf-wide-table-bench",
			description: "Hold a row and its total width fixed while varying the number of tracks under one spanning cell. Units are the number of fixed filler tracks.",
		},
		builder,
		{ defaults: options, max_units: filler_width },
		|units, iteration, _| document(units, iteration),
	)
}

filler_width : U64
filler_width = 65535

options : Pdf.Options
options = {
	page_size: Custom({ width: 1264, height: 842 }),
	theme: {
		page_margin: { top: 36, right: 0.385, bottom: 36, left: 0 },
		body: { size: 0.1, leading: 2 },
		latin_shaping: NominalGlyphs,
		table: { cell_padding: 0, row_gap: 0, rule: NoRule },
	},
}

# Each glyph is 90 millipoints in the packaged Inter Regular at 0.1 pt.
# The share frame is exactly 13312 glyph advances. With these minima and
# weights, each redistribution clamps one column before the final division.
shared_tracks : List({ glyphs : U64, weight : U16 })
shared_tracks = [
	{ glyphs: 7168, weight: 1024 },
	{ glyphs: 3328, weight: 512 },
	{ glyphs: 1536, weight: 256 },
	{ glyphs: 704, weight: 128 },
	{ glyphs: 320, weight: 64 },
	{ glyphs: 144, weight: 32 },
	{ glyphs: 64, weight: 16 },
	{ glyphs: 28, weight: 8 },
	{ glyphs: 12, weight: 4 },
	{ glyphs: 5, weight: 2 },
	{ glyphs: 2, weight: 1 },
	{ glyphs: 1, weight: 1 },
]

document : U64, U64 -> Document
document = |units, iteration| {
	var $columns = List.with_capacity(shared_tracks.len() + units)
	var $cells = List.with_capacity(shared_tracks.len() + 1)
	var $index = 0
	while $index < shared_tracks.len() {
		track = shared_tracks.get($index) ?? crash "shared track escaped"
		$columns = $columns.append({ width: Share(track.weight), align: Start })
		inlines = [Pdf.text(Str.repeat("M", track.glyphs))]
		cell = if ($index == 0) Pdf.header_cell(Row, inlines) else Pdf.cell(inlines)
		$cells = $cells.append(cell)
		$index = $index + 1
	}
	base = filler_width // units
	remainder = filler_width % units
	$index = 0
	while $index < units {
		width = base + (if ($index < remainder) 1 else 0)
		$columns = $columns.append({ width: Fixed(Layout.Unit.millipoints(width.to_i64_wrap())), align: Start })
		$index = $index + 1
	}
	$cells = $cells.append(Pdf.cell([]).spanning(units.to_u16_wrap()))
	Pdf.document({
		title: "Wide table, run ${iteration.to_str()}",
		language: "en-AU",
		contents: [
			Pdf.table({
				columns: $columns,
				header_rows: [],
				body_rows: [Pdf.row($cells)],
				footer_rows: [],
				caption: Pdf.no_caption,
				row_split: KeepRows,
			}),
		],
	})
}
