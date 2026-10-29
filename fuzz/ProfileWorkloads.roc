import "../vendor/fonts/Inter-4.1-Regular.ttf" as inter : List(U8)
import pdf.Document
import pdf.Font
import pdf.Pdf

## The documents `allocation_profile` measures. Each workload is split into
## the stages a caller sees (font registration, authoring, preparation and
## emission) so the profile attributes allocations to one of them.
ProfileWorkloads :: [].{
	Workload : [Report, ReportScaled, BuiltInParagraphs, BuiltInParagraphsScaled]

	Setup : { options : Pdf.Options }

	all : List(Workload)
	all = [Report, ReportScaled, BuiltInParagraphs, BuiltInParagraphsScaled]

	select : U64 -> Workload
	select = |index| all.get(index % all.len()) ?? Report

	name : Workload -> Str
	name = |workload| match workload {
		Report => "report"
		ReportScaled => "report_x10"
		BuiltInParagraphs => "builtin_paragraphs"
		BuiltInParagraphsScaled => "builtin_paragraphs_x10"
	}

	## The one-page operations report of the PDF comparison benchmark, set in
	## a caller-registered face like the benchmark's runtime-loaded font.
	fonts : Workload -> Try(Setup, Font.ResourceError)
	fonts = |workload| match workload {
		Report | ReportScaled => {
			registered = Font.Registry.empty.register({ bytes: inter, registration: { provision: BuiltIn, scripts: ["Latn"] }, limits: Font.ValidationLimits.default })?
			Ok({
				options: {
					page_size: Custom({ width: 595, height: 842 }),
					fonts: Registered(registered.registry),
					theme: {
						face: registered.face,
						title: { size: 18, leading: 22 },
						body: { size: 11, leading: 15 },
						page_margin: { top: 50, right: 50, bottom: 50, left: 50 },
						paragraph_spacing: 10,
						furniture: Own({ size: 9, leading: 12 }),
						table: { cell_padding: 5, row_gap: 0, rule: NoRule },
					},
				},
			})
		}

		BuiltInParagraphs | BuiltInParagraphsScaled => Ok({ options: Pdf.Options.default })
	}

	document : Workload, Setup -> Document
	document = |workload, _setup| match workload {
		Report => report(1)
		ReportScaled => report(10)
		BuiltInParagraphs => paragraphs(1)
		BuiltInParagraphsScaled => paragraphs(10)
	}
}

title : Str
title = "Monthly operations report"

body : List(Str)
body = [
	"Harbour Services completed the May reporting period with steady demand across its three service teams. This report summarises completed work, response times and the actions planned for the next month.",
	"The team completed 128 requests and met its response target on 121 of them. Seven requests needed specialist review. All outstanding reviews now have an assigned owner and a planned completion date.",
	"Next month the team will update the intake checklist, review the remaining exceptions and reserve two training sessions for new staff. The service manager will review progress at the next monthly meeting.",
]

rows : List(List(Str))
rows = [["Customer support", "64", "62"], ["Field services", "41", "38"], ["Specialist review", "23", "21"], ["Total", "128", "121"]]

report : U64 -> Document
report = |copies| {
	var $blocks = [Pdf.title(title)]
	var $copy = 0
	while $copy < copies {
		for paragraph in body {
			$blocks = $blocks.append(Pdf.paragraph(paragraph))
		}
		$blocks = $blocks.append(
			Pdf.table({
				caption: Pdf.caption("Completed requests by team"),
				columns: [{ width: Fixed(240), align: Start }, { width: Fixed(120), align: End }, { width: Fixed(135), align: End }],
				header_rows: [Pdf.row(["Service team", "Completed", "Within target"].map(|text| Pdf.header_cell(Column, [Pdf.text(text)])))],
				body_rows: rows.map(|cells| Pdf.row(cells.map(|text| Pdf.cell([Pdf.text(text)])))),
				footer_rows: [],
			}),
		)
		$copy = $copy + 1
	}
	$blocks = $blocks.append(Pdf.paragraph("Trial revision B: updated."))
	footer = Pdf.region({ height: 12, start: [Pdf.furniture_text([Pdf.text("Harbour Services | Internal operations | May 2026")])] })
	Pdf.document({
		title,
		language: "en-AU",
		contents: $blocks,
		page_templates: Templates({ first: Pdf.first_page_template({ footer, gap: 12 }), continuation: Pdf.page_template({ footer, gap: 12 }) }),
	})
}

## Plain paragraphs and headings in the built-in face under default options.
paragraphs : U64 -> Document
paragraphs = |copies| {
	var $blocks = [Pdf.title(title)]
	var $copy = 0
	while $copy < copies {
		$blocks = $blocks.append(Pdf.heading(2, "Section ${($copy + 1).to_str()}"))
		for paragraph in body {
			$blocks = $blocks.append(Pdf.paragraph(paragraph))
		}
		$copy = $copy + 1
	}
	Pdf.document({ title, language: "en-AU", contents: $blocks })
}
