import KernelGate2Objects
import KernelGate2PipelineFixture
import KernelObject

KernelGate3FontObjects :: [].{
	Error : [ArithmeticOverflow, LimitExceeded({ attempted : U64, limit : U64 }), NoFonts]

	FontObjects : { first : KernelObject.ObjectId, type0 : KernelObject.ObjectId }

	## Planned object identities per Type 0 font: font file, its length, the
	## descriptor, ToUnicode stream and length, CIDFont, widths, CMap-facing
	## objects, and the Type 0 font itself.
	font_object_count : U64
	font_object_count = objects_per_font

	Work : { font_objects : U64, fonts : U64, object_identities : U64 }

	Plan :: { base : KernelGate2Objects.Plan, fonts : List(FontObjects), work : Work, xref : KernelObject.ObjectId }.{
		build : KernelGate2Objects.Plan, U64, U64 -> Try(Plan, Error)
		build = |base, font_count, max_objects| build_plan(base, font_count, max_objects)

		base : Plan -> KernelGate2Objects.Plan
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

build_plan : KernelGate2Objects.Plan, U64, U64 -> Try(KernelGate3FontObjects.Plan, KernelGate3FontObjects.Error)
build_plan = |base, font_count, max_objects| {
	if font_count == 0 {
		return Err(NoFonts)
	}
	font_objects = checked_times(font_count, objects_per_font)?
	base_count = KernelGate2Objects.Plan.object_count(base)
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
		KernelGate3FontObjects.Plan.{
			base,
			fonts: $fonts,
			work: { font_objects, fonts: font_count, object_identities: object_count },
			xref: object_id(checked_add(object_count, 1)?),
		},
	)
}

checked_add : U64, U64 -> Try(U64, KernelGate3FontObjects.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_times : U64, U64 -> Try(U64, KernelGate3FontObjects.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

object_id : U64 -> KernelObject.ObjectId
object_id = |number| match KernelObject.ObjectId.from_number(number) {
	Err(_) => {
		crash "checked Gate 3 font object number escaped"
	}
	Ok(id) => id
}

objects_per_font : U64
objects_per_font = 9

## Font identities append after the complete Gate 2 plan and move only xref.
expect {
	pipeline = KernelGate2PipelineFixture.pipeline({})?
	base = pipeline.objects
	plan = KernelGate3FontObjects.Plan.build(base, 2, KernelGate2Objects.Plan.object_count(base) + 18)?
	first = list_at(KernelGate3FontObjects.Plan.fonts(plan), 0)
	second = list_at(KernelGate3FontObjects.Plan.fonts(plan), 1)
	KernelObject.ObjectId.number(first.first) == KernelGate2Objects.Plan.object_count(base) + 1 and
		KernelObject.ObjectId.number(first.type0) == KernelGate2Objects.Plan.object_count(base) + 9 and
			KernelObject.ObjectId.number(second.first) == KernelGate2Objects.Plan.object_count(base) + 10 and
				KernelObject.ObjectId.number(second.type0) == KernelGate2Objects.Plan.object_count(base) + 18 and
					KernelObject.ObjectId.number(KernelGate3FontObjects.Plan.xref(plan)) == KernelGate2Objects.Plan.object_count(base) + 19
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated Gate 3 font-plan index escaped"
	}
	Ok(value) => value
}
