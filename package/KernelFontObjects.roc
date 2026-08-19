import KernelObjectPlan
import KernelPipelineFixture
import KernelObject

KernelFontObjects :: [].{
	Error : [ArithmeticOverflow, LimitExceeded({ attempted : U64, limit : U64 }), NoFonts]

	FontObjects : { first : KernelObject.ObjectId, type0 : KernelObject.ObjectId }

	## Planned object identities per Type 0 font: font file, its length, the
	## descriptor, ToUnicode stream and length, CIDFont, widths, CMap-facing
	## objects, and the Type 0 font itself.
	font_object_count : U64
	font_object_count = objects_per_font

	Work : { font_objects : U64, fonts : U64, object_identities : U64 }

	Plan :: { base : KernelObjectPlan.Plan, fonts : List(FontObjects), work : Work, xref : KernelObject.ObjectId }.{
		build : KernelObjectPlan.Plan, U64, U64 -> Try(Plan, Error)
		build = |base, font_count, max_objects| build_plan(base, font_count, max_objects)

		base : Plan -> KernelObjectPlan.Plan
		base = |plan| plan.base

		fonts : Plan -> List(FontObjects)
		fonts = |plan| plan.fonts

		object_count : Plan -> U64
		object_count = |plan| plan.work.object_identities

		work : Plan -> Work
		work = |plan| plan.work

		xref : Plan -> KernelObject.ObjectId
		xref = |plan| plan.xref
	}
}

build_plan : KernelObjectPlan.Plan, U64, U64 -> Try(KernelFontObjects.Plan, KernelFontObjects.Error)
build_plan = |base, font_count, max_objects| {
	if font_count == 0 {
		return Err(NoFonts)
	}
	font_objects = checked_times(font_count, objects_per_font)?
	base_count = KernelObjectPlan.Plan.object_count(base)
	object_count = checked_add(base_count, font_objects)?
	if object_count > max_objects {
		return Err(LimitExceeded({ attempted: object_count, limit: max_objects }))
	}
	var $fonts = List.with_capacity(font_count)
	var $index = 0
	while $index < font_count {
		first = base_count + 1 + $index * objects_per_font
		$fonts = $fonts.append({ first: object_id(first), type0: object_id(first + objects_per_font - 1) })
		$index = $index + 1
	}
	Ok(
		KernelFontObjects.Plan.{
			base,
			fonts: $fonts,
			work: { font_objects, fonts: font_count, object_identities: object_count },
			xref: object_id(checked_add(object_count, 1)?),
		},
	)
}

checked_add : U64, U64 -> Try(U64, KernelFontObjects.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_times : U64, U64 -> Try(U64, KernelFontObjects.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

object_id : U64 -> KernelObject.ObjectId
object_id = |number| match KernelObject.ObjectId.from_number(number) {
	Err(_) => {
		crash "checked text-layout font object number escaped"
	}
	Ok(id) => id
}

objects_per_font : U64
objects_per_font = 9

## Font identities append after the complete tagged-visual plan and move only xref.
expect {
	pipeline = KernelPipelineFixture.pipeline({})?
	base = pipeline.objects
	plan = KernelFontObjects.Plan.build(base, 2, KernelObjectPlan.Plan.object_count(base) + 18)?
	first = list_at(KernelFontObjects.Plan.fonts(plan), 0)
	second = list_at(KernelFontObjects.Plan.fonts(plan), 1)
	KernelObject.ObjectId.number(first.first) == KernelObjectPlan.Plan.object_count(base) + 1 and
		KernelObject.ObjectId.number(first.type0) == KernelObjectPlan.Plan.object_count(base) + 9 and
			KernelObject.ObjectId.number(second.first) == KernelObjectPlan.Plan.object_count(base) + 10 and
				KernelObject.ObjectId.number(second.type0) == KernelObjectPlan.Plan.object_count(base) + 18 and
					KernelObject.ObjectId.number(KernelFontObjects.Plan.xref(plan)) == KernelObjectPlan.Plan.object_count(base) + 19
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated text-layout font-plan index escaped"
	}
	Ok(value) => value
}
