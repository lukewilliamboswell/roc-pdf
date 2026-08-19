import pdf.KernelColor
import pdf.KernelContent
import pdf.KernelEmit
import pdf.KernelGeometry
import pdf.KernelObjectPlan
import pdf.KernelOutputBound
import pdf.KernelPageObjects
import pdf.KernelPipelineFixture
import pdf.KernelTaggedObjects
import pdf.KernelResourceObjects
import pdf.KernelResourceName
import pdf.KernelTaggedStructure
import pdf.KernelImage
import pdf.KernelObject
import pdf.KernelResourceUse
import pdf.KernelScene
import pdf.KernelSemantics
import pdf.KernelTagged
import pdf.Layout
import pdf.Scene

Fixture :: [].{
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
				crash "tagged-visual geometry probe invariant failed"
			}
		}

		{ x: transformed.x.raw(), y: transformed.y.raw() }
	}

	minimal_pdf : U64 -> Try(List(U8), [EvidenceFailure, InvalidRuntimeGuard])
	minimal_pdf = |runtime_guard| if runtime_guard == 0 build_minimal_pdf({}) else Err(InvalidRuntimeGuard)
}

build_minimal_pdf : {} -> Try(List(U8), [EvidenceFailure, InvalidRuntimeGuard])
build_minimal_pdf = |_| {
	pipeline = KernelPipelineFixture.contextual_pipeline({}) ? |_| EvidenceFailure
	object_limits : KernelObject.Limits
	object_limits = {
		max_array_items: 192,
		max_byte_string_bytes: 0,
		max_byte_strings: 0,
		max_dictionary_entries: 320,
		max_direct_depth: 8,
		max_name_bytes: 3072,
		max_names: 128,
		max_objects: 16,
		max_payload_bytes: 1024,
		max_payloads: 3,
		max_streams: 3,
		max_text_string_bytes: 64,
		max_text_strings: 1,
		max_values: 640,
	}
	plan = KernelTaggedStructure.Plan.build(
		pipeline.tagged,
		pipeline.colors,
		pipeline.images,
		pipeline.content,
		pipeline.objects,
		KernelTaggedStructure.Limits.make({
			object_limits: object_limits,
		}),
	) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(KernelTaggedStructure.Plan.structure(plan)) ? |_| EvidenceFailure
	Ok(bytes)
}

## The tagged-visual evidence package links the private analytical geometry kernel.
expect Fixture.geometry_probe({ x: 2000, y: 3000 }) == { x: 2000, y: 9000 }
