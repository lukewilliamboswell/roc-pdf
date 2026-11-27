import pdf.Document
import pdf.Font
import pdf.Pdf
import "fonts/IBMPlexSansArabic-Regular.ttf" as arabic_bytes : List(U8)

Invoice :: [].{
	options : {} -> Try(Pdf.Options, [Policy(Font.PolicyError), Registration(Font.ResourceError)])
	options = |_| {
		limits = Font.ValidationLimits.default
		latin = Font.Registry.register_built_in(Font.Registry.empty, limits) ? Registration
		arabic = latin.registry.register({ bytes: arabic_bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Arab")] }, limits }) ? Registration
		selected = arabic.registry.with_policy([latin.face, arabic.face]) ? Policy
		Ok(
			Pdf.Options.{
				fonts: Registered(selected.registry),
				theme: {
					international_text: ArabicLatin,
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
		title: "Supplier invoice AE-118",
		language: "en-AU",
		contents: [
			Pdf.title("Supplier invoice AE-118"),
			Pdf.heading(1, "Supplier"),
			Pdf.rich_paragraph([Pdf.in_language("ar", [Pdf.text("شركة السلام")]), Pdf.text(" AE-118")]),
			Pdf.heading(1, "Items"),
			Pdf.table({
				caption: Pdf.no_caption,
				columns: [{ width: Share(1), align: Start }, { width: Fixed(95), align: End }],
				header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Description")]), Pdf.header_cell(Column, [Pdf.text("Total due")])])],
				body_rows: [
					Pdf.row([
						Pdf.cell([Pdf.in_language("ar", [Pdf.text("خدمات النقل")]), Pdf.text(" TR-17")]),
						Pdf.cell([Pdf.text("AED 2,400.00")]),
					]),
				],
			}),
			Pdf.heading(1, "Payment"),
			Pdf.rich_paragraph([Pdf.in_language("ar", [Pdf.text("المبلغ المستحق")]), Pdf.text(" AED 2,400.00")]),
		],
	})
}
