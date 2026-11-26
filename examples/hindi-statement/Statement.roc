import pdf.Document
import pdf.Font
import pdf.Pdf
import "fonts/IBMPlexSansDevanagari-Regular.ttf" as hindi_bytes : List(U8)

Statement :: [].{
	options : {} -> Try(Pdf.Options, [Policy(Font.PolicyError), Registration(Font.ResourceError)])
	options = |_| {
		limits = Font.ValidationLimits.default
		latin = Font.Registry.register_built_in(Font.Registry.empty, limits) ? Registration
		hindi = latin.registry.register({ bytes: hindi_bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Deva")] }, limits }) ? Registration
		selected = hindi.registry.with_policy([latin.face, hindi.face]) ? Policy
		Ok(
			Pdf.Options.{
				fonts: Registered(selected.registry),
				theme: {
					international_text: HindiLatin,
					font_selection: Policy(selected.policy),
					title: { color: "#183454", size: 26, leading: 32 },
					headings: { all: { color: "#183454", size: 13, leading: 18 } },
					inline: { strong: { color: Themed("#183454") } },
					table: {
						header_color: Themed("#FFFFFF"),
						header_fill: Fill("#183454"),
						body_rule: Rule({ color: "#DCE2E9", width: 0.5 }),
						cell_padding: 5,
					},
				},
			},
		)
	}

	document : {} -> Document
	document = |_| Pdf.document({
		title: "Account statement IN-42",
		language: "en-AU",
		contents: [
			Pdf.title("Account statement IN-42"),
			Pdf.heading(1, "Period"),
			Pdf.rich_paragraph([Pdf.in_language("hi", [Pdf.text("वित्तीय विवरण")]), Pdf.text(" FY 2026")]),
			Pdf.heading(1, "Activity"),
			Pdf.table({
				caption: Pdf.no_caption,
				columns: [{ width: Share(1), align: Start }, { width: Fixed(95), align: End }],
				header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Description")]), Pdf.header_cell(Column, [Pdf.text("Balance")])])],
				body_rows: [
					Pdf.row([
						Pdf.cell([Pdf.in_language("hi", [Pdf.text("प्रशिक्षण शुल्क")]), Pdf.text(" IN-42")]),
						Pdf.cell([Pdf.text("INR 8,400.00")]),
					]),
				],
			}),
			Pdf.heading(1, "Payment"),
			Pdf.rich_paragraph([Pdf.in_language("hi", [Pdf.text("कृपया भुगतान करें")]), Pdf.text(" by 30 November.")]),
		],
	})
}
