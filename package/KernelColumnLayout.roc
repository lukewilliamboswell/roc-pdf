import Layout
import Semantics

## Sequential, page-local columns. The caller commits source cuts separately
## and advances the frame only at a legal cut.
KernelColumnLayout :: [].{
	Widths := { first : Layout.Unit, second : Layout.Unit, gutter : Layout.Unit }

	Side : [First, Second]
	Error : [
		InvalidBody,
		InvalidWidth(Side),
		InvalidGutter,
		ColumnsTooWide({ available : I64, required : I64 }),
		GeometryOverflow,
		PageLimit({ limit : U64 }),
		InvalidLineMetrics,
		LineTooTall({ available : I64, required : I64 }),
	]

	Frame : {
		available : Layout.Unit,
		left : Layout.Unit,
		page : Semantics.PageId,
		side : Side,
		top : Layout.Unit,
		width : Layout.Unit,
	}

	Cursor :: {
		bottom : I64,
		first_left : I64,
		max_pages : U64,
		page : U64,
		second_left : I64,
		side : Side,
		top : I64,
		used : I64,
		widths : Widths,
	}.{

		## The body is in page coordinates. Column widths may differ. A
		## surplus in the body remains to the right of the second column.
		start : Layout.Rect, Widths, U64 -> Try(Cursor, Error)
		start = |body, widths, max_pages| start_columns(body, widths, max_pages)

		frame : Cursor -> Frame
		frame = |Cursor.(cursor)| {
			position = match cursor.side {
				First => { left: cursor.first_left, width: cursor.widths.first }
				Second => { left: cursor.second_left, width: cursor.widths.second }
			}
			top = cursor.top - cursor.used
			{
				available: Layout.Unit.from_raw(top - cursor.bottom),
				left: Layout.Unit.from_raw(position.left),
				page: Semantics.PageId.from_index(cursor.page),
				side: cursor.side,
				top: Layout.Unit.from_raw(top),
				width: position.width,
			}
		}

		## Enter the second column of this page, or the first column of
		## the next page. The reported page is always physical.
		advance_frame : Cursor -> Try(Cursor, Error)
		advance_frame = |Cursor.(cursor)| match cursor.side {
			First => Ok(Cursor.{ ..cursor, side: Second, used: 0 })
			Second => {
				if cursor.page + 1 >= cursor.max_pages {
					Err(PageLimit({ limit: cursor.max_pages }))
				} else {
					Ok(Cursor.{ ..cursor, page: cursor.page + 1, side: First, used: 0 })
				}
			}
		}

		## Commit a positive nominal line box and return its baseline.
		## Measuring the line against the frame's width precedes this call.
		place_line : Cursor, { baseline : Layout.Unit, leading : Layout.Unit } -> Try({ baseline : Layout.Point, next : Cursor }, Error)
		place_line = |cursor, metrics| place_column_line(cursor, metrics)

		## Inter-paragraph spacing cannot carry into a later column.
		## A negative gap is represented as invalid line metrics.
		space_after : Cursor, Layout.Unit -> Try(Cursor, Error)
		space_after = |Cursor.(cursor), space| {
			if space.raw() < 0 {
				return Err(InvalidLineMetrics)
			}
			available = cursor.top - cursor.bottom - cursor.used
			Ok(Cursor.{ ..cursor, used: cursor.used + I64.min(available, space.raw()) })
		}
	}
}

start_columns : Layout.Rect, KernelColumnLayout.Widths, U64 -> Try(KernelColumnLayout.Cursor, KernelColumnLayout.Error)
start_columns = |body, widths, max_pages| {
	x = body.origin.x.raw()
	y = body.origin.y.raw()
	available = body.size.width.raw()
	height = body.size.height.raw()
	first = widths.first.raw()
	second = widths.second.raw()
	gutter = widths.gutter.raw()
	if x < 0 or y < 0 or available <= 0 or height <= 0 {
		return Err(InvalidBody)
	}
	if first <= 0 {
		return Err(InvalidWidth(First))
	}
	if second <= 0 {
		return Err(InvalidWidth(Second))
	}
	if gutter <= 0 {
		return Err(InvalidGutter)
	}
	if max_pages == 0 {
		return Err(PageLimit({ limit: max_pages }))
	}
	second_offset = I64.plus_try(first, gutter) ? |_| GeometryOverflow
	required = I64.plus_try(second_offset, second) ? |_| GeometryOverflow
	if required > available {
		return Err(ColumnsTooWide({ available, required }))
	}
	_ = I64.plus_try(x, available) ? |_| GeometryOverflow
	top = I64.plus_try(y, height) ? |_| GeometryOverflow
	second_left = I64.plus_try(x, second_offset) ? |_| GeometryOverflow
	Ok(KernelColumnLayout.Cursor.{ bottom: y, first_left: x, max_pages, page: 0, second_left, side: First, top, used: 0, widths })
}

place_column_line : KernelColumnLayout.Cursor, { baseline : Layout.Unit, leading : Layout.Unit } -> Try({ baseline : Layout.Point, next : KernelColumnLayout.Cursor }, KernelColumnLayout.Error)
place_column_line = |cursor, metrics| {
	leading = metrics.leading.raw()
	baseline = metrics.baseline.raw()
	if leading <= 0 or baseline <= 0 or baseline > leading {
		return Err(InvalidLineMetrics)
	}
	frame = cursor.frame()
	if leading > frame.available.raw() {
		return Err(LineTooTall({ available: frame.available.raw(), required: leading }))
	}
	KernelColumnLayout.Cursor.(facts) = cursor
	Ok({
		baseline: { x: frame.left, y: Layout.Unit.from_raw(frame.top.raw() - baseline) },
		next: KernelColumnLayout.Cursor.{ ..facts, used: facts.used + leading },
	})
}

test_body : Layout.Rect
test_body = Layout.rect({ x: 12, y: 10, width: 100, height: 20 })

test_widths : KernelColumnLayout.Widths
test_widths = { first: 45, second: 47, gutter: 8 }

expect {
	begin = KernelColumnLayout.Cursor.start(test_body, test_widths, 2)?
	placed = begin.place_line({ baseline: 12, leading: 20 })?
	second = placed.next.advance_frame()?
	third = second.advance_frame()?
	placed.baseline.x.raw() == 12000 and
		placed.baseline.y.raw() == 18000 and
			placed.next.frame().available.raw() == 0 and
				second.frame().page.index() == 0 and
					second.frame().side == Second and
						second.frame().left.raw() == 65000 and
							second.frame().width.raw() == 47000 and
								third.frame().page.index() == 1 and
									third.frame().side == First and
										third.frame().available.raw() == 20000
}

expect match KernelColumnLayout.Cursor.start(test_body, { ..test_widths, gutter: Layout.Unit.from_raw(8001) }, 2) {
	Err(ColumnsTooWide({ available: 100000, required: 100001 })) => True
	_ => False
}

expect match KernelColumnLayout.Cursor.start(test_body, { ..test_widths, gutter: Layout.Unit.from_raw(I64.highest) }, 2) {
	Err(GeometryOverflow) => True
	_ => False
}

expect {
	begin = KernelColumnLayout.Cursor.start(test_body, test_widths, 1)?
	second = begin.advance_frame()?
	match second.advance_frame() {
		Err(PageLimit({ limit: 1 })) => True
		_ => False
	}
}
