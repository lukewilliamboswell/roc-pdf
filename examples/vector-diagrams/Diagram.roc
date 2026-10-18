import PreparedDiagram
import pdf.Document
import pdf.Font
import pdf.Pdf
import pdf.Theme
import "fonts/Inter-Regular.ttf" as font_bytes : List(U8)

## Public-API-only adapter output, shared by the runnable example and evidence.
Diagram :: [].{
	options : U64 -> Try(Pdf.Options, [FontRejected])
	options = |context| {
		registered = Font.Registry.empty.register(font_bytes, { provision: BuiltIn, scripts: ["Latn"] }, if context > 0 Font.ValidationLimits.default else Font.ValidationLimits.make({ max_bytes: 0, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 })) ? |_| FontRejected
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
