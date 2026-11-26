import KernelLex
import KernelObject
import KernelWidgetFields

## ISO 32000-2:2020 12.5.5, 12.5.6.19, 12.7.2–12.7.4, 12.7.5.3.
## The AcroForm points to one combined terminal-field/widget dictionary
## per validated field. The shared editable face covers the entire accepted
## repertoire independently of the value that happens to be initial.
KernelWidgetObjects :: [].{
	Error : [
		InvalidPlan,
		Object(KernelObject.Error),
	]

	Slot : { appearance : KernelObject.ObjectId, field : KernelWidgetFields.Field, widget : KernelObject.ObjectId }
	Plan : {
		descriptor : KernelObject.ObjectId,
		font : KernelWidgetFields.EditableFont,
		font_object : KernelObject.ObjectId,
		font_stream : KernelObject.ObjectId,
		slots : List(Slot),
		to_unicode : KernelObject.ObjectId,
		xref : KernelObject.ObjectId,
	}

	Selection : [NoWidgetPlan, WithWidgetPlan(Plan)]
	Prepared : [NoPreparedWidgets, WithPreparedWidgets(KernelWidgetFields.Plan)]
	Evidence : [NoWidgetEvidence, WidgetEvidence({ acro_form_edge : U64, editable_font_value : U64, widget_values : List(U64) })]

	plan : Prepared, U64 -> Try(Selection, Error)
	plan = |selection, previous_objects| match selection {
		NoPreparedWidgets => Ok(NoWidgetPlan)
		WithPreparedWidgets(prepared) => {
			fields = KernelWidgetFields.Plan.fields(prepared)
			if fields.is_empty() or previous_objects > U64.highest - 7 - 3 * fields.len() {
				return Err(InvalidPlan)
			}
			font_stream = object_id(previous_objects + 1)?
			to_unicode = object_id(previous_objects + 3)?
			descriptor = object_id(previous_objects + 5)?
			font_object = object_id(previous_objects + 6)?
			var $next = previous_objects + 7
			var $slots = List.with_capacity(fields.len())
			for field in fields {
				appearance = object_id($next)?
				widget = object_id($next + 2)?
				$slots = $slots.append({ appearance, field, widget })
				$next = $next + 3
			}
			xref = object_id($next)?
			Ok(WithWidgetPlan({ descriptor, font: KernelWidgetFields.Plan.font(prepared), font_object, font_stream, slots: $slots, to_unicode, xref }))
		}
	}

	catalog_entry : KernelObject.Builder, Plan -> Try({ builder : KernelObject.Builder, entry : KernelObject.DictionaryEntry }, Error)
	catalog_entry = |builder, prepared| {
		var $builder = builder
		var $refs = List.with_capacity(prepared.slots.len())
		for slot in prepared.slots {
			ref = KernelObject.add_reference($builder, slot.widget) ? Object
			$builder = ref.builder
			$refs = $refs.append(ref.id)
		}
		fields = KernelObject.add_array($builder, $refs) ? Object
		appearance = text(fields.builder, default_appearance)?
		dr = font_resources(appearance.builder, prepared.font_object)?
		form = dictionary(dr.builder, [{ key: "DA", value: appearance.id }, { key: "DR", value: dr.id }, { key: "Fields", value: fields.id }])?
		key = KernelObject.add_name(form.builder, Str.to_utf8("AcroForm")) ? Object
		Ok({ builder: key.builder, entry: { key: key.id, value: form.id } })
	}

	lower : KernelObject.Builder, Plan, { catalog : KernelObject.ObjectId, content_streams : U64, pages : List(KernelObject.ObjectId) } -> Try({ builder : KernelObject.Builder, evidence : Evidence }, Error)
	lower = |builder, prepared, context| {
		var $builder = add_editable_font(builder, prepared)?
		resources = font_resources($builder, prepared.font_object)?
		default = text(resources.builder, default_appearance)?
		$builder = default.builder
		var $slot = 0
		for slot in prepared.slots {
			page = context.pages.get(slot.field.location.page) ? |_| InvalidPlan
			$builder = add_text_widget($builder, slot, page, context.content_streams + $slot, { resources: resources.id, default: default.id })?
			$slot = $slot + 1
		}
		if KernelObject.counts($builder).objects + 1 != KernelObject.ObjectId.number(prepared.xref) {
			return Err(InvalidPlan)
		}
		evidence = check_lowered($builder.store, prepared, context)?
		Ok({ builder: $builder, evidence })
	}

	## The monotone widget value IDs let archive validation scope its widget
	## exception without another object scan or per-field linear search.
	allows_widget : Evidence, U64 -> Bool
	allows_widget = |evidence, position| match evidence {
		NoWidgetEvidence => False
		WidgetEvidence({ widget_values, .. }) => has_sorted(widget_values, position)
	}
}

