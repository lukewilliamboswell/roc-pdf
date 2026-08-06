import KernelEmit
import KernelFont
import KernelFontPlan
import KernelFontSubset
import KernelObject
import KernelPdfFont
import KernelSeal
import KernelStructure
import "../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)

Gate3PdfFontEvidence :: [].{
	font_objects : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	font_objects = |runtime_guard| {
		sample = sample_font_objects(runtime_guard)?
		bytes = blank_pdf(runtime_guard)?
		counts = KernelSeal.Plan.counts(sample.sealed)
		build_work = KernelSeal.Plan.build_work(sample.sealed)
		seal_work = KernelSeal.Plan.seal_work(sample.sealed)
		font_work = KernelPdfFont.Plan.work(sample.pdf_font)
		Ok({
			bytes,
			work: [
				sample.font.bytes.len(),
				sample.subset.work.output_bytes,
				font_work.font_program_bytes,
				font_work.cid_map_bytes,
				font_work.to_unicode_bytes,
				font_work.unicode_mappings,
				font_work.unicode_scalars,
				font_work.widths,
				font_work.tables,
				font_work.objects,
				counts.objects,
				counts.streams,
				counts.payloads,
				build_work.bytes_checked,
				build_work.edges_appended,
				build_work.index_checks,
				build_work.values_appended,
				seal_work.objects_checked,
				seal_work.references_checked,
				seal_work.streams_checked,
				seal_work.values_checked,
				bytes.len(),
			],
		})
	}
}

Sample := {
	font : KernelFont.Inspection,
	pdf_font : KernelPdfFont.Plan,
	sealed : KernelSeal.Plan,
	subset : KernelFontSubset.Subset,
}

sample_font_objects : U64 -> Try(Sample, [EvidenceFailure, InvalidRuntimeGuard])
sample_font_objects = |runtime_guard| {
	if runtime_guard != 0 {
		return Err(InvalidRuntimeGuard)
	}
	font = inspect_font({})?
	plan = sample_font_plan(font)?
	subset = KernelFontSubset.build(font, plan) ? |_| EvidenceFailure
	pdf_font = KernelPdfFont.Plan.build(
		KernelObject.init(object_limits),
		font,
		plan,
		subset,
		descriptor,
		unicode_mappings,
		KernelPdfFont.Limits.make({ max_to_unicode_bytes: 4096, max_unicode_mappings: 8, max_unicode_scalars: 16 }),
	) ? |_| EvidenceFailure
	sealed = KernelSeal.seal(KernelPdfFont.Plan.builder(pdf_font)) ? |_| EvidenceFailure
	Ok({ font, pdf_font, sealed, subset })
}

inspect_font : {} -> Try(KernelFont.Inspection, [EvidenceFailure, InvalidRuntimeGuard])
inspect_font = |_| {
	font = KernelFont.inspect(
		built_in_font_bytes,
		KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
	) ? |_| EvidenceFailure
	Ok(font)
}

sample_font_plan : KernelFont.Inspection -> Try(KernelFontPlan.Plan, [EvidenceFailure, InvalidRuntimeGuard])
sample_font_plan = |font| {
	glyph_a = required_glyph(font, 0x41)?
	glyph_e_acute = required_glyph(font, 0x00e9)?
	result = KernelFontPlan.plan(
		font,
		[{ glyph: glyph_a }, { glyph: glyph_e_acute }, { glyph: glyph_a }],
		KernelFontPlan.Limits.make({ max_retained_glyphs: 64 }),
	) ? |_| EvidenceFailure
	Ok(result)
}

required_glyph : KernelFont.Inspection, U32 -> Try(U32, [EvidenceFailure, InvalidRuntimeGuard])
required_glyph = |font, scalar| match KernelFont.glyph_for_scalar(font, scalar) {
	None => Err(EvidenceFailure)
	Some(glyph) => Ok(glyph)
}

descriptor : KernelPdfFont.Descriptor
descriptor = {
	cap_height: 2076,
	flags: 32,
	italic_angle: 0,
	postscript_name: Str.to_utf8("RocPdfSans-Regular"),
	stem_v: 80,
}

unicode_mappings : List(KernelPdfFont.UnicodeMapping)
unicode_mappings = [{ cid: 1, scalars: [0x41] }, { cid: 3, scalars: [0x00e9] }]

object_limits : KernelObject.Limits
object_limits = {
	max_array_items: 32,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 64,
	max_direct_depth: 8,
	max_name_bytes: 1024,
	max_names: 32,
	max_objects: 9,
	max_payload_bytes: 200000,
	max_payloads: 3,
	max_streams: 3,
	max_text_string_bytes: 32,
	max_text_strings: 2,
	max_values: 128,
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

expect {
	sample = sample_font_objects(0)?
	objects = KernelPdfFont.Plan.objects(sample.pdf_font)
	counts = KernelSeal.Plan.counts(sample.sealed)
	KernelObject.ObjectId.number(objects.font_file) == 1 and
		KernelObject.ObjectId.number(objects.font_file_length) == 2 and
			KernelObject.ObjectId.number(objects.cid_to_gid) == 3 and
				KernelObject.ObjectId.number(objects.cid_to_gid_length) == 4 and
					KernelObject.ObjectId.number(objects.to_unicode) == 5 and
						KernelObject.ObjectId.number(objects.to_unicode_length) == 6 and
							KernelObject.ObjectId.number(objects.descriptor) == 7 and
								KernelObject.ObjectId.number(objects.cid_font) == 8 and
									KernelObject.ObjectId.number(objects.type0) == 9 and
										counts.objects == 9 and
											counts.streams == 3 and
												counts.payloads == 3
}

expect {
	sample = sample_font_objects(0)?
	store = KernelSeal.Plan.store(sample.sealed)
	cid_map = list_at(store.payloads, 1).bytes
	to_unicode = list_at(store.payloads, 2).bytes
	cid_map == [0, 0, 0, 1, 0, 2, 0, 3, 0, 4] and
		contains_bytes(to_unicode, Str.to_utf8("<0001> <0041>\n")) and
			contains_bytes(to_unicode, Str.to_utf8("<0003> <00E9>\n"))
}

expect {
	font = inspect_font({})?
	plan = sample_font_plan(font)?
	subset = KernelFontSubset.build(font, plan)?
	result = KernelPdfFont.Plan.build(
		KernelObject.init(object_limits),
		font,
		plan,
		subset,
		descriptor,
		[{ cid: 1, scalars: [0x41] }],
		KernelPdfFont.Limits.make({ max_to_unicode_bytes: 4096, max_unicode_mappings: 8, max_unicode_scalars: 16 }),
	)
	match result {
		Err(IncompleteUnicodeMapping({ cid: 3 })) => Bool.True
		_ => Bool.False
	}
}

contains_bytes : List(U8), List(U8) -> Bool
contains_bytes = |haystack, needle| {
	if needle.is_empty() {
		return True
	}
	var $start = 0
	var $found = False
	while $found == False and $start + needle.len() <= haystack.len() {
		var $index = 0
		var $matches = True
		while $matches and $index < needle.len() {
			if list_at(haystack, $start + $index) != list_at(needle, $index) {
				$matches = False
			}
			$index = $index + 1
		}
		if $matches {
			$found = True
		}
		$start = $start + 1
	}
	$found
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "Gate 3 PDF font evidence index escaped"
	}
	Ok(value) => value
}
