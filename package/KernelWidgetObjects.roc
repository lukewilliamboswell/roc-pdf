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

	Slot : { appearance : [TextAppearance(KernelObject.ObjectId), CheckboxAppearance], field : KernelWidgetFields.Field, widget : KernelObject.ObjectId }
	TextObjects : {
		descriptor : KernelObject.ObjectId,
		font : KernelWidgetFields.EditableFont,
		font_object : KernelObject.ObjectId,
		font_stream : KernelObject.ObjectId,
		to_unicode : KernelObject.ObjectId,
	}
	CheckboxObjects : { off : KernelObject.ObjectId, yes : KernelObject.ObjectId }
	EditableFontPlan : [NoTextObjects, WithTextObjects(TextObjects)]
	CheckboxPlan : [NoCheckboxObjects, WithCheckboxObjects(CheckboxObjects)]
	Plan : {
		text_objects : EditableFontPlan,
		checkbox_objects : CheckboxPlan,
		slots : List(Slot),
		text_capacity : TextCapacity,
		xref : KernelObject.ObjectId,
	}

	Selection : [NoWidgetPlan, WithWidgetPlan(Plan)]
	Prepared : [NoPreparedWidgets, WithPreparedWidgets(KernelWidgetFields.Plan)]
	Evidence : [NoWidgetEvidence, WidgetEvidence({ acro_form_edge : U64, editable_font_value : [NoEditableFontValue, EditableFontValue(U64)], widget_values : List(U64) })]

	plan : Prepared, U64 -> Try(Selection, Error)
	plan = |selection, previous_objects| match selection {
		NoPreparedWidgets => Ok(NoWidgetPlan)
		WithPreparedWidgets(prepared) => {
			fields = KernelWidgetFields.Plan.fields(prepared)
			if fields.is_empty() or previous_objects > U64.highest - 11 or fields.len() > (U64.highest - 11 - previous_objects) // 3 {
				return Err(InvalidPlan)
			}
			{ text_objects, first_widget_resource } = match KernelWidgetFields.Plan.font(prepared) {
				NoEditableFont => { text_objects: NoTextObjects, first_widget_resource: previous_objects + 1 }
				WithEditableFont(font) => {
					font_stream = object_id(previous_objects + 1)?
					to_unicode = object_id(previous_objects + 3)?
					descriptor = object_id(previous_objects + 5)?
					font_object = object_id(previous_objects + 6)?
					{ text_objects: WithTextObjects({ descriptor, font, font_object, font_stream, to_unicode }), first_widget_resource: previous_objects + 7 }
				}
			}
			{ checkbox_objects, first_widget } = if fields.any(
				|field| match field.value {
					Checkbox(_) => True
					Text(_) => False
				},
			) {
				off = object_id(first_widget_resource)?
				yes = object_id(first_widget_resource + 2)?
				{ checkbox_objects: WithCheckboxObjects({ off, yes }), first_widget: first_widget_resource + 4 }
			} else {
				{ checkbox_objects: NoCheckboxObjects, first_widget: first_widget_resource }
			}
			var $next = first_widget
			# The catalog writes its DA into the fresh store alongside the
			# document language and output intent. Count the DA lowered later.
			var $text_count = match text_objects {
				NoTextObjects => 0
				WithTextObjects(_) => 1
			}
			var $text_bytes = $text_count * default_appearance.count_utf8_bytes()
			var $slots = List.with_capacity(fields.len())
			for field in fields {
				slot = match field.value {
					Text(value) => {
						appearance = object_id($next)?
						widget = object_id($next + 2)?
						{ plan: { appearance: TextAppearance(appearance), field, widget }, next: $next + 3, text_count: 3, value_bytes: value.count_utf8_bytes() }
					}
					Checkbox(_) => {
						widget = object_id($next)?
						{ plan: { appearance: CheckboxAppearance, field, widget }, next: $next + 1, text_count: 2, value_bytes: 0 }
					}
				}
				$text_count = $text_count + slot.text_count
				$text_bytes = add_text_bytes($text_bytes, slot.value_bytes)?
				$text_bytes = add_text_bytes($text_bytes, field.id.count_utf8_bytes())?
				$text_bytes = add_text_bytes($text_bytes, field.label.count_utf8_bytes())?
				$slots = $slots.append(slot.plan)
				$next = slot.next
			}
			xref = object_id($next)?
			Ok(WithWidgetPlan({ checkbox_objects, text_objects, slots: $slots, text_capacity: { count: $text_count, bytes: $text_bytes }, xref }))
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
		form = match prepared.text_objects {
			NoTextObjects => dictionary(fields.builder, [{ key: "Fields", value: fields.id }])?
			WithTextObjects(font) => {
				appearance = text(fields.builder, default_appearance)?
				dr = font_resources(appearance.builder, font.font_object)?
				dictionary(dr.builder, [{ key: "DA", value: appearance.id }, { key: "DR", value: dr.id }, { key: "Fields", value: fields.id }])?
			}
		}
		key = KernelObject.add_name(form.builder, Str.to_utf8("AcroForm")) ? Object
		Ok({ builder: key.builder, entry: { key: key.id, value: form.id } })
	}

	lower : KernelObject.Builder, Plan, { catalog : KernelObject.ObjectId, content_streams : U64, pages : List(KernelObject.ObjectId) } -> Try({ builder : KernelObject.Builder, evidence : Evidence }, Error)
	lower = |input, prepared, context| {
		builder = allow_widget_text(input, prepared.text_capacity)?
		{ text_values, after_text } = match prepared.text_objects {
			NoTextObjects => { text_values: NoTextValues, after_text: builder }
			WithTextObjects(font) => {
				font_builder = add_editable_font(builder, font)?
				resources = font_resources(font_builder, font.font_object)?
				default = text(resources.builder, default_appearance)?
				{ text_values: WithTextValues({ resources: resources.id, default: default.id }), after_text: default.builder }
			}
		}
		var $builder = match prepared.checkbox_objects {
			NoCheckboxObjects => after_text
			WithCheckboxObjects(checkboxes) => add_checkbox_appearances(after_text, checkboxes)?
		}
		var $slot = 0
		for slot in prepared.slots {
			page = context.pages.get(slot.field.location.page) ? |_| InvalidPlan
			structure_parent = context.content_streams + $slot
			match (slot.appearance, slot.field.value, text_values, prepared.checkbox_objects) {
				(TextAppearance(appearance), Text(value), WithTextValues(values), _) => {
					$builder = add_text_widget($builder, slot, page, structure_parent, { appearance, value, resources: values.resources, default: values.default })?
				}
				(CheckboxAppearance, Checkbox(state), _, WithCheckboxObjects(checkboxes)) => {
					$builder = add_checkbox_widget($builder, slot, page, structure_parent, checkboxes, state)?
				}
				_ => return Err(InvalidPlan)
			}
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

TextCapacity : { bytes : U64, count : U64 }

add_text_bytes : U64, U64 -> Try(U64, KernelWidgetObjects.Error)
add_text_bytes = |current, added| U64.plus_try(current, added).map_err(|_| Object(Overflow(TextStringBytes)))

## The shared builder has already enforced ordinary document text limits.
## Reserve room for the admitted IDs, labels, initial values, and shared DA.
allow_widget_text : KernelObject.Builder, TextCapacity -> Try(KernelObject.Builder, KernelWidgetObjects.Error)
allow_widget_text = |builder, capacity| {
	{ limits, store, total_text_string_bytes, .. } = builder
	count = U64.plus_try(store.text_strings.len(), capacity.count) ? |_| Object(Overflow(TextStrings))
	bytes = add_text_bytes(total_text_string_bytes, capacity.bytes)?
	Ok({
		..builder,
		limits: {
			..limits,
			max_text_strings: U64.max(limits.max_text_strings, count),
			max_text_string_bytes: U64.max(limits.max_text_string_bytes, bytes),
		},
	})
}

default_appearance : Str
default_appearance = "0 0 0 rg /Ftx 10 Tf"

add_editable_font : KernelObject.Builder, KernelWidgetObjects.TextObjects -> Try(KernelObject.Builder, KernelWidgetObjects.Error)
add_editable_font = |builder, { font, font_stream, to_unicode, descriptor, font_object }| {
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

add_text_widget : KernelObject.Builder, KernelWidgetObjects.Slot, KernelObject.ObjectId, U64, { resources : KernelObject.ValueId, default : KernelObject.ValueId, appearance : KernelObject.ObjectId, value : Str } -> Try(KernelObject.Builder, KernelWidgetObjects.Error)
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
	appearance_bytes = text_appearance(width, height, values.value)?
	appearance = KernelObject.add_payload(appearance_fields.builder, appearance_bytes, Generated) ? Object
	stream = KernelObject.add_stream_object(appearance.builder, appearance_fields.entries, Deflate, appearance.id) ? Object
	ensure(stream.id, values.appearance)?
	normal = KernelObject.add_reference(stream.builder, values.appearance) ? Object
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
	value = text(annot.builder, values.value)?
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

## ISO 32000-2:2020 12.7.5.2.3, ISO 19005-4:2020 6.3.3. Both normal
## appearances are present even if every field selects the same state.
## A checkbox-only form has no editable text font or default text resources.
checkbox_appearance : KernelWidgetFields.CheckState -> List(U8)
checkbox_appearance = |state| match state {
	Unchecked => Str.to_utf8("q\n1 1 1 rg\n0 0 0 RG\n1 w\n0.5 0.5 21 21 re B\nQ\n")
	Checked => Str.to_utf8("q\n1 1 1 rg\n0 0 0 RG\n1 w\n0.5 0.5 21 21 re B\n2 w\n1 J\n1 j\n5 11 m 9 7 l 17 15 l S\nQ\n")
}

checkbox_name : KernelWidgetFields.CheckState -> Str
checkbox_name = |state| match state {
	Unchecked => "Off"
	Checked => "Yes"
}

add_checkbox_appearances : KernelObject.Builder, KernelWidgetObjects.CheckboxObjects -> Try(KernelObject.Builder, KernelWidgetObjects.Error)
add_checkbox_appearances = |builder, planned| {
	bbox = decimal_array(builder, [0, 0, 22000, 22000])?
	resources = dictionary(bbox.builder, [])?
	xobject = name_value(resources.builder, "XObject")?
	form = name_value(xobject.builder, "Form")?
	fields = entries(
		form.builder,
		[
			{ key: "BBox", value: bbox.id },
			{ key: "Resources", value: resources.id },
			{ key: "Subtype", value: form.id },
			{ key: "Type", value: xobject.id },
		],
	)?
	off = KernelObject.add_payload(fields.builder, checkbox_appearance(Unchecked), Generated) ? Object
	off_stream = KernelObject.add_stream_object(off.builder, fields.entries, Deflate, off.id) ? Object
	ensure(off_stream.id, planned.off)?
	yes = KernelObject.add_payload(off_stream.builder, checkbox_appearance(Checked), Generated) ? Object
	yes_stream = KernelObject.add_stream_object(yes.builder, fields.entries, Deflate, yes.id) ? Object
	ensure(yes_stream.id, planned.yes)?
	Ok(yes_stream.builder)
}

add_checkbox_widget : KernelObject.Builder, KernelWidgetObjects.Slot, KernelObject.ObjectId, U64, KernelWidgetObjects.CheckboxObjects, KernelWidgetFields.CheckState -> Try(KernelObject.Builder, KernelWidgetObjects.Error)
add_checkbox_widget = |builder, slot, page, structure_parent, planned, state| {
	off = KernelObject.add_reference(builder, planned.off) ? Object
	yes = KernelObject.add_reference(off.builder, planned.yes) ? Object
	normal = dictionary(yes.builder, [{ key: "Off", value: off.id }, { key: "Yes", value: yes.id }])?
	ap = dictionary(normal.builder, [{ key: "N", value: normal.id }])?
	flags = KernelObject.add_integer(ap.builder, 4) ? Object
	field_type = name_value(flags.builder, "Btn")?
	field_flags = KernelObject.add_integer(field_type.builder, 0) ? Object
	page_ref = KernelObject.add_reference(field_flags.builder, page) ? Object
	{ origin, size } = slot.field.widget
	x = origin.x.raw()
	y = origin.y.raw()
	rect = decimal_array(page_ref.builder, [x, y, x + size.width.raw(), y + size.height.raw()])?
	owner = KernelObject.add_integer(rect.builder, structure_parent.to_i64_wrap()) ? Object
	subtype = name_value(owner.builder, "Widget")?
	name = text(subtype.builder, slot.field.id)?
	label = text(name.builder, slot.field.label)?
	annot = name_value(label.builder, "Annot")?
	value = name_value(annot.builder, checkbox_name(state))?
	widget_dict = dictionary(
		value.builder,
		[
			{ key: "AP", value: ap.id },
			{ key: "AS", value: value.id },
			{ key: "F", value: flags.id },
			{ key: "FT", value: field_type.id },
			{ key: "Ff", value: field_flags.id },
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
	font_value = match planned.text_objects {
		NoTextObjects if form.length == 1 => NoEditableFontValue
		NoTextObjects => return Err(InvalidPlan)
		WithTextObjects(font) => EditableFontValue(check_text_resources(store, form, font)?)
	}
	match planned.checkbox_objects {
		NoCheckboxObjects => {}
		WithCheckboxObjects(checkboxes) => {
			verify_checkbox_appearance(store, checkboxes.off, Unchecked)?
			verify_checkbox_appearance(store, checkboxes.yes, Checked)?
		}
	}
	field_values = as_array(field(store, form, "Fields")?)?
	if field_values.length != planned.slots.len() {
		return Err(InvalidPlan)
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
			verify_widget(store, slot, widget_value, page, context.content_streams + $slot, planned.text_objects, planned.checkbox_objects)?
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
	Ok(WidgetEvidence({ acro_form_edge: acro.edge, editable_font_value: font_value, widget_values: $widget_values }))
}

check_text_resources : KernelObject.Store, KernelObject.Span, KernelWidgetObjects.TextObjects -> Try(U64, KernelWidgetObjects.Error)
check_text_resources = |store, form, font_plan| {
	if form.length != 3 or !text_matches(store, field(store, form, "DA")?, default_appearance)? {
		return Err(InvalidPlan)
	}
	verify_font_resources(store, as_dictionary(field(store, form, "DR")?)?, font_plan.font_object)?
	font_value = stored_id(store, font_plan.font_object)?
	font = as_dictionary(value_at(store, font_value)?)?
	if !name_matches(store, field(store, font, "Subtype")?, "TrueType")?
		or !name_matches(store, field(store, font, "Encoding")?, "WinAnsiEncoding")?
		or !ref_matches(field(store, font, "FontDescriptor")?, font_plan.descriptor)
		or !ref_matches(field(store, font, "ToUnicode")?, font_plan.to_unicode)
		or !int_matches(field(store, font, "FirstChar")?, 32)
		or !int_matches(field(store, font, "LastChar")?, 126) {
		return Err(InvalidPlan)
	}
	widths = as_array(field(store, font, "Widths")?)?
	if widths.length != font_plan.font.widths.len() {
		return Err(InvalidPlan)
	}
	var $width = 0
	for expected in font_plan.font.widths {
		if !int_matches(array_at(store, widths, $width)?, expected) {
			return Err(InvalidPlan)
		}
		$width = $width + 1
	}
	Ok(KernelObject.ValueId.index(font_value))
}

verify_widget : KernelObject.Store, KernelWidgetObjects.Slot, KernelObject.ValueId, KernelObject.ObjectId, U64, KernelWidgetObjects.EditableFontPlan, KernelWidgetObjects.CheckboxPlan -> Try({}, KernelWidgetObjects.Error)
verify_widget = |store, slot, id, page, struct_parent, text_plan, checkbox_plan| {
	entries_value = as_dictionary(value_at(store, id)?)?
	types = field(store, entries_value, "Type")?
	if !name_matches(store, types, "Annot")?
		or !name_matches(store, field(store, entries_value, "Subtype")?, "Widget")?
		or !int_matches(field(store, entries_value, "F")?, 4)
		or !int_matches(field(store, entries_value, "Ff")?, 0)
		or !text_matches(store, field(store, entries_value, "T")?, slot.field.id)?
		or !text_matches(store, field(store, entries_value, "TU")?, slot.field.label)?
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
	if appearance.length != 1 {
		return Err(InvalidPlan)
	}
	normal = field(store, appearance, "N")?
	match (slot.appearance, slot.field.value, text_plan, checkbox_plan) {
		(TextAppearance(expected), Text(text_value), WithTextObjects(font), _) => {
			if !name_matches(store, field(store, entries_value, "FT")?, "Tx")?
				or !text_matches(store, field(store, entries_value, "DA")?, default_appearance)?
				or !int_matches(field(store, entries_value, "MaxLen")?, KernelWidgetFields.max_characters.to_i64_wrap())
				or !text_matches(store, field(store, entries_value, "V")?, text_value)?
				or !ref_matches(normal, expected) {
				return Err(InvalidPlan)
			}
			stream = verify_widget_appearance(store, expected, w, h)?
			verify_font_resources(store, as_dictionary(field(store, stream.dictionary, "Resources")?)?, font.font_object)
		}
		(CheckboxAppearance, Checkbox(state), _, WithCheckboxObjects(expected)) => {
			selection = checkbox_name(state)
			states = as_dictionary(normal)?
			if !name_matches(store, field(store, entries_value, "FT")?, "Btn")?
				or !name_matches(store, field(store, entries_value, "V")?, selection)?
				or !name_matches(store, field(store, entries_value, "AS")?, selection)?
				or states.length != 2
				or !ref_matches(field(store, states, "Off")?, expected.off)
				or !ref_matches(field(store, states, "Yes")?, expected.yes) {
				return Err(InvalidPlan)
			}
			Ok({})
		}
		_ => Err(InvalidPlan)
	}
}

verify_widget_appearance : KernelObject.Store, KernelObject.ObjectId, I64, I64 -> Try(KernelObject.StreamObject, KernelWidgetObjects.Error)
verify_widget_appearance = |store, expected, width, height| {
	stream_id = match value_at(store, stored_id(store, expected)?)? {
		Stream(stream) => stream
		_ => return Err(InvalidPlan)
	}
	stream = store.streams.get(KernelObject.StreamId.index(stream_id)) ? |_| InvalidPlan
	if stream.object != expected or !name_matches(store, field(store, stream.dictionary, "Type")?, "XObject")?
		or !name_matches(store, field(store, stream.dictionary, "Subtype")?, "Form")? {
		return Err(InvalidPlan)
	}
	verify_box(store, field(store, stream.dictionary, "BBox")?, [0, 0, width, height])?
	Ok(stream)
}

verify_checkbox_appearance : KernelObject.Store, KernelObject.ObjectId, KernelWidgetFields.CheckState -> Try({}, KernelWidgetObjects.Error)
verify_checkbox_appearance = |store, expected, state| {
	stream = verify_widget_appearance(store, expected, 22000, 22000)?
	resources = as_dictionary(field(store, stream.dictionary, "Resources")?)?
	payload = store.payloads.get(KernelObject.PayloadId.index(stream.source)) ? |_| InvalidPlan
	if resources.length != 0 or payload.bytes != checkbox_appearance(state) {
		return Err(InvalidPlan)
	}
	Ok({})
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
