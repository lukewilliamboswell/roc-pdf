import pdf.KernelEmit
import pdf.KernelFont
import pdf.KernelFontLeaf
import pdf.KernelFontPlan
import pdf.KernelFontSubset
import pdf.KernelObject
import pdf.KernelPdfFont
import pdf.KernelSeal
import pdf.KernelStructure
import "../../package/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)

Fixture :: [].{
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
				font_work.identity_cid_entries,
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
	pdf_font = KernelPdfFont.Plan.build(KernelObject.init(object_limits), font, plan, subset, descriptor, unicode_mappings, KernelPdfFont.Limits.make({ max_to_unicode_bytes: 4096, max_unicode_mappings: 8, max_unicode_scalars: 16 })) ? |_| EvidenceFailure
	sealed = KernelSeal.seal(KernelPdfFont.Plan.builder(pdf_font)) ? |_| EvidenceFailure
	Ok({ font, pdf_font, sealed, subset })
}

inspect_font : {} -> Try(KernelFont.Inspection, [EvidenceFailure, InvalidRuntimeGuard])
inspect_font = |_| {
	font = KernelFont.inspect(built_in_font_bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })) ? |_| EvidenceFailure
	Ok(font)
}

sample_font_plan : KernelFont.Inspection -> Try(KernelFontPlan.Plan, [EvidenceFailure, InvalidRuntimeGuard])
sample_font_plan = |font| {
	glyph_a = required_glyph(font, 0x41)?
	glyph_e_acute = required_glyph(font, 0x00e9)?
	result = KernelFontPlan.plan(font, [{ glyph: glyph_a }, { glyph: glyph_e_acute }, { glyph: glyph_a }], KernelFontPlan.Limits.make({ max_retained_glyphs: 64 })) ? |_| EvidenceFailure
	Ok(result)
}

required_glyph : KernelFont.Inspection, U32 -> Try(U32, [EvidenceFailure, InvalidRuntimeGuard])
required_glyph = |font, scalar| match KernelFont.glyph_for_scalar(font, scalar) {
	None => Err(EvidenceFailure)
	Some(glyph) => Ok(glyph)
}

descriptor : KernelPdfFont.Descriptor
descriptor = {
	flags: 32,
	italic_angle: 0,
	stem_v: 80,
}

unicode_mappings : List(KernelPdfFont.UnicodeMapping)
unicode_mappings = [{ cid: 1, scalars: [0x41] }, { cid: 3, scalars: [0x00e9] }]

object_limits : KernelObject.Limits
object_limits = {
	max_array_items: 32,
	max_byte_string_bytes: 13,
	max_byte_strings: 2,
	max_dictionary_entries: 64,
	max_direct_depth: 8,
	max_name_bytes: 1024,
	max_names: 32,
	max_objects: 9,
	max_payload_bytes: 200000,
	max_payloads: 3,
	max_streams: 3,
	max_text_string_bytes: 19,
	max_text_strings: 0,
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
			KernelObject.ObjectId.number(objects.to_unicode) == 3 and
				KernelObject.ObjectId.number(objects.to_unicode_length) == 4 and
					KernelObject.ObjectId.number(objects.descriptor) == 5 and
						KernelObject.ObjectId.number(objects.cid_font) == 6 and
							KernelObject.ObjectId.number(objects.type0) == 7 and
								counts.objects == 7 and
									counts.streams == 2 and
										counts.payloads == 2
}

expect {
	sample = sample_font_objects(0)?
	store = KernelSeal.Plan.store(sample.sealed)
	to_unicode = list_at(store.payloads, 1).bytes
	KernelPdfFont.Plan.work(sample.pdf_font).identity_cid_entries == 5 and
		contains_bytes(to_unicode, Str.to_utf8("<0001> <0041>\n")) and
			contains_bytes(to_unicode, Str.to_utf8("<0003> <00E9>\n"))
}

expect {
	font = inspect_font({})?
	plan = sample_font_plan(font)?
	subset = KernelFontSubset.build(font, plan)?
	result = KernelPdfFont.Plan.build(KernelObject.init(object_limits), font, plan, subset, descriptor, [{ cid: 1, scalars: [0x41] }], KernelPdfFont.Limits.make({ max_to_unicode_bytes: 4096, max_unicode_mappings: 8, max_unicode_scalars: 16 }))
	match result {
		Err(IncompleteUnicodeMapping({ cid: 3 })) => True
		_ => False
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
		crash "text-layout PDF font evidence index escaped"
	}
	Ok(value) => value
}

