app [main!] {
	pdf: "../../package/all.roc",
	pf: platform "../platform/main.roc",
}

import pdf.Font
import pdf.KernelBidiBoundary
import pdf.KernelFont
import pdf.KernelInternationalLine
import pdf.KernelInternationalSelection
import pdf.KernelInternationalShape
import pdf.KernelInternationalText
import pdf.KernelUnicode
import pdf.Layout
import pdf.Semantics
import pdf.RocFont
import pdf.Text
import "../assets/IBMPlexSansHebrew-Rtl-Fixture.ttf" as hebrew_bytes : List(U8)
import "../../examples/bilingual-invoice/fonts/IBMPlexSansHebrew-Regular.ttf" as invoice_hebrew : List(U8)

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

## L1/L2, UAX #9 revision 52. A two-piece line paints its Latin run at
## x=0, but logical piece 0 is still the author's Hebrew occurrence.
## A line ending before Latin resolves independently.
expect {
	source = "אב AV"
	analysis = KernelUnicode.analyze(source, KernelUnicode.default_limits)?
	limits = KernelBidiBoundary.Limits.make({ max_clusters: 5, max_scalars: 5, max_visual_order: 5 })
	paragraph = KernelBidiBoundary.analyze_paragraph(source, analysis, Auto, limits)?
	store : Text.Store
	store = {
		clusters: [
			cluster(0, 0, 2),
			cluster(1, 2, 2),
			cluster(2, 4, 1),
			cluster(3, 5, 1),
			cluster(4, 6, 1),
		],
		glyphs: [3, 5, 7, 4, 6].map_with_index(
			|advance, index| {
				id: Text.GlyphId.from_raw(index.to_u32_wrap() + 1),
				advance_x: Layout.Unit.from_raw(advance),
				advance_y: 0,
				offset_x: 0,
				offset_y: 0,
			},
		),
		glyph_indices: [2, 1, 0, 3, 4],
		runs: [
			positioned_run(0, RightToLeft, "Hebr", 0, 3, range(0, 5)),
			positioned_run(1, LeftToRight, "Latn", 3, 2, range(5, 2)),
		],
		substitutions: [],
		transformations: [],
	}
	owners = KernelInternationalLine.cluster_owners(store)?
	full = KernelInternationalLine.position(paragraph, store, owners, { advance: Layout.Unit.from_raw(25), clusters: range(0, 5), source: { scalars: range(0, 5), utf8_bytes: range(0, 7) } }, limits)?
	wrapped = KernelInternationalLine.position(paragraph, store, owners, { advance: Layout.Unit.from_raw(15), clusters: range(0, 3), source: { scalars: range(0, 3), utf8_bytes: range(0, 5) } }, limits)?
	full.pieces.map(|piece| (piece.run.index(), piece.origin.raw())) == [(0, 10), (1, 0)] and
		wrapped.pieces.map(|piece| (piece.run.index(), piece.origin.raw())) == [(0, 0)] and full.work.glyphs == 5 and wrapped.work.glyphs == 3
}

cluster : U64, U64, U64 -> Text.Cluster
cluster = |index, byte_start, byte_length| {
	glyphs: range(index, 1),
	kind: OneToOne,
	source: { scalars: range(index, 1), utf8_bytes: range(byte_start, byte_length) },
}

positioned_run : U64, Text.Direction, Str, U64, U64, Semantics.IndexRange -> Text.Run
positioned_run = |index, direction, script, start, length, bytes| {
	actual_text: FromOccurrence,
	clusters: range(start, length),
	direction,
	glyphs: range(start, length),
	id: Text.RunId.from_index(index),
	instance: Font.InstanceId.from_index(0),
	language: Language(if (direction == RightToLeft) "he" else "en"),
	script: Font.Script.from_iso15924(script),
	size: 11,
	source: { scalars: range(start, length), utf8_bytes: bytes },
	substitutions: range(0, 0),
	transformations: range(0, 0),
	unicode: OccurrenceText(Semantics.OccurrenceId.from_index(index)),
	writing_mode: Horizontal,
}

