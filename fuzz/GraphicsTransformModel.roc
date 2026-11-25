import fuzz.Model
import pdf.KernelContent
import pdf.KernelFixture
import pdf.KernelScene
import pdf.KernelSemantics
import pdf.KernelTagged
import pdf.Scene
import pdf.Semantics
import StructureOracle

GraphicsTransformModel := [].{}

Affine : [Rotate, Scale, Shear, Reflect]

World : List(Affine)

machine : Model.Machine(World, Affine)
machine = {
	init: [],
	actions: |world| match world.len() {
		0 | 1 => [Rotate, Scale]
		2 => [Shear, Reflect]
		_ => []
	},
	step: |world, action| world.append(action),
	rules: [
		Model.always("Form placement maps its local basis through the authored transforms", agrees),
		Model.sometimes("a rotation encloses a scale and a signed fractional shear", |world| world == [Rotate, Scale, Shear]),
		Model.sometimes("a scale encloses a rotation and a reflection", |world| world == [Scale, Rotate, Reflect]),
	],
}

expect {
	report = Model.explore(machine, { depth: 4, key: |world| world, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 15 and report.steps == 14 and report.depth == 3 and report.reached.len() == 2
}

Coefficients : (I64, I64, I64, I64, I64, I64)

coefficients : Affine -> Coefficients
coefficients = |affine| match affine {
	Rotate => (0, 1000, -1000, 0, 7000, 250)
	Scale => (2000, 0, 0, 500, 1500, 2750)
	Shear => (1250, 500, -250, 1000, -500, 2250)
	Reflect => (-1000, 0, 0, 1000, 4250, 1000)
}

Point : { x : Dec, y : Dec }

Basis : { origin : Point, x_end : Point, y_end : Point }

basis : Basis
basis = { origin: { x: 0, y: 0 }, x_end: { x: 1, y: 0 }, y_end: { x: 0, y: 1 } }

map_basis : Basis, (Point -> Point) -> Basis
map_basis = |frame, transform| { origin: transform(frame.origin), x_end: transform(frame.x_end), y_end: transform(frame.y_end) }

# ISO 32000-2 §8.3.4 maps local coordinates outward. The authored oracle
# applies each distinct enclosing transform to the point, starting at the
# placement. This does not call the production geometry or emission helpers.
apply : Affine, Point -> Point
apply = |affine, point| {
	(a, b, c, d, e, f) = coefficients(affine)
	{
		x: (a.to_dec() * point.x + c.to_dec() * point.y + e.to_dec()) * 0.001,
		y: (b.to_dec() * point.x + d.to_dec() * point.y + f.to_dec()) * 0.001,
	}
}

agrees : World -> Bool
agrees = |world| match world {
	[outer, inner, placement] => {
		local = |point| apply(placement, point)
		expected = [
			map_basis(basis, |point| apply(outer, apply(inner, local(point)))),
			map_basis(basis, |point| apply(outer, local(point))),
			map_basis(basis, local),
		]
		match emitted(outer, inner, placement) {
			Err(_) => False
			Ok(bytes) => correlate(bytes) == Ok(expected)
		}
	}
	_ => True
}

# The observed CTM is represented by the page-space images of the local
# origin and two basis endpoints. The emitted `cm` gives new local basis
# coordinates, which the previous frame maps into the page. A Form in this
# package has identity /Matrix, so invocation adds no implicit affine term.
correlate : List(U8) -> Try(List(Basis), [InvalidTrace])
correlate = |bytes| {
	operations = StructureOracle.affine_operations(bytes) ? |_| InvalidTrace
	var $saved = []
	var $current = basis
	var $placements = []
	for operation in operations {
		match operation {
			Save => {
				$saved = $saved.append($current)
			}
			Restore => {
				$current = $saved.last() ? |_| InvalidTrace
				$saved = $saved.drop_last(1)
			}
			Concat({ origin, x_end, y_end }) => {
				previous = $current
				$current = map_basis({ origin, x_end, y_end }, |point| position(previous, point))
			}
			Invoke(name) => {
				if name != "XO1_0" {
					return Err(InvalidTrace)
				}
				$placements = $placements.append($current)
			}
		}
	}
	if ($saved.is_empty() and $current == basis) Ok($placements) else Err(InvalidTrace)
}

position : Basis, Point -> Point
position = |frame, point| {
	{ origin, x_end, y_end } = frame
	{
		x: origin.x + (x_end.x - origin.x) * point.x + (y_end.x - origin.x) * point.y,
		y: origin.y + (x_end.y - origin.y) * point.x + (y_end.y - origin.y) * point.y,
	}
}

# The three invocations use a real validated Form store. Each subsequent
# sibling is one scope shallower, exposing leaked CTM as well as coefficient
# order, sign or scale. Only the actual page content plan is observed here.
emitted : Affine, Affine, Affine -> Try(List(U8), [FixtureInvalid])
emitted = |outer, inner, placement| {
	fixture = KernelFixture.scene
	group = fixture.groups.first() ? |_| FixtureInvalid
	page = fixture.pages.first() ? |_| FixtureInvalid
	path = fixture.commands.first() ? |_| FixtureInvalid
	form = Scene.FormId.from_index(0)
	invoke = PlaceForm({ form, transform: scene_matrix(placement) })
	forms : Scene.FormStore
	forms = { commands: [path], forms: [{ bbox: KernelFixture.rect(0, 0, 1000, 1000), commands: range(0, 1), group: NoGroup, id: form }] }
	scene = {
		..fixture,
		commands: [Transform({ children: range(2, 2), matrix: scene_matrix(outer) }), invoke, Transform({ children: range(4, 1), matrix: scene_matrix(inner) }), invoke, invoke],
		groups: [{ ..group, commands: range(0, 2) }],
		page_groups: [group.id],
		pages: [{ ..page, paint_order: range(0, 1) }],
	}
	semantic = KernelSemantics.Plan.build(KernelFixture.semantics, 1, 1, KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 })) ? |_| FixtureInvalid
	resources = KernelScene.Resources.with_forms({ color_spaces: 1, forms: 1, images: 0, text_runs: 0 })
	validated = KernelScene.FormPlan.build(scene, forms, resources, KernelScene.Limits.make({ max_commands: 5, max_dash_lengths: 0, max_graphics_depth: 4, max_groups: 1, max_pages: 1, max_path_segments: 1, max_paths: 1 }), KernelScene.FormLimits.make({ max_form_commands: 1, max_forms: 1 })) ? |_| FixtureInvalid
	tagged = KernelTagged.Plan.build(semantic, KernelScene.FormPlan.page(validated)) ? |_| FixtureInvalid
	arena = KernelScene.FormPlan.forms(validated).commands
	context = { arena, color_names: [0], font_names: [], form_names: [0], form_states: [], image_names: [], page_states: [], pattern_arena: [], pattern_names: [], pattern_streams: [], shading_names: [], streams: [range(0, 1)] }
	content = KernelContent.Plan.build_with_forms(tagged, context, KernelContent.Limits.make({ max_content_bytes: 1024, max_content_streams: 1 })) ? |_| FixtureInvalid
	Ok(KernelContent.Plan.stream(content, Semantics.ContentStreamId.from_index(0)).bytes)
}

scene_matrix : Affine -> Scene.Matrix
scene_matrix = |affine| {
	(a, b, c, d, e, f) = coefficients(affine)
	unit = KernelFixture.unit
	{ a: unit(a), b: unit(b), c: unit(c), d: unit(d), e: unit(e), f: unit(f) }
}

range : U64, U64 -> Semantics.IndexRange
range = |start, length| Semantics.IndexRange.from_start_and_length({ start, length })
