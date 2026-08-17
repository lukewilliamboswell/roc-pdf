import KernelFont
import KernelFontPlan
import KernelFontSubset
import KernelObject

KernelPdfFont :: [].{
	Error : [
		ArithmeticOverflow,
		IncompleteUnicodeMapping({ cid : U32 }),
		InvalidDescriptor,
		InvalidFontPlan,
		InvalidPostScriptName,
		InvalidSubset,
		InvalidUnicodeScalar(U32),
		Object(KernelObject.Error),
		UnexpectedUnicodeMapping({ cid : U32 }),
		UnicodeMappingLimitExceeded({ attempted : U64, limit : U64 }),
	]

	Descriptor : {
		flags : I64,
		italic_angle : I64,
		stem_v : I64,
	}

	UnicodeMapping : {
		cid : U32,
		scalars : List(U32),
	}

	Limits :: { max_to_unicode_bytes : U64, max_unicode_mappings : U64, max_unicode_scalars : U64 }.{
		make : { max_to_unicode_bytes : U64, max_unicode_mappings : U64, max_unicode_scalars : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	## The exact font-unit-to-text-space scaling the emitted descriptor and
	## width integers use (1000 per em, rounding half away from zero). Shared
	## so canonical font-leaf recipes serialize the same integers this
	## lowering emits.
	scaled_signed_metric : I64, U16 -> Try(I64, Error)
	scaled_signed_metric = |value, units_per_em| scale_signed(value, units_per_em)

	scaled_unsigned_metric : U16, U16 -> Try(U64, Error)
	scaled_unsigned_metric = |value, units_per_em| scale_unsigned(value, units_per_em)

	## Whether bytes are valid as the PostScript-name segment of an emitted
	## BaseFont name. Shared with the canonical font-leaf identity boundary
	## so one charset rule guards both.
	valid_font_name_bytes : List(U8) -> Bool
	valid_font_name_bytes = |bytes| valid_postscript_name(bytes)

	Objects : {
		cid_font : KernelObject.ObjectId,
		cid_to_gid : KernelObject.ObjectId,
		cid_to_gid_length : KernelObject.ObjectId,
		descriptor : KernelObject.ObjectId,
		font_file : KernelObject.ObjectId,
		font_file_length : KernelObject.ObjectId,
		to_unicode : KernelObject.ObjectId,
		to_unicode_length : KernelObject.ObjectId,
		type0 : KernelObject.ObjectId,
	}

	Work : {
		cid_map_bytes : U64,
		font_program_bytes : U64,
		objects : U64,
		tables : U64,
		to_unicode_bytes : U64,
		unicode_mappings : U64,
		unicode_scalars : U64,
		widths : U64,
	}

	Plan :: { builder : KernelObject.Builder, objects : Objects, work : Work }.{
		build : KernelObject.Builder, KernelFont.Inspection, KernelFontPlan.Plan, KernelFontSubset.Subset, Descriptor, List(UnicodeMapping), Limits -> Try(Plan, Error)
		build = |builder, font, font_plan, subset, descriptor, mappings, limits| build_plan(builder, font, font_plan, subset, descriptor, mappings, limits)

		builder : Plan -> KernelObject.Builder
		builder = |plan| plan.builder

		objects : Plan -> Objects
		objects = |plan| plan.objects

		work : Plan -> Work
		work = |plan| plan.work
	}
}

Names := {
	ascent : KernelObject.NameId,
	base_font : KernelObject.NameId,
	cid_font_type2 : KernelObject.NameId,
	cid_system_info : KernelObject.NameId,
	cid_to_gid_map : KernelObject.NameId,
	cap_height : KernelObject.NameId,
	dw : KernelObject.NameId,
	descendant_fonts : KernelObject.NameId,
	descent : KernelObject.NameId,
	encoding : KernelObject.NameId,
	flags : KernelObject.NameId,
	font : KernelObject.NameId,
	font_bbox : KernelObject.NameId,
	font_descriptor : KernelObject.NameId,
	font_file2 : KernelObject.NameId,
	font_name : KernelObject.NameId,
	identity_h : KernelObject.NameId,
	italic_angle : KernelObject.NameId,
	length1 : KernelObject.NameId,
	ordering : KernelObject.NameId,
	registry : KernelObject.NameId,
	stem_v : KernelObject.NameId,
	subtype : KernelObject.NameId,
	supplement : KernelObject.NameId,
	to_unicode : KernelObject.NameId,
	type_name : KernelObject.NameId,
	type0 : KernelObject.NameId,
	w : KernelObject.NameId,
}

build_plan : KernelObject.Builder, KernelFont.Inspection, KernelFontPlan.Plan, KernelFontSubset.Subset, KernelPdfFont.Descriptor, List(KernelPdfFont.UnicodeMapping), KernelPdfFont.Limits -> Try(KernelPdfFont.Plan, KernelPdfFont.Error)
build_plan = |builder, font, font_plan, subset, descriptor, mappings, limits| {
	if descriptor.flags < 0 or descriptor.stem_v <= 0 {
		return Err(InvalidDescriptor)
	}
	postscript_name = KernelFont.postscript_name(font)
	if !valid_postscript_name(postscript_name) {
		return Err(InvalidPostScriptName)
	}
	if font_plan.prefix.len() != 6 or font_plan.entries.len() == 0 or font_plan.entries.len() > 65535 {
		return Err(InvalidFontPlan)
	}
	if subset.bytes.len() != subset.work.output_bytes or subset.bytes.len() > I64.highest.to_u64_wrap() {
		return Err(InvalidSubset)
	}
	starting_objects = builder.store.objects.len()
	font_program_bytes = subset.work.output_bytes
	mapping_work = validate_mappings(font_plan, mappings, limits)?
	cid_map = build_cid_map(font_plan)?
	to_unicode = build_to_unicode(mappings, limits.max_to_unicode_bytes)?
	base_font_bytes = build_base_font_name(font_plan.prefix, postscript_name)
	added_names = add_names(builder)?
	base_font = KernelObject.add_name(added_names.builder, base_font_bytes) ? Object

	length1 = KernelObject.add_integer(base_font.builder, subset.bytes.len().to_i64_wrap()) ? Object
	font_payload = KernelObject.add_payload(length1.builder, subset.bytes, Generated) ? Object
	font_stream = KernelObject.add_stream_object(font_payload.builder, [{ key: added_names.names.length1, value: length1.id }], Unfiltered, font_payload.id) ? Object

	cid_payload = KernelObject.add_payload(font_stream.builder, cid_map, Generated) ? Object
	cid_stream = KernelObject.add_stream_object(cid_payload.builder, [], Unfiltered, cid_payload.id) ? Object

	unicode_payload = KernelObject.add_payload(cid_stream.builder, to_unicode, Generated) ? Object
	unicode_stream = KernelObject.add_stream_object(unicode_payload.builder, [], Unfiltered, unicode_payload.id) ? Object

	descriptor_object = add_descriptor(unicode_stream.builder, added_names.names, base_font.id, font_stream.id, font, descriptor)?
	cid_font_object = add_cid_font(descriptor_object.builder, added_names.names, base_font.id, cid_stream.id, descriptor_object.id, font, font_plan)?
	type0_object = add_type0(cid_font_object.builder, added_names.names, base_font.id, cid_font_object.id, unicode_stream.id)?

	Ok(
		KernelPdfFont.Plan.{
			builder: type0_object.builder,
			objects: {
				cid_font: cid_font_object.id,
				cid_to_gid: cid_stream.id,
				cid_to_gid_length: cid_stream.length_object,
				descriptor: descriptor_object.id,
				font_file: font_stream.id,
				font_file_length: font_stream.length_object,
				to_unicode: unicode_stream.id,
				to_unicode_length: unicode_stream.length_object,
				type0: type0_object.id,
			},
			work: {
				cid_map_bytes: cid_map.len(),
				font_program_bytes,
				objects: type0_object.builder.store.objects.len() - starting_objects,
				tables: subset.work.tables,
				to_unicode_bytes: to_unicode.len(),
				unicode_mappings: mappings.len(),
				unicode_scalars: mapping_work.scalars,
				widths: font_plan.entries.len(),
			},
		},
	)
}

add_names : KernelObject.Builder -> Try({ builder : KernelObject.Builder, names : Names }, KernelPdfFont.Error)
add_names = |builder| {
	ascent = KernelObject.add_name(builder, Str.to_utf8("Ascent")) ? Object
	base_font = KernelObject.add_name(ascent.builder, Str.to_utf8("BaseFont")) ? Object
	cid_font_type2 = KernelObject.add_name(base_font.builder, Str.to_utf8("CIDFontType2")) ? Object
	cid_system_info = KernelObject.add_name(cid_font_type2.builder, Str.to_utf8("CIDSystemInfo")) ? Object
	cid_to_gid_map = KernelObject.add_name(cid_system_info.builder, Str.to_utf8("CIDToGIDMap")) ? Object
	cap_height = KernelObject.add_name(cid_to_gid_map.builder, Str.to_utf8("CapHeight")) ? Object
	dw = KernelObject.add_name(cap_height.builder, Str.to_utf8("DW")) ? Object
	descendant_fonts = KernelObject.add_name(dw.builder, Str.to_utf8("DescendantFonts")) ? Object
	descent = KernelObject.add_name(descendant_fonts.builder, Str.to_utf8("Descent")) ? Object
	encoding = KernelObject.add_name(descent.builder, Str.to_utf8("Encoding")) ? Object
	flags = KernelObject.add_name(encoding.builder, Str.to_utf8("Flags")) ? Object
	font = KernelObject.add_name(flags.builder, Str.to_utf8("Font")) ? Object
	font_bbox = KernelObject.add_name(font.builder, Str.to_utf8("FontBBox")) ? Object
	font_descriptor = KernelObject.add_name(font_bbox.builder, Str.to_utf8("FontDescriptor")) ? Object
	font_file2 = KernelObject.add_name(font_descriptor.builder, Str.to_utf8("FontFile2")) ? Object
	font_name = KernelObject.add_name(font_file2.builder, Str.to_utf8("FontName")) ? Object
	identity_h = KernelObject.add_name(font_name.builder, Str.to_utf8("Identity-H")) ? Object
	italic_angle = KernelObject.add_name(identity_h.builder, Str.to_utf8("ItalicAngle")) ? Object
	length1 = KernelObject.add_name(italic_angle.builder, Str.to_utf8("Length1")) ? Object
	ordering = KernelObject.add_name(length1.builder, Str.to_utf8("Ordering")) ? Object
	registry = KernelObject.add_name(ordering.builder, Str.to_utf8("Registry")) ? Object
	stem_v = KernelObject.add_name(registry.builder, Str.to_utf8("StemV")) ? Object
	subtype = KernelObject.add_name(stem_v.builder, Str.to_utf8("Subtype")) ? Object
	supplement = KernelObject.add_name(subtype.builder, Str.to_utf8("Supplement")) ? Object
	to_unicode = KernelObject.add_name(supplement.builder, Str.to_utf8("ToUnicode")) ? Object
	type_name = KernelObject.add_name(to_unicode.builder, Str.to_utf8("Type")) ? Object
	type0 = KernelObject.add_name(type_name.builder, Str.to_utf8("Type0")) ? Object
	w = KernelObject.add_name(type0.builder, Str.to_utf8("W")) ? Object
	Ok({
		builder: w.builder,
		names: {
			ascent: ascent.id,
			base_font: base_font.id,
			cid_font_type2: cid_font_type2.id,
			cid_system_info: cid_system_info.id,
			cid_to_gid_map: cid_to_gid_map.id,
			cap_height: cap_height.id,
			dw: dw.id,
			descendant_fonts: descendant_fonts.id,
			descent: descent.id,
			encoding: encoding.id,
			flags: flags.id,
			font: font.id,
			font_bbox: font_bbox.id,
			font_descriptor: font_descriptor.id,
			font_file2: font_file2.id,
			font_name: font_name.id,
			identity_h: identity_h.id,
			italic_angle: italic_angle.id,
			length1: length1.id,
			ordering: ordering.id,
			registry: registry.id,
			stem_v: stem_v.id,
			subtype: subtype.id,
			supplement: supplement.id,
			to_unicode: to_unicode.id,
			type_name: type_name.id,
			type0: type0.id,
			w: w.id,
		},
	})
}

add_descriptor : KernelObject.Builder, Names, KernelObject.NameId, KernelObject.ObjectId, KernelFont.Inspection, KernelPdfFont.Descriptor -> Try({ builder : KernelObject.Builder, id : KernelObject.ObjectId }, KernelPdfFont.Error)
add_descriptor = |builder, names, base_font, font_file, font, descriptor| {
	ascent = add_scaled_integer(builder, font.metrics.ascent, font.metrics.units_per_em)?
	cap_height = add_scaled_integer(ascent.builder, font.metrics.cap_height, font.metrics.units_per_em)?
	descent = add_scaled_integer(cap_height.builder, font.metrics.descent, font.metrics.units_per_em)?
	flags = KernelObject.add_integer(descent.builder, descriptor.flags) ? Object
	x_min = add_scaled_integer(flags.builder, font.metrics.x_min, font.metrics.units_per_em)?
	y_min = add_scaled_integer(x_min.builder, font.metrics.y_min, font.metrics.units_per_em)?
	x_max = add_scaled_integer(y_min.builder, font.metrics.x_max, font.metrics.units_per_em)?
	y_max = add_scaled_integer(x_max.builder, font.metrics.y_max, font.metrics.units_per_em)?
	bbox = KernelObject.add_array(y_max.builder, [x_min.id, y_min.id, x_max.id, y_max.id]) ? Object
	file_reference = KernelObject.add_reference(bbox.builder, font_file) ? Object
	font_name = KernelObject.add_name_value(file_reference.builder, base_font) ? Object
	italic_angle = KernelObject.add_integer(font_name.builder, descriptor.italic_angle) ? Object
	stem_v = KernelObject.add_integer(italic_angle.builder, descriptor.stem_v) ? Object
	type_value = KernelObject.add_name_value(stem_v.builder, names.font_descriptor) ? Object
	dictionary = KernelObject.add_dictionary(
		type_value.builder,
		[
			{ key: names.ascent, value: ascent.id },
			{ key: names.cap_height, value: cap_height.id },
			{ key: names.descent, value: descent.id },
			{ key: names.flags, value: flags.id },
			{ key: names.font_bbox, value: bbox.id },
			{ key: names.font_file2, value: file_reference.id },
			{ key: names.font_name, value: font_name.id },
			{ key: names.italic_angle, value: italic_angle.id },
			{ key: names.stem_v, value: stem_v.id },
			{ key: names.type_name, value: type_value.id },
		],
	) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	Ok(object)
}

add_cid_font : KernelObject.Builder, Names, KernelObject.NameId, KernelObject.ObjectId, KernelObject.ObjectId, KernelFont.Inspection, KernelFontPlan.Plan -> Try({ builder : KernelObject.Builder, id : KernelObject.ObjectId }, KernelPdfFont.Error)
add_cid_font = |builder, names, base_font, cid_to_gid, descriptor, font, plan| {
	base_value = KernelObject.add_name_value(builder, base_font) ? Object
	system_info = add_cid_system_info(base_value.builder, names)?
	cid_map_reference = KernelObject.add_reference(system_info.builder, cid_to_gid) ? Object
	dw = KernelObject.add_integer(cid_map_reference.builder, 1000) ? Object
	descriptor_reference = KernelObject.add_reference(dw.builder, descriptor) ? Object
	subtype = KernelObject.add_name_value(descriptor_reference.builder, names.cid_font_type2) ? Object
	type_value = KernelObject.add_name_value(subtype.builder, names.font) ? Object
	widths = add_widths(type_value.builder, font, plan)?
	dictionary = KernelObject.add_dictionary(
		widths.builder,
		[
			{ key: names.base_font, value: base_value.id },
			{ key: names.cid_system_info, value: system_info.id },
			{ key: names.cid_to_gid_map, value: cid_map_reference.id },
			{ key: names.dw, value: dw.id },
			{ key: names.font_descriptor, value: descriptor_reference.id },
			{ key: names.subtype, value: subtype.id },
			{ key: names.type_name, value: type_value.id },
			{ key: names.w, value: widths.id },
		],
	) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	Ok(object)
}

add_cid_system_info : KernelObject.Builder, Names -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelPdfFont.Error)
add_cid_system_info = |builder, names| {
	ordering_text = KernelObject.add_text_string(builder, "Identity") ? Object
	ordering = KernelObject.add_text_string_value(ordering_text.builder, ordering_text.id) ? Object
	registry_text = KernelObject.add_text_string(ordering.builder, "Adobe") ? Object
	registry = KernelObject.add_text_string_value(registry_text.builder, registry_text.id) ? Object
	supplement = KernelObject.add_integer(registry.builder, 0) ? Object
	dictionary = KernelObject.add_dictionary(
		supplement.builder,
		[
			{ key: names.ordering, value: ordering.id },
			{ key: names.registry, value: registry.id },
			{ key: names.supplement, value: supplement.id },
		],
	) ? Object
	Ok(dictionary)
}

add_widths : KernelObject.Builder, KernelFont.Inspection, KernelFontPlan.Plan -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelPdfFont.Error)
add_widths = |builder, font, plan| {
	var $builder = builder
	var $width_values = List.with_capacity(plan.entries.len())
	var $index = 0
	var $error = NoError
	while $index < plan.entries.len() and $error == NoError {
		entry = list_at(plan.entries, $index)
		scaled = scale_unsigned(entry.width, font.metrics.units_per_em)
		match scaled {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(value) => match KernelObject.add_integer($builder, value.to_i64_wrap()) {
				Err(error) => {
					$error = Invalid(Object(error))
				}
				Ok(added) => {
					$builder = added.builder
					$width_values = $width_values.append(added.id)
				}
			}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => {
			width_array = KernelObject.add_array($builder, $width_values) ? Object
			first_cid = KernelObject.add_integer(width_array.builder, 0) ? Object
			outer = KernelObject.add_array(first_cid.builder, [first_cid.id, width_array.id]) ? Object
			Ok(outer)
		}
	}
}

add_type0 : KernelObject.Builder, Names, KernelObject.NameId, KernelObject.ObjectId, KernelObject.ObjectId -> Try({ builder : KernelObject.Builder, id : KernelObject.ObjectId }, KernelPdfFont.Error)
add_type0 = |builder, names, base_font, cid_font, to_unicode| {
	base_value = KernelObject.add_name_value(builder, base_font) ? Object
	descendant_reference = KernelObject.add_reference(base_value.builder, cid_font) ? Object
	descendants = KernelObject.add_array(descendant_reference.builder, [descendant_reference.id]) ? Object
	encoding = KernelObject.add_name_value(descendants.builder, names.identity_h) ? Object
	subtype = KernelObject.add_name_value(encoding.builder, names.type0) ? Object
	unicode_reference = KernelObject.add_reference(subtype.builder, to_unicode) ? Object
	type_value = KernelObject.add_name_value(unicode_reference.builder, names.font) ? Object
	dictionary = KernelObject.add_dictionary(
		type_value.builder,
		[
			{ key: names.base_font, value: base_value.id },
			{ key: names.descendant_fonts, value: descendants.id },
			{ key: names.encoding, value: encoding.id },
			{ key: names.subtype, value: subtype.id },
			{ key: names.to_unicode, value: unicode_reference.id },
			{ key: names.type_name, value: type_value.id },
		],
	) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	Ok(object)
}

validate_mappings : KernelFontPlan.Plan, List(KernelPdfFont.UnicodeMapping), KernelPdfFont.Limits -> Try({ scalars : U64 }, KernelPdfFont.Error)
validate_mappings = |plan, mappings, limits| {
	if mappings.len() > limits.max_unicode_mappings {
		return Err(UnicodeMappingLimitExceeded({ attempted: mappings.len(), limit: limits.max_unicode_mappings }))
	}
	var $mapping_index = 0
	var $scalar_count = 0
	var $entry_index = 0
	while $entry_index < plan.entries.len() {
		entry = list_at(plan.entries, $entry_index)
		if entry.cid.to_u64() != $entry_index or entry.subset_glyph != entry.cid {
			return Err(InvalidFontPlan)
		}
		if entry.content {
			if $mapping_index >= mappings.len() {
				return Err(IncompleteUnicodeMapping({ cid: entry.cid }))
			}
			mapping = list_at(mappings, $mapping_index)
			if mapping.cid != entry.cid {
				return if mapping.cid < entry.cid Err(UnexpectedUnicodeMapping({ cid: mapping.cid })) else Err(IncompleteUnicodeMapping({ cid: entry.cid }))
			}
			if mapping.scalars.len() == 0 {
				return Err(IncompleteUnicodeMapping({ cid: entry.cid }))
			}
			var $scalar_index = 0
			while $scalar_index < mapping.scalars.len() {
				scalar = list_at(mapping.scalars, $scalar_index)
				if scalar > 0x10ffff or (scalar >= 0xd800 and scalar <= 0xdfff) {
					return Err(InvalidUnicodeScalar(scalar))
				}
				$scalar_count = checked_add($scalar_count, 1)?
				if $scalar_count > limits.max_unicode_scalars {
					return Err(UnicodeMappingLimitExceeded({ attempted: $scalar_count, limit: limits.max_unicode_scalars }))
				}
				$scalar_index = $scalar_index + 1
			}
			$mapping_index = $mapping_index + 1
		}
		$entry_index = $entry_index + 1
	}
	if $mapping_index != mappings.len() {
		return Err(UnexpectedUnicodeMapping({ cid: list_at(mappings, $mapping_index).cid }))
	}
	Ok({ scalars: $scalar_count })
}

build_cid_map : KernelFontPlan.Plan -> Try(List(U8), KernelPdfFont.Error)
build_cid_map = |plan| {
	length = checked_times(plan.entries.len(), 2)?
	var $bytes = List.with_capacity(length)
	var $index = 0
	while $index < plan.entries.len() {
		entry = list_at(plan.entries, $index)
		if entry.cid.to_u64() != $index or entry.subset_glyph != entry.cid or entry.cid > 0xffff {
			return Err(InvalidFontPlan)
		}
		$bytes = append_u16($bytes, entry.subset_glyph.to_u16_wrap())
		$index = $index + 1
	}
	Ok($bytes)
}

build_to_unicode : List(KernelPdfFont.UnicodeMapping), U64 -> Try(List(U8), KernelPdfFont.Error)
build_to_unicode = |mappings, limit| {
	expected_size = to_unicode_size(mappings)?
	if expected_size > limit {
		return Err(UnicodeMappingLimitExceeded({ attempted: expected_size, limit }))
	}
	var $bytes = List.with_capacity(expected_size)
	$bytes = append_ascii($bytes, to_unicode_header)
	var $mapping_index = 0
	while $mapping_index < mappings.len() {
		remaining = mappings.len() - $mapping_index
		block_count = if remaining < 100 remaining else 100
		$bytes = append_u64_decimal($bytes, block_count)
		$bytes = append_ascii($bytes, " beginbfchar\n")
		var $block_index = 0
		while $block_index < block_count {
			mapping = list_at(mappings, $mapping_index + $block_index)
			$bytes = $bytes.append(0x3c)
			$bytes = append_hex_u16($bytes, mapping.cid.to_u16_wrap())
			$bytes = append_ascii($bytes, "> <")
			var $scalar_index = 0
			while $scalar_index < mapping.scalars.len() {
				$bytes = append_scalar_utf16_hex($bytes, list_at(mapping.scalars, $scalar_index))?
				$scalar_index = $scalar_index + 1
			}
			$bytes = append_ascii($bytes, ">\n")
			$block_index = $block_index + 1
		}
		$bytes = append_ascii($bytes, "endbfchar\n")
		$mapping_index = $mapping_index + block_count
	}
	$bytes = append_ascii($bytes, to_unicode_footer)
	Ok($bytes)
}

to_unicode_size : List(KernelPdfFont.UnicodeMapping) -> Try(U64, KernelPdfFont.Error)
to_unicode_size = |mappings| {
	var $size = checked_add(to_unicode_header.count_utf8_bytes(), to_unicode_footer.count_utf8_bytes())?
	var $mapping_index = 0
	while $mapping_index < mappings.len() {
		remaining = mappings.len() - $mapping_index
		block_count = if remaining < 100 remaining else 100
		$size = checked_add($size, decimal_digits(block_count))?
		$size = checked_add($size, Str.count_utf8_bytes(" beginbfchar\n"))?
		$size = checked_add($size, Str.count_utf8_bytes("endbfchar\n"))?
		var $block_index = 0
		while $block_index < block_count {
			mapping = list_at(mappings, $mapping_index + $block_index)
			var $utf16_units = 0
			var $scalar_index = 0
			while $scalar_index < mapping.scalars.len() {
				scalar = list_at(mapping.scalars, $scalar_index)
				$utf16_units = checked_add($utf16_units, if scalar <= 0xffff 1 else 2)?
				$scalar_index = $scalar_index + 1
			}
			$size = checked_add($size, checked_add(10, checked_times($utf16_units, 4)?)?)?
			$block_index = $block_index + 1
		}
		$mapping_index = $mapping_index + block_count
	}
	Ok($size)
}

decimal_digits : U64 -> U64
decimal_digits = |value| if value < 10 1 else if value < 100 2 else if value < 1000 3 else 20

append_scalar_utf16_hex : List(U8), U32 -> Try(List(U8), KernelPdfFont.Error)
append_scalar_utf16_hex = |bytes, scalar| {
	if scalar > 0x10ffff or (scalar >= 0xd800 and scalar <= 0xdfff) {
		return Err(InvalidUnicodeScalar(scalar))
	}
	if scalar <= 0xffff {
		Ok(append_hex_u16(bytes, scalar.to_u16_wrap()))
	} else {
		value = scalar - 0x10000
		high = 0xd800 + value.shr_wrap(10)
		low = 0xdc00 + value.bitwise_and(0x3ff)
		Ok(append_hex_u16(append_hex_u16(bytes, high.to_u16_wrap()), low.to_u16_wrap()))
	}
}

build_base_font_name : List(U8), List(U8) -> List(U8)
build_base_font_name = |prefix, postscript| {
	var $bytes = List.with_capacity(prefix.len() + 1 + postscript.len())
	$bytes = append_all($bytes, prefix)
	$bytes = $bytes.append(0x2b)
	append_all($bytes, postscript)
}

valid_postscript_name : List(U8) -> Bool
valid_postscript_name = |bytes| {
	if bytes.len() == 0 or bytes.len() > 96 {
		return False
	}
	var $index = 0
	var $valid = True
	while $valid and $index < bytes.len() {
		byte = list_at(bytes, $index)
		# PDF name delimiters, whitespace, controls, non-ASCII, and '+' are excluded.
		# The subset separator is added here and cannot be caller-controlled.
		if byte <= 0x20 or byte >= 0x7f or byte == 0x23 or byte == 0x25 or byte == 0x28 or byte == 0x29 or byte == 0x2b or byte == 0x2f or byte == 0x3c or byte == 0x3e or byte == 0x5b or byte == 0x5d or byte == 0x7b or byte == 0x7d {
			$valid = False
		}
		$index = $index + 1
	}
	$valid
}

add_scaled_integer : KernelObject.Builder, I64, U16 -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelPdfFont.Error)
add_scaled_integer = |builder, value, units_per_em| {
	scaled = scale_signed(value, units_per_em)?
	added = KernelObject.add_integer(builder, scaled) ? Object
	Ok(added)
}