default_appearance : Str
default_appearance = "0 0 0 rg /Ftx 10 Tf"

add_editable_font : KernelObject.Builder, KernelWidgetObjects.Plan -> Try(KernelObject.Builder, KernelWidgetObjects.Error)
add_editable_font = |builder, { font, font_stream, to_unicode, descriptor, font_object, .. }| {
	length = KernelObject.add_integer(builder, font.bytes.len().to_i64_wrap()) ? Object
	program_fields = entries(length.builder, [{ key: "Length1", value: length.id }])?
	program = KernelObject.add_payload(program_fields.builder, font.bytes, Generated) ? Object
	stream = KernelObject.add_stream_object(program.builder, program_fields.entries, Deflate, program.id) ? Object
	ensure(stream.id, font_stream)?
	mapping = KernelObject.add_payload(stream.builder, Str.to_utf8(ascii_cmap), Generated) ? Object
	cmap = KernelObject.add_stream_object(mapping.builder, [], Deflate, mapping.id) ? Object
	ensure(cmap.id, to_unicode)?

	types = name_value(cmap.builder, "FontDescriptor")?
	base = name_value(types.builder, font.name)?
	font_file = KernelObject.add_reference(base.builder, font_stream) ? Object
	bbox = integer_array(font_file.builder, font.metrics.bbox)?
	ascent = KernelObject.add_integer(bbox.builder, font.metrics.ascent) ? Object
	descent = KernelObject.add_integer(ascent.builder, font.metrics.descent) ? Object
	cap = KernelObject.add_integer(descent.builder, font.metrics.cap_height) ? Object
	flags = KernelObject.add_integer(cap.builder, 32) ? Object
	angle = KernelObject.add_integer(flags.builder, 0) ? Object
	stem = KernelObject.add_integer(angle.builder, 80) ? Object
	desc_dict = dictionary(
		stem.builder,
		[
			{ key: "Ascent", value: ascent.id },
			{ key: "CapHeight", value: cap.id },
			{ key: "Descent", value: descent.id },
			{ key: "Flags", value: flags.id },
			{ key: "FontBBox", value: bbox.id },
			{ key: "FontFile2", value: font_file.id },
			{ key: "FontName", value: base.id },
			{ key: "ItalicAngle", value: angle.id },
			{ key: "StemV", value: stem.id },
			{ key: "Type", value: types.id },
		],
	)?
	desc = KernelObject.add_object(desc_dict.builder, desc_dict.id) ? Object
	ensure(desc.id, descriptor)?

	font_type = name_value(desc.builder, "Font")?
	font_subtype = name_value(font_type.builder, "TrueType")?
	encoding = name_value(font_subtype.builder, "WinAnsiEncoding")?
	widths = integer_array(encoding.builder, font.widths)?
	first = KernelObject.add_integer(widths.builder, 32) ? Object
	last = KernelObject.add_integer(first.builder, 126) ? Object
	fdesc = KernelObject.add_reference(last.builder, descriptor) ? Object
	unicode = KernelObject.add_reference(fdesc.builder, to_unicode) ? Object
	font_dict = dictionary(
		unicode.builder,
		[
			{ key: "BaseFont", value: base.id },
			{ key: "Encoding", value: encoding.id },
			{ key: "FirstChar", value: first.id },
			{ key: "FontDescriptor", value: fdesc.id },
			{ key: "LastChar", value: last.id },
			{ key: "Subtype", value: font_subtype.id },
			{ key: "ToUnicode", value: unicode.id },
			{ key: "Type", value: font_type.id },
			{ key: "Widths", value: widths.id },
		],
	)?
	font_indirect = KernelObject.add_object(font_dict.builder, font_dict.id) ? Object
	ensure(font_indirect.id, font_object)?
	Ok(font_indirect.builder)
}

