import PreparedDiagram
import pdf.Document
import pdf.Font
import pdf.Pdf
import pdf.Theme
import "fonts/Inter-Regular.ttf" as font_bytes : List(U8)

## Public-API-only adapter output, shared by the runnable example and evidence.
Diagram :: [].{
	options : Font.ValidationLimits -> Try(Pdf.Options, Font.ResourceError)
	options = |limits| {
		registered = Font.Registry.empty.register({ bytes: font_bytes, registration: { provision: BuiltIn, scripts: ["Latn"] }, limits: limits })?
		Ok(Pdf.Options.{ theme: { face: registered.face, page_margin: { top: 24, bottom: 24, left: 24, right: 24 } }, fonts: Registered(registered.registry) })
	}

	document : U64 -> Document
	document = |count| {
		var $contents = List.with_capacity(count)
		var $index = 0
		while $index < count {
			drawing = PreparedDiagram.drawing({})
			$contents = $contents.append(Pdf.figure({ drawing: drawing, alt: "Café: receive an order, check stock or order timber, then dispatch.", caption: Pdf.caption("Order processing") }))
			$index = $index + 1
		}
		Pdf.document({ title: "Prepared vector diagrams", language: "en", contents: $contents })
	}
}

expect {
	limits = Font.ValidationLimits.make({ max_bytes: 0, max_cmap_mappings: 1200000, max_glyphs: 65535, max_tables: 128 })
	match Diagram.options(limits) {
		Err(LimitExceeded({ attempted, dimension: FontBytes, limit: 0 })) => attempted == font_bytes.len()
		_ => False
	}
}
