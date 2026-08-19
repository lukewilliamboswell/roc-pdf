app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pf.Stdout
import pdf.Color
import pdf.Image
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme

main! = |_args| {
	navy = Color.srgb8({ red: 20, green: 48, blue: 82 })
	base_title = Theme.title_style(Theme.default)
	base_body = Theme.body_style(Theme.default)
	theme = Theme.default
		.with_title_style({ ..base_title, color: navy, size: Layout.Unit.points(30), leading: Layout.Unit.points(34) })
		.with_heading_color(navy)
		.with_body_style({ ..base_body, size: Layout.Unit.points(10), leading: Layout.Unit.points(15) })
		.with_page_margin({ top: Layout.Unit.points(45), right: Layout.Unit.points(45), bottom: Layout.Unit.points(45), left: Layout.Unit.points(45) })
		.with_paragraph_spacing(Layout.Unit.points(6))
	document = Pdf.document({
		title: "Northstar quarterly report",
		language: "en-AU",
		contents: [
			Pdf.title("Northstar / Q2"),
			Pdf.paragraph("A concise operating report generated entirely in Roc."),
			Pdf.figure(
				Scene.drawing({}).image(quarter_chart, Layout.rect(0, 0, 400, 130)),
				"A navy quarterly bar chart rising from 62 to 94 percent across four periods",
				Pdf.caption("Retention trend — four consecutive quarters of improvement."),
			),
			Pdf.heading(1, "Highlights"),
			Pdf.bullets(["Revenue grew 18%", "Retention reached 94%", "Two regions launched"]),
			Pdf.heading(1, "Outlook"),
			Pdf.paragraph("The next quarter focuses on reliability, onboarding, and measured expansion."),
		],
	})
	bytes = Pdf.to_bytes_with(document, Pdf.Options.default.with_theme(theme)).map_err(|err| PdfFailed(err))?
	output : Path
	output = "quarterly-report.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote quarterly-report.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

quarter_chart : Image.Source
quarter_chart = {
	width : U64
	width = 48
	height : U64
	height = 16
	var $pixels = List.with_capacity(width * height * 3)
	var $y = 0
	while $y < height {
		var $x = 0
		while $x < width {
			bar = if $x >= 5 and $x <= 11 8 else if $x >= 15 and $x <= 21 10 else if $x >= 25 and $x <= 31 12 else if $x >= 35 and $x <= 41 14 else 0
			filled = bar > 0 and $y >= height - bar
			grid = $y == 4 or $y == 8 or $y == 12
			color = if filled { red: 28, green: 86, blue: 132 } else if grid { red: 207, green: 218, blue: 228 } else { red: 244, green: 247, blue: 250 }
			$pixels = $pixels.append(color.red).append(color.green).append(color.blue)
			$x = $x + 1
		}
		$y = $y + 1
	}
	Image.Source.rgb8({ alpha: NoAlpha, dimensions: { height: height.to_u32_wrap(), width: width.to_u32_wrap() }, pixels: $pixels, row_stride: width * 3 })
}
