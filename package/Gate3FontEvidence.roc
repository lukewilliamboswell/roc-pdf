import Font
import KernelEmit
import KernelFont
import KernelFontPlan
import KernelStructure
import Theme
import "../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)
import "../tests/assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)

Gate3FontEvidence :: [].{
	caller_registration : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	caller_registration = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		registered = Font.Registry.empty.register(
			caller_font_bytes,
			{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
			Font.ValidationLimits.default,
		) ? |_| EvidenceFailure
		store = registered.registry.store()
		theme = Theme.with_font(Theme.default, registered.face)
		if theme.body_font().index() != registered.face.index() or
			store.resources.len() != 1 or
				store.faces.len() != 1 or
					store.instances.len() != 1 or
						store.policies.len() != 1 or
							list_at(store.resources, 0).bytes.len() != caller_font_bytes.len() {
			return Err(EvidenceFailure)
		}
		bytes = blank_pdf(runtime_guard)?
		Ok({
			bytes,
			work: [
				registered.work.input_bytes,
				registered.work.retained_input_bytes,
				registered.work.copied_input_bytes,
				registered.work.table_visits,
				registered.work.glyph_visits,
				registered.work.cmap_mapping_visits,
				registered.work.component_edge_visits,
				store.coverage_spans.len(),
				registered.face.index(),
				registered.instance.index(),
				registered.policy.index(),
				store.resources.len(),
				store.faces.len(),
				store.instances.len(),
				store.policies.len(),
				bytes.len(),
			],
		})
	}

	font_inspection : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	font_inspection = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		font = inspect_built_in(runtime_guard)?
		glyph_a = match required_glyph(font, 0x41) {
			Err(_) => return Err(EvidenceFailure)
			Ok(value) => value
		}
		width_a = match KernelFont.advance_width(font, glyph_a) {
			Err(_) => return Err(EvidenceFailure)
			Ok(value) => value
		}
		bytes = blank_pdf(runtime_guard)?
		Ok({
			bytes,
			work: [
				font.bytes.len(),
				font.tables.len(),
				font.metrics.glyph_count,
				font.coverage.len(),
				font.work.checksum_bytes,
				font.work.cmap_mapping_visits,
				font.work.loca_entries,
				font.work.overlap_comparisons,
				font.work.glyph_visits,
				font.work.component_edge_visits,
				glyph_a.to_u64(),
				width_a.to_u64(),
			],
		})
	}

	font_planning : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	font_planning = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		font = inspect_built_in(runtime_guard)?
		glyph_a = match required_glyph(font, 0x41) {
			Err(_) => return Err(EvidenceFailure)
			Ok(value) => value
		}
		glyph_e_acute = match required_glyph(font, 0x00e9) {
			Err(_) => return Err(EvidenceFailure)
			Ok(value) => value
		}
		plan = match KernelFontPlan.plan(
			font,
			[{ glyph: glyph_a }, { glyph: glyph_e_acute }, { glyph: glyph_a }],
			KernelFontPlan.Limits.make({ max_retained_glyphs: 64 }),
		) {
			Err(_) => return Err(EvidenceFailure)
			Ok(value) => value
		}
		subset_a = list_at(plan.original_to_subset, glyph_a.to_u64())
		subset_e_acute = list_at(plan.original_to_subset, glyph_e_acute.to_u64())
		if subset_a == 0xffffffff or subset_e_acute == 0xffffffff {
			return Err(EvidenceFailure)
		}
		bytes = blank_pdf(runtime_guard)?
		Ok({
			bytes,
			work: [
				font.bytes.len(),
				plan.work.usage_visits,
				plan.work.retained_glyphs,
				plan.work.component_index_visits,
				plan.work.component_edge_visits,
				plan.work.glyph_scans,
				plan.entries.len(),
				glyph_a.to_u64(),
				glyph_e_acute.to_u64(),
				subset_a.to_u64(),
				subset_e_acute.to_u64(),
				plan.prefix.fold(0, |sum, byte| sum + byte.to_u64()),
			],
		})
	}
}

inspect_built_in : U64 -> Try(KernelFont.Inspection, [EvidenceFailure, InvalidRuntimeGuard])
inspect_built_in = |runtime_guard| {
	if runtime_guard != 0 {
		return Err(InvalidRuntimeGuard)
	}
	font = KernelFont.inspect(
		built_in_font_bytes,
		KernelFont.Limits.make({
			max_bytes: 200000,
			max_cmap_mappings: 10000,
			max_glyphs: 10000,
			max_tables: 32,
		}),
	) ? |_| EvidenceFailure
	Ok(font)
}

required_glyph : KernelFont.Inspection, U32 -> Try(U32, [EvidenceFailure])
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
		crash "Gate 3 font evidence index escaped"
	}
	Ok(value) => value
}

expect {
	result = Gate3FontEvidence.font_inspection(0)?
	result.work.len() == 12
}

expect {
	result = Gate3FontEvidence.font_planning(0)?
	result.work.len() == 12
}

## Invalid caller bytes fail without returning a usable face or registry.
expect match Font.Registry.empty.register(
	List.repeat(0, 12),
	{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
	Font.ValidationLimits.default,
) {
	Err(UnsupportedFormat(0)) => Bool.True
	_ => Bool.False
}
