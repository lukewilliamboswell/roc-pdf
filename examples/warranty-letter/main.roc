app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0/GNN5tt2gKdX4dhawg4915C4YB193woHFdcCkz31fhGxv.tar.zst",
	pdf: "../../package/main.roc",
}
import pf.Path
import pf.Stdout
import pdf.Color
import pdf.Document
import pdf.Font
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme
import "fonts/Literata-Regular.ttf" as regular_bytes : List(U8)
import "fonts/Literata-Bold.ttf" as bold_bytes : List(U8)
import "fonts/Literata-Italic.ttf" as italic_bytes : List(U8)

## The reference business letter (docs/reference-documents.md), set in
## Literata: a letterhead whose mark sits above a navy and brass rule as
## page furniture, with the sender's name and address as semantic blocks
## in the first-page lead region; a footer over a hairline; continuation
## pages with the recipient, date, and `Page N of M` inset above a
## hairline; an unsplittable signature block; and an explicit break before
## the covered-items schedule. The letter has no visible title; readers
## show its metadata title.
main! = |_args| {
	fonts = register_fonts({})?
	options : Pdf.Options
	options = { theme: theme(fonts), fonts: Registered(fonts.registry) }
	document = Pdf.document({
		contents: opening.concat(body).concat(closing),
		language: "en-AU",
		title: "Letter to Northstar Cooperative about the warranty extension, 21 September 2026",
		page_templates: Templates(templates),
		created: Explicit("2026-09-21T00:00:00Z"),
		modified: Explicit("2026-09-21T00:00:00Z"),
	})
	bytes = Pdf.to_bytes_with(document, options).map_err(|err| PdfFailed(err))?
	output : Path
	output = "warranty-letter.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote warranty-letter.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

Faces : { bold : Font.FaceId, italic : Font.FaceId, regular : Font.FaceId, registry : Font.Registry }

## Literata Regular, Bold, and Italic, each retained byte-for-byte from
## its upstream release in `fonts/` beside this file.
register_fonts : {} -> Try(Faces, [FontRejected(Font.ResourceError)])
register_fonts = |_| {
	latin : List(Font.Script)
	latin = ["Latn"]
	add = |registry, bytes| registry.register(bytes, { provision: BuiltIn, scripts: latin }, Font.ValidationLimits.default).map_err(|err| FontRejected(err))
	regular = add(Font.Registry.empty, regular_bytes)?
	bold = add(regular.registry, bold_bytes)?
	italic = add(bold.registry, italic_bytes)?
	Ok({ bold: bold.face, italic: italic.face, regular: regular.face, registry: italic.registry })
}

opening : List(Document.Block)
opening = [
	Pdf.paragraph("21 September 2026"),
	Pdf.rich_paragraph([
		Pdf.text("Ms Priya Raman"),
		Pdf.line_break,
		Pdf.text("Operations Manager"),
		Pdf.line_break,
		Pdf.text("Northstar Cooperative Ltd"),
		Pdf.line_break,
		Pdf.text("42 Kestrel Parade"),
		Pdf.line_break,
		Pdf.text("Fremantle WA 6160"),
	]),
	Pdf.spacer(12),
	Pdf.paragraph("Dear Ms Raman,"),
	Pdf.rich_paragraph([Pdf.text("Subject: "), Pdf.strong([Pdf.text("Extended warranty for your Level 2–5 fit-out")])]),
]

closing : List(Document.Block)
closing = [
	Pdf.numbered_list({}, terms.map(|term| Pdf.list_item([Pdf.paragraph(term)]))),
	Pdf.paragraph("The enclosed schedule lists every covered item by product code. Please keep this letter and the schedule with your asset register, so that your team can quote them when lodging a claim by telephone or email."),
	Pdf.paragraph("If you have any questions about the extension, or would like the November inspection scheduled at a particular time, please call me directly on (03) 5550 0142. We look forward to supporting Northstar Cooperative for many years to come."),
	Pdf.keep_together([
		Pdf.paragraph("Yours sincerely,"),
		Pdf.spacer(36),
		Pdf.paragraph("Tom Finch"),
		Pdf.paragraph("Director, Harbour & Finch Pty Ltd"),
	]),
	Pdf.rich_paragraph([Pdf.text("Enclosure: "), Pdf.emphasis([Pdf.text("Schedule 1, covered items")])]),
	Pdf.page_break,
	Pdf.section([Pdf.heading(1, "Schedule 1. Covered items"), schedule]),
]

navy : Color.SourceValue
navy = "#183454"

brass : Color.SourceValue
brass = "#C49640"

ink : Color.SourceValue
ink = "#2B2B2B"

slate : Color.SourceValue
slate = "#56657A"

## A4 with 48 pt top and bottom and 72 pt side margins: a 451 × 746 pt
## body. Literata Regular for body text; Bold for the heading and
## `Pdf.strong`; Italic for `Pdf.emphasis`.
theme : Faces -> Theme
theme = |faces| {
	face: faces.regular,
	body: { color: ink, size: 10.5, leading: 15 },
	headings: { all: { color: navy, face: Face(faces.bold), size: 14, leading: 19 } },
	inline: { strong: { color: Themed(navy), font: Face(faces.bold) }, emphasis: { font: Face(faces.italic) } },
	page_margin: { top: 48, right: 72, bottom: 48, left: 72 },
	table: {
		header_color: Themed(navy),
		header_fill: Fill("#E8EDF3"),
		row_header_color: Themed(navy),
		body_rule: Rule({ color: "#D9DFE6", width: 0.5 }),
		rule: Rule({ color: navy, width: 0.8 }),
		cell_padding: 5,
	},
}

## The Harbour & Finch mark, 140 × 48 pt: three navy bars beside a navy
## tile holding a brass finch's wing, aligned to the page's end edge.
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

## The letterhead's rule under the mark: a 2 pt navy band over a 1 pt
## brass keyline along the header region's bottom edge, the full 451 pt
## width.
masthead : Scene.Drawing
masthead = Scene.Drawing.empty.rectangle(Layout.rect(0, 3, 451, 2), navy).rectangle(Layout.rect(0, 0, 451, 1), brass)

## A 0.6 pt hairline the full width of the body, `y` points up.
hairline : I64 -> Scene.Drawing
hairline = |y| Scene.Drawing.empty.rectangle({ origin: Layout.point(0, y), size: { height: 0.6, width: 451 } }, "#B8C2CE")

## `Page N of M` end-aligned in 62 pt: in Literata at 10.5 pt the widest
## value LET-A2's eleven pages need, `Page 10 of 11`, is 58.7 pt.
page_of : Pdf.Inline
page_of = Pdf.reserved_width(62, End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])

