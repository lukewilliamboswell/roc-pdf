import Layout
import Scene
import Semantics

KernelGeometry :: [].{
	BoxKind : [ArtBox, BleedBox, CropBox, MediaBox, TrimBox]
	Error : [
		BoxOutside({ inner : BoxKind, outer : BoxKind }),
		CoordinateOverflow,
		NonPositiveBox(BoxKind),
	]
	Work : {
		box_checks : U64,
		containment_checks : U64,
		coordinate_checks : U64,
	}

	validate_page : Scene.Page -> Try(Work, Error)
	validate_page = |page| {
		validate_rect(page.boxes.media, MediaBox)?
		validate_rect(page.boxes.crop, CropBox)?
		validate_rect(page.boxes.bleed, BleedBox)?
		validate_rect(page.boxes.trim, TrimBox)?
		validate_rect(page.boxes.art, ArtBox)?
		validate_contained(page.boxes.crop, CropBox, page.boxes.media, MediaBox)?
		validate_contained(page.boxes.bleed, BleedBox, page.boxes.crop, CropBox)?
		validate_contained(page.boxes.trim, TrimBox, page.boxes.crop, CropBox)?
		validate_contained(page.boxes.art, ArtBox, page.boxes.crop, CropBox)?

		Ok({ box_checks: 5, containment_checks: 4, coordinate_checks: 20 })
	}

	transform_point : Scene.Matrix, Layout.Point -> Try(Layout.Point, Error)
	transform_point = |matrix, point| {
		x_numerator = checked_add(
			checked_times(matrix.a.raw(), point.x.raw())?,
			checked_times(matrix.c.raw(), point.y.raw())?,
		)?
		y_numerator = checked_add(
			checked_times(matrix.b.raw(), point.x.raw())?,
			checked_times(matrix.d.raw(), point.y.raw())?,
		)?
		x = checked_add(round_half_even(x_numerator, 1000)?, matrix.e.raw())?
		y = checked_add(round_half_even(y_numerator, 1000)?, matrix.f.raw())?

		Ok({ x: Layout.Unit.from_raw(x), y: Layout.Unit.from_raw(y) })
	}
}

validate_rect : Layout.Rect, KernelGeometry.BoxKind -> Try({}, KernelGeometry.Error)
validate_rect = |rect, kind| {
	if rect.size.width.raw() <= 0 or rect.size.height.raw() <= 0 {
		Err(NonPositiveBox(kind))
	} else {
		_ = checked_add(rect.origin.x.raw(), rect.size.width.raw())?
		_ = checked_add(rect.origin.y.raw(), rect.size.height.raw())?
		Ok({})
	}
}

validate_contained : Layout.Rect, KernelGeometry.BoxKind, Layout.Rect, KernelGeometry.BoxKind -> Try({}, KernelGeometry.Error)
validate_contained = |inner, inner_kind, outer, outer_kind| {
	inner_right = checked_add(inner.origin.x.raw(), inner.size.width.raw())?
	inner_top = checked_add(inner.origin.y.raw(), inner.size.height.raw())?
	outer_right = checked_add(outer.origin.x.raw(), outer.size.width.raw())?
	outer_top = checked_add(outer.origin.y.raw(), outer.size.height.raw())?

	if inner.origin.x.raw() < outer.origin.x.raw() or
		inner.origin.y.raw() < outer.origin.y.raw() or
			inner_right > outer_right or
				inner_top > outer_top {
		Err(BoxOutside({ inner: inner_kind, outer: outer_kind }))
	} else {
		Ok({})
	}
}

round_half_even : I64, I64 -> Try(I64, KernelGeometry.Error)
round_half_even = |value, scale| {
	quotient = I64.div_trunc_by(value, scale)
	remainder = I64.rem_by(value, scale)
	abs_remainder = if remainder < 0 -remainder else remainder
	twice_remainder = checked_times(abs_remainder, 2)?
	adjust = twice_remainder > scale or
		(twice_remainder == scale and I64.rem_by(quotient, 2) != 0)

	if adjust {
		checked_add(quotient, if value < 0 -1 else 1)
	} else {
		Ok(quotient)
	}
}

checked_add : I64, I64 -> Try(I64, KernelGeometry.Error)
checked_add = |left, right| match I64.plus_try(left, right) {
	Err(Overflow) => Err(CoordinateOverflow)
	Ok(total) => Ok(total)
}

checked_times : I64, I64 -> Try(I64, KernelGeometry.Error)
checked_times = |left, right| match I64.times_try(left, right) {
	Err(Overflow) => Err(CoordinateOverflow)
	Ok(total) => Ok(total)
}

page_rect : I64, I64, I64, I64 -> Layout.Rect
page_rect = |x, y, width, height| {
	origin: { x: Layout.Unit.from_raw(x), y: Layout.Unit.from_raw(y) },
	size: { height: Layout.Unit.from_raw(height), width: Layout.Unit.from_raw(width) },
}

test_page : Scene.Page
test_page = {
	boxes: {
		art: page_rect(1000, 1000, 8000, 8000),
		bleed: page_rect(500, 500, 9000, 9000),
		crop: page_rect(0, 0, 10000, 10000),
		media: page_rect(0, 0, 10000, 10000),
		trim: page_rect(750, 750, 8500, 8500),
	},
	id: Semantics.PageId.from_index(0),
	paint_order: Semantics.Range.from_start_and_length(0, 0),
	rotation: Rotate0,
}

## Resolved page boxes validate in one fixed amount of work per page.
expect KernelGeometry.validate_page(test_page)? == {
	box_checks: 5,
	containment_checks: 4,
	coordinate_checks: 20,
}

## A page box outside its required containing box is rejected atomically.
expect {
	bad = {
		..test_page,
		boxes: { ..test_page.boxes, art: page_rect(9000, 9000, 2000, 2000) },
	}

	KernelGeometry.validate_page(bad) == Err(BoxOutside({ inner: ArtBox, outer: CropBox }))
}

## Non-positive page boxes are rejected before containment is considered.
expect {
	bad = {
		..test_page,
		boxes: { ..test_page.boxes, art: page_rect(1000, 1000, 0, 8000) },
	}

	KernelGeometry.validate_page(bad) == Err(NonPositiveBox(ArtBox))
}

## Affine point transforms use checked fixed-point half-even rounding.
expect {
	matrix : Scene.Matrix
	matrix = {
		a: Layout.Unit.from_raw(0),
		b: Layout.Unit.from_raw(1000),
		c: Layout.Unit.from_raw(-1000),
		d: Layout.Unit.from_raw(0),
		e: Layout.Unit.from_raw(5000),
		f: Layout.Unit.from_raw(7000),
	}
	point = { x: Layout.Unit.from_raw(2000), y: Layout.Unit.from_raw(3000) }
	transformed = KernelGeometry.transform_point(matrix, point)?

	transformed.x.raw() == 2000 and transformed.y.raw() == 9000
}

## Transform arithmetic reports overflow rather than wrapping coordinates.
expect {
	matrix : Scene.Matrix
	matrix = {
		a: Layout.Unit.from_raw(I64.highest),
		b: Layout.Unit.from_raw(0),
		c: Layout.Unit.from_raw(0),
		d: Layout.Unit.from_raw(1000),
		e: Layout.Unit.from_raw(0),
		f: Layout.Unit.from_raw(0),
	}
	point = { x: Layout.Unit.from_raw(2), y: Layout.Unit.from_raw(0) }

	match KernelGeometry.transform_point(matrix, point) {
		Err(CoordinateOverflow) => True
		_ => False
	}
}
