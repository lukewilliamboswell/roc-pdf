import KernelObjectPlan
import KernelFontObjects
import KernelObject

## production-visual object planning: canonical Form XObject stream objects (one stream
## plus its indirect length per physical form, in canonical-ID order — the
## documented total order), then one dictionary object per canonical
## graphics state, one per canonical shading, one per canonical function,
## one stream pair per canonical tiling pattern, each in the same canonical
## order, followed by the Type 0 font objects when text is present, appended
## after the unchanged tagged-visual base plan. Canonical resource identity stays
## independent of these object numbers.
KernelFormObjects :: [].{
	Error : [ArithmeticOverflow, LimitExceeded({ attempted : U64, limit : U64 })]

	StreamObjects : { length : KernelObject.ObjectId, stream : KernelObject.ObjectId }

	PaintCounts : { functions : U64, patterns : U64, shadings : U64 }

	Work : { font_objects : U64, form_objects : U64, function_objects : U64, object_identities : U64, pattern_objects : U64, shading_objects : U64, state_objects : U64 }

	Plan :: {
		base : KernelObjectPlan.Plan,
		fonts : List(KernelFontObjects.FontObjects),
		forms : List(StreamObjects),
		functions : List(KernelObject.ObjectId),
		patterns : List(StreamObjects),
		shadings : List(KernelObject.ObjectId),
		states : List(KernelObject.ObjectId),
		work : Work,
		xref : KernelObject.ObjectId,
	}.{
		build : KernelObjectPlan.Plan, U64, U64, U64 -> Try(Plan, Error)
		build = |base, canonical_forms, font_count, max_objects| build_plan(base, canonical_forms, 0, no_paints, font_count, max_objects)

		## The transparency-aware variant: canonical graphics-state objects
		## are planned between the form streams and the font objects. With a
		## zero state count the plan is identical to `build`.
		build_with_states : KernelObjectPlan.Plan, U64, U64, U64, U64 -> Try(Plan, Error)
		build_with_states = |base, canonical_forms, canonical_states, font_count, max_objects| build_plan(base, canonical_forms, canonical_states, no_paints, font_count, max_objects)

		## The paint-aware variant: shading dictionaries, function
		## dictionaries, and pattern stream pairs are planned between the
		## graphics states and the font objects. Zero paint counts leave
		## every existing plan identical.
		build_with_paints : KernelObjectPlan.Plan, U64, U64, PaintCounts, U64, U64 -> Try(Plan, Error)
		build_with_paints = |base, canonical_forms, canonical_states, paints, font_count, max_objects| build_plan(base, canonical_forms, canonical_states, paints, font_count, max_objects)

		functions : Plan -> List(KernelObject.ObjectId)
		functions = |plan| plan.functions

		patterns : Plan -> List(StreamObjects)
		patterns = |plan| plan.patterns

		shadings : Plan -> List(KernelObject.ObjectId)
		shadings = |plan| plan.shadings

		base : Plan -> KernelObjectPlan.Plan
		base = |plan| plan.base

		fonts : Plan -> List(KernelFontObjects.FontObjects)
		fonts = |plan| plan.fonts

		forms : Plan -> List(StreamObjects)
		forms = |plan| plan.forms

		object_count : Plan -> U64
		object_count = |plan| plan.work.object_identities

		states : Plan -> List(KernelObject.ObjectId)
		states = |plan| plan.states

		work : Plan -> Work
		work = |plan| plan.work

		xref : Plan -> KernelObject.ObjectId
		xref = |plan| plan.xref
	}
}

no_paints : KernelFormObjects.PaintCounts
no_paints = { functions: 0, patterns: 0, shadings: 0 }

build_plan : KernelObjectPlan.Plan, U64, U64, KernelFormObjects.PaintCounts, U64, U64 -> Try(KernelFormObjects.Plan, KernelFormObjects.Error)
build_plan = |base, canonical_forms, canonical_states, paints, font_count, max_objects| {
	base_count = KernelObjectPlan.Plan.object_count(base)
	form_objects = checked_times(canonical_forms, 2)?
	pattern_objects = checked_times(paints.patterns, 2)?
	font_objects = checked_times(font_count, KernelFontObjects.font_object_count)?
	paint_objects = checked_add(checked_add(paints.shadings, paints.functions)?, pattern_objects)?
	object_count = checked_add(checked_add(checked_add(checked_add(base_count, form_objects)?, canonical_states)?, paint_objects)?, font_objects)?
	if object_count > max_objects {
		return Err(LimitExceeded({ attempted: object_count, limit: max_objects }))
	}
	var $forms = List.with_capacity(canonical_forms)
	var $ordinal = 0
	while $ordinal < canonical_forms {
		stream = base_count + 1 + $ordinal * 2
		$forms = $forms.append({ length: object_id(stream + 1), stream: object_id(stream) })
		$ordinal = $ordinal + 1
	}
	states_start = checked_add(base_count, form_objects)?
	var $states = List.with_capacity(canonical_states)
	var $state = 0
	while $state < canonical_states {
		$states = $states.append(object_id(states_start + 1 + $state))
		$state = $state + 1
	}
	shadings_start = checked_add(states_start, canonical_states)?
	var $shadings = List.with_capacity(paints.shadings)
	var $shading = 0
	while $shading < paints.shadings {
		$shadings = $shadings.append(object_id(shadings_start + 1 + $shading))
		$shading = $shading + 1
	}
	functions_start = checked_add(shadings_start, paints.shadings)?
	var $functions = List.with_capacity(paints.functions)
	var $function = 0
	while $function < paints.functions {
		$functions = $functions.append(object_id(functions_start + 1 + $function))
		$function = $function + 1
	}
	patterns_start = checked_add(functions_start, paints.functions)?
	var $patterns = List.with_capacity(paints.patterns)
	var $pattern = 0
	while $pattern < paints.patterns {
		stream = patterns_start + 1 + $pattern * 2
		$patterns = $patterns.append({ length: object_id(stream + 1), stream: object_id(stream) })
		$pattern = $pattern + 1
	}
	fonts_start = checked_add(patterns_start, pattern_objects)?
	var $fonts = List.with_capacity(font_count)
	var $font = 0
	while $font < font_count {
		first = fonts_start + 1 + $font * KernelFontObjects.font_object_count
		$fonts = $fonts.append({ first: object_id(first), type0: object_id(first + KernelFontObjects.font_object_count - 1) })
		$font = $font + 1
	}
	Ok(
		KernelFormObjects.Plan.{
			base,
			fonts: $fonts,
			forms: $forms,
			functions: $functions,
			patterns: $patterns,
			shadings: $shadings,
			states: $states,
			work: { font_objects, form_objects, function_objects: paints.functions, object_identities: object_count, pattern_objects, shading_objects: paints.shadings, state_objects: canonical_states },
			xref: object_id(checked_add(object_count, 1)?),
		},
	)
}

checked_add : U64, U64 -> Try(U64, KernelFormObjects.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_times : U64, U64 -> Try(U64, KernelFormObjects.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

object_id : U64 -> KernelObject.ObjectId
object_id = |number| match KernelObject.ObjectId.from_number(number) {
	Err(_) => {
		crash "checked production-visual form object number escaped"
	}
	Ok(id) => id
}
