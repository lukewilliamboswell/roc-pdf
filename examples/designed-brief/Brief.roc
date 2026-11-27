import pdf.Color
import pdf.Document
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme

## The Sprout product brief's material on explicitly placed sheets.
Brief :: [].{
	document : U64 -> Document
	document = |count| {
		var $pages = List.with_capacity(count)
		var $index = 0
		while $index < count {
			$pages = $pages.append(sheet($index % 2 == 1))
			$index = $index + 1
		}
		Pdf.fixed_document({ title: "Sprout 2.4 launch brief", language: "en-AU", pages: $pages })
	}

	theme : Theme
	theme = {
		body: { color: forest, size: 12, leading: 18 },
		title: { color: white, size: 35, leading: 44 },
		paragraph_spacing: 10,
	}
}

forest : Color.SourceValue
forest = "#14352C"

teal : Color.SourceValue
teal = "#146F62"

lime : Color.SourceValue
lime = "#D5E88B"

sage : Color.SourceValue
sage = "#DDE9E1"

white : Color.SourceValue
white = "#FFFFFF"

paper : Color.SourceValue
paper = "#F4F7F3"

rect : Scene.Drawing, I64, I64, I64, I64, Color.SourceValue -> Scene.Drawing
rect = |drawing, x, y, width, height, color| drawing.rectangle({ bounds: Layout.rect({ x, y, width, height }), color })

## Board diagram. The caption and the figure alternative give the
## meaning of the color-coded columns.
board : Scene.Drawing
board = {
	var $drawing = rect(Scene.Drawing.empty, 0, 0, 487, 218, forest)
	var $x = 13
	for count in [3, 2, 4] {
		$drawing = rect($drawing, $x, 26, 146, 178, sage)
		$drawing = rect($drawing, $x + 10, 188, 34 + count * 7, 4, teal)
		var $card = 0
		while $card < count {
			y = 148 - $card * 29
			$drawing = rect($drawing, $x + 10, y, 126, 22, white)
			$drawing = rect($drawing, $x + 10, y, 4, 22, if (count == 4) teal else lime)
			$drawing = rect($drawing, $x + 21, y + 13, 68 - $card * 6, 3, sage)
			$drawing = rect($drawing, $x + 21, y + 6, 45 + $card * 3, 2, sage)
			$card = $card + 1
		}
		$x = $x + 157
	}
	track = rect($drawing, 13, 11, 460, 4, sage)
	rect(track, 13, 11, 300, 4, lime)
}

sheet : Bool -> Document.FixedPage
sheet = |a4| {
	width = if (a4) 595 else 612
	height = if (a4) 842 else 792
	top = height - 136
	card = height - 293
	sheet_size : Layout.Size
	sheet_size = { width: Layout.Unit.points(width), height: Layout.Unit.points(height) }
	sheet_background = rect(Scene.Drawing.empty, 0, 0, width, height, paper)
	title_band = rect(sheet_background, 0, top, width, 136, forest)
	background = rect(title_band, 54, card, 487, 108, white)
	title_accent = rect(Scene.Drawing.empty, 54, top + 20, 39, 4, lime)
	card_accent = rect(title_accent, 54, card + 53, 3, 55, teal)
	accents = rect(card_accent, 54, 70, 487, 1, sage)
	figures = Pdf.rich_paragraph([
		Pdf.strong([Pdf.text("Key figures")]),
		Pdf.line_break,
		Pdf.text("Three rollout waves from October to November 2026."),
		Pdf.line_break,
		Pdf.text("Three plans with boards and a shared decision log."),
		Pdf.line_break,
		Pdf.text("Team starts at USD 12 per editor per month."),
	])
	figure = Pdf.figure({
		drawing: board,
		alt: "Sprout board with three proposed cards, two decisions in progress and four decided cards. The progress bar is about two-thirds full.",
		caption: Pdf.caption("The Sprout board moves each decision from proposed through deciding to decided."),
	})

	## Declaration order is title, key figures, then figure and caption.
	## The physical permutation paints that last placement first.
	Pdf.fixed_page(sheet_size)
		.background(background)
		.place({ block: Pdf.title("Sprout 2.4 launch brief"), frame: Layout.rect({ x: 54, y: top + 55, width: 487, height: 48 }) })
		.place({ block: figures, frame: Layout.rect({ x: 70, y: card + 13, width: 456, height: 82 }) })
		.place({ block: figure, frame: Layout.rect({ x: 54, y: card - 299, width: 487, height: 260 }) })
		.with_paint_order([2, 0, 1])
		.overlay({ drawing: accents, kind: Decoration })
		.finish()
}
