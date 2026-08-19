app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pf.Stdout
import pdf.Pdf

main! = |_args| {
	document = Pdf.document({
		title: "Northstar quarterly report",
		language: "en-AU",
		contents: [
			Pdf.title("Northstar / Q2"),
			Pdf.paragraph("A concise operating report generated entirely in Roc."),
			Pdf.heading(1, "Highlights"),
			Pdf.bullets(["Revenue grew 18%", "Retention reached 94%", "Two regions launched"]),
			Pdf.heading(1, "Outlook"),
			Pdf.paragraph("The next quarter focuses on reliability, onboarding, and measured expansion."),
		],
	})
	bytes = Pdf.to_bytes(document).map_err(|err| PdfFailed(err))?
	output : Path
	output = "quarterly-report.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote quarterly-report.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}
