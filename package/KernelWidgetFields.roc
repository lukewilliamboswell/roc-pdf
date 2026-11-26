import KernelBuiltInFont
import KernelFont
import KernelSpan
import Layout

## Authored fixed-page text widgets. Each dense field identity relates its
## visible label group to a checked page rectangle and one initial value.
## ISO 32000-2:2020 12.5.6.19 and 12.7.4. Authoring policy independently
## bounds names, labels and the repertoire that the editable face covers.
KernelWidgetFields :: [].{
	InitialText := [Blank, Prefilled(Str)]

	TextFieldProps := {
		id : Str,
		label : Str,
		width : Layout.Unit,
		value : InitialText ?? Blank,
	}

	Geometry : { label : Layout.Rect, widget : Layout.Rect }
	Location : { page : U64, placement : U64 }
	Authored : { field : TextFieldProps, geometry : Geometry, group : U64, location : Location }
	Field : { group : U64, id : Str, label : Str, location : Location, value : Str, widget : Layout.Rect }

	EditableFont : {
		bytes : List(U8),
		name : Str,
		metrics : { ascent : I64, bbox : List(I64), cap_height : I64, descent : I64 },
		widths : List(I64),
	}

	Error : [
		FontUnavailable,
		CountLimit({ actual : U64, maximum : U64 }),
		DuplicateId(Location),
		InvalidId(Location),
		InvalidLabel(Location),
		InvalidValue(Location),
		ValueDoesNotFit({ width : I64, required : I64, location : Location }),
	]

	Plan :: { fields : List(Field), font : EditableFont }.{
		fields : Plan -> List(Field)
		fields = |plan| plan.fields

		font : Plan -> EditableFont
		font = |plan| plan.font
	}

	max_fields : U64
	max_fields = 128

	max_characters : U64
	max_characters = 64

	## A fixed record retains the widget frame and its distinct, visible label
	## frame. Both within-page range checks precede the additions. The widget
	## is 22 pt high and the label has 24 pt of space above a 2 pt gap.
	geometry : Layout.Point, Layout.Unit, Layout.Size -> [Frames(Geometry), InvalidFrames]
	geometry = |origin, width, page| {
		x = origin.x.raw()
		y = origin.y.raw()
		w = width.raw()
		if w < 48000 or w > 1024000 or x < 0 or y < 0 or page.width.raw() < 0 or page.height.raw() < 0
			or !KernelSpan.end_within(x.to_u64_wrap(), w.to_u64_wrap(), page.width.raw().to_u64_wrap()).is_ok()
			or !KernelSpan.end_within(y.to_u64_wrap(), 48000, page.height.raw().to_u64_wrap()).is_ok() {
			return InvalidFrames
		}
		Frames({
			widget: { origin, size: { width, height: 22 } },
			label: { origin: { x: origin.x, y: Layout.Unit.from_raw(y + 24000) }, size: { width, height: 24 } },
		})
	}

	prepare : List(Authored) -> Try(Plan, Error)
	prepare = |fields| {
		if fields.len() > max_fields {
			return Err(CountLimit({ actual: fields.len(), maximum: max_fields }))
		}
		font = editable_font?
		var $prepared = List.with_capacity(fields.len())
		for input in fields {
			resolved = validate_field(input, font.widths)?
			$prepared = $prepared.append(resolved)
		}
		check_unique_ids($prepared)?
		Ok(Plan.{ fields: $prepared, font })
	}
}

