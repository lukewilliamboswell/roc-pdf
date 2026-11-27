import pdf.Document
import pdf.Font
import pdf.Pdf
import "fonts/IBMPlexSansHebrew-Regular.ttf" as hebrew_bytes : List(U8)

Invoice :: [].{
	options : {} -> Try(Pdf.Options, [Policy(Font.PolicyError), Registration(Font.ResourceError)])
	options = |_| {
		limits = Font.ValidationLimits.default
		latin = Font.Registry.register_built_in(Font.Registry.empty, limits) ? Registration
		hebrew = latin.registry.register({ bytes: hebrew_bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Hebr")] }, limits }) ? Registration
		selected = hebrew.registry.with_policy([latin.face, hebrew.face]) ? Policy
		Ok(
			Pdf.Options.{
				fonts: Registered(selected.registry),
				theme: {
					international_text: HebrewLatin,
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
		title: "Tax invoice IL-1042",
		language: "en-AU",
		contents: [
			Pdf.title("Tax invoice IL-1042"),
			Pdf.paragraph("Harbour & Finch Pty Ltd"),
			Pdf.heading(1, "Bill to"),
			Pdf.custom_block({
				name: "Billing address",
				size: { width: 164, height: 56 },
				inset: 4,
				contents: [
					Pdf.rich_paragraph([
						Pdf.strong([Pdf.in_language("he", [Pdf.text("נועה לוי רחוב הרצל 24 תל אביב")]), Pdf.text(" (PO-1042)")]),
						Pdf.in_language("he", [Pdf.text(" ישראל")]),
					]),
				],
			}),
			Pdf.heading(1, "Items"),
			Pdf.table({
				caption: Pdf.no_caption,
				columns: [{ width: Share(1), align: Start }, { width: Fixed(95), align: End }],
				header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Service and item reference")]), Pdf.header_cell(Column, [Pdf.text("Total due")])])],
				body_rows: [
					Pdf.row([
						Pdf.cell([Pdf.in_language("he", [Pdf.text("ייעוץ בטיחות")]), Pdf.text(" SKU-42 ILS 1,250.00")]),
						Pdf.cell([Pdf.text("ILS 1,250.00")]),
					]),
				],
			}),
			Pdf.heading(1, "Payment"),
			Pdf.rich_paragraph([Pdf.text("Pay by bank transfer ("), Pdf.in_language("fr", [Pdf.text("virement bancaire, s'il vous plaît")]), Pdf.text(").")]),
		],
	})
}
