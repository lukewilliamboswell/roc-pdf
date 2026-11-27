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
import weaver.Cli
import weaver.Opt

main! = |args| {
	builder = Cli.weave(
		Bench.common_args(32),
		Opt.u64({ short: "", long: "rasters", help: "Distinct raster sources to cycle through. Zero uses one per figure.", default: Value(1) }),
		|common, workload| { common, workload },
	)
	Bench.run_with!(
		args,
		{
			name: "pdf-graphics-bench",
			description: "Prepare and emit one tagged raster and vector figure per unit, reusing a configurable set of raster sources.",
		},
		builder,
		document,
	)
}

document : U64, U64, U64 -> Document
document = |units, iteration, requested_rasters| {
	raster_count = if (requested_rasters == 0) units else U64.min(requested_rasters, units)
	rasters = raster_sources(raster_count)
	var $blocks = [Pdf.heading(1, "Survey stations")]
	var $index = 0
	while $index < units {
		station = ($index + 1).to_str()
		image = rasters.get($index % raster_count) ?? crash "benchmark raster index out of bounds"
		$blocks = $blocks.append(
			Pdf.figure({
				drawing: station_drawing(image, $index % 9),
				alt: "A false-color survey image next to a bar chart of relative sensor readings.",
				caption: Pdf.caption("Station ${station}. Survey image and sensor readings."),
			}),
		)
		$index = $index + 1
	}
	Pdf.document({
		title: "Sensor survey atlas, run ${iteration.to_str()}",
		language: "en-AU",
		contents: [Pdf.title("Sensor survey atlas"), Pdf.section($blocks)],
	})
}

raster_sources : U64 -> List(Image.Source)
raster_sources = |count| {
	base = sensor_pixels({})
	var $images = List.with_capacity(count)
	var $ordinal = 0
	while $ordinal < count {
		pixels = if ($ordinal == 0) base else stamp_raster(base, $ordinal)
		$images = $images.append(
			Image.Source.rgb8({
				pixels,
				row_stride: 192,
				alpha: NoAlpha,
				dimensions: { width: 64, height: 64 },
			}),
		)
		$ordinal = $ordinal + 1
	}
	$images
}

# Preserve the same texture and dimensions while varying source identity.
stamp_raster : List(U8), U64 -> List(U8)
stamp_raster = |base, ordinal| {
	var $pixels = base
	var $index = 0
	while $index < 8 {
		byte = ($pixels.get($index) ?? crash "benchmark stamp out of bounds").bitwise_xor(ordinal.shr_wrap(($index * 8).to_u8_wrap()).to_u8_wrap())
		$pixels = $pixels.set($index, byte) ?? crash "benchmark stamp out of bounds"
		$index = $index + 1
	}
	$pixels
}

sensor_pixels : {} -> List(U8)
sensor_pixels = |{}| {
	width : U32
	width = 64
	height : U32
	height = 64
	stride = width.to_u64() * 3
	var $pixels = List.with_capacity(stride * height.to_u64())
	var $y = 0
	while $y < height {
		var $x = 0
		while $x < width {
			# Broad color bands with deterministic fine variation model sensor data.
			texture = (($x * 17 + $y * 13) % 9) + (($x * $y) % 7)
			red = (24 + $x * 2 + texture).to_u8_wrap()
			green = (38 + $y * 5 // 2 + texture).to_u8_wrap()
			blue = (68 + ($x // 8 + $y // 8) % 6 * 21 + texture).to_u8_wrap()
			$pixels = $pixels.append(red).append(green).append(blue)
			$x = $x + 1
		}
		$y = $y + 1
	}
	$pixels
}

station_drawing : Image.Source, U64 -> Scene.Drawing
station_drawing = |image, offset| {
	var $chart = Scene.Drawing.empty.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 162, height: 96 }), color: "#EDF4F5" })
	for y in [16, 32, 48, 64, 80] {
		$chart = $chart.rectangle({ bounds: Layout.rect({ x: 8, y, width: 146, height: 1 }), color: "#B4C9CC" })
	}
	var $index = 0
	while $index < 12 {
		x = ($index.to_i64_wrap() * 12) + 10
		height = (18 + (($index * 17 + offset * 11) % 57)).to_i64_wrap()
		$chart = $chart.rectangle({ bounds: Layout.rect({ x, y: 8, width: 8, height }), color: "#316575" })
		$index = $index + 1
	}
	axis = Scene.PathBuilder.start
		.move_to(Layout.point({ x: 8, y: 88 }))
		.line_to(Layout.point({ x: 8, y: 8 }))
		.line_to(Layout.point({ x: 154, y: 8 }))
		.finish()
	$chart = $chart.path({ path: axis, style: Scene.solid_stroke("#244550", 1) })
	Scene.Drawing.empty
		.image({ image, placement: Layout.rect({ x: 0, y: 0, width: 96, height: 96 }) })
		.group({ offset: Layout.point({ x: 112, y: 0 }), drawing: $chart })
}