ascii_cmap : Str
ascii_cmap = "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n/CMapName /ROCPdfWidgetASCII def\n/CMapType 2 def\n1 begincodespacerange\n<20> <7E>\nendcodespacerange\n1 beginbfrange\n<20> <7E> <0020>\nendbfrange\nendcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n"

add_text_widget : KernelObject.Builder, KernelWidgetObjects.Slot, KernelObject.ObjectId, U64, { resources : KernelObject.ValueId, default : KernelObject.ValueId } -> Try(KernelObject.Builder, KernelWidgetObjects.Error)
add_text_widget = |builder, slot, page, structure_parent, values| {
	{ origin, size } = slot.field.widget
	width = size.width.raw()
	height = size.height.raw()
	bbox = decimal_array(builder, [0, 0, width, height])?
	xobject = name_value(bbox.builder, "XObject")?
	form = name_value(xobject.builder, "Form")?
	appearance_fields = entries(
		form.builder,
		[
			{ key: "BBox", value: bbox.id },
			{ key: "Resources", value: values.resources },
			{ key: "Subtype", value: form.id },
			{ key: "Type", value: xobject.id },
		],
	)?
	appearance_bytes = text_appearance(width, height, slot.field.value)?
	appearance = KernelObject.add_payload(appearance_fields.builder, appearance_bytes, Generated) ? Object
	stream = KernelObject.add_stream_object(appearance.builder, appearance_fields.entries, Deflate, appearance.id) ? Object
	ensure(stream.id, slot.appearance)?
	normal = KernelObject.add_reference(stream.builder, slot.appearance) ? Object
	ap = dictionary(normal.builder, [{ key: "N", value: normal.id }])?
	flags = KernelObject.add_integer(ap.builder, 4) ? Object
	field_type = name_value(flags.builder, "Tx")?
	field_flags = KernelObject.add_integer(field_type.builder, 0) ? Object
	max_len = KernelObject.add_integer(field_flags.builder, KernelWidgetFields.max_characters.to_i64_wrap()) ? Object
	characteristics = appearance_characteristics(max_len.builder)?
	page_ref = KernelObject.add_reference(characteristics.builder, page) ? Object
	rect = decimal_array(page_ref.builder, [origin.x.raw(), origin.y.raw(), origin.x.raw() + width, origin.y.raw() + height])?
	owner = KernelObject.add_integer(rect.builder, structure_parent.to_i64_wrap()) ? Object
	subtype = name_value(owner.builder, "Widget")?
	name = text(subtype.builder, slot.field.id)?
	label = text(name.builder, slot.field.label)?
	annot = name_value(label.builder, "Annot")?
	value = text(annot.builder, slot.field.value)?
	widget_dict = dictionary(
		value.builder,
		[
			{ key: "AP", value: ap.id },
			{ key: "DA", value: values.default },
			{ key: "F", value: flags.id },
			{ key: "FT", value: field_type.id },
			{ key: "Ff", value: field_flags.id },
			{ key: "MK", value: characteristics.id },
			{ key: "MaxLen", value: max_len.id },
			{ key: "P", value: page_ref.id },
			{ key: "Rect", value: rect.id },
			{ key: "StructParent", value: owner.id },
			{ key: "Subtype", value: subtype.id },
			{ key: "T", value: name.id },
			{ key: "TU", value: label.id },
			{ key: "Type", value: annot.id },
			{ key: "V", value: value.id },
		],
	)?
	widget = KernelObject.add_object(widget_dict.builder, widget_dict.id) ? Object
	ensure(widget.id, slot.widget)?
	Ok(widget.builder)
}

