app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pdf.Color
import pdf.Image
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme

main! = |_args| {
	green = Color.srgb8({ red: 15, green: 128, blue: 81 })
	base_title = Theme.title_style(Theme.default)
	theme = Theme.default
		.with_heading_color(green)
		.with_title_style({ ..base_title, color: green, size: Layout.Unit.points(42), leading: Layout.Unit.points(48) })
		.with_page_margin({ top: Layout.Unit.points(120), right: Layout.Unit.points(84), bottom: Layout.Unit.points(60), left: Layout.Unit.points(84) })
		.with_paragraph_spacing(Layout.Unit.points(16))
		.with_bullet_indent(Layout.Unit.points(24))
	document = Pdf.document({
		title: "Sprout product brief",
		language: "en",
		contents: [
			Pdf.title("Sprout"),
			Pdf.paragraph("Planning software for small teams that prefer clarity over ceremony."),
			Pdf.figure(
				Scene.drawing({}).image(product_illustration, Layout.rect(0, 0, 400, 170)),
				"A green planning board with three warm progress cards moving toward launch",
				Pdf.caption("A calm workspace for decisions, progress, and launch readiness."),
			),
			Pdf.heading(1, "The problem"),
			Pdf.paragraph("Important decisions disappear across chat, tickets, and meeting notes."),
			Pdf.heading(1, "The approach"),
			Pdf.bullets(["One visible decision log", "Typed ownership", "Exports that remain useful offline"]),
			Pdf.heading(1, "Learn more"),
			Pdf.link("Visit the product site", "https://example.com/sprout"),
		],
	})
	bytes = Pdf.to_bytes_with(document, Pdf.Options.default.with_theme(theme)).map_err(|err| PdfFailed(err))?
	output : Path
	output = "product-brief.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Ok({})
}

product_illustration : Image.Source
product_illustration = {
	width : U64
	width = 40
	height : U64
	height = 17
	var $pixels = List.with_capacity(width * height * 3)
	var $y = 0
	while $y < height {
		var $x = 0
		while $x < width {
			card = $y >= 5 and $y <= 12 and (($x >= 4 and $x <= 12) or ($x >= 15 and $x <= 24) or ($x >= 27 and $x <= 36))
			sprout = ($x >= 31 and $x <= 33 and $y >= 2 and $y <= 5) or ($x >= 29 and $x <= 31 and $y >= 2 and $y <= 3) or ($x >= 33 and $x <= 35 and $y >= 1 and $y <= 2)
			color = if sprout {
				{ red: 25, green: 145, blue: 88 }
			} else if card {
				accent = if $x <= 12 232 else if $x <= 24 248 else 204
				{ red: accent, green: if $x <= 12 238 else 218, blue: if $x <= 24 168 else 186 }
			} else {
				shade = (244 - ($y * 2)).to_u8_wrap()
				{ red: shade, green: (248 - $y).to_u8_wrap(), blue: (240 - $y).to_u8_wrap() }
			}
			$pixels = $pixels.append(color.red).append(color.green).append(color.blue)
			$x = $x + 1
		}
		$y = $y + 1
	}
	Image.Source.rgb8({ alpha: NoAlpha, dimensions: { height: height.to_u32_wrap(), width: width.to_u32_wrap() }, pixels: $pixels, row_stride: width * 3 })
}
