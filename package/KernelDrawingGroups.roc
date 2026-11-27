## Translated facade drawings use a flat command stream and an explicit stack.
KernelDrawingGroups :: [].{
	DepthLimit : { attempted : U64, command : U64, limit : U64 }

	default_depth : U64
	default_depth = 8

	coordinate_bound : I64
	coordinate_bound = 1000000000000

	## Leave room for a drawing coordinate, its extent, any stroke half-width
	## and decoration spacing. Each of those contributions is independently
	## bounded before drawing arithmetic.
	accumulate : I64, I64 -> Try(I64, [OutOfRange])
	accumulate = |current, offset| {
		next = I64.plus_try(current, offset) ? |_| OutOfRange
		room = 5 * coordinate_bound
		if (next < I64.lowest + room or next > I64.highest - room) Err(OutOfRange) else Ok(next)
	}
}

expect {
	room = 5 * KernelDrawingGroups.coordinate_bound
	last = I64.highest - room
	KernelDrawingGroups.accumulate(last - 1, 1) == Ok(last)
		and KernelDrawingGroups.accumulate(last, 1) == Err(OutOfRange)
		and KernelDrawingGroups.accumulate(I64.lowest, -1) == Err(OutOfRange)
}
