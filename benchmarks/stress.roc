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
import "../examples/business-report/drying-yard.jpg" as photo : List(U8)

main! = |args| {
	navigation_args = Cli.weave(
		Cli.weave(
			Opt.flag({ short: "", long: "generated-contents", help: "Prepend a table of contents linking to named headings." }),
			Opt.flag({ short: "", long: "flow-references", help: "Add one body reference to the next station's page." }),
			|generated_contents, flow_references| { generated_contents, flow_references },
		),
		Opt.u64({ short: "", long: "index-targets-per-term", help: "Append an index with up to this many consecutive station links per term. Zero omits the index.", default: Value(0) }),
		|{ generated_contents, flow_references }, index_targets| { generated_contents, flow_references, index_targets },
	)
	workload_args = Cli.weave(
		Opt.u64({ short: "", long: "detail-every", help: "Add a table and captioned drawing every N pages. Zero makes a plain-text control.", default: Value(4) }),
		navigation_args,
		|detail_every, { generated_contents, flow_references, index_targets }| { detail_every, generated_contents, flow_references, index_targets },
	)
	builder = Cli.weave(
		Bench.common_args(128),
		workload_args,
		|common, workload| { common, workload },
	)
	Bench.run_with!(
		args,
		{
			name: "pdf-stress-bench",
			description: "Generate a report with one authored unit per page and collect or drain its bytes.",
		},
		builder,
		document,
	)
}

Workload : { detail_every : U64, flow_references : Bool, generated_contents : Bool, index_targets : U64 }

document : U64, U64, Workload -> Document
document = |units, iteration, { detail_every, flow_references, generated_contents, index_targets }| {
	var $contents = if generated_contents {
		[
			Pdf.generated_contents({ depth: 1, leader: Dots, numbering: PageLabel, page_width: 56 }),
			Pdf.page_break,
		]
	} else {
		[]
	}
	var $page = 0
	var $entries = []
	var $destinations = []
	var $first_station = 1
	while $page < units {
		if $page > 0 {
			$contents = $contents.append(Pdf.page_break)
		}
		if detail_every == 0 {
			if generated_contents or flow_references or index_targets > 0 {
				$contents = $contents.append(station_heading(($page + 1).to_str()))
			}
			$contents = $contents.append(Pdf.paragraph("The inspection team checked the drying yard and recorded the equipment readings."))
		} else {
			number = ($page + 1).to_str()
			$contents = $contents.append(station_heading(number))
			$contents = $contents.append(
				Pdf.rich_paragraph([
					Pdf.strong([Pdf.text("Inspection complete. ")]),
					Pdf.text("Compare results with "),
					Pdf.inline_internal_link([Pdf.text("the first station")], "station-1"),
					Pdf.text(" before signing off the maintenance review."),
				]),
			)
			if $page % detail_every == 0 {
				$contents = $contents.append(ledger(number)).append(figure)
			}
		}
		$page = $page + 1
		if flow_references {
			next = if ($page == units) 1 else $page + 1
			$contents = $contents.append(
				Pdf.rich_paragraph([
					Pdf.text("Continue the maintenance review on page "),
					Pdf.flow_page_reference({ destination: "station-${next.to_str()}" }),
					Pdf.text("."),
				]),
			)
		}
		if index_targets > 0 {
			$destinations = $destinations.append("station-${$page.to_str()}")
			if $destinations.len() == index_targets or $page == units {
				$entries = $entries.append({ term: "Stations ${$first_station.to_str()} to ${$page.to_str()}", destinations: $destinations })
				$destinations = []
				$first_station = $page.plus_saturated(1)
			}
		}
	}
	if index_targets > 0 {
		$contents = $contents.append(Pdf.page_break).append(Pdf.index({ entries: $entries, numbering: Physical }))
	}
	Pdf.document({ title: "Drying yard maintenance, run ${iteration.to_str()}", language: "en-AU", contents: $contents })
}

station_heading : Str -> Document.Block
station_heading = |number| Pdf.destination_heading({ name: "station-${number}", level: 1, text: "Station ${number}" })

ledger : Str -> Document.Block
ledger = |number| Pdf.table({
	caption: Pdf.no_caption,
	columns: [{ width: Content, align: Start }, { width: Share(1), align: Start }],
	header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Station")]), Pdf.header_cell(Column, [Pdf.text("Result")])])],
	body_rows: [Pdf.row([Pdf.cell([Pdf.text(number)]), Pdf.cell([Pdf.text("Reviewed")])])],
	footer_rows: [],
	row_split: KeepRows,
})

figure : Document.Block
figure = Pdf.figure({
	drawing: Scene.Drawing.empty
		.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 132, height: 74 }), color: "#EBF0F1" })
		.image({ image: Image.Source.jpeg_srgb(photo, RequireDisplayReady), placement: Layout.rect({ x: 6, y: 5, width: 120, height: 64 }) }),
	alt: "Stacks of boards drying under the yard shelter.",
	caption: Pdf.caption("The drying yard shelter."),
})
