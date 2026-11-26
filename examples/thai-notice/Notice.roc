import pdf.Document
import pdf.Font
import pdf.Pdf
import "fonts/IBMPlexSansThaiLooped-Regular.ttf" as thai_bytes : List(U8)

Notice :: [].{
	options : {} -> Try(Pdf.Options, [Policy(Font.PolicyError), Registration(Font.ResourceError)])
	options = |_| {
		limits = Font.ValidationLimits.default
		latin = Font.Registry.register_built_in(Font.Registry.empty, limits) ? Registration
		thai = latin.registry.register({ bytes: thai_bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Thai")] }, limits }) ? Registration
		selected = thai.registry.with_policy([latin.face, thai.face]) ? Policy
		Ok(
			Pdf.Options.{
				fonts: Registered(selected.registry),
				theme: {
					international_text: ThaiLatin({ revision: "notice-v1", words: ["กรุณา", "ชำระ", "เงิน", "ภายใน", "วันนี้"] }),
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
		title: "Payment notice TH-2026",
		language: "en-AU",
		contents: [
			Pdf.title("Payment notice TH-2026"),
			Pdf.heading(1, "Due today"),
			Pdf.custom_block({
				name: "Thai payment notice",
				size: { width: 88, height: 56 },
				inset: 4,
				contents: [Pdf.rich_paragraph([Pdf.in_language("th", [Pdf.text("กรุณาชำระเงินภายในวันนี้")])])],
			}),
			Pdf.paragraph("Quote TH-2026 with your payment."),
		],
	})
}