## The letterhead: the sender's name in the Strong face, then the address
## and contacts in slate.
letterhead : List(Document.Block)
letterhead = [
	Pdf.rich_paragraph([Pdf.strong([Pdf.text("Harbour & Finch Pty Ltd")])]),
	Pdf.scoped(
		{ text: Themed(slate) },
		[
			Pdf.rich_paragraph([
				Pdf.text("Level 3, 18 Wharf Street, Hobart TAS 7000"),
				Pdf.line_break,
				Pdf.text("(03) 5550 0142 · hello@harbourfinch.example · ABN 00 123 456 789"),
			]),
		],
	),
]

templates : { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = {
	first: Pdf.first_page_template({
		header: Pdf.region({ height: 58, end: [Pdf.furniture_image(logo)], backdrop: Backdrop(masthead), slot_inset: 10 }),
		lead: Pdf.lead_region(64, letterhead),
		footer: Pdf.region({ height: 22, center: [Pdf.furniture_text([Pdf.text("harbourfinch.example")])], backdrop: Backdrop(hairline(21)), slot_inset: 6 }),
		gap: 12,
	}),
	continuation: Pdf.page_template({
		header: Pdf.region({
			height: 21,
			start: [Pdf.furniture_text([Pdf.text("Northstar Cooperative Ltd · 21 September 2026")])],
			end: [Pdf.furniture_text([page_of])],
			backdrop: Backdrop(hairline(0)),
			slot_inset: 4,
		}),
		gap: 14,
	}),
}

body : List(Document.Block)
body = [
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
	columns: [{ width: Content, align: Start }, { width: Share(1), align: Start }, { width: Fixed(96), align: Start }],
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
})
