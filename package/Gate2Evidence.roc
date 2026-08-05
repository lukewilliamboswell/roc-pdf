import KernelColor
import KernelGeometry
import KernelImage
import KernelResourceUse
import KernelScene
import KernelSemantics
import KernelTagged
import Layout
import Scene

Gate2Evidence :: [].{
	geometry_probe : { x : I64, y : I64 } -> { x : I64, y : I64 }
	geometry_probe = |input| {
		matrix : Scene.Matrix
		matrix = {
			a: Layout.Unit.from_raw(0),
			b: Layout.Unit.from_raw(1000),
			c: Layout.Unit.from_raw(-1000),
			d: Layout.Unit.from_raw(0),
			e: Layout.Unit.from_raw(5000),
			f: Layout.Unit.from_raw(7000),
		}
		point = { x: Layout.Unit.from_raw(input.x), y: Layout.Unit.from_raw(input.y) }
		transformed = match KernelGeometry.transform_point(matrix, point) {
			Ok(value) => value
			Err(_) => {
				crash "Gate 2 geometry probe invariant failed"
			}
		}

		{ x: transformed.x.raw(), y: transformed.y.raw() }
	}
}

## The Gate 2 evidence package links the private analytical geometry kernel.
expect Gate2Evidence.geometry_probe({ x: 2000, y: 3000 }) == { x: 2000, y: 9000 }
