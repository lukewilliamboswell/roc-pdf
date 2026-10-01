import pdf.Color
import pdf.Document
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme

## The reference business letter (docs/reference-documents.md), authored
## through the public `Pdf` constructors exactly as `examples/warranty-letter/main.roc`
## authors it, with the knobs its adverse variants change. `ordinary`
## produces the gallery letter byte for byte.
Letter :: [].{
	Config : {
		body_field : Bool,
		continuation_start : Str,
		lead_height : I64,
		letterhead_lines : U64,
		paragraphs : U64,
		recipient : List(Str),
		signature_space : I64,
		title : Str,
	}

	ordinary : Config
	ordinary = {
		body_field: False,
		continuation_start: "Northstar Cooperative Ltd · 21 September 2026",
		lead_height: 60,
		letterhead_lines: 0,
		paragraphs: 6,
		recipient: ["Ms Priya Raman", "Operations Manager", "Northstar Cooperative Ltd", "42 Kestrel Parade", "Fremantle WA 6160"],
		signature_space: 36,
		title: "Letter to Northstar Cooperative about the warranty extension, 21 September 2026",
	}

	theme : Theme
	theme = letter_theme

	options : Pdf.Options
	options = Pdf.Options.{ theme: letter_theme }

	document : Config -> Document
	document = |config| {
		var $body = List.with_capacity(config.paragraphs)
		var $index = 0
		while $index < config.paragraphs {
			$body = $body.append(body_paragraph($index))
			$index = $index + 1
		}
		opening = [
			Pdf.paragraph("21 September 2026"),
			lines_paragraph(config.recipient),
			Pdf.spacer(points(12)),
			Pdf.paragraph("Dear Ms Raman,"),
			Pdf.rich_paragraph([Pdf.text("Subject: "), Pdf.strong([Pdf.text("Extended warranty for your Level 2–5 fit-out")])]),
		]
		field = if config.body_field [Pdf.rich_paragraph([Pdf.text("This is page "), Pdf.page_number(Decimal), Pdf.text(" of the letter.")])] else []
		closing = [
			Pdf.numbered_list({ start: 1, style: Decimal }, terms.map(|term| Pdf.list_item([Pdf.paragraph(term)]))),
			Pdf.paragraph("The enclosed schedule lists every covered item by product code. Please keep this letter and the schedule with your asset register, so that your team can quote them when lodging a claim by telephone or email."),
			Pdf.paragraph("If you have any questions about the extension, or would like the November inspection scheduled at a particular time, please call me directly on (03) 5550 0142. We look forward to supporting Northstar Cooperative for many years to come."),
			Pdf.keep_together([
				Pdf.paragraph("Yours sincerely,"),
				Pdf.spacer(points(config.signature_space)),
				Pdf.paragraph("Tom Finch"),
				Pdf.paragraph("Director, Harbour & Finch Pty Ltd"),
			]),
			Pdf.paragraph("Enclosure: Schedule 1, covered items"),
			Pdf.page_break,
			Pdf.section([Pdf.heading(1, "Schedule 1. Covered items"), schedule]),
		]
		Pdf.document({ contents: [opening, field, $body, closing].join(), language: "en-AU", title: config.title })
			.with_page_templates(templates(config))
			.with_created("2026-09-21T00:00:00Z")
			.with_modified("2026-09-21T00:00:00Z")
	}
}

points : I64 -> Layout.Unit
points = |value| Layout.Unit.points(value)

navy : Color.SourceValue
navy = Color.srgb8({ red: 24, green: 52, blue: 84 })

brass : Color.SourceValue
brass = Color.srgb8({ red: 196, green: 150, blue: 64 })

letter_theme : Theme
letter_theme = Theme.{ headings: { all: { color: navy } }, inline: { strong: { color: Themed(navy) } }, page_margin: { top: points(48), right: points(72), bottom: points(48), left: points(72) } }

