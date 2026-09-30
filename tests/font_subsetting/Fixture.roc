import pdf.KernelEmit
import pdf.KernelFont
import pdf.KernelFontPlan
import pdf.KernelFontSubset
import pdf.KernelStructure
import "../../package/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)
import "../assets/CallerFont-Unhinted.ttf" as unhinted_font_bytes : List(U8)

Fixture :: [].{
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
		crash "text-layout subset evidence index escaped"
	}
	Ok(value) => value
}

expect {
	result = Fixture.font_program(0)?
	result.bytes.len() == list_at(result.work, 2)
}

## Subset a font with the given scalars and inspect the subset it writes.
subset_and_reinspect : List(U8), List(U32) -> Try({ subset : KernelFontSubset.Subset, tags : List(U32) }, [EvidenceFailure])
subset_and_reinspect = |bytes, scalars| {
	limits = KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })
	font = KernelFont.inspect(bytes, limits) ? |_| EvidenceFailure
	var $usage = []
	for scalar in scalars {
		glyph = match KernelFont.glyph_for_scalar(font, scalar) {
			None => return Err(EvidenceFailure)
			Some(value) => value
		}
		$usage = $usage.append({ glyph: glyph })
	}
	plan = KernelFontPlan.plan(font, $usage, KernelFontPlan.Limits.make({ max_retained_glyphs: 64 })) ? |_| EvidenceFailure
	subset = KernelFontSubset.build(font, plan) ? |_| EvidenceFailure
	reinspected = KernelFont.inspect(subset.bytes, limits) ? |_| EvidenceFailure
	Ok({ subset, tags: reinspected.tables.map(|table| table.tag) })
}

## An unhinted source (no cvt, fpgm, gasp, or prep table) subsets to the
## ten required tables, and the subset is itself a valid TrueType font.
expect {
	result = subset_and_reinspect(unhinted_font_bytes, [0x43, 0x61, 0xe9])?
	hinting = [0x63767420, 0x6670676d, 0x67617370, 0x70726570]
	result.subset.work.tables == 10 and result.tags.len() == 10 and !result.tags.any(|tag| hinting.contains(tag))
}

## A hinted source keeps all four hinting tables: fourteen tables.
expect {
	result = subset_and_reinspect(built_in_font_bytes, [0x41, 0xe9])?
	hinting = [0x63767420, 0x6670676d, 0x67617370, 0x70726570]
	result.subset.work.tables == 14 and hinting.all(|tag| result.tags.contains(tag))
}
