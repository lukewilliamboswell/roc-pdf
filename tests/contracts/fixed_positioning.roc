app [main!] {
	pdf: "../../package/all.roc",
	pf: platform "../platform/main.roc",
}

import pdf.Document
import pdf.KernelBuiltInFont
import pdf.KernelFacadeFixed
import pdf.KernelFacadeLines
import pdf.KernelFacadeSemantics
import pdf.KernelFacadeShape
import pdf.KernelFacadeSources
import pdf.KernelFacadeText
import pdf.KernelFont
import pdf.KernelLineLayout
import pdf.KernelSemantics
import pdf.KernelShape
import pdf.KernelTextSemantics
import pdf.Layout
import pdf.Pdf
import pdf.Theme

fixed_limits : Document.FixedLimits
fixed_limits = { max_pages: 20, max_placements: 40, max_rectangles: 32 }

lines_limits = KernelFacadeLines.Limits.make({
	line: KernelLineLayout.BatchLimits.make({
		line: KernelLineLayout.Limits.make({ max_boundaries: 1024, max_candidates: 4096, max_clusters: 4096, max_glyph_indices: 4096, max_glyphs: 4096, max_lines: 256 }),
		max_key_probes: 1024,
		max_lines: 256,
		max_runs: 128,
		max_table_slots: 128,
		max_templates: 128,
	}),
	max_blocks: 40,
	max_runs: 128,
})

page = |first_height, first_width| {
	Pdf.fixed_page({ height: 500, width: 350 })
		.place({ block: Pdf.paragraph("First in semantic order."), frame: Layout.rect({ x: 10, y: 200, width: first_width, height: first_height }) })
		.place({ block: Pdf.rich_paragraph([Pdf.text("Alpha "), Pdf.in_language("en", [Pdf.text("beta")]), Pdf.line_break, Pdf.text("Gamma delta epsilon zeta eta theta.")]), frame: Layout.rect({ x: 180, y: 300, width: 92, height: 150 }) })
		.with_paint_order([1, 0])
		.finish()
}

position = |pages| {
	doc = Pdf.fixed_document({ pages, title: "Fixed smoke", language: "en" })
	fixed = match Document.normalize_fixed(doc, fixed_limits) {
		Ok(Fixed(value)) => value
		other => crash Str.inspect(other)
	}
	view = fixed.view()
	authoring = view.authoring
	font = KernelFont.inspect(KernelBuiltInFont.bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 100000, max_glyphs: 10000, max_tables: 32 })) ? |_| Font
	semantic = KernelFacadeSemantics.Plan.build(authoring, semantic_limits) ? Semantic
	sources = KernelFacadeSources.Plan.sources(KernelFacadeSemantics.Plan.sources(semantic))
	shape = KernelFacadeShape.Plan.build(authoring, KernelFacadeSemantics.Plan.block_ownership(semantic), KernelFacadeSemantics.Plan.flow_text(semantic), sources, font, Theme.default, KernelFacadeShape.Limits.make({ max_requests: 128, shape: KernelShape.Limits.make({ max_clusters: 4096, max_glyphs: 4096, max_scalars: 4096, max_source_bytes: 4096 }) })) ? Shape
	lines = KernelFacadeLines.Plan.build_fixed(authoring, shape, sources, view.frames, lines_limits) ? Lines
	KernelFacadeFixed.position(fixed, shape, lines, { max_pieces: 256 }).map_err(|error| Position(error))
}

# One rich block uses multiple style/occurrence runs and explicit break
# segments. Its pieces stay on its frame, precede the first-authored block in
# paint order, and lower into the regular text store.
expect {
	result = position([page(40, 160)])?
	pieces = result.positioned.pieces
	text = KernelFacadeText.Plan.build_positioned(result.positioned, [], { decorations: [], figure_scales: [], panels: [] }, KernelFacadeText.Limits.make({ max_clusters: 4096, max_glyph_indices: 4096, max_glyphs: 4096, max_pages: 20, max_placements: 128, max_runs: 128 }))?
	rendered_runs = KernelFacadeText.Plan.text(text).runs
	pieces.len() == 5
		and pieces.sublist({ start: 0, len: pieces.len() - 1 }).all(|piece| piece.origin.x.raw() == 180000)
		and (pieces.last()?).origin.x.raw() == 10000
		and rendered_runs.len() > pieces.len()
}

# A width failure is located before positioning. A height failure is
# located against the complete nominal line boxes in the selected frame.
expect {
	width = match position([page(40, 2)]) {
		Err(Lines(FixedUnbreakable({ block: 0, available }))) => available.raw() == 2000
		_ => False
	}
	height = match position([page(1, 160)]) {
		Err(Position(LineBoxesTooTall({ page: 0, placement: 0, actual, maximum: 1000 }))) => actual > 1000
		_ => False
	}
	width and height
}

# Reusing the same authored sheet still creates independent placements on each
# page. Verify exact placement, line, physical-run and piece work for the
# small and large paths.
expect {
	sheet = page(40, 160)
	small = (position(List.repeat(sheet, 2))?).work
	large = (position(List.repeat(sheet, 20))?).work
	small == { placements: 4, line_visits: 10, run_visits: 24, piece_writes: 10 }
		and large == { placements: 40, line_visits: 100, run_visits: 240, piece_writes: 100 }
}

main! = |_| { bytes: [], work: [] }

semantic_limits : KernelFacadeSemantics.Limits
semantic_limits = KernelFacadeSemantics.Limits.make({
	max_container_depth: 16,
	max_content_spine: 8192,
	max_inline_depth: 8,
	max_nodes: 4096,
	max_occurrences: 2048,
	max_properties: 2048,
	max_source_inputs: 2048,
	semantics: KernelSemantics.Limits.make({ max_attributes: 8192, max_content_spine: 8192, max_fragments: 0, max_namespaces: 2, max_nodes: 4096, max_occurrences: 2048, max_semantic_depth: 32 }),
	sources: KernelFacadeSources.Limits.make({
		max_hash_probes: 1000000,
		max_inputs: 2048,
		max_source_bytes: 1000000,
		max_source_scalars: 1000000,
		max_table_slots: 8192,
		max_unique_sources: 2048,
		unicode: { max_graphemes: 1000000, max_line_boundaries: 1000001, max_scalars: 1000000, max_script_runs: 2048 },
	}),
	text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 2048, max_text_property_bytes: 1000000, max_text_source_bytes: 1000000, max_text_source_scalars: 1000000, max_text_sources: 2048 }),
})
