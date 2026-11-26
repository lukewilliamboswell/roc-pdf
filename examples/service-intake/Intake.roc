import pdf.Document
import pdf.Layout
import pdf.Pdf

Intake :: [].{
	document : Bool -> Document
	document = |duplicate| {
		page = Pdf.fixed_page({ width: 595, height: 842 })
			.place({ block: Pdf.title("Service intake"), frame: Layout.rect({ x: 56, y: 732, width: 480, height: 44 }) })
			.place({ block: Pdf.paragraph("Enter your name and confirm the service reference. Use Tab to move between fields."), frame: Layout.rect({ x: 56, y: 679, width: 480, height: 46 }) })
			.place_text_field({ field: { id: "contact_name", label: "Contact name", width: 300 }, origin: { x: 56, y: 614 } })
			.place_text_field({ field: { id: if (duplicate) "contact_name" else "service_reference", label: "Service reference", width: 180, value: Prefilled("HF-2041") }, origin: { x: 56, y: 550 } })
			.finish()
		Pdf.fixed_document({ pages: [page], language: "en-AU", title: "Service intake" })
	}

	mixed_document : Bool -> Document
	mixed_document = |duplicate| {
		page = Pdf.fixed_page({ width: 595, height: 842 })
			.place({ block: Pdf.title("Service intake"), frame: Layout.rect({ x: 56, y: 732, width: 480, height: 44 }) })
			.place({ block: Pdf.paragraph("Enter your name, confirm the service reference, and select the services you need. Use Tab to move between fields."), frame: Layout.rect({ x: 56, y: 679, width: 480, height: 46 }) })
			.place_text_field({ field: { id: "contact_name", label: "Contact name", width: 300 }, origin: { x: 56, y: 614 } })
			.place_checkbox({ field: { id: "inspection_report", label: "Include an inspection report", state: Checked }, origin: { x: 56, y: 570 } })
			.place_text_field({ field: { id: "service_reference", label: "Service reference", width: 180, value: Prefilled("HF-2041") }, origin: { x: 56, y: 500 } })
			.place_checkbox({ field: { id: if (duplicate) "contact_name" else "site_visit", label: "Request a site visit" }, origin: { x: 56, y: 456 } })
			.finish()
		Pdf.fixed_document({ pages: [page], language: "en-AU", title: "Service intake" })
	}

}
