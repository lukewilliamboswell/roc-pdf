import pdf.Document
import pdf.Pdf

Pilot :: [].{
	document : U64 -> Document
	document = |copies| compose(List.repeat(Pdf.paragraph(findings), copies))

	kept : {} -> Document
	kept = |_| compose([Pdf.keep_together([Pdf.paragraph(findings)])])

	compose : List(Document.Block) -> Document
	compose = |paragraphs| Pdf.document({
		language: "en-AU",
		title: "Pilot findings",
		contents: [
			Pdf.multi_column({
				first: 206,
				gutter: 16,
				second: 186,
				contents: List.concat([Pdf.title("Pilot findings")], paragraphs),
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
}