appearance_characteristics : KernelObject.Builder -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelWidgetObjects.Error)
appearance_characteristics = |builder| {
	border = integer_array(builder, [0, 0, 0])?
	background = integer_array(border.builder, [1, 1, 1])?
	dictionary(background.builder, [{ key: "BC", value: border.id }, { key: "BG", value: background.id }])
}

font_resources : KernelObject.Builder, KernelObject.ObjectId -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelWidgetObjects.Error)
font_resources = |builder, font| {
	font_ref = KernelObject.add_reference(builder, font) ? Object
	font_dict = dictionary(font_ref.builder, [{ key: "Ftx", value: font_ref.id }])?
	dictionary(font_dict.builder, [{ key: "Font", value: font_dict.id }])
}

text_appearance : I64, I64, Str -> Try(List(U8), KernelWidgetObjects.Error)
text_appearance = |width, height, content| {
	inner_width = KernelLex.Decimal.from_coefficient(width - 1000, 3) ? |_| InvalidPlan
	inner_height = KernelLex.Decimal.from_coefficient(height - 1000, 3) ? |_| InvalidPlan
	escaped = KernelLex.text_string(content) ? |_| InvalidPlan
	var $bytes = List.with_capacity(240 + escaped.len())
	$bytes = append($bytes, Str.to_utf8("q\n1 1 1 rg\n0 0 0 RG\n1 w\n0.5 0.5 "))
	$bytes = KernelLex.append_real($bytes, inner_width).append(32)
	$bytes = KernelLex.append_real($bytes, inner_height)
	$bytes = append($bytes, Str.to_utf8(" re B\nQ\n/Tx BMC\nq\nBT\n"))
	$bytes = append($bytes, Str.to_utf8(default_appearance))
	$bytes = append($bytes, Str.to_utf8("\n4 7 Td\n"))
	$bytes = append($bytes, escaped)
	Ok(append($bytes, Str.to_utf8(" Tj\nET\nQ\nEMC\n")))
}

Entry : { key : Str, value : KernelObject.ValueId }

Added : { builder : KernelObject.Builder, id : KernelObject.ValueId }

entries : KernelObject.Builder, List(Entry) -> Try({ builder : KernelObject.Builder, entries : List(KernelObject.DictionaryEntry) }, KernelWidgetObjects.Error)
entries = |builder, fields| {
	var $builder = builder
	var $entries = List.with_capacity(fields.len())
	for field in fields {
		key = KernelObject.add_name($builder, Str.to_utf8(field.key)) ? Object
		$builder = key.builder
		$entries = $entries.append({ key: key.id, value: field.value })
	}
	Ok({ builder: $builder, entries: $entries })
}

dictionary : KernelObject.Builder, List(Entry) -> Try(Added, KernelWidgetObjects.Error)
dictionary = |builder, fields| {
	added = entries(builder, fields)?
	KernelObject.add_dictionary(added.builder, added.entries).map_err(|error| Object(error))
}

integer_array : KernelObject.Builder, List(I64) -> Try(Added, KernelWidgetObjects.Error)
integer_array = |builder, numbers| {
	var $builder = builder
	var $values = List.with_capacity(numbers.len())
	for number in numbers {
		value = KernelObject.add_integer($builder, number) ? Object
		$builder = value.builder
		$values = $values.append(value.id)
	}
	KernelObject.add_array($builder, $values).map_err(|error| Object(error))
}

decimal_array : KernelObject.Builder, List(I64) -> Try(Added, KernelWidgetObjects.Error)
decimal_array = |builder, numbers| {
	var $builder = builder
	var $values = List.with_capacity(numbers.len())
	for number in numbers {
		decimal = KernelLex.Decimal.from_coefficient(number, 3) ? |_| InvalidPlan
		value = KernelObject.add_real($builder, decimal) ? Object
		$builder = value.builder
		$values = $values.append(value.id)
	}
	KernelObject.add_array($builder, $values).map_err(|error| Object(error))
}

name_value : KernelObject.Builder, Str -> Try(Added, KernelWidgetObjects.Error)
name_value = |builder, value| {
	id = KernelObject.add_name(builder, Str.to_utf8(value)) ? Object
	KernelObject.add_name_value(id.builder, id.id).map_err(|error| Object(error))
}

