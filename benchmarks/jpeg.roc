app [main!] {
	pdf: "../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.11.0/7CdYzjBAJmprmnK45oTpmH6BXt76ZASN2Ck5uZQEoWsK.tar.zst",
}

import Bench
import pdf.Document
import pdf.Image
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import "../examples/business-report/drying-yard.jpg" as photo : List(U8)

main! = |args| Bench.run!(
	args,
	{
		name: "pdf-jpeg-bench",
		description: "Prepare and emit one tagged figure per unit, all sharing an encoded JPEG.",
		default_units: 32,
	},
	document,
)

document : U64, U64 -> Document
document = |units, iteration| {
	image = Image.Source.jpeg_srgb(photo, RequireDisplayReady)
	drawing = Scene.Drawing.empty.image({ image, placement: Layout.rect({ x: 0, y: 0, width: 240, height: 130 }) })
	var $blocks = [Pdf.title("Drying yard field guide")]
	var $index = 0
	while $index < units {
		$blocks = $blocks.append(
			Pdf.figure({
				drawing,
				alt: "Stacks of boards drying under a roof.",
				caption: Pdf.caption("Station ${($index + 1).to_str()}. Reference photograph."),
			}),
		)
		$index = $index + 1
	}
	Pdf.document({ title: "Drying yard inspection, run ${iteration.to_str()}", language: "en-AU", contents: $blocks })
}