scale_signed : I64, U16 -> Try(I64, KernelPdfFont.Error)
scale_signed = |value, units_per_em| {
	if units_per_em == 0 {
		return Err(InvalidDescriptor)
	}
	negative = value < 0
	magnitude = if negative {
		# Convert the two's-complement representation without negating I64.lowest.
		value.to_u64_wrap().bitwise_xor(U64.highest) + 1
	} else {
		value.to_u64_wrap()
	}
	product = checked_times(magnitude, 1000)?
	rounded = checked_add(product, units_per_em.to_u64() / 2)?
	scaled = U64.div_by(rounded, units_per_em.to_u64())
	if scaled > I64.highest.to_u64_wrap() {
		Err(ArithmeticOverflow)
	} else if negative {
		Ok(0 - scaled.to_i64_wrap())
	} else {
		Ok(scaled.to_i64_wrap())
	}
}

scale_unsigned : U16, U16 -> Try(U64, KernelPdfFont.Error)
scale_unsigned = |value, units_per_em| {
	if units_per_em == 0 {
		return Err(InvalidDescriptor)
	}
	product = checked_times(value.to_u64(), 1000)?
	rounded = checked_add(product, units_per_em.to_u64() / 2)?
	Ok(U64.div_by(rounded, units_per_em.to_u64()))
}