logo : Scene.Drawing
logo = {
	wing = Scene.PathBuilder.start
		.move_to(Layout.point(100, 12))
		.cubic_to({ control_1: Layout.point(108, 36), control_2: Layout.point(124, 42), end: Layout.point(132, 40) })
		.cubic_to({ control_1: Layout.point(124, 32), control_2: Layout.point(114, 22), end: Layout.point(100, 12) })
		.close()
		.finish()
	tile = Scene.Drawing.empty.rectangle(Layout.rect(92, 0, 48, 48), navy).path(wing, Scene.solid_fill(brass))
	bars = tile.rectangle(Layout.rect(0, 32, 82, 8), navy).rectangle(Layout.rect(22, 20, 60, 6), navy)
	bars.rectangle(Layout.rect(42, 10, 40, 4), brass)
}

page_of : Pdf.Inline
page_of = Pdf.reserved_width(points(72), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])

## One paragraph of lines separated by explicit line breaks.
lines_paragraph : List(Str) -> Document.Block
lines_paragraph = |lines| {
	var $inlines = List.with_capacity(lines.len() * 2)
	for line in lines {
		$inlines = if $inlines.is_empty() $inlines.append(Pdf.text(line)) else $inlines.append(Pdf.line_break).append(Pdf.text(line))
	}
	Pdf.rich_paragraph($inlines)
}

## The letterhead, with `extra` further address lines (LET-A3b).
letterhead : U64 -> List(Document.Block)
letterhead = |extra| {
	var $address = [
		Pdf.text("Level 3, 18 Wharf Street, Hobart TAS 7000"),
		Pdf.line_break,
		Pdf.text("(03) 5550 0142 · hello@harbourfinch.example · ABN 00 123 456 789"),
	]
	var $line = 0
	while $line < extra {
		$address = $address.append(Pdf.line_break).append(Pdf.text("Branch office ${($line + 1).to_str()}, Harbour & Finch Pty Ltd"))
		$line = $line + 1
	}
	[Pdf.rich_paragraph([Pdf.strong([Pdf.text("Harbour & Finch Pty Ltd")])]), Pdf.rich_paragraph($address)]
}