expect {
	limits = Font.ValidationLimits.default
	registered = Font.Registry.empty.register({ bytes: invoice_hebrew, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Hebr")] }, limits })?
	demo = RocFont.register(registered.registry, limits)?
	combined = demo.registry.with_policy([demo.body, registered.face])?
	policy = KernelInternationalSelection.policy(combined.registry, combined.policy)?
	source = "אב AV"
	analysis = KernelUnicode.analyze(source, KernelUnicode.default_limits)?
	owners : List(KernelInternationalText.Occurrence)
	owners = [
		{ id: Semantics.OccurrenceId.from_index(0), language: Language("he"), source: { scalars: range(0, 3), utf8_bytes: range(0, 5) } },
		{ id: Semantics.OccurrenceId.from_index(1), language: Language("en"), source: { scalars: range(3, 2), utf8_bytes: range(5, 2) } },
	]
	analyzed = KernelInternationalText.plan(source, analysis, Auto, owners, UnpointedHebrewLatin, { max_clusters: 5, max_items: 8, max_scalars: 5 })?
	selected = KernelInternationalSelection.select(policy, Semantics.TextSourceId.from_index(0), Language("en"), analyzed)?
	selection = selected.selected.map(|entry| (entry.face, entry.item.level, entry.item.source.scalars.start(), entry.item.source.scalars.length()))
	latin_only = combined.registry.with_policy([demo.body])?
	uncovered = KernelInternationalSelection.policy(latin_only.registry, latin_only.policy)?
	missing = match KernelInternationalSelection.select(uncovered, Semantics.TextSourceId.from_index(0), Language("en"), analyzed) {
		Err(NoCoverage({ scalar: 0x5d0, scalar_index: 0 })) => True
		_ => False
	}
	missing and selected.work.graphemes == 5 and selection == [(1, 1, 0, 2), (0, 1, 2, 1), (0, 2, 3, 2)]
}

## HarfBuzz 14.6.0 with the exact gallery IBM Plex Sans Hebrew bytes,
## script Hebr, language he, RTL, default features. The vendor's UTF-8
## offsets are relative to the buffer; the adapter keeps the paragraph's
## nonzero origin. The last painted glyph carries a positioned offset.
expect {
	font = KernelFont.inspect(invoice_hebrew, KernelFont.Limits.make({ max_bytes: 100000, max_cmap_mappings: 2000, max_glyphs: 2000, max_tables: 128 }))?
	face = KernelInternationalShape.prepare(font)?
	provider = KernelInternationalShape.program(face, { direction: RightToLeft, language: Language("he"), script: "Hebr" })
	scalars : List(KernelInternationalText.ScalarAt)
	scalars = [
		{ scalar: 0x41, offset: 0 },
		{ scalar: 0x20, offset: 1 },
		{ scalar: 0x5e8, offset: 2 },
		{ scalar: 0x5d7, offset: 4 },
		{ scalar: 0x5d5, offset: 6 },
		{ scalar: 0x5d1, offset: 8 },
	]
	street = { ..item, source: { scalars: range(2, 4), utf8_bytes: range(2, 8) } }
	shaped = KernelInternationalShape.shape(provider, street, scalars, 4)?
	glyphs = shaped.glyphs.map(|glyph| (glyph.id, glyph.advance.x, glyph.advance.y, glyph.offset.x, glyph.offset.y))
	boundaries = shaped.clusters.map(|entry| (entry.glyphs.start(), entry.source.scalars.start(), entry.source.utf8_bytes.start()))
	glyphs == [(285, 552, 0, 0, 0), (289, 260, 0, 0, 0), (291, 647, 0, 0, 0), (308, 496, 0, -30, 0)] and boundaries == [(3, 2, 2), (2, 3, 4), (1, 4, 6), (0, 5, 8)]
}