# The per-destination limit counts decoded UTF-16BE bytes. The combined
# CMap is longer than 512 bytes even when each destination is in range.
expect {
	font = inspect_font({})?
	plan = sample_font_plan(font)?
	subset = KernelFontSubset.build(font, plan)?
	limits = KernelPdfFont.Limits.make({ max_to_unicode_bytes: 4096, max_unicode_mappings: 8, max_unicode_scalars: 1024 })
	mappings = [{ cid: 1, scalars: List.repeat(0x0041, 256) }, { cid: 3, scalars: List.repeat(0x1f600, 128) }]
	leaf = KernelFontLeaf.Leaf.build({ font, plan, subset, descriptor, mappings })?
	pdf_font = KernelPdfFont.Plan.build(KernelObject.init(object_limits), font, plan, subset, descriptor, mappings, limits)?
	store = KernelSeal.Plan.store(KernelSeal.seal(KernelPdfFont.Plan.builder(pdf_font))?)
	stream = store.streams.keep_if(|item| item.object == KernelPdfFont.Plan.objects(pdf_font).to_unicode).first()?
	cmap = list_at(store.payloads, stream.source.index()).bytes
	bmp = List.repeat(Str.to_utf8("0041"), 256).join()
	supplementary = List.repeat(Str.to_utf8("D83DDE00"), 128).join()
	KernelFontLeaf.Leaf.work(leaf).mapping_scalars == 384 and
		contains_bytes(cmap, [Str.to_utf8("2 beginbfchar\n<0001> <"), bmp, Str.to_utf8(">\n<0003> <"), supplementary, Str.to_utf8(">\nendbfchar\n")].join())
}

expect {
	font = inspect_font({})?
	plan = sample_font_plan(font)?
	subset = KernelFontSubset.build(font, plan)?
	limits = KernelPdfFont.Limits.make({ max_to_unicode_bytes: 4096, max_unicode_mappings: 8, max_unicode_scalars: 1024 })
	[
		{ attempted: 514, scalars: List.repeat(0x1f600, 128).append(0x0041) },
		{ attempted: 516, scalars: List.repeat(0x1f600, 129) },
	].all(
		|boundary| {
			mappings = [{ cid: 1, scalars: [0x0041] }, { cid: 3, scalars: boundary.scalars }]
			bundle = { font, plan, subset, descriptor, mappings }
			match (KernelFontLeaf.Leaf.build(bundle), KernelPdfFont.Plan.build(KernelObject.init(object_limits), font, plan, subset, descriptor, mappings, limits)) {
				(Err(UnicodeDestinationTooLong({ attempted: leaf, cid: 3, limit: 512 })), Err(UnicodeDestinationTooLong({ attempted: emitted, cid: 3, limit: 512 }))) =>
					leaf == boundary.attempted and emitted == boundary.attempted
				_ => False
			}
		},
	)
}

# 101 two-CID ranges followed by 101 individual mappings require two
# blocks of each kind. The consecutive source or destination pairs at
# 00FF/0100 must stay individually mapped when either low byte would carry.
expect {
	font = inspect_font({})?
	var $usages = []
	var $mappings = []
	var $cid = 1
	while $cid <= 303 {
		scalar = match $cid {
			255 => 0x0041
			256 => 0x0042
			263 => 0x00ff
			264 => 0x0100
			_ => if ($cid <= 202) (if ($cid.bitwise_and(1) == 1) 0x0041 else 0x0042) else 0x20ac
		}
		$usages = $usages.append({ glyph: $cid })
		$mappings = $mappings.append({ cid: $cid, scalars: [scalar] })
		$cid = $cid + 1
	}
	plan = KernelFontPlan.plan(font, $usages, KernelFontPlan.Limits.make({ max_retained_glyphs: 512 }))?
	subset = KernelFontSubset.build(font, plan)?
	limits = KernelPdfFont.Limits.make({ max_to_unicode_bytes: 8192, max_unicode_mappings: 303, max_unicode_scalars: 303 })
	builder = KernelObject.init({ ..object_limits, max_array_items: 1024, max_values: 1024 })
	pdf_font = KernelPdfFont.Plan.build(builder, font, plan, subset, descriptor, $mappings, limits)?
	store = KernelSeal.Plan.store(KernelSeal.seal(KernelPdfFont.Plan.builder(pdf_font))?)
	stream = store.streams.keep_if(|item| item.object == KernelPdfFont.Plan.objects(pdf_font).to_unicode).first()?
	cmap = Str.from_utf8_lossy(list_at(store.payloads, stream.source.index()).bytes)
	cmap.contains("100 beginbfrange\n<0001> <0002> <0041>\n")
		and cmap.contains("<00C7> <00C8> <0041>\nendbfrange\n1 beginbfrange\n<00C9> <00CA> <0041>\nendbfrange\n100 beginbfchar\n<00CB> <20AC>\n")
		and cmap.contains("<00FF> <0041>\n<0100> <0042>\n")
		and cmap.contains("<0107> <00FF>\n<0108> <0100>\n")
		and cmap.contains("<012E> <20AC>\nendbfchar\n1 beginbfchar\n<012F> <20AC>\nendbfchar\nendcmap\n")
}