templates : Letter.Config -> { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = |config| {
	first: Pdf.first_page_template({
		header: Pdf.region({ height: points(48), start: [], center: [], end: [Pdf.furniture_image(logo)] }),
		lead: Pdf.lead_region(points(config.lead_height), letterhead(config.letterhead_lines)),
		footer: Pdf.region({ height: points(16), start: [], center: [Pdf.furniture_text([Pdf.text("harbourfinch.example")])], end: [] }),
		gap: points(12),
	}),
	continuation: Pdf.page_template({
		header: Pdf.region({
			height: points(16),
			start: [Pdf.furniture_text([Pdf.text(config.continuation_start)])],
			center: [],
			end: [Pdf.furniture_text([page_of])],
		}),
		footer: Pdf.no_region,
		gap: points(12),
	}),
}

authored_body : List(Document.Block)
authored_body = [
	Pdf.paragraph("Thank you for choosing Harbour & Finch for the Level 2 to 5 fit-out at 42 Kestrel Parade. Your facilities team told us in August that the new workstations have settled in well, and that the standing desks in particular have changed how the operations floor works through a long day. We are writing to confirm an extension of the warranty that covers the furniture and fittings we supplied under purchase order PO 88213, and to explain what the extension means for your team in practice, including how to lodge a claim."),
	Pdf.paragraph("Our standard warranty covers every item for two years from delivery. From today, we are extending that cover by a further three years for all four levels, so that frames, motors, desktops, chairs, lamps, and cable trays remain covered until 30 September 2031. The extension is provided at no charge. It reflects the volume of the order, the care your team has taken in following our assembly guidance, and the confidence we have in the materials and components we selected for this fit-out."),
	Pdf.rich_paragraph([
		Pdf.text("The desktops were milled from Tasmanian oak supplied by our long-standing partner in France, the joinery workshop of our oak supplier "),
		Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")]),
		Pdf.text(" in Lyon. Each board was kiln-dried to a moisture content between nine and eleven percent before it was oiled, which is why we are comfortable covering the desktops against warping and delamination for the full extended term. If a desktop does develop a fault, we will replace the top with one from the same batch wherever stock allows, so that finishes remain consistent across a level."),
	]),
	Pdf.paragraph("The motors in the standing desk frames are sealed units rated for twenty thousand cycles. Under ordinary office use, which we estimate at six adjustments a day, that rating represents more than twelve years of service. We have nevertheless included the motors and control boxes in the extension, together with the height presets and the anti-collision sensors. If a frame stops responding, please do not open the control box: the seal is part of the safety rating, and our technicians will replace the whole unit on site."),
	Pdf.paragraph("The task chairs carry their manufacturer's own ten-year warranty on the gas lift and base, which continues unchanged. Our extension adds cover for the mechanisms, armrests, and upholstery seams, which the manufacturer covers for only three years. Mesh backs are covered against tearing that arises from ordinary use, though not against cuts or burns. Where a chair needs repair, we will lend your team a replacement chair of the same model for the duration of the repair, so that nobody is left without a seat."),
	Pdf.paragraph("To make the extension simple to use, our installers will visit each level in November to inspect every desk frame and record its serial number against your asset register. The inspection takes about an hour per level and can be scheduled outside business hours if that suits your team better. After the visit, we will send your facilities manager a schedule of serial numbers and a short guide to lodging claims, so that anyone on your team can report a fault quickly and accurately."),
]

## Body paragraph `index`: the six authored paragraphs, cycled for the
## long-letter variants.
body_paragraph : U64 -> Document.Block
body_paragraph = |index| match authored_body.get(index % authored_body.len()) {
	Ok(value) => value
	Err(OutOfBounds) => crash "letter paragraph escaped"
}

terms : List(Str)
terms = [
	"Frames, motors, and control boxes are covered until 30 September 2031.",
	"Desktops are covered against warping and delamination for the same term.",
	"Chair mechanisms, armrests, and upholstery seams are covered for the same term.",
	"Replacement parts are dispatched within ten business days of an accepted claim.",
]

schedule : Document.Block
schedule = Pdf.table({
	caption: Pdf.caption("Items covered by the extended warranty"),
	columns: [{ width: Content, align: Start }, { width: Share(1), align: Start }, { width: Fixed(points(96)), align: Start }],
	header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Code")]), Pdf.header_cell(Column, [Pdf.text("Description")]), Pdf.header_cell(Column, [Pdf.text("Warranty until")])])],
	body_rows: [
		("HF-DSK-140", [Pdf.text("Standing desk frame, twin motor, 1400 mm")]),
		("HF-TOP-OAK", [Pdf.text("Tasmanian oak desktop, 1400 × 700 mm, oiled")]),
		("HF-CHR-ERG", [Pdf.text("Ergonomic task chair, mesh back, adjustable lumbar support")]),
		("HF-CAF-ELG", [Pdf.in_language("fr", [Pdf.text("Cafetière « Élégance »")]), Pdf.text(", 1 L, for the staff kitchen")]),
		("HF-LMP-LED", [Pdf.text("LED task lamp, 4000 K, clamp mount")]),
		("HF-CBL-TRY", [Pdf.text("Under-desk cable tray, powder-coated steel")]),
		("HF-INS-HRS", [Pdf.text("Installation labour (workmanship)")]),
		("HF-DEL-MET", [Pdf.text("Metropolitan delivery, Hobart (transit damage)")]),
	].map(|(code, description)| Pdf.row([Pdf.header_cell(Row, [Pdf.text(code)]), Pdf.cell(description), Pdf.cell([Pdf.text("30 Sep 2031")])])),
	footer_rows: [],
	row_split: KeepRows,
})
