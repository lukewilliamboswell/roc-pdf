import KernelColor
import KernelContent
import KernelEmit
import KernelGeometry
import KernelGate2Objects
import KernelGate2OutputBound
import KernelGate2PageObjects
import KernelGate2PipelineFixture
import KernelGate2TaggedObjects
import KernelGate2ResourceObjects
import KernelGate2ResourceName
import KernelGate2Structure
import KernelImage
import KernelObject
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

	minimal_pdf : U64 -> Try(List(U8), [EvidenceFailure, InvalidRuntimeGuard])
	minimal_pdf = |runtime_guard| if runtime_guard == 0 build_minimal_pdf({}) else Err(InvalidRuntimeGuard)
}

build_minimal_pdf : {} -> Try(List(U8), [EvidenceFailure, InvalidRuntimeGuard])
build_minimal_pdf = |_| {
	pipeline = KernelGate2PipelineFixture.pipeline({}) ? |_| EvidenceFailure
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
	plan = KernelGate2Structure.Plan.build(
		pipeline.tagged,
		pipeline.colors,
		pipeline.images,
		pipeline.content,
		pipeline.objects,
		KernelGate2Structure.Limits.make({
			object_limits: object_limits,
		}),
	) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(KernelGate2Structure.Plan.structure(plan)) ? |_| EvidenceFailure
	Ok(bytes)
}

## The Gate 2 evidence package links the private analytical geometry kernel.
expect Gate2Evidence.geometry_probe({ x: 2000, y: 3000 }) == { x: 2000, y: 9000 }
