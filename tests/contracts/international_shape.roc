app [main!] {
	pdf: "../../package/all.roc",
	pf: platform "../platform/main.roc",
}

import pdf.KernelFont
import pdf.KernelInternationalShape
import pdf.KernelInternationalText
import pdf.Semantics
import "../assets/IBMPlexSansHebrew-Rtl-Fixture.ttf" as hebrew_bytes : List(U8)

main! = |_| { bytes: [], work: [] }

inspection = KernelFont.inspect(hebrew_bytes, KernelFont.Limits.make({ max_bytes: 32768, max_cmap_mappings: 512, max_glyphs: 512, max_tables: 128 }))

item : KernelInternationalText.Item
item = {
	direction: RightToLeft,
	language: Language("he"),
	level: 1,
	occurrence: Semantics.OccurrenceId.from_index(2),
	script: "Hebr",
	source: { scalars: range(2, 3), utf8_bytes: range(2, 5) },
}

input : List(KernelInternationalText.ScalarAt)
input = [{ scalar: 0x67, offset: 0 }, { scalar: 0x68, offset: 1 }, { scalar: 0x5d0, offset: 2 }, { scalar: 0x28, offset: 4 }, { scalar: 0x5d1, offset: 5 }]

range : U64, U64 -> Semantics.IndexRange
range = |start, length| Semantics.IndexRange.from_start_and_length({ start, length })

## UAX #9 L4 mirrors the bracket's painted glyph, while the checked
## provider's byte offsets preserve the original opening bracket.
expect {
	font = inspection?
	face = KernelInternationalShape.prepare(font)?
	provider = KernelInternationalShape.program(face, { direction: RightToLeft, language: Language("he"), script: "Hebr" })
	shaped = KernelInternationalShape.shape(provider, item, input, 3)?
	logical = shaped.clusters.map(|cluster| (cluster.glyphs.start(), cluster.source.utf8_bytes.start(), cluster.source.utf8_bytes.length()))
	visual = shaped.glyphs.map(|glyph| Some(glyph.id))
	logical == [(2, 2, 2), (1, 4, 1), (0, 5, 2)] and
		visual == [KernelFont.glyph_for_scalar(font, 0x5d1), KernelFont.glyph_for_scalar(font, 0x29), KernelFont.glyph_for_scalar(font, 0x5d0)]
}

expect {
	font = inspection?
	face = KernelInternationalShape.prepare(font)?
	provider = KernelInternationalShape.program(face, { direction: RightToLeft, language: Language("he"), script: "Hebr" })
	match KernelInternationalShape.shape(provider, item, input, 2) {
		Err(GlyphLimit({ attempted: 3, limit: 2 })) => True
		_ => False
	}
}
