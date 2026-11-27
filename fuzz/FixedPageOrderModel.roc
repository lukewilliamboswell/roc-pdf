import fuzz.Model
import pdf.Color
import pdf.Document
import pdf.Layout
import pdf.Pdf
import pdf.Scene

FixedPageOrderModel := [].{}

World : { placements : U64, order : List(U64), closed : Bool, underlay : Bool, overlay : Bool }

Action : [Start({ placements : U64, underlay : Bool, overlay : Bool }), Append(U64), Finish]

machine : Model.Machine(World, Action)
machine = {
	init: { placements: 0, order: [], closed: False, underlay: False, overlay: False },
	actions: |world| {
		if world.placements == 0 {
			var $choices = []
			for placements in [1, 2, 3, 4] {
				for underlay in [False, True] {
					for overlay in [False, True] {
						$choices = $choices.append(Start({ placements, underlay, overlay }))
					}
				}
			}
			$choices
		} else if world.closed {
			[]
		} else if world.order.len() >= world.placements {
			[Finish]
		} else {
			[0, 1, 2, 3, 4].keep_if(|index| index <= world.placements).map(|index| Append(index)).append(Finish)
		}
	},
	step: |world, action| match action {
		Start({ placements, underlay, overlay }) => { ..world, placements, underlay, overlay }
		Append(index) => { ..world, order: world.order.append(index) }
		Finish => { ..world, closed: True }
	},
	rules: [
		Model.always("validated sheets preserve logical placements and separate physical paint", |world| !world.closed or (agrees(world, TextOnly) and agrees(world, WithFigure))),
		Model.sometimes("reversed paint with both artifact layers", |world| world.closed and world.order == [3, 2, 1, 0] and world.underlay and world.overlay),
		Model.sometimes("duplicate paint with full count", |world| world.closed and world.placements == 2 and world.order == [0, 0]),
		Model.sometimes("one placement is omitted from paint", |world| world.closed and world.placements == 2 and world.order == [1]),
		Model.sometimes("one index names a nonexistent placement", |world| world.closed and world.placements == 2 and world.order == [0, 2]),
	],
}

Content : [TextOnly, WithFigure]

agrees : World, Content -> Bool
agrees = |world, content| {
	indices = [0, 1, 2, 3].keep_if(|index| index < world.placements)
	valid = world.order.len() == world.placements and indices.all(|index| world.order.count_if(|paint| paint == index) == 1)
	page = build_page(indices, world, content)
	document = Pdf.fixed_document({ pages: [page], language: "en", title: "Fixed page model" })
	match Document.normalize_fixed(document, { max_pages: 1, max_placements: 4, max_rectangles: 2 }) {
		Err(_) => !valid
		Ok(Flow) => False
		Ok(Fixed(plan)) => {
			view = Document.NormalizedFixed.view(plan)
			match view.pages {
				[sheet] => {
					artifacts = view.artifacts.map(
						|rect| match rect.kind {
							Background => 1
							Decoration => 2
							_ => 0
						},
					)
					expected = (if (world.underlay) [1] else []).concat(if (world.overlay) [2] else [])
					frames = indices.map(|index| if (content == WithFigure and index == 1) [frame(index), frame(index)] else [frame(index)]).join()
					logical = indices.map(|index| if (content == WithFigure and index == 1) [" ", "Caption"] else [index.to_str()]).join()
					paint = world.order.map(
						|index|
							if content == TextOnly or index == 0 {
								[index]
							} else if index == 1 {
								[1, 2]
							} else {
								[index + 1]
							},
					).join()
					valid and view.frames == frames and view.paint_order == paint and artifacts == expected and
						view.authoring.blocks.map(|block| block.text) == logical and
							sheet.placements.start() == 0 and sheet.placements.length() == indices.len() and
								sheet.paint.start() == 0 and sheet.paint.length() == frames.len() and
									sheet.underlays.start() == 0 and sheet.underlays.length() == (if (world.underlay) 1 else 0) and
										sheet.overlays.start() == sheet.underlays.length() and sheet.overlays.length() == (if (world.overlay) 1 else 0)
				}
				_ => False
			}
		}
	}
}

frame : U64 -> Layout.Rect
frame = |index| Layout.rect({ x: 10, y: 10 + index.to_i64_wrap() * 20, width: 80, height: 20 })

build_page : List(U64), World, Content -> Document.FixedPage
build_page = |indices, world, content| {
	drawing = Scene.Drawing.empty.rectangle({ bounds: frame(0), color: Color.srgb8({ red: 25, green: 50, blue: 75 }) })
	var $page = Pdf.fixed_page({ width: 100, height: 100 })
	if world.underlay {
		$page = $page.background(drawing)
	}
	for index in indices {
		block = if content == WithFigure and index == 1 {
			local = Scene.Drawing.empty.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 10, height: 5 }), color: Color.srgb8({ red: 25, green: 50, blue: 75 }) })
			Pdf.figure({ drawing: local, alt: "Colored patch", caption: Pdf.caption("Caption") })
		} else {
			Pdf.paragraph(index.to_str())
		}
		$page = $page.place({ frame: frame(index), block })
	}
	if world.overlay {
		$page = $page.overlay({ drawing, kind: Decoration })
	}
	$page.with_paint_order(world.order).finish()
}

expect {
	report = Model.explore(machine, { depth: 7, key: |world| world, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	# For each of the four layer choices, every prefix has an unfinished
	# world and a finished world. There are 3, 13, 85 and 781 prefixes.
	report.states == 7057 and report.steps == 7056 and report.depth == 6 and report.reached.len() == 4
}
