import pdf.Font
import pdf.KernelEmit
import pdf.KernelFont
import pdf.KernelFontPlan
import pdf.KernelStructure
import pdf.Semantics
import pdf.Theme
import "../../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)
import "../assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)
import "../assets/NotoSansSC-CJK-Fixture.ttf" as cjk_font_bytes : List(U8)

Fixture :: [].{
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
							list_at(store.resources, 0).bytes.len() != caller_font_bytes.len() or
								list_at(store.faces, 0).postscript_name.len() != 25 {
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

	## The selection boundary receives already-segmented grapheme scalar facts;
	## it checks each candidate face's retained cmap spans once and returns
	## exact dense instance ranges. The fixture intentionally uses a caller
	## Latin face followed by a test-only CJK face so the middle cluster proves
	## an ordered second-face selection while the surrounding clusters reuse the
	## first inspection and source allocation.
	multi_face_planning : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	multi_face_planning = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		caller = Font.Registry.empty.register(
			caller_font_bytes,
			{ provision: AdvancedRunsRequired, scripts: [Font.Script.from_iso15924("Latn")] },
			Font.ValidationLimits.default,
		) ? |_| EvidenceFailure
		cjk = caller.registry.register(
			cjk_font_bytes,
			{ provision: AdvancedRunsRequired, scripts: [Font.Script.from_iso15924("Hani")] },
			Font.ValidationLimits.default,
		) ? |_| EvidenceFailure
		configured = cjk.registry.with_policy([caller.face, cjk.face]) ? |_| EvidenceFailure
		if configured.registry.store().policies.len() != 3 {
			return Err(EvidenceFailure)
		}
		request = plan_request(configured.policy, [cluster(0, "Latn", [0x43]), cluster(1, "Hani", [0x4e2d]), cluster(2, "Latn", [0x00e9])])
		plan = match configured.registry.plan(request) {
			Complete(value) => value
			Rejected(_) => return Err(EvidenceFailure)
		}
		if plan.face_ranges.len() != 3 or
			list_at(plan.face_ranges, 0).instance.index() != caller.instance.index() or
				list_at(plan.face_ranges, 1).instance.index() != cjk.instance.index() or
					list_at(plan.face_ranges, 2).instance.index() != caller.instance.index() {
			return Err(EvidenceFailure)
		}
		uncovered = match configured.registry.plan(plan_request(configured.policy, [cluster(0, "Latn", [0x10ffff])])) {
			Rejected([MissingCoverage({ cluster: 0, .. })]) => True
			_ => False
		}
		mismatched_script = match configured.registry.plan(plan_request(configured.policy, [cluster(0, "Hani", [0x43])])) {
			Rejected([MissingCoverage({ cluster: 0, .. })]) => True
			_ => False
		}
		ambiguous = match cjk.registry.with_policy([caller.face, caller.face]) {
			Err(AmbiguousFace(face)) => face.index() == caller.face.index()
			_ => False
		}
		invalid = match cjk.registry.with_policy([Font.FaceId.from_index(99)]) {
			Err(UnknownPolicyFace(face)) => face.index() == 99
			_ => False
		}
		if uncovered == False or mismatched_script == False or ambiguous == False or invalid == False {
			return Err(EvidenceFailure)
		}
		bytes = blank_pdf(runtime_guard)?
		Ok({
			bytes,
			work: [
				caller.work.input_bytes,
				cjk.work.input_bytes,
				caller.work.retained_input_bytes,
				cjk.work.retained_input_bytes,
				caller.work.copied_input_bytes + cjk.work.copied_input_bytes,
				configured.registry.store().resources.len(),
				configured.registry.store().faces.len(),
				configured.registry.store().instances.len(),
				configured.registry.store().policies.len(),
				plan.work.grapheme_visits,
				plan.work.face_visits,
				plan.work.coverage_span_visits,
				plan.face_ranges.len(),
				bytes.len(),
			],
		})
	}

	## Adversarial ordered selection: alternating Latin/Han clusters force the
	## worst-case policy walk, because every Han cluster probes and rejects
	## the first (Latin) face before selecting the second. Every reported
	## dimension must stay linear in the cluster count, and the alternating
	## pattern prevents any face-range merging.
	multi_face_probe_scale : U64, U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	multi_face_probe_scale = |count, runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		if count == 0 or count % 2 != 0 {
			return Err(EvidenceFailure)
		}
		caller = Font.Registry.empty.register(
			caller_font_bytes,
			{ provision: AdvancedRunsRequired, scripts: [Font.Script.from_iso15924("Latn")] },
			Font.ValidationLimits.default,
		) ? |_| EvidenceFailure
		cjk = caller.registry.register(
			cjk_font_bytes,
			{ provision: AdvancedRunsRequired, scripts: [Font.Script.from_iso15924("Hani")] },
			Font.ValidationLimits.default,
		) ? |_| EvidenceFailure
		configured = cjk.registry.with_policy([caller.face, cjk.face]) ? |_| EvidenceFailure
		var $clusters = List.with_capacity(count)
		var $index = 0
		while $index < count {
			next = if $index % 2 == 0 cluster($index, "Latn", [0x43]) else cluster($index, "Hani", [0x4e2d])
			$clusters = $clusters.append(next)
			$index = $index + 1
		}
		plan = match configured.registry.plan(plan_request(configured.policy, $clusters)) {
			Complete(value) => value
			Rejected(_) => return Err(EvidenceFailure)
		}
		if plan.face_ranges.len() != count or plan.work.grapheme_visits != count {
			return Err(EvidenceFailure)
		}
		bytes = blank_pdf(runtime_guard)?
		Ok({
			bytes,
			work: [
				count,
				plan.work.grapheme_visits,
				plan.work.face_visits,
				plan.work.coverage_span_visits,
				plan.face_ranges.len(),
				bytes.len(),
			],
		})
	}
}

cluster : U64, Str, List(U32) -> Font.SourceCluster
cluster = |index, script, scalars| {
	range = Semantics.Range.from_start_and_length(index, scalars.len())
	{ scalars, script: Font.Script.from_iso15924(script), source: { scalars: range, utf8_bytes: range } }
}

plan_request : Font.PolicyId, List(Font.SourceCluster) -> Font.PlanRequest
plan_request = |policy, clusters| {
	{ clusters, language: Language("und"), policy, source: Semantics.TextSourceId.from_index(0) }
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
		crash "text-layout font evidence index escaped"
	}
	Ok(value) => value
}

expect {
	result = Fixture.font_inspection(0)?
	result.work.len() == 12
}

expect {
	result = Fixture.font_planning(0)?
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
