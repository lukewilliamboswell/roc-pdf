app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import pf.Path
import pdf.Document
import pdf.Pdf

main! = |_args| {
	prepared = Pdf.prepare(article, options).map_err(|error| PdfFailed(error))?
	bytes = Pdf.to_bytes_prepared(prepared).map_err(|error| PdfFailed(error))?
	target : Path
	target = "pilot-findings.pdf"
	target.write_bytes!(bytes).map_err(|error| WriteFailed(error))
}

article : Document
article = Pdf.document({
	language: "en-AU",
	title: "Pilot findings",
	contents: [
		Pdf.multi_column({
			first: 206,
			gutter: 16,
			second: 186,
			contents: [
				Pdf.title("Pilot findings"),
				Pdf.paragraph(findings),
			],
		}),
	],
})

options : Pdf.Options
options = {
	page_size: Custom({ width: 456, height: 228 }),
	theme: {
		body: { size: 11, leading: 16 },
		page_margin: { left: 24, right: 24, top: 24, bottom: 24 },
		title: { size: 20, leading: 24 },
	},
}

findings : Str
findings = Str.join_with(
	[
		"The three-week trial tested whether a community shuttle could connect the railway station, the library and the clinic within a single afternoon loop.",
		"Drivers logged each boarding stop and departure time. The team used these counts to match service to demand while keeping individual journey information private.",
		"The library collected the largest share of afternoon boardings. The clinic accounted for most of the return journeys after four o'clock, particularly on the days when appointments finished close together.",
		"Drivers could complete the short route on time when the vehicle left the railway station at the published time. When the connection arrived late, a two-minute hold helped passengers transfer without making the next loop late.",
		"The long route served more neighbourhoods, but missed the connection on several afternoons. Most of the delay came from a junction near the station, where a right turn sometimes required two signal cycles.",
		"The next trial will keep the short route and test two departures per hour. Staff will measure transfer time, missed boardings and the fraction of loops that need the full hold.",
		"The council will compare those outcomes with the existing hourly service before selecting the timetable for summer.",
	],
	" ",
)