validate_field : KernelWidgetFields.Authored, List(I64) -> Try(KernelWidgetFields.Field, KernelWidgetFields.Error)
validate_field = |{ field, geometry, group, location }, widths| {
	if !valid_id(field.id) {
		return Err(InvalidId(location))
	}
	if field.label.trim().is_empty() or field.label.count_utf8_bytes() > 256 or Str.to_utf8(field.label).any(|byte| byte < 32 or byte == 127) {
		return Err(InvalidLabel(location))
	}
	value = match field.value {
		Blank => ""
		Prefilled(text) => text
	}
	bytes = Str.to_utf8(value)
	if bytes.len() > KernelWidgetFields.max_characters {
		return Err(InvalidValue(location))
	}
	var $required = 0
	for byte in bytes {
		if byte < 32 or byte > 126 {
			return Err(InvalidValue(location))
		}

		## The simple TrueType font's /Widths are integer thousandths of an
		## em. At a fixed ten-point size each width represents 10 millipoints.
		$required = $required + list_at(widths, (byte - 32).to_u64()) * 10
	}
	room = geometry.widget.size.width.raw() - 8000
	if $required > room {
		return Err(ValueDoesNotFit({ width: room, required: $required, location }))
	}
	Ok({ group, id: field.id, label: field.label, location, value, widget: geometry.widget })
}

valid_id : Str -> Bool
valid_id = |id| {
	bytes = Str.to_utf8(id)
	if bytes.is_empty() or bytes.len() > 64 {
		return False
	}
	for byte in bytes {
		if !((byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 45 or byte == 95) {
			return False
		}
	}
	True
}

## Sort only the bounded identities; physical and logical order remain the
## original field order. A collision identifies its later authored input.
check_unique_ids : List(KernelWidgetFields.Field) -> Try({}, KernelWidgetFields.Error)
check_unique_ids = |fields| {
	var $identities = List.with_capacity(fields.len())
	var $order = 0
	for field in fields {
		$identities = $identities.append({ bytes: Str.to_utf8(field.id), location: field.location, order: $order })
		$order = $order + 1
	}
	sorted = $identities.sort_with(
		|left, right| match compare_ids(left.bytes, right.bytes) {
			Same => if (left.order < right.order) Before else if (left.order > right.order) After else Same
			order => order
		},
	)
	var $index = 1
	while $index < sorted.len() {
		current = list_at(sorted, $index)
		if list_at(sorted, $index - 1).bytes == current.bytes {
			return Err(DuplicateId(current.location))
		}
		$index = $index + 1
	}
	Ok({})
}

compare_ids : List(U8), List(U8) -> [After, Before, Same]
compare_ids = |left, right| {
	common = U64.min(left.len(), right.len())
	var $index = 0
	while $index < common {
		a = list_at(left, $index)
		b = list_at(right, $index)
		if a != b {
			return if (a < b) Before else After
		}
		$index = $index + 1
	}
	if (left.len() < right.len()) Before else if (left.len() > right.len()) After else Same
}

editable_font : Try(KernelWidgetFields.EditableFont, KernelWidgetFields.Error)
editable_font = build_editable_font({})

build_editable_font : {} -> Try(KernelWidgetFields.EditableFont, KernelWidgetFields.Error)
build_editable_font = |_| {
	font = KernelFont.inspect(KernelBuiltInFont.bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 20000, max_glyphs: 2000, max_tables: 64 })) ? |_| FontUnavailable
	if font.embedding_rights == PreviewAndPrint {
		return Err(FontUnavailable)
	}
	metrics = font.metrics
	scale = |dimension| {
		upem = metrics.units_per_em.to_i64()
		if dimension < 0 {
			0 - (-dimension * 1000 + upem // 2) // upem
		} else {
			(dimension * 1000 + upem // 2) // upem
		}
	}
	var $widths = List.with_capacity(95)
	var $code = 32
	while $code <= 126 {
		glyph = match KernelFont.glyph_for_scalar(font, $code) {
			None => return Err(FontUnavailable)
			Some(id) => id
		}
		width = KernelFont.advance_width(font, glyph) ? |_| FontUnavailable
		$widths = $widths.append(scale(width.to_i64()))
		$code = $code + 1
	}
	Ok({
		bytes: font.bytes,
		name: "RocPdfSans-Regular",
		metrics: { ascent: scale(metrics.ascent), bbox: [scale(metrics.x_min), scale(metrics.y_min), scale(metrics.x_max), scale(metrics.y_max)], cap_height: scale(metrics.cap_height), descent: scale(metrics.descent) },
		widths: $widths,
	})
}

list_at : List(a), U64 -> a
list_at = |list, index| list.get(index) ?? crash "validated editable form field index escaped its store"
