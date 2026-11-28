import KernelDrawingGroups
import Layout
import Scene

## Authoring validation shared by flow and furniture drawings. Bounds include
## the control hull and are computed before translation. The scene kernel
## independently checks its dense stores (ISO 32000-2:2020, §8.5.2).
KernelDrawingPath :: [].{
	Bounds : { max_x : I64, max_y : I64, min_x : I64, min_y : I64 }

	Error : [Empty, NoPaint, Order(U64), RectangleSize(U64), CoordinateRange(U64)]

	PlacementError : { command : U64, error : Error }

	bounds : List(Scene.PathSegment) -> Try(Bounds, Error)
	bounds = |segments| {
		if segments.is_empty() {
			return Err(Empty)
		}
		var $open = False
		var $paints = False
		var $bounds = { max_x: I64.lowest, max_y: I64.lowest, min_x: I64.highest, min_y: I64.highest }
		var $index = 0
		for segment in segments {
			match segment {
				MoveTo(point) => {
					$open = True
					$bounds = include_point($bounds, point, $index)?
				}
				LineTo(point) => {
					if !$open {
						return Err(Order($index))
					}
					$paints = True
					$bounds = include_point($bounds, point, $index)?
				}
				CubicTo({ control_1, control_2, end }) => {
					if !$open {
						return Err(Order($index))
					}
					$paints = True
					$bounds = include_point($bounds, control_1, $index)?
					$bounds = include_point($bounds, control_2, $index)?
					$bounds = include_point($bounds, end, $index)?
				}
				Close => {
					if !$open {
						return Err(Order($index))
					}
					$open = False
				}
				Rectangle({ origin, size }) => {
					if !in_range(size.width.raw()) or !in_range(size.height.raw()) {
						return Err(CoordinateRange($index))
					}
					if size.width <= 0 or size.height <= 0 {
						return Err(RectangleSize($index))
					}
					$open = False
					$paints = True
					$bounds = include_point($bounds, origin, $index)?
					$bounds = include_raw($bounds, origin.x.raw() + size.width.raw(), origin.y.raw() + size.height.raw())
				}
			}
			$index = $index + 1
		}
		if ($paints) Ok($bounds) else Err(NoPaint)
	}

	translate : List(Scene.PathSegment), I64, I64 -> List(Scene.PathSegment)
	translate = |segments, dx, dy| {
		if dx == 0 and dy == 0 {
			return segments
		}
		move = |point| { x: Layout.Unit.from_raw(point.x.raw() + dx), y: Layout.Unit.from_raw(point.y.raw() + dy) }
		segments.map(
			|segment| match segment {
				Close => Close
				CubicTo({ control_1, control_2, end }) => CubicTo({ control_1: move(control_1), control_2: move(control_2), end: move(end) })
				LineTo(point) => LineTo(move(point))
				MoveTo(point) => MoveTo(move(point))
				Rectangle(rect) => Rectangle({ origin: move(rect.origin), size: rect.size })
			},
		)
	}

	location : Str, PlacementError -> Str
	location = |drawing, { command, error }| {
		path = "${drawing}.commands[${command.to_str()}]"
		match error {
			Order(index) | RectangleSize(index) | CoordinateRange(index) => "${path}.segments[${index.to_str()}]"
			Empty | NoPaint => path
		}
	}

	message : Error -> Str
	message = |error| match error {
		Order(_) => "A line, curve, or close needs an open subpath. Start one with move_to; close and rectangle end the open subpath."
		RectangleSize(_) => "A path rectangle needs positive width and height."
		CoordinateRange(_) => "A path coordinate or rectangle dimension lies outside the supported range of ±10^9 pt."
		Empty => "A drawing path needs segments."
		NoPaint => "A drawing path needs a line, curve, or rectangle to paint."
	}

	include_point : Bounds, Layout.Point, U64 -> Try(Bounds, Error)
	include_point = |current, point, index| {
		x = point.x.raw()
		y = point.y.raw()
		if !(in_range(x) and in_range(y)) {
			return Err(CoordinateRange(index))
		}
		Ok(include_raw(current, x, y))
	}

	include_raw : Bounds, I64, I64 -> Bounds
	include_raw = |current, x, y| {
		{ max_x: I64.max(current.max_x, x), max_y: I64.max(current.max_y, y), min_x: I64.min(current.min_x, x), min_y: I64.min(current.min_y, y) }
	}

	in_range : I64 -> Bool
	in_range = |value| value <= KernelDrawingGroups.coordinate_bound and value >= 0 - KernelDrawingGroups.coordinate_bound
}
