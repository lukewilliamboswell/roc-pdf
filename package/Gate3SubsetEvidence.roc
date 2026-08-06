import KernelEmit
import KernelFont
import KernelFontPlan
import KernelFontSubset
import KernelStructure
import "../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)

Gate3SubsetEvidence :: [].{
	font_subset : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	font_subset = |runtime_guard| {
		sample = sample_subset(runtime_guard)?
		bytes = blank_pdf(runtime_guard)?
		Ok({
			bytes,
			work: [
				sample.font.bytes.len(),
				sample.plan.work.usage_visits,
				sample.plan.entries.len(),
				sample.subset.work.entry_visits,
				sample.subset.work.source_glyph_bytes,
				sample.subset.work.component_rewrites,
				sample.subset.work.glyf_bytes,
				sample.subset.work.hmtx_bytes,
				sample.subset.work.loca_bytes,
				sample.subset.work.cmap_mappings,
				sample.subset.work.tables,
				sample.subset.work.output_bytes,
				bytes.len(),
			],
		})
	}

	font_program : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	font_program = |runtime_guard| {
		sample = sample_subset(runtime_guard)?
		Ok({
			bytes: sample.subset.bytes,
			work: [
				sample.font.bytes.len(),
				sample.plan.entries.len(),
				sample.subset.bytes.len(),
			],
		})
	}
}

sample_subset : U64 -> Try({ font : KernelFont.Inspection, plan : KernelFontPlan.Plan, subset : KernelFontSubset.Subset }, [EvidenceFailure, InvalidRuntimeGuard])
sample_subset = |runtime_guard| {
	if runtime_guard != 0 {
		return Err(InvalidRuntimeGuard)
	}
	font = KernelFont.inspect(
		built_in_font_bytes,
		KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
	) ? |_| EvidenceFailure
	glyph_a = required_glyph(font, 0x41)?
	glyph_e_acute = required_glyph(font, 0x00e9)?
	plan = KernelFontPlan.plan(
		font,
		[{ glyph: glyph_a }, { glyph: glyph_e_acute }, { glyph: glyph_a }],
		KernelFontPlan.Limits.make({ max_retained_glyphs: 64 }),
	) ? |_| EvidenceFailure
	subset = KernelFontSubset.build(font, plan) ? |_| EvidenceFailure
	Ok({ font, plan, subset })
}

required_glyph : KernelFont.Inspection, U32 -> Try(U32, [EvidenceFailure, InvalidRuntimeGuard])
required_glyph = |font, scalar| match KernelFont.glyph_for_scalar(font, scalar) {
	None => Err(EvidenceFailure)
	Some(glyph) => Ok(glyph)
}

blank_pdf : U64 -> Try(List(U8), [EvidenceFailure, InvalidRuntimeGuard])
blank_pdf = |runtime_guard| {
	if runtime_guard != 0 {
		return Err(InvalidRuntimeGuard)
	}
	plan = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(plan) ? |_| EvidenceFailure
	Ok(bytes)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "Gate 3 subset evidence index escaped"
	}
	Ok(value) => value
}

expect {
	result = Gate3SubsetEvidence.font_program(0)?
	result.bytes.len() == list_at(result.work, 2)
}