text : KernelObject.Builder, Str -> Try(Added, KernelWidgetObjects.Error)
text = |builder, value| {
	id = KernelObject.add_text_string(builder, value) ? Object
	KernelObject.add_text_string_value(id.builder, id.id).map_err(|error| Object(error))
}

append : List(U8), List(U8) -> List(U8)
append = |out, bytes| {
	var $output = out
	for byte in bytes {
		$output = $output.append(byte)
	}
	$output
}

object_id : U64 -> Try(KernelObject.ObjectId, KernelWidgetObjects.Error)
object_id = |number| KernelObject.ObjectId.from_number(number).map_err(|error| Object(error))

ensure : KernelObject.ObjectId, KernelObject.ObjectId -> Try({}, KernelWidgetObjects.Error)
ensure = |actual, expected| if (actual == expected) Ok({}) else Err(InvalidPlan)

## Validate the closed catalog, default-resource and widget associations before
## sealing. Existing tagged object validation owns OBJR/ParentTree and checks
## that each dense annotation ID maps to its one semantic owner.
check_lowered : KernelObject.Store, KernelWidgetObjects.Plan, { catalog : KernelObject.ObjectId, content_streams : U64, pages : List(KernelObject.ObjectId) } -> Try(KernelWidgetObjects.Evidence, KernelWidgetObjects.Error)
check_lowered = |store, planned, context| {
	catalog = object_dictionary(store, context.catalog)?
	acro = find_field(store, catalog, "AcroForm")?
	form = as_dictionary(value_at(store, acro.value)?)?
	if form.length != 3 or !text_matches(store, field(store, form, "DA")?, default_appearance)? {
		return Err(InvalidPlan)
	}
	resources = as_dictionary(field(store, form, "DR")?)?
	verify_font_resources(store, resources, planned.font_object)?
	field_values = as_array(field(store, form, "Fields")?)?
	if field_values.length != planned.slots.len() {
		return Err(InvalidPlan)
	}
	font_value = stored_id(store, planned.font_object)?
	font = as_dictionary(value_at(store, font_value)?)?
	if !name_matches(store, field(store, font, "Subtype")?, "TrueType")?
		or !name_matches(store, field(store, font, "Encoding")?, "WinAnsiEncoding")?
		or !ref_matches(field(store, font, "FontDescriptor")?, planned.descriptor)
		or !ref_matches(field(store, font, "ToUnicode")?, planned.to_unicode)
		or !int_matches(field(store, font, "FirstChar")?, 32)
		or !int_matches(field(store, font, "LastChar")?, 126) {
		return Err(InvalidPlan)
	}
	widths = as_array(field(store, font, "Widths")?)?
	if widths.length != planned.font.widths.len() {
		return Err(InvalidPlan)
	}
	var $width = 0
	for expected in planned.font.widths {
		if !int_matches(array_at(store, widths, $width)?, expected) {
			return Err(InvalidPlan)
		}
		$width = $width + 1
	}
	var $slot = 0
	var $page = 0
	var $widget_values = List.with_capacity(planned.slots.len())
	for page in context.pages {
		first = $slot
		while $slot < planned.slots.len() {
			slot = planned.slots.get($slot) ? |_| InvalidPlan
			if slot.field.location.page != $page {
				break
			}
			if !ref_matches(array_at(store, field_values, $slot)?, slot.widget) {
				return Err(InvalidPlan)
			}
			widget_value = stored_id(store, slot.widget)?
			verify_widget(store, slot, widget_value, page, context.content_streams + $slot, planned.font_object)?
			$widget_values = $widget_values.append(KernelObject.ValueId.index(widget_value))
			$slot = $slot + 1
		}
		if first < $slot {
			fields = object_dictionary(store, page)?
			annots = as_array(field(store, fields, "Annots")?)?
			if annots.length != $slot - first or !name_matches(store, field(store, fields, "Tabs")?, "S")? {
				return Err(InvalidPlan)
			}
			var $annotation = 0
			while $annotation < annots.length {
				expected = planned.slots.get(first + $annotation) ? |_| InvalidPlan
				if !ref_matches(array_at(store, annots, $annotation)?, expected.widget) {
					return Err(InvalidPlan)
				}
				$annotation = $annotation + 1
			}
		}
		$page = $page + 1
	}
	if $slot != planned.slots.len() {
		return Err(InvalidPlan)
	}
	Ok(WidgetEvidence({ acro_form_edge: acro.edge, editable_font_value: KernelObject.ValueId.index(font_value), widget_values: $widget_values }))
}

