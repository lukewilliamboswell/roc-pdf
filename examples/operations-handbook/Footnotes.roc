import pdf.Document
import pdf.Pdf

Footnotes :: [].{
	options : Pdf.Options
	options = { page_size: Custom({ width: 385, height: 265 }), theme: { page_margin: { top: 29, right: 28, bottom: 29, left: 28 } } }

	document : Bool -> Document
	document = |oversized| {
		clock_body = if oversized {
			(Str.from_utf8(List.repeat(120, 1600)) ?? "").replace_each("xxxxx", "word ")
		} else {
			"The response clock starts when the primary on-call receives a usable alert, including the affected service and a symptom that can be checked."
		}
		Pdf.document({
			title: "Payments platform on-call runbook",
			language: "en-AU",
			contents: [
				Pdf.title("Payments platform on-call runbook"),
				Pdf.paragraph("Review the scope of the alert before declaring an incident."),
				Pdf.spacer(72),
				Pdf.heading(1, "Severity levels"),
				Pdf.rich_paragraph([
					Pdf.text("Start the response clock "),
					Pdf.footnote_marker({ id: "response-clock", text: "[1]" }),
					Pdf.text(" before assigning severity. Use affected customer traffic and observed symptoms to choose the severity."),
				]),
				Pdf.page_break,
				Pdf.heading(1, "Escalation"),
				Pdf.rich_paragraph([
					Pdf.text("Escalate when the response clock "),
					Pdf.footnote_marker({ id: "response-clock", text: "[1]" }),
					Pdf.text(" expires. Give the next responder the current scope and the most recent verified signal."),
				]),
				Pdf.footnote_definition({ id: "response-clock", label: "[1]", body: clock_body }),
			],
		})
	}
}
