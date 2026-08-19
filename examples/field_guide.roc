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
	coastal = Color.srgb8({ red: 12, green: 103, blue: 103 })
	base_heading = Theme.heading_style(Theme.default)
	theme = Theme.default
		.with_title_color(coastal)
		.with_heading_style({ ..base_heading, color: coastal, size: Layout.Unit.points(18), leading: Layout.Unit.points(22) })
		.with_page_margin({ top: Layout.Unit.points(48), right: Layout.Unit.points(48), bottom: Layout.Unit.points(60), left: Layout.Unit.points(72) })
		.with_paragraph_spacing(Layout.Unit.points(11))
	document = Pdf.document({
		title: "Coastal field guide",
		language: "en-AU",
		contents: [
			Pdf.title("Coastal field guide"),
			Pdf.figure(
				Scene.drawing({}).image(coastal_landscape, Layout.rect(0, 0, 410, 150)),
				"Layered coastal dunes, teal water, a pale sky, and two shorebirds",
				Pdf.caption("Survey habitat: sheltered dunes meeting tidal shallows."),
			),
			Pdf.destination_heading("habitat", 1, "Habitat"),
			Pdf.paragraph("Look for sheltered dunes, heath, and tidal wetlands."),
			Pdf.link("Atlas of Living Australia", "https://www.ala.org.au/"),
			Pdf.destination_heading("survey", 1, "Survey notes"),
			Pdf.paragraph("Record weather, location, and observed behaviour."),
			Pdf.internal_link("Return to habitat", "habitat"),
		],
	}).with_outline([
		{ depth: 0, destination: "habitat", open: True, title: "Habitat" },
		{ depth: 0, destination: "survey", open: True, title: "Survey notes" },
	]).with_page_labels([{ prefix: "FG-", start_number: 1, start_page: 0, style: DecimalArabic }])
	bytes = Pdf.to_bytes_with(document, Pdf.Options.default.with_theme(theme)).map_err(|err| PdfFailed(err))?
	output : Path
	output = "field-guide.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Ok({})
}

coastal_landscape : Image.Source
coastal_landscape = {
	width : U64
	width = 48
	height : U64
	height = 18
	var $pixels = List.with_capacity(width * height * 3)
	var $y = 0
	while $y < height {
		var $x = 0
		while $x < width {
			bird = (($x == 10 or $x == 12) and $y == 5) or (($x == 35 or $x == 37) and $y == 7)
			color = if bird {
				{ red: 40, green: 54, blue: 58 }
			} else if $y < 7 {
				{ red: (196 + $y * 3).to_u8_wrap(), green: (224 + $y * 2).to_u8_wrap(), blue: 230 }
			} else if $y < 12 {
				wave = if ($x + $y) % 9 < 2 24 else 12
				{ red: 24, green: (124 + wave).to_u8_wrap(), blue: (144 + wave).to_u8_wrap() }
			} else {
				dune = if ($x + $y) % 11 < 5 214 else 192
				{ red: dune, green: (dune - 20).to_u8_wrap(), blue: 132 }
			}
			$pixels = $pixels.append(color.red).append(color.green).append(color.blue)
			$x = $x + 1
		}
		$y = $y + 1
	}
	Image.Source.rgb8({ alpha: NoAlpha, dimensions: { height: height.to_u32_wrap(), width: width.to_u32_wrap() }, pixels: $pixels, row_stride: width * 3 })
}