verify_widget : KernelObject.Store, KernelWidgetObjects.Slot, KernelObject.ValueId, KernelObject.ObjectId, U64, KernelObject.ObjectId -> Try({}, KernelWidgetObjects.Error)
verify_widget = |store, slot, id, page, struct_parent, font| {
	entries_value = as_dictionary(value_at(store, id)?)?
	types = field(store, entries_value, "Type")?
	if !name_matches(store, types, "Annot")?
		or !name_matches(store, field(store, entries_value, "Subtype")?, "Widget")?
		or !name_matches(store, field(store, entries_value, "FT")?, "Tx")?
		or !text_matches(store, field(store, entries_value, "DA")?, default_appearance)?
		or !int_matches(field(store, entries_value, "F")?, 4)
		or !int_matches(field(store, entries_value, "Ff")?, 0)
		or !int_matches(field(store, entries_value, "MaxLen")?, KernelWidgetFields.max_characters.to_i64_wrap())
		or !text_matches(store, field(store, entries_value, "T")?, slot.field.id)?
		or !text_matches(store, field(store, entries_value, "TU")?, slot.field.label)?
		or !text_matches(store, field(store, entries_value, "V")?, slot.field.value)?
		or !ref_matches(field(store, entries_value, "P")?, page)
		or !int_matches(field(store, entries_value, "StructParent")?, struct_parent.to_i64_wrap()) {
		return Err(InvalidPlan)
	}
	{ origin, size } = slot.field.widget
	x = origin.x.raw()
	y = origin.y.raw()
	w = size.width.raw()
	h = size.height.raw()
	verify_box(store, field(store, entries_value, "Rect")?, [x, y, x + w, y + h])?
	appearance = as_dictionary(field(store, entries_value, "AP")?)?
	if appearance.length != 1 or !ref_matches(field(store, appearance, "N")?, slot.appearance) {
		return Err(InvalidPlan)
	}
	stream_id = match value_at(store, stored_id(store, slot.appearance)?)? {
		Stream(stream) => stream
		_ => return Err(InvalidPlan)
	}
	stream = store.streams.get(KernelObject.StreamId.index(stream_id)) ? |_| InvalidPlan
	if stream.object != slot.appearance or !name_matches(store, field(store, stream.dictionary, "Type")?, "XObject")?
		or !name_matches(store, field(store, stream.dictionary, "Subtype")?, "Form")? {
		return Err(InvalidPlan)
	}
	verify_box(store, field(store, stream.dictionary, "BBox")?, [0, 0, w, h])?
	verify_font_resources(store, as_dictionary(field(store, stream.dictionary, "Resources")?)?, font)
}

verify_box : KernelObject.Store, KernelObject.Value, List(I64) -> Try({}, KernelWidgetObjects.Error)
verify_box = |store, value, expected| {
	array = as_array(value)?
	if array.length != expected.len() {
		return Err(InvalidPlan)
	}
	var $index = 0
	for coordinate in expected {
		match array_at(store, array, $index)? {
			Real(decimal) if KernelLex.Decimal.coefficient(decimal) == coordinate and KernelLex.Decimal.scale(decimal) == 3 => {}
			_ => return Err(InvalidPlan)
		}
		$index = $index + 1
	}
	Ok({})
}

verify_font_resources : KernelObject.Store, KernelObject.Span, KernelObject.ObjectId -> Try({}, KernelWidgetObjects.Error)
verify_font_resources = |store, resources, expected| {
	fonts = as_dictionary(field(store, resources, "Font")?)?
	if resources.length != 1 or fonts.length != 1 or !ref_matches(field(store, fonts, "Ftx")?, expected) {
		return Err(InvalidPlan)
	}
	Ok({})
}

