KernelSpan :: [].{

	## Check the exclusive end of a half-open range before walking a dense
	## store. An empty range at the end of a store is valid; callers that
	## require entries check that rule separately.
	end_within : U64, U64, U64 -> Try(U64, [Outside])
	end_within = |start, length, available| {
		ending = Arithmetic.wrapped_end(start, length)
		if Arithmetic.fits(start, ending, available, |left, right| left <= right, |left, right| left and right) {
			Ok(ending)
		} else {
			Err(Outside)
		}
	}

	## Shared scalar terms for concrete integers and symbolic checking.
	## A wrapped sum of two unsigned values is smaller than its start
	## exactly when it overflowed.
	Arithmetic :: [].{
		wrapped_end = |start, length| start.plus_wrap(length)
		fits = |start, ending, available, at_most, both| both(at_most(start, ending), at_most(ending, available))
	}
}