append_ascii : List(U8), Str -> List(U8)
append_ascii = |bytes, text| append_all(bytes, Str.to_utf8(text))

append_u64_decimal : List(U8), U64 -> List(U8)
append_u64_decimal = |bytes, value| {
	if value == 0 {
		return bytes.append(0x30)
	}
	var $divisor = 1
	while value / $divisor >= 10 {
		$divisor = $divisor * 10
	}
	var $bytes = bytes
	while $divisor > 0 {
		digit = value / $divisor % 10
		$bytes = $bytes.append(0x30 + digit.to_u8_wrap())
		$divisor = $divisor / 10
	}
	$bytes
}

append_hex_u16 : List(U8), U16 -> List(U8)
append_hex_u16 = |bytes, value| {
	var $result = bytes
	$result = $result.append(hex_digit(value.shr_wrap(12).to_u8_wrap()))
	$result = $result.append(hex_digit(value.shr_wrap(8).bitwise_and(0xf).to_u8_wrap()))
	$result = $result.append(hex_digit(value.shr_wrap(4).bitwise_and(0xf).to_u8_wrap()))
	$result.append(hex_digit(value.bitwise_and(0xf).to_u8_wrap()))
}

hex_digit : U8 -> U8
hex_digit = |value| if value < 10 0x30 + value else 0x41 + value - 10

append_u16 : List(U8), U16 -> List(U8)
append_u16 = |bytes, value| bytes.append(value.shr_wrap(8).to_u8_wrap()).append(value.to_u8_wrap())

append_all : List(U8), List(U8) -> List(U8)
append_all = |target, source| {
	var $result = target
	var $index = 0
	while $index < source.len() {
		$result = $result.append(list_at(source, $index))
		$index = $index + 1
	}
	$result
}

checked_add : U64, U64 -> Try(U64, KernelPdfFont.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_times : U64, U64 -> Try(U64, KernelPdfFont.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated PDF font index escaped"
	}
	Ok(value) => value
}

to_unicode_header : Str
to_unicode_header = "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n"

to_unicode_footer : Str
to_unicode_footer = "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n"

expect append_hex_u16([], 0x04e9) == Str.to_utf8("04E9")

expect append_scalar_utf16_hex([], 0x1f600)? == Str.to_utf8("D83DDE00")