stored_id : KernelObject.Store, KernelObject.ObjectId -> Try(KernelObject.ValueId, KernelWidgetObjects.Error)
stored_id = |store, id| {
	object = store.objects.get(KernelObject.ObjectId.number(id) - 1) ? |_| InvalidPlan
	match object.content {
		Stored(value) => Ok(value)
		LengthOf(_) => Err(InvalidPlan)
	}
}

value_at : KernelObject.Store, KernelObject.ValueId -> Try(KernelObject.Value, KernelWidgetObjects.Error)
value_at = |store, id| store.values.get(KernelObject.ValueId.index(id)).map_err(|_| InvalidPlan)

object_dictionary : KernelObject.Store, KernelObject.ObjectId -> Try(KernelObject.Span, KernelWidgetObjects.Error)
object_dictionary = |store, id| as_dictionary(value_at(store, stored_id(store, id)?)?)

as_dictionary : KernelObject.Value -> Try(KernelObject.Span, KernelWidgetObjects.Error)
as_dictionary = |value| match value {
	Dictionary(span) => Ok(span)
	_ => Err(InvalidPlan)
}

as_array : KernelObject.Value -> Try(KernelObject.Span, KernelWidgetObjects.Error)
as_array = |value| match value {
	Array(span) => Ok(span)
	_ => Err(InvalidPlan)
}

array_at : KernelObject.Store, KernelObject.Span, U64 -> Try(KernelObject.Value, KernelWidgetObjects.Error)
array_at = |store, span, index| {
	if index >= span.length {
		return Err(InvalidPlan)
	}
	value_at(store, store.array_items.get(span.start + index) ? |_| InvalidPlan)
}

field : KernelObject.Store, KernelObject.Span, Str -> Try(KernelObject.Value, KernelWidgetObjects.Error)
field = |store, span, key| value_at(store, find_field(store, span, key)?.value)

find_field : KernelObject.Store, KernelObject.Span, Str -> Try({ edge : U64, value : KernelObject.ValueId }, KernelWidgetObjects.Error)
find_field = |store, span, key| {
	name = Str.to_utf8(key)
	var $index = 0
	while $index < span.length {
		edge = span.start + $index
		entry = store.dictionary_entries.get(edge) ? |_| InvalidPlan
		key_name = store.names.get(KernelObject.NameId.index(entry.key)) ? |_| InvalidPlan
		if KernelLex.Name.bytes(key_name) == name {
			return Ok({ edge, value: entry.value })
		}
		$index = $index + 1
	}
	Err(InvalidPlan)
}

name_matches : KernelObject.Store, KernelObject.Value, Str -> Try(Bool, KernelWidgetObjects.Error)
name_matches = |store, value, expected| match value {
	Name(id) => {
		name = store.names.get(KernelObject.NameId.index(id)) ? |_| InvalidPlan
		Ok(KernelLex.Name.bytes(name) == Str.to_utf8(expected))
	}
	_ => Ok(False)
}

text_matches : KernelObject.Store, KernelObject.Value, Str -> Try(Bool, KernelWidgetObjects.Error)
text_matches = |store, value, expected| match value {
	TextString(id) => {
		text_value = store.text_strings.get(KernelObject.TextStringId.index(id)) ? |_| InvalidPlan
		Ok(KernelLex.Text.bytes(text_value) == Str.to_utf8(expected))
	}
	_ => Ok(False)
}

ref_matches : KernelObject.Value, KernelObject.ObjectId -> Bool
ref_matches = |value, expected| match value {
	Reference(id) => id == expected
	_ => False
}

int_matches : KernelObject.Value, I64 -> Bool
int_matches = |value, expected| match value {
	Integer(number) => number == expected
	_ => False
}

has_sorted : List(U64), U64 -> Bool
has_sorted = |values, wanted| {
	var $low = 0
	var $high = values.len()
	while $low < $high {
		middle = $low + ($high - $low) // 2
		number = values.get(middle) ?? crash "validated widget index range"
		if number == wanted {
			return True
		} else if number < wanted {
			$low = middle + 1
		} else {
			$high = middle
		}
	}
	False
}
